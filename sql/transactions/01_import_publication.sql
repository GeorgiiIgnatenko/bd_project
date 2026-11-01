-- Транзакция: импорт одной публикации за один запуск сбора (SC-05)
\set ON_ERROR_STOP on
-- Изменяемые таблицы: scrape_run, news, news_category, import_result, news_source.
-- Шаги:
--   1. создать запуск сбора («запущен»);
--   2. сохранить новость (дубликат по canonical_url не вставляется, БП-4);
--   3. привязать категорию; если не найдена/неактивна - «Без категории» (БП-5);
--   4. записать результат импорта («успех» или «дубликат»);
--   5. закрыть запуск («завершен»);
--   6. вернуть источник из «ошибка подключения» в «активен» (AC-SC06-06).
BEGIN;
\ir import_body.sql
-- Проверка внутри транзакции (до фиксации)
SELECT s.status AS source_status,
    r.id AS run_id,
    r.status AS run_status,
    ir.status AS import_status,
    n.title,
    c.name AS category
FROM scrape_run r
    JOIN news_source s ON s.id = r.source_id
    JOIN import_result ir ON ir.scrape_run_id = r.id
    LEFT JOIN news n ON n.id = ir.news_id
    LEFT JOIN news_category nc ON nc.news_id = n.id
    LEFT JOIN category c ON c.id = nc.category_id
WHERE s.url = 'https://globalnews.example/feed'
ORDER BY r.id DESC
LIMIT 1;
COMMIT;
