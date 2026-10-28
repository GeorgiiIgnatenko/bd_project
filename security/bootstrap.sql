\set ON_ERROR_STOP on
-- Run only by the existing cluster administrator. Do not log password statements.
SET log_statement = 'none';
SET log_min_error_statement = 'panic';
SET password_encryption = 'scram-sha-256';
BEGIN;
DO $$
BEGIN
  IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
    RAISE EXCEPTION 'Bootstrap setup requires the existing superuser';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'news_bootstrap') THEN
    IF current_user <> 'news_app' THEN
      RAISE EXCEPTION 'Expected the legacy news_app bootstrap role';
    END IF;
    -- Preserve the original superuser OID and its system-catalog ownership.
    -- A session cannot rename its own login, so briefly use a local-only helper.
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'news_setup') THEN
      CREATE ROLE news_setup LOGIN SUPERUSER PASSWORD NULL;
    END IF;
  END IF;
END;
$$;
COMMIT;
SELECT NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'news_bootstrap') AS legacy \gset
\if :legacy
  \connect -reuse-previous=on - news_setup
  ALTER ROLE news_app RENAME TO news_bootstrap;
\endif
-- Reconnect above resets session settings during a legacy upgrade.
SET log_statement = 'none';
SET log_min_error_statement = 'panic';
SET password_encryption = 'scram-sha-256';
\getenv bootstrap_password POSTGRES_PASSWORD
ALTER ROLE news_bootstrap LOGIN SUPERUSER PASSWORD :'bootstrap_password';
