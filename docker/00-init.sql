\set ON_ERROR_STOP on
\ir /workspace/security/bootstrap.sql
\ir /workspace/security/roles.sql
-- Schema migrations run from start.sh after the server becomes healthy.
-- pg_stat_statements requires bootstrap; application roles cannot install it.
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
