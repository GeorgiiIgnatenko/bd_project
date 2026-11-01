-- q4.
-- Статистика сбора по источникам (SC-05, SC-06)
-- Бизнес-вопрос: сколько запусков сбора было у каждого источника за период
--   и чем закончилась обработка материалов (успех / дубликат / ошибка)?
-- Параметры: date_from

SELECT s.id,
       s.name,
       s.status,
       COUNT(DISTINCT r.id)                               AS runs,
       COUNT(ir.id) FILTER (WHERE ir.status = 'успех')    AS imported,
       COUNT(ir.id) FILTER (WHERE ir.status = 'дубликат') AS duplicates,
       COUNT(ir.id) FILTER (WHERE ir.status = 'ошибка')   AS failed_items
FROM news_source s
LEFT JOIN scrape_run r     ON r.source_id = s.id
                          AND r.started_at >= :'date_from'
                          AND r.started_at < :'as_of'::timestamptz
LEFT JOIN import_result ir ON ir.scrape_run_id = r.id
GROUP BY s.id, s.name, s.status
ORDER BY s.id;
