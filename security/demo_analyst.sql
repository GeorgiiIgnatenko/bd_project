\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE operation record;
BEGIN
  IF current_user <> 'news_analyst' OR EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = current_user
      AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
  ) THEN RAISE EXCEPTION 'Expected a read-only news_analyst login'; END IF;
  PERFORM s.id, count(i.id) FROM public.news_source s
    LEFT JOIN public.scrape_run r ON r.source_id = s.id
    LEFT JOIN public.import_result i ON i.scrape_run_id = r.id GROUP BY s.id;
  PERFORM n.id, c.name FROM public.news n
    JOIN public.news_category nc ON nc.news_id = n.id
    JOIN public.category c ON c.id = nc.category_id LIMIT 10;
  RAISE NOTICE 'PASS analyst: reading publications and aggregate collection metrics';
  FOR operation IN SELECT * FROM (VALUES
    ('insert data', 'INSERT INTO public.category (name) VALUES (''Lab 4 forbidden'')'),
    ('update data', 'UPDATE public.news SET title = title WHERE false'),
    ('delete data', 'DELETE FROM public.news WHERE false'),
    ('truncate business data', 'TRUNCATE public.news'),
    ('read accounts and password hashes', 'SELECT password_hash FROM public.app_user LIMIT 1'),
    ('read personal favorites', 'SELECT * FROM public.favorite LIMIT 1'),
    ('create tables', 'CREATE TABLE public.lab4_analyst_probe (id integer)'),
    ('assume application identity', 'SET ROLE news_app'),
    ('assume bootstrap identity', 'SET ROLE news_bootstrap')
  ) denied(label, statement) LOOP
    BEGIN
      EXECUTE operation.statement;
      RAISE EXCEPTION 'FAIL analyst: unexpectedly allowed %', operation.label;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASS analyst: denied % (42501)', operation.label;
    END;
  END LOOP;
END;
$$;
ROLLBACK;
