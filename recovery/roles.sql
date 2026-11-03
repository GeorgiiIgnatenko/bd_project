\set ON_ERROR_STOP on
SET log_statement = 'none';
SET log_min_error_statement = 'panic';
SET pg_stat_statements.track_utility = off;
SET password_encryption = 'scram-sha-256';
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'news_replicator') THEN
    CREATE ROLE news_replicator;
  END IF;
END $$;
\getenv replication_password REPLICATION_PASSWORD
ALTER ROLE news_replicator LOGIN REPLICATION NOSUPERUSER NOCREATEDB
  NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD :'replication_password';
COMMIT;
