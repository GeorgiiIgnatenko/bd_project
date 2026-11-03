-- Q7: между какими публикациями источника были самые длинные паузы в периоде?
-- Параметры: as_of, window_days, page_size, page_offset.
-- Роль: news_analyst / news_admin. Период [as_of - window_days, as_of).
-- LAG видит только выбранный период; у первой новости previous_published_at = NULL.
-- Одновременные публикации упорядочены по ID и дают нулевой интервал.
-- Пагинация применяется после LAG. Текущий простой источника не измеряется.
WITH publications AS (
    SELECT n.id, n.title, s.id AS source_id, s.name AS source, n.published_at,
           lag(n.published_at) OVER (
               PARTITION BY n.source_id ORDER BY n.published_at, n.id
           ) AS previous_published_at
    FROM news n
    JOIN news_source s ON s.id = n.source_id
    WHERE n.published_at >= :'as_of'::timestamptz - (:window_days * INTERVAL '1 day')
      AND n.published_at < :'as_of'::timestamptz
)
SELECT id, title, source_id, source, published_at, previous_published_at,
       published_at - previous_published_at AS publication_gap
FROM publications
ORDER BY publication_gap DESC NULLS LAST, published_at DESC, id DESC
LIMIT :page_size OFFSET :page_offset;
