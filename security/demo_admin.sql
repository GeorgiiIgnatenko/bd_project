\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE operation record;
BEGIN
  IF current_user <> 'news_admin' OR (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
    RAISE EXCEPTION 'Expected a real, non-superuser news_admin connection';
  END IF;
  CREATE TABLE public.lab4_admin_probe (id integer PRIMARY KEY);
  INSERT INTO public.lab4_admin_probe VALUES (1);
  ALTER TABLE public.lab4_admin_probe ADD COLUMN note text;
  UPDATE public.lab4_admin_probe SET note = 'allowed';
  DROP TABLE public.lab4_admin_probe;
  RAISE NOTICE 'PASS admin: CREATE/ALTER/DROP TABLE and data changes';
  FOR operation IN SELECT * FROM (VALUES
    ('create cluster role', 'CREATE ROLE lab4_forbidden_role'),
    ('become superuser', 'ALTER ROLE news_admin SUPERUSER'),
    ('assume bootstrap identity', 'SET ROLE news_bootstrap'),
    ('read database password verifiers', 'SELECT rolpassword FROM pg_authid'),
    ('read server files', 'SELECT pg_read_file(''/etc/passwd'', 0, 16)')
  ) denied(label, statement) LOOP
    BEGIN
      EXECUTE operation.statement;
      RAISE EXCEPTION 'FAIL admin: unexpectedly allowed %', operation.label;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASS admin: denied % (42501)', operation.label;
    END;
  END LOOP;
END;
$$;
ROLLBACK;
