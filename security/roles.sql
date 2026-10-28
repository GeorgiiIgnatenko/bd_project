\set ON_ERROR_STOP on
-- Cluster bootstrap only. Reapplying this file does not delete application rows.
SET log_statement = 'none';
SET log_min_error_statement = 'panic';
SET password_encryption = 'scram-sha-256';
BEGIN;
DO $$
DECLARE role_name text; membership record;
BEGIN
  IF current_user <> 'news_bootstrap' THEN
    RAISE EXCEPTION 'Connect as news_bootstrap for role provisioning';
  END IF;
  FOREACH role_name IN ARRAY ARRAY['news_admin', 'news_app', 'news_analyst'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE format('CREATE ROLE %I LOGIN', role_name);
    END IF;
    -- NOINHERIT alone would still allow SET ROLE; remove memberships as well.
    FOR membership IN SELECT parent.rolname FROM pg_auth_members m
      JOIN pg_roles parent ON parent.oid = m.roleid
      JOIN pg_roles member ON member.oid = m.member
      WHERE member.rolname = role_name
    LOOP
      EXECUTE format('REVOKE %I FROM %I', membership.rolname, role_name);
    END LOOP;
  END LOOP;
END;
$$;

-- Never REASSIGN all objects of the initial superuser: it also owns system catalogs.
-- Transfer only project schemas/relations/functions; system objects stay at bootstrap.
SELECT format('ALTER DATABASE %I OWNER TO news_admin', current_database()) \gexec
DO $$
DECLARE item record;
BEGIN
  FOR item IN SELECT nspname FROM pg_namespace
    WHERE nspname NOT LIKE 'pg_%' AND nspname <> 'information_schema'
      AND nspowner = (SELECT oid FROM pg_roles WHERE rolname = 'news_bootstrap')
  LOOP
    EXECUTE format('ALTER SCHEMA %I OWNER TO news_admin', item.nspname);
  END LOOP;
  FOR item IN SELECT n.nspname, c.relname, c.relkind FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname <> 'information_schema'
      AND c.relowner = (SELECT oid FROM pg_roles WHERE rolname = 'news_bootstrap')
      AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
    ORDER BY CASE WHEN c.relkind = 'S' THEN 1 ELSE 0 END, c.oid
  LOOP
    EXECUTE format('ALTER %s %I.%I OWNER TO news_admin',
      CASE item.relkind WHEN 'S' THEN 'SEQUENCE' WHEN 'v' THEN 'VIEW'
           WHEN 'm' THEN 'MATERIALIZED VIEW' ELSE 'TABLE' END,
      item.nspname, item.relname);
  END LOOP;
  FOR item IN SELECT p.oid::regprocedure AS identity, p.prokind FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname <> 'information_schema'
      AND p.proowner = (SELECT oid FROM pg_roles WHERE rolname = 'news_bootstrap')
      AND p.prokind IN ('f', 'p')
  LOOP
    EXECUTE format('ALTER %s %s OWNER TO news_admin',
      CASE WHEN item.prokind = 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END, item.identity);
  END LOOP;
END;
$$;

ALTER ROLE news_admin LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS NOINHERIT;
ALTER ROLE news_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS NOINHERIT;
ALTER ROLE news_analyst LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
  NOREPLICATION NOBYPASSRLS NOINHERIT;

\getenv admin_password ADMIN_PASSWORD
\getenv app_password APP_PASSWORD
\getenv analyst_password ANALYST_PASSWORD
ALTER ROLE news_admin PASSWORD :'admin_password';
ALTER ROLE news_app PASSWORD :'app_password';
ALTER ROLE news_analyst PASSWORD :'analyst_password';

DO $$
DECLARE role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['news_admin', 'news_app', 'news_analyst'] LOOP
    EXECUTE format('ALTER ROLE %I IN DATABASE %I SET search_path TO public, pg_catalog',
      role_name, current_database());
  END LOOP;
END;
$$;

SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC, news_app, news_analyst', current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO news_admin, news_app, news_analyst', current_database()) \gexec
-- Admin is the project database owner, so it can create schemas and temporary fixtures.
ALTER DEFAULT PRIVILEGES FOR ROLE news_admin REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE news_admin REVOKE ALL ON SEQUENCES FROM PUBLIC;
-- Sessions authenticated before the legacy superuser was renamed must reconnect
-- as the restricted application role; network bootstrap logins are now rejected.
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
WHERE usesysid = (SELECT oid FROM pg_roles WHERE rolname = 'news_bootstrap')
  AND client_addr IS NOT NULL AND pid <> pg_backend_pid();
DROP ROLE IF EXISTS news_setup;
COMMIT;
