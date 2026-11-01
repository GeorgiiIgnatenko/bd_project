-- q1 
-- Персонализированная лента пользователя (SC-03, БП-8, БП-9)
-- Бизнес-вопрос: какие новости показать пользователю, чтобы подписанные шли
--      первым блоком, остальные вторым, оба блока по дате (новые сверху)?
-- Параметры: user_id, window_days (окно актуальности, 30),
--            page_size (20), page_offset (0)
-- user_id задаётся вызывающим кодом; контекст RLS устанавливается через SET LOCAL.
SELECT n.id,
    n.title,
    s.name AS source,
    n.published_at,
    (
        -- подписка на источник не даёт приоритета, если источник отключён
        EXISTS (
            SELECT 1
            FROM subscription_source ss
            WHERE ss.user_id = :user_id
                AND ss.source_id = n.source_id
                AND s.status NOT IN ('неактивен', 'отключён вручную')
        )
        OR -- подписка на категорию: категория активна и не служебная
        EXISTS (
            SELECT 1
            FROM news_category nc
                JOIN subscription_category sc ON sc.category_id = nc.category_id
                JOIN category c ON c.id = nc.category_id
            WHERE nc.news_id = n.id
                AND sc.user_id = :user_id
                AND c.is_active
                AND c.name <> 'Без категории'
        )
    ) AS is_priority
FROM news n
    JOIN news_source s ON s.id = n.source_id
WHERE n.published_at >= :'as_of'::timestamptz - (:window_days * INTERVAL '1 day')
  AND n.published_at < :'as_of'::timestamptz
ORDER BY is_priority DESC,
    n.published_at DESC, n.id DESC
LIMIT :page_size OFFSET :page_offset;
