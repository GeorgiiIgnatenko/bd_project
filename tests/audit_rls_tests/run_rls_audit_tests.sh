#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

TEST_PATH="/workspace/tests/audit_rls_tests/security_rls_audit.sql"

echo "Запуск тестов безопасности (RLS, аудит)"

docker compose up -d --wait postgres

docker compose exec -T postgres sh -c '
    exec psql -X -w \
        -U news_bootstrap \
        -d "$POSTGRES_DB" \
        -v ON_ERROR_STOP=1 \
        -f /workspace/tests/audit_rls_tests/security_rls_audit.sql
'

echo "Готово."
