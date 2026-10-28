-- Избранное: пользователь видит и изменяет только собственные записи
ALTER TABLE public.favorite ENABLE ROW LEVEL SECURITY;
 
CREATE POLICY favorite_user_policy
ON public.favorite
FOR ALL
TO news_app
USING (
    user_id = NULLIF(
        current_setting('app.current_user_id', true), ''
    )::bigint
)
WITH CHECK (
    user_id = NULLIF(
        current_setting('app.current_user_id', true), ''
    )::bigint
);
 
-- Подписки на категории
ALTER TABLE public.subscription_category
    ENABLE ROW LEVEL SECURITY;
 
CREATE POLICY subscription_category_user_policy
ON public.subscription_category
FOR ALL
TO news_app
USING (
    user_id = NULLIF(
        current_setting('app.current_user_id', true), ''
    )::bigint
)
WITH CHECK (
    user_id = NULLIF(
        current_setting('app.current_user_id', true), ''
    )::bigint
);
 
-- Подписки на источники новостей
ALTER TABLE public.subscription_source
    ENABLE ROW LEVEL SECURITY;
 
CREATE POLICY subscription_source_user_policy
ON public.subscription_source
FOR ALL
TO news_app
USING (
    user_id = NULLIF(
        current_setting('app.current_user_id', true), ''
    )::bigint
)
WITH CHECK (
    user_id = NULLIF(
        current_setting('app.current_user_id', true), ''
    )::bigint
);