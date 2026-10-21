\set ON_ERROR_STOP on
BEGIN;
\ir /workspace/migrations/001_init.up.sql
\ir /workspace/migrations/002_add_scrape_run_status_check.up.sql
\ir /workspace/migrations/003_model_consistency.up.sql
\ir /workspace/migrations/004_add_trgm_indexes.up.sql
COMMIT;
