#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
for role in admin app analyst; do
  docker compose run --rm -T "$role" -f "/workspace/security/demo_$role.sql"
done

# Test a real attempted network connection, in addition to SET ROLE denials.
output=$(mktemp)
trap 'rm -f "$output"' EXIT HUP INT TERM
if docker compose run --rm -T app -U news_bootstrap -c 'SELECT current_user' > "$output" 2>&1; then
  echo 'FAIL: bootstrap accepted an application/network connection' >&2
  exit 1
fi
if ! grep -q 'pg_hba.conf rejects connection' "$output"; then
  cat "$output" >&2
  exit 1
fi
echo 'PASS: bootstrap network connection rejected by pg_hba.conf'
