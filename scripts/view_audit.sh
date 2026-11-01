#!/usr/bin/env sh
set -e

cd "$(dirname "$0")/.." || exit 1

echo "Просмотр журнала аудита (public.audit_log)"

SQL_QUERY="
SELECT 
    id,
    to_char(changed_at, 'YYYY-MM-DD HH24:MI:SS') AS time,
    db_role,
    app_user_id AS user_id,
    table_name,
    operation,
    CASE 
        WHEN operation = 'INSERT' THEN new_data::text
        WHEN operation = 'DELETE' THEN old_data::text
        ELSE E'OLD: ' || old_data::text || E'\\nNEW: ' || new_data::text
    END AS data_changes
FROM public.audit_log
ORDER BY id DESC
LIMIT 15;
"

docker compose run --rm admin -c "$SQL_QUERY"
echo "Просмотр завершен."