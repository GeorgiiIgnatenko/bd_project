BEGIN;

DROP TRIGGER IF EXISTS audit_log_no_truncate
    ON public.audit_log;

DROP TRIGGER IF EXISTS audit_log_no_update_delete
    ON public.audit_log;

DROP TRIGGER IF EXISTS audit_app_user
    ON public.app_user;

DROP TRIGGER IF EXISTS audit_news_source
    ON public.news_source;

DROP TRIGGER IF EXISTS audit_news
    ON public.news;

DROP TRIGGER IF EXISTS audit_favorite
    ON public.favorite;

DROP TRIGGER IF EXISTS audit_subscription_category
    ON public.subscription_category;

DROP TRIGGER IF EXISTS audit_subscription_source
    ON public.subscription_source;

DROP TRIGGER IF EXISTS audit_news_category
    ON public.news_category;

DROP FUNCTION IF EXISTS public.prevent_audit_log_mutation();
DROP FUNCTION IF EXISTS public.audit_row_change();

DROP TABLE IF EXISTS public.audit_log;

COMMIT;