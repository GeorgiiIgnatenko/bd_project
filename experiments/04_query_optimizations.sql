-- ==============================================================================
-- 4. ОПТИМИЗАЦИЯ 5 БИЗНЕС-ЗАПРОСОВ (БАЗОВЫЕ И ОПТИМИЗИРОВАННЫЕ ВЕРСИИ)
-- ==============================================================================

SET search_path TO dev, pg_catalog;

-- ==============================================================================
-- ЗАПРОС 1 (Q1): Персонализированная лента пользователя (SC-03)
-- ==============================================================================
-- Базовая версия:
EXPLAIN (ANALYZE, BUFFERS)
SELECT n.id,
    n.title,
    s.name AS source,
    n.published_at,
    (
        EXISTS (
            SELECT 1
            FROM subscription_source ss
            WHERE ss.user_id = 1
                AND ss.source_id = n.source_id
                AND s.status NOT IN ('неактивен', 'отключён вручную')
        )
        OR
        EXISTS (
            SELECT 1
            FROM news_category nc
                JOIN subscription_category sc ON sc.category_id = nc.category_id
                JOIN category c ON c.id = nc.category_id
            WHERE nc.news_id = n.id
                AND sc.user_id = 1
                AND c.is_active
                AND c.name <> 'Без категории'
        )
    ) AS is_priority
FROM news n
    JOIN news_source s ON s.id = n.source_id
WHERE n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
ORDER BY is_priority DESC,
    n.published_at DESC
LIMIT 20 OFFSET 0;

-- Оптимизированная версия (предварительное вычисление подписок в CTE):
EXPLAIN (ANALYZE, BUFFERS)
WITH user_sources AS (
    SELECT source_id 
    FROM subscription_source 
    WHERE user_id = 1
),
user_categories AS (
    SELECT sc.category_id 
    FROM subscription_category sc
    JOIN category c ON c.id = sc.category_id
    WHERE sc.user_id = 1 AND c.is_active AND c.name <> 'Без категории'
),
priority_news AS (
    SELECT DISTINCT nc.news_id 
    FROM news_category nc 
    JOIN user_categories uc ON uc.category_id = nc.category_id
)
SELECT n.id, 
       n.title, 
       s.name AS source, 
       n.published_at,
       (
           (s.status NOT IN ('неактивен', 'отключён вручную') AND EXISTS (SELECT 1 FROM user_sources us WHERE us.source_id = n.source_id))
           OR EXISTS (SELECT 1 FROM priority_news pn WHERE pn.news_id = n.id)
       ) AS is_priority
FROM news n
JOIN news_source s ON s.id = n.source_id
WHERE n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
ORDER BY is_priority DESC, n.published_at DESC 
LIMIT 20;

-- ==============================================================================
-- ЗАПРОС 2 (Q2): Поиск новостей по категории и тексту (SC-02)
-- ==============================================================================
-- Оптимизированный запрос с триграммным индексом:
EXPLAIN (ANALYZE, BUFFERS)
SELECT n.id,
       n.title,
       s.name AS source,
       c.name AS category,
       n.published_at
FROM category c
JOIN news_category nc ON nc.category_id = c.id
JOIN news n           ON n.id = nc.news_id
JOIN news_source s    ON s.id = n.source_id
WHERE c.name = 'Спорт' 
  AND (n.title ILIKE '%спорт%' OR n.content ILIKE '%спорт%')
ORDER BY n.published_at DESC 
LIMIT 20;

-- ==============================================================================
-- ЗАПРОС 3 (Q3): Популярность категорий (SC-02, SC-07)
-- ==============================================================================
-- Оптимизированная версия (устранение декартова произведения с 126 млн строк -> раздельная агрегация):
EXPLAIN (ANALYZE, BUFFERS)
WITH cat_news AS (
    SELECT nc.category_id, 
           COUNT(nc.news_id) AS news_count, 
           MAX(n.published_at) AS last_news_at
    FROM news_category nc
    JOIN news n ON n.id = nc.news_id 
               AND n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
    GROUP BY nc.category_id
),
cat_subs AS (
    SELECT category_id, 
           COUNT(user_id) AS subscribers
    FROM subscription_category
    GROUP BY category_id
)
SELECT c.id, 
       c.name,
       COALESCE(cn.news_count, 0) AS news_count,
       COALESCE(cs.subscribers, 0) AS subscribers,
       cn.last_news_at
FROM category c
LEFT JOIN cat_news cn ON cn.category_id = c.id
LEFT JOIN cat_subs cs ON cs.category_id = c.id
ORDER BY news_count DESC, subscribers DESC, c.name;

-- ==============================================================================
-- ЗАПРОС 4 (Q4): Статистика сбора по источникам (SC-05, SC-06)
-- ==============================================================================
-- Оптимизированная версия (предварительная группировка запусков сбора):
EXPLAIN (ANALYZE, BUFFERS)
WITH run_stats AS (
    SELECT r.source_id,
           COUNT(DISTINCT r.id) AS runs,
           COUNT(ir.id) FILTER (WHERE ir.status = 'успех') AS imported,
           COUNT(ir.id) FILTER (WHERE ir.status = 'дубликат') AS duplicates,
           COUNT(ir.id) FILTER (WHERE ir.status = 'ошибка') AS failed_items
    FROM scrape_run r
    LEFT JOIN import_result ir ON ir.scrape_run_id = r.id
    WHERE r.started_at >= '2026-01-01'
    GROUP BY r.source_id
)
SELECT s.id, 
       s.name, 
       s.status,
       COALESCE(rs.runs, 0) AS runs,
       COALESCE(rs.imported, 0) AS imported,
       COALESCE(rs.duplicates, 0) AS duplicates,
       COALESCE(rs.failed_items, 0) AS failed_items
FROM news_source s
LEFT JOIN run_stats rs ON rs.source_id = s.id
ORDER BY s.id;

-- ==============================================================================
-- ЗАПРОС 5 (Q5): Проблемные источники (HAVING) (SC-06, БП-7)
-- ==============================================================================
-- Оптимизированная версия (предварительная фильтрация ошибок перед агрегацией источников):
EXPLAIN (ANALYZE, BUFFERS)
WITH failed_runs AS (
    SELECT r.source_id, 
           r.id AS run_id,
           COUNT(e.id) AS error_records, 
           MAX(e.created_at) AS last_error_at
    FROM scrape_run r
    LEFT JOIN scrape_error_log e ON e.scrape_run_id = r.id
    WHERE r.status = 'ошибка' 
      AND r.started_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (7 * INTERVAL '1 day')
    GROUP BY r.source_id, r.id
)
SELECT s.id, 
       s.name, 
       s.status,
       COUNT(fr.run_id) AS failed_runs,
       COALESCE(SUM(fr.error_records), 0) AS error_records,
       MAX(fr.last_error_at) AS last_error_at
FROM news_source s
JOIN failed_runs fr ON fr.source_id = s.id
GROUP BY s.id, s.name, s.status
HAVING COUNT(fr.run_id) >= 1
ORDER BY failed_runs DESC, s.id;
