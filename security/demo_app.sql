\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE operation record; probe_id integer := -pg_backend_pid();
BEGIN
  IF current_user <> 'news_app' OR EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = current_user
      AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
  ) THEN RAISE EXCEPTION 'Expected a restricted news_app login'; END IF;
  IF NOT has_sequence_privilege('public.news_id_seq', 'USAGE') THEN
    RAISE EXCEPTION 'Application lacks identity sequence usage';
  END IF;
  -- Explicit negative IDs leave real identity sequence states untouched.
  INSERT INTO public.news_source (id, name, url, status) OVERRIDING SYSTEM VALUE
    VALUES (probe_id, 'Lab 4 probe', 'https://lab4.invalid/' || pg_backend_pid(), 'активен');
  INSERT INTO public.category (id, name) OVERRIDING SYSTEM VALUE
    VALUES (probe_id, 'Lab 4 probe ' || pg_backend_pid());
  INSERT INTO public.news (id, source_id, canonical_url, title, content, published_at)
    OVERRIDING SYSTEM VALUE VALUES (probe_id, probe_id,
      'https://lab4.invalid/news/' || pg_backend_pid(), 'Probe', 'Probe text', now());
  INSERT INTO public.news_category VALUES (probe_id, probe_id);
  PERFORM n.title FROM public.news n JOIN public.news_category nc ON nc.news_id = n.id
    WHERE n.id = probe_id;
  UPDATE public.news_source SET status = 'отключён вручную' WHERE id = probe_id;
  DELETE FROM public.news_category WHERE news_id = probe_id;
  INSERT INTO public.news_category VALUES (probe_id, probe_id);
  RAISE NOTICE 'PASS app: SELECT/INSERT/UPDATE/DELETE with valid foreign keys';
  FOR operation IN SELECT * FROM (VALUES
    ('create tables', 'CREATE TABLE public.lab4_app_probe (id integer)'),
    ('change table structure', 'ALTER TABLE public.news ADD COLUMN lab4_probe text'),
    ('truncate business data', 'TRUNCATE public.news'),
    ('change role dictionary', 'INSERT INTO public.role (name) VALUES (''Lab 4 forbidden'')'),
    ('rewrite saved publications', 'UPDATE public.news SET content = content WHERE false'),
    ('delete saved publications', 'DELETE FROM public.news WHERE false'),
    ('rewrite import history', 'UPDATE public.import_result SET status = status WHERE false'),
    ('delete error history', 'DELETE FROM public.scrape_error_log WHERE false'),
    ('create cluster role', 'CREATE ROLE lab4_forbidden_role'),
    ('become superuser', 'ALTER ROLE news_app SUPERUSER'),
    ('assume administrator identity', 'SET ROLE news_admin'),
    ('assume bootstrap identity', 'SET ROLE news_bootstrap'),
    ('read database password verifiers', 'SELECT rolpassword FROM pg_authid'),
    ('read server files', 'SELECT pg_read_file(''/etc/passwd'', 0, 16)')
  ) denied(label, statement) LOOP
    BEGIN
      EXECUTE operation.statement;
      RAISE EXCEPTION 'FAIL app: unexpectedly allowed %', operation.label;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASS app: denied % (42501)', operation.label;
    END;
  END LOOP;
END;
$$;
ROLLBACK;
