-- ==============================================================================
-- 2. НАСТРОЙКА И ОТЧЕТ ПО PG_STAT_STATEMENTS
-- ==============================================================================

-- 1. Подключение расширения
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Сброс статистики перед сбором профиля
SELECT pg_stat_statements_reset();

-- 2. Диагностический запрос: Топ-10 наиболее ресурсоемких запросов по суммарному времени (total_exec_time)
SELECT 
    queryid,
    calls,
    ROUND(total_exec_time::numeric, 2) AS total_exec_time_ms,
    ROUND(mean_exec_time::numeric, 2) AS mean_exec_time_ms,
    ROUND(min_exec_time::numeric, 2) AS min_exec_time_ms,
    ROUND(max_exec_time::numeric, 2) AS max_exec_time_ms,
    rows,
    shared_blks_hit,
    shared_blks_read,
    ROUND((100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0))::numeric, 2) AS cache_hit_pct,
    SUBSTRING(REGEXP_REPLACE(query, '\s+', ' ', 'g') FROM 1 FOR 100) AS query_preview
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
  AND query NOT LIKE '%SET search_path%'
ORDER BY total_exec_time DESC
LIMIT 10;

-- 3. Диагностический запрос: Топ запросов по операциям дискового ввода-вывода (shared_blks_read)
SELECT 
    queryid,
    calls,
    shared_blks_read,
    shared_blks_hit,
    ROUND(mean_exec_time::numeric, 2) AS mean_exec_time_ms,
    SUBSTRING(REGEXP_REPLACE(query, '\s+', ' ', 'g') FROM 1 FOR 100) AS query_preview
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY shared_blks_read DESC
LIMIT 10;
