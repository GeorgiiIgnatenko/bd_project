BEGIN;

DROP POLICY IF EXISTS favorite_user_policy
    ON public.favorite;

ALTER TABLE public.favorite
    DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscription_category_user_policy
    ON public.subscription_category;

ALTER TABLE public.subscription_category
    DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subscription_source_user_policy
    ON public.subscription_source;

ALTER TABLE public.subscription_source
    DISABLE ROW LEVEL SECURITY;

COMMIT;