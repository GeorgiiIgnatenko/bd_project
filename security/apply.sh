#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
docker compose exec -T postgres sh -c '
  exec psql -X -w -v ON_ERROR_STOP=1 -U news_bootstrap -d "$POSTGRES_DB" \
    -f /workspace/security/bootstrap.sql \
    -f /workspace/security/roles.sql -f /workspace/security/grants.sql
'
