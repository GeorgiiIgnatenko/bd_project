\set ON_ERROR_STOP on
-- Cluster bootstrap only. Reapplying this file does not delete application rows.
SET log_statement = 'none';
SET pg_stat_statements.track_utility = off;
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

-- Database ownership grants schema management, not cluster administration.
SELECT format('ALTER DATABASE %I OWNER TO news_admin', current_database()) \gexec

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
COMMIT;
