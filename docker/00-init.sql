\set ON_ERROR_STOP on
\ir /workspace/security/bootstrap.sql
\ir /workspace/security/roles.sql
BEGIN;
SET LOCAL ROLE news_admin;
\ir /workspace/migrations/001_init.up.sql
\ir /workspace/migrations/002_add_scrape_run_status_check.up.sql
\ir /workspace/migrations/003_model_consistency.up.sql
\ir /workspace/migrations/004_add_trgm_indexes.up.sql
\ir /workspace/security/grants.sql
COMMIT;
