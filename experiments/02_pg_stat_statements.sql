-- Extension installed by bootstrap; preload configured in compose.yaml.
-- Only our administrator's SELECT workload in this database. Never dump
-- bootstrap/role-management statements into a public report.
SELECT queryid, calls, round(total_exec_time::numeric, 3) AS total_ms,
       round(mean_exec_time::numeric, 3) AS mean_ms, rows,
       shared_blks_hit, shared_blks_read,
       left(regexp_replace(query, '\s+', ' ', 'g'), 160) AS query_preview
FROM public.pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND userid = (SELECT oid FROM pg_roles WHERE rolname = 'news_admin')
  AND query NOT ILIKE '%pg_stat_statements%'
  AND query ~* '^(SELECT|WITH)[[:space:]]'
  AND (query ILIKE '%FROM news n%' OR query ILIKE '%FROM news_source s%'
       OR query ILIKE '%FROM news_category nc%' OR query ILIKE '%FROM scrape_run r%')
ORDER BY total_exec_time DESC
LIMIT 10;
