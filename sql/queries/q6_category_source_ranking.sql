-- Q6: какие источники публикуют больше всего новостей в каждой категории?
-- Параметры: as_of, window_days, top_ranks (число мест, по умолчанию 3).
-- Роль: news_analyst / news_admin. Только активные обычные категории.
-- Период [as_of - window_days, as_of); статус источника не исключает его статьи.
-- Одинаковое количество даёт одно место: top_ranks может вернуть больше строк.
WITH source_counts AS (
    SELECT c.id AS category_id, c.name AS category,
           s.id AS source_id, s.name AS source, count(*) AS news_count
    FROM category c
    JOIN news_category nc ON nc.category_id = c.id
    JOIN news n ON n.id = nc.news_id
    JOIN news_source s ON s.id = n.source_id
    WHERE c.is_active AND c.name <> 'Без категории'
      AND n.published_at >= :'as_of'::timestamptz - (:window_days * INTERVAL '1 day')
      AND n.published_at < :'as_of'::timestamptz
    GROUP BY c.id, c.name, s.id, s.name
), ranked AS (
    SELECT *, dense_rank() OVER (
        PARTITION BY category_id ORDER BY news_count DESC
    ) AS source_rank
    FROM source_counts
)
SELECT category_id, category, source_id, source, news_count, source_rank
FROM ranked
WHERE source_rank <= :top_ranks
ORDER BY category_id, source_rank, source_id;
