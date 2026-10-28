\set ON_ERROR_STOP on
-- Applicable both by bootstrap and by the project owner after migrations/generation.
DO $$
DECLARE schema_name text; table_name text; sequence_name text; permission record;
BEGIN
  FOR schema_name IN SELECT nspname FROM pg_namespace
    WHERE nspname IN ('public', 'dev', 'load', 'lab3_dev', 'lab3_load')
  LOOP
    EXECUTE format('REVOKE ALL ON SCHEMA %I FROM PUBLIC, news_app, news_analyst', schema_name);
    EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA %I FROM PUBLIC, news_app, news_analyst', schema_name);
    EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA %I FROM PUBLIC, news_app, news_analyst', schema_name);
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO news_analyst', schema_name);
    -- Analytics gets public content and collection metrics, not accounts/preferences.
    FOREACH table_name IN ARRAY ARRAY[
      'role', 'category', 'news_source', 'news', 'news_category',
      'scrape_run', 'import_result', 'scrape_error_log'
    ] LOOP
      IF to_regclass(format('%I.%I', schema_name, table_name)) IS NOT NULL THEN
        EXECUTE format('GRANT SELECT ON %I.%I TO news_analyst', schema_name, table_name);
      END IF;
    END LOOP;
  END LOOP;

  GRANT USAGE ON SCHEMA public TO news_app;
  IF to_regclass('public.role') IS NOT NULL THEN
    GRANT SELECT ON public.role TO news_app;
  END IF;
  FOR permission IN SELECT * FROM (VALUES
    ('app_user', 'SELECT, INSERT, UPDATE'),
    ('category', 'SELECT, INSERT, UPDATE'),
    ('news_source', 'SELECT, INSERT, UPDATE'),
    ('news', 'SELECT, INSERT'),
    ('news_category', 'SELECT, INSERT, DELETE'),
    ('subscription_category', 'SELECT, INSERT, DELETE'),
    ('subscription_source', 'SELECT, INSERT, DELETE'),
    ('favorite', 'SELECT, INSERT, DELETE'),
    ('scrape_run', 'SELECT, INSERT, UPDATE'),
    ('import_result', 'SELECT, INSERT'),
    ('scrape_error_log', 'SELECT, INSERT')
  ) policy(table_name, privileges) LOOP
    table_name := permission.table_name;
    IF to_regclass(format('public.%I', table_name)) IS NOT NULL THEN
      EXECUTE format('GRANT %s ON public.%I TO news_app', permission.privileges, table_name);
      IF EXISTS (SELECT 1 FROM pg_attribute
        WHERE attrelid = to_regclass(format('public.%I', table_name))
          AND attname = 'id' AND attidentity <> '') THEN
        sequence_name := pg_get_serial_sequence(format('public.%I', table_name), 'id');
        EXECUTE format('GRANT USAGE ON SEQUENCE %s TO news_app', sequence_name);
      END IF;
    END IF;
  END LOOP;
END;
$$;
