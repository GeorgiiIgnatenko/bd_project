set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

TEST_PATH="/workspace/tests/audit_rls_tests/security_rls_audit.sql"

echo "Запуск тестов безопасности (RLS, аудит)"

docker compose up -d postgres
echo "Ожидание готовности PostgreSQL"
for i in $(seq 1 60); do
    if docker compose exec -T postgres \
        pg_isready -U news_bootstrap -d "${POSTGRES_DB:-news_aggregator}" \
        >/dev/null 2>&1; then
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "Ошибка: PostgreSQL не стала готовой за 60 секунд."
        exit 1
    fi
    sleep 1
done

docker compose exec -T postgres sh -c '
    exec psql -X -w \
        -U news_bootstrap \
        -d "$POSTGRES_DB" \
        -v ON_ERROR_STOP=1 \
        -f /workspace/tests/audit_rls_tests/security_rls_audit.sql
'

echo "Готово."