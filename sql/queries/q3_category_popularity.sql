-- Q3: сколько новостей и подписчиков у категории, когда последняя новость?
-- Параметры: as_of, window_days. Роль: news_admin (все подписки, без RLS).
-- Агрегируем независимые множества до JOIN: иначе новости × подписчики.
WITH category_news AS (
    SELECT nc.category_id, count(*) AS news_count, max(n.published_at) AS last_news_at
    FROM news_category nc
    JOIN news n ON n.id = nc.news_id
    WHERE n.published_at >= :'as_of'::timestamptz - (:window_days * INTERVAL '1 day')
      AND n.published_at < :'as_of'::timestamptz
    GROUP BY nc.category_id
), category_subscribers AS (
    SELECT category_id, count(*) AS subscribers
    FROM subscription_category
    GROUP BY category_id
)
SELECT c.id, c.name,
       coalesce(n.news_count, 0) AS news_count,
       coalesce(s.subscribers, 0) AS subscribers,
       n.last_news_at
FROM category c
LEFT JOIN category_news n ON n.category_id = c.id
LEFT JOIN category_subscribers s ON s.category_id = c.id
ORDER BY news_count DESC, subscribers DESC, c.name;
