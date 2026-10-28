#!/bin/sh
set -eu
if [ "$#" -gt 1 ]; then
  echo 'Usage: sh security/apply.sh [existing_superuser]' >&2
  exit 64
fi
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
existing_superuser=${1:-news_bootstrap}
if [ "$#" -eq 0 ] && ! docker compose exec -T postgres sh -c '
  psql -X -w -U news_bootstrap -d "$POSTGRES_DB" -c "SELECT 1"
' > /dev/null 2>&1; then
  existing_superuser=news_app
fi
docker compose exec -T postgres sh -c '
  exec psql -X -w -v ON_ERROR_STOP=1 -U "$1" -d "$POSTGRES_DB" \
    -f /workspace/security/bootstrap.sql
' sh "$existing_superuser"
docker compose exec -T postgres sh -c '
  exec psql -X -w -v ON_ERROR_STOP=1 -U news_bootstrap -d "$POSTGRES_DB" \
    -f /workspace/security/roles.sql -f /workspace/security/grants.sql
'
