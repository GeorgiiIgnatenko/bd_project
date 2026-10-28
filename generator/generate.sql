-- psql -X -v ON_ERROR_STOP=1 -v mode=dev -v seed=42 -f generator/generate.sql
\set ON_ERROR_STOP on
\timing on
\if :{?mode}
\else
  \set mode dev
\endif
\if :{?seed}
\else
  \set seed 42
\endif

BEGIN;
SET LOCAL timezone TO 'UTC';
CREATE TEMP TABLE generation_config (
  mode text NOT NULL CHECK (mode IN ('dev', 'load')),
  seed bigint NOT NULL CHECK (seed BETWEEN 0 AND 2147483647),
  news_count bigint NOT NULL,
  user_count bigint NOT NULL,
  reference_time timestamptz NOT NULL
) ON COMMIT DROP;
INSERT INTO generation_config VALUES (
  :'mode', :'seed'::bigint,
  CASE :'mode' WHEN 'dev' THEN 80000 ELSE 3000000 END,
  CASE :'mode' WHEN 'dev' THEN 10000 ELSE 100000 END,
  TIMESTAMPTZ '2026-10-01 00:00:00+00'
);

-- Derive the schema only from a validated mode, even when psql receives -v schema.
-- Dropping, rebuilding and loading commit together; an error restores the old set.
SELECT mode AS schema FROM generation_config \gset
DROP SCHEMA IF EXISTS :"schema" CASCADE;
CREATE SCHEMA :"schema";
-- Shared pg_trgm operator classes are installed in public by initial migrations.
SET LOCAL search_path TO :"schema", public, pg_catalog;
\ir ../migrations/001_init.up.sql
\ir ../migrations/002_add_scrape_run_status_check.up.sql
\ir ../migrations/003_model_consistency.up.sql
\ir ../migrations/004_add_trgm_indexes.up.sql

SELECT jsonb_build_object(
  'generator_version', 3, 'mode', mode, 'seed', seed,
  'news_count', news_count, 'user_count', user_count,
  'reference_time', reference_time
)::text AS generation_metadata FROM generation_config \gset
COMMENT ON SCHEMA :"schema" IS :'generation_metadata';

-- A draw depends on a seed, a named dimension and an entity ID, not query order.
-- MD5 is used only to distribute synthetic values, never to hash passwords.
CREATE FUNCTION pg_temp.draw(seed bigint, dimension text, entity_id bigint, bound bigint)
RETURNS bigint LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
  SELECT ('x' || substr(md5(seed::text || ':' || dimension || ':' || entity_id::text), 1, 8))
           ::bit(32)::bigint % bound;
$$;

\ir populate.sql
\ir validate.sql

-- RESTART is transactional, unlike setval: failures also restore sequence states.
DO $$
DECLARE
  table_name text;
  last_id bigint;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'role', 'app_user', 'category', 'news_source', 'news',
    'scrape_run', 'import_result', 'scrape_error_log'
  ] LOOP
    EXECUTE format('SELECT max(id) FROM %I', table_name) INTO last_id;
    EXECUTE format('ALTER SEQUENCE %s RESTART WITH %s',
      pg_get_serial_sequence(table_name, 'id'), last_id + 1);
  END LOOP;
END;
$$;

-- Populate planner statistics without changing indexes or disabling constraints.
ANALYZE role;
ANALYZE app_user;
ANALYZE category;
ANALYZE news_source;
ANALYZE news;
ANALYZE news_category;
ANALYZE subscription_category;
ANALYZE subscription_source;
ANALYZE favorite;
ANALYZE scrape_run;
ANALYZE import_result;
ANALYZE scrape_error_log;
DROP FUNCTION pg_temp.draw(bigint, text, bigint, bigint);
\ir summary.sql
COMMIT;

\echo 'Generation committed in schema' :schema
