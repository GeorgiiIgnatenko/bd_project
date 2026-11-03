\set ON_ERROR_STOP on
SET timezone = 'UTC';
-- One line per table/sequence, without exposing row values or account hashes.
SELECT format(
  'SELECT %L, count(*), md5(COALESCE(string_agg(to_jsonb(t)::text, E''\n'' ORDER BY to_jsonb(t)::text COLLATE "C"), '''')) FROM %I.%I t;',
  n.nspname || '.' || c.relname, n.nspname, c.relname)
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('public', 'recovery_lab', 'dev', 'load') AND c.relkind = 'r'
ORDER BY n.nspname, c.relname \gexec
SELECT format('SELECT %L, last_value, is_called FROM %I.%I;',
              n.nspname || '.' || c.relname, n.nspname, c.relname)
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('public', 'recovery_lab', 'dev', 'load') AND c.relkind = 'S'
ORDER BY n.nspname, c.relname \gexec
