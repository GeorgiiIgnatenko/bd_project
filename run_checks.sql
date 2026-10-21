\set ON_ERROR_STOP on
\echo 'Checking migrations and integrity constraints...'

BEGIN;
-- A separate schema avoids changing application rows or identity sequences.
SELECT format('lab_checks_%s', pg_backend_pid()) AS check_schema \gset
CREATE SCHEMA :"check_schema";
SET LOCAL search_path TO :"check_schema", public, pg_catalog;

\ir migrations/001_init.up.sql
\ir migrations/002_add_scrape_run_status_check.up.sql
\ir migrations/003_model_consistency.up.sql
\ir migrations/004_add_trgm_indexes.up.sql
\ir tests/assertions.sql

SAVEPOINT integrity_fixtures;
\ir tests/integrity.sql
SELECT count(*) AS integrity_passed FROM pg_temp.check_results \gset
ROLLBACK TO SAVEPOINT integrity_fixtures;

-- Exercise the actual report scripts, not only independent test fixtures.
\ir sql/seed/report_test.sql
\ir tests/seed.sql
\ir sql/scenarios/01_user.sql
\ir sql/scenarios/02_source.sql
\ir sql/scenarios/03_news.sql
\ir tests/scenarios.sql
\ir tests/negative_examples.sql

SELECT :integrity_passed + count(*) AS passed_checks FROM pg_temp.check_results;
ROLLBACK;
\echo 'All checks passed. Test schema and data rolled back.'
