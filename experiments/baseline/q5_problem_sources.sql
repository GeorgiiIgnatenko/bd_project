-- q5
-- Проблемные источники (HAVING) (SC-06, БП-7)
-- Бизнес-вопрос: у каких источников за последние дни было не меньше N
--   неудачных запусков сбора (кандидаты на перевод в «неактивен»)?
-- Параметры: days (период), min_failed_runs (N; по БП-7 равно 3,
--   для демонстрации используется 1)

SELECT s.id,
       s.name,
       s.status,
       COUNT(DISTINCT r.id) AS failed_runs,
       COUNT(e.id)          AS error_records,
       MAX(e.created_at)    AS last_error_at
FROM news_source s
JOIN scrape_run r            ON r.source_id = s.id
                            AND r.status = 'ошибка'
                            AND r.started_at >= :'as_of'::timestamptz - (:days * INTERVAL '1 day')
                            AND r.started_at < :'as_of'::timestamptz
LEFT JOIN scrape_error_log e ON e.scrape_run_id = r.id
GROUP BY s.id, s.name, s.status
HAVING COUNT(DISTINCT r.id) >= :min_failed_runs
ORDER BY failed_runs DESC, s.id;
