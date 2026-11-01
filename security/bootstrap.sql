\set ON_ERROR_STOP on
-- Local bootstrap only; passwords are neither logged nor included in statistics.
SET log_statement = 'none';
SET log_min_error_statement = 'panic';
SET pg_stat_statements.track_utility = off;
SET password_encryption = 'scram-sha-256';
\getenv bootstrap_password POSTGRES_PASSWORD
ALTER ROLE news_bootstrap LOGIN SUPERUSER PASSWORD :'bootstrap_password';
