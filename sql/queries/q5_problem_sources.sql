-- Q5: у каких источников >= N неудачных запусков за период?
-- Параметры: as_of, days, min_failed_runs. Роль: news_analyst или news_admin.
-- Это кандидаты для диагностики; N ошибок за период не означает N подряд.
WITH failed AS (
    SELECT r.source_id, r.id, count(e.id) AS error_records,
           max(e.created_at) AS last_error_at
    FROM scrape_run r
    LEFT JOIN scrape_error_log e ON e.scrape_run_id = r.id
    WHERE r.status = 'ошибка'
      AND r.started_at >= :'as_of'::timestamptz - (:days * INTERVAL '1 day')
      AND r.started_at < :'as_of'::timestamptz
    GROUP BY r.source_id, r.id
)
SELECT s.id, s.name, s.status, count(*) AS failed_runs,
       sum(f.error_records)::bigint AS error_records, max(f.last_error_at) AS last_error_at
FROM news_source s
JOIN failed f ON f.source_id = s.id
GROUP BY s.id, s.name, s.status
HAVING count(*) >= :min_failed_runs
ORDER BY failed_runs DESC, s.id;
