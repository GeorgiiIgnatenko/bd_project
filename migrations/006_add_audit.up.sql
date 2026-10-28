CREATE TABLE public.audit_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    db_role TEXT NOT NULL,
    app_user_id BIGINT,
    table_schema TEXT NOT NULL,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL
        CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data JSONB,
    new_data JSONB
);
 
CREATE INDEX audit_log_changed_at_idx ON public.audit_log (changed_at);
CREATE INDEX audit_log_table_idx ON public.audit_log (table_name, changed_at);
 
REVOKE ALL ON public.audit_log FROM PUBLIC;
REVOKE ALL ON public.audit_log FROM news_app, news_analyst;
 
-- Запись аудита выполняется от имени владельца функции
CREATE OR REPLACE FUNCTION public.audit_row_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    old_row JSONB;
    new_row JSONB;
    actor_role TEXT;
    actor_user_id BIGINT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        new_row := to_jsonb(NEW);
 
        -- Хеш пароля не должен попадать в журнал и при регистрации
        IF TG_TABLE_NAME = 'app_user' THEN
            new_row := new_row - 'password_hash';
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        old_row := to_jsonb(OLD);
        new_row := to_jsonb(NEW);
 
        -- Не журналируем обновления без изменения данных
        IF old_row = new_row THEN
            RETURN NEW;
        END IF;
 
        -- Не сохраняем хеш пароля в журнале
        IF TG_TABLE_NAME = 'app_user' THEN
            old_row := old_row - 'password_hash';
            new_row := new_row - 'password_hash';
 
            IF OLD.password_hash IS DISTINCT FROM NEW.password_hash THEN
                new_row := new_row || '{"password_changed": true}'::jsonb;
            END IF;
        END IF;
    ELSE
        old_row := to_jsonb(OLD);
 
        IF TG_TABLE_NAME = 'app_user' THEN
            old_row := old_row - 'password_hash';
        END IF;
    END IF;
 
    actor_role := NULLIF(current_setting('role', true), 'none');
 
    IF actor_role IS NULL THEN
        actor_role := session_user;
    END IF;
 
    actor_user_id := NULLIF(
        current_setting('app.current_user_id', true), ''
    )::bigint;
 
    INSERT INTO public.audit_log (
        db_role,
        app_user_id,
        table_schema,
        table_name,
        operation,
        old_data,
        new_data
    )
    VALUES (
        actor_role,
        actor_user_id,
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        TG_OP,
        old_row,
        new_row
    );
 
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
 
    RETURN NEW;
END;
$$;
 
-- Не разрешаем приложению вызывать функцию напрямую
REVOKE ALL ON FUNCTION public.audit_row_change() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.audit_row_change()
    FROM news_app, news_analyst;
 
-- Фиксируем изменения критичных таблиц
CREATE TRIGGER audit_app_user
AFTER INSERT OR UPDATE OR DELETE ON public.app_user
FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
 
CREATE TRIGGER audit_news_source
AFTER INSERT OR UPDATE OR DELETE ON public.news_source
FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
 
CREATE TRIGGER audit_news
AFTER INSERT OR UPDATE OR DELETE ON public.news
FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
 
CREATE TRIGGER audit_favorite
AFTER INSERT OR UPDATE OR DELETE ON public.favorite
FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
 
CREATE TRIGGER audit_subscription_category
AFTER INSERT OR UPDATE OR DELETE ON public.subscription_category
FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
 
CREATE TRIGGER audit_subscription_source
AFTER INSERT OR UPDATE OR DELETE ON public.subscription_source
FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
 
CREATE TRIGGER audit_news_category
AFTER INSERT OR UPDATE OR DELETE ON public.news_category
FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
 
-- Читать журнал может администратор проекта
GRANT SELECT ON public.audit_log TO news_admin;
 
-- Защита журнала от изменения и удаления строк
CREATE OR REPLACE FUNCTION public.prevent_audit_log_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'audit_log is append-only';
END;
$$;
 
REVOKE ALL ON FUNCTION public.prevent_audit_log_mutation() FROM PUBLIC;
 
CREATE TRIGGER audit_log_no_update_delete
BEFORE UPDATE OR DELETE ON public.audit_log
FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_mutation();
 
CREATE TRIGGER audit_log_no_truncate
BEFORE TRUNCATE ON public.audit_log
FOR EACH STATEMENT EXECUTE FUNCTION public.prevent_audit_log_mutation();