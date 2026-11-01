-- q3
-- Популярность категорий (SC-02, SC-07)
-- Бизнес-вопрос: сколько новостей и подписчиков у каждой категории
--   и когда вышла последняя новость? (для администратора: какие категории
--   востребованы, а какие пустуют)
-- Параметры: window_days (учитываются новости за последние N дней)

SELECT c.id,
       c.name,
       COUNT(DISTINCT n.id)       AS news_count,
       COUNT(DISTINCT sc.user_id) AS subscribers,
       MAX(n.published_at)        AS last_news_at
FROM category c
LEFT JOIN news_category nc        ON nc.category_id = c.id
LEFT JOIN news n                  ON n.id = nc.news_id
                                 AND n.published_at >= :'as_of'::timestamptz - (:window_days * INTERVAL '1 day')
                                 AND n.published_at < :'as_of'::timestamptz
LEFT JOIN subscription_category sc ON sc.category_id = c.id
GROUP BY c.id, c.name
ORDER BY news_count DESC, subscribers DESC, c.name;
