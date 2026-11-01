-- Автотест RLS и аудита (КТ-04). Самодостаточный: сам создаёт
-- фикстуры с отрицательными id и в конце откатывает ВСЁ (ROLLBACK).

\set ON_ERROR_STOP on
\echo 'Тесты RLS и аудита'

BEGIN;

-- конфигурация
DO $$
DECLARE
    t text;
    r text;
BEGIN
    IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION
            'FAIL: запускайте тест от news_bootstrap (sh tests/run_security_tests.sh)';
    END IF;

    IF to_regclass('public.audit_log') IS NULL THEN
        RAISE EXCEPTION 'FAIL: нет public.audit_log, примените миграции 005 и 006';
    END IF;

    FOREACH r IN ARRAY ARRAY['news_admin', 'news_app', 'news_analyst'] LOOP
        IF EXISTS (
            SELECT 1 FROM pg_roles
            WHERE rolname = r AND (rolsuper OR rolbypassrls OR rolcreaterole)
        ) THEN
            RAISE EXCEPTION 'FAIL: у роли % есть лишние привилегии', r;
        END IF;
    END LOOP;
    RAISE NOTICE 'PASS: роли admin/app/analyst без SUPERUSER, BYPASSRLS, CREATEROLE';

    FOREACH t IN ARRAY ARRAY[
        'favorite', 'subscription_category', 'subscription_source'
    ] LOOP
        IF NOT (SELECT relrowsecurity FROM pg_class
                WHERE oid = format('public.%I', t)::regclass) THEN
            RAISE EXCEPTION 'FAIL: RLS не включён на %', t;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE schemaname = 'public' AND tablename = t
              AND 'news_app' = ANY (roles)
        ) THEN
            RAISE EXCEPTION 'FAIL: нет политики для news_app на %', t;
        END IF;
    END LOOP;
    RAISE NOTICE 'PASS: RLS включён и политики есть на favorite и подписках';

    FOREACH t IN ARRAY ARRAY[
        'app_user', 'news_source', 'news', 'favorite',
        'subscription_category', 'subscription_source', 'news_category'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger
            WHERE tgrelid = format('public.%I', t)::regclass
              AND tgname = 'audit_' || t AND NOT tgisinternal
        ) THEN
            RAISE EXCEPTION 'FAIL: нет аудит-триггера на %', t;
        END IF;
    END LOOP;
    RAISE NOTICE 'PASS: аудит-триггеры установлены на 7 таблицах';
END;
$$;

-- 1. Фикстуры

INSERT INTO public.role (id, name) OVERRIDING SYSTEM VALUE
VALUES (-9001, 'rls_test_role');

INSERT INTO public.app_user (id, role_id, email, password_hash)
OVERRIDING SYSTEM VALUE
VALUES
    (-9001, -9001, 'rls.a@test.invalid', 'scrypt$test$hash_a_secret'),
    (-9002, -9001, 'rls.b@test.invalid', 'scrypt$test$hash_b_secret');

INSERT INTO public.category (id, name) OVERRIDING SYSTEM VALUE
VALUES (-9001, 'rls_test_category');

INSERT INTO public.news_source (id, name, url, status) OVERRIDING SYSTEM VALUE
VALUES (-9001, 'rls test source', 'https://rls.test.invalid/rss', 'активен');

INSERT INTO public.news (id, source_id, canonical_url, title, content, published_at)
OVERRIDING SYSTEM VALUE
VALUES
    (-9001, -9001, 'https://rls.test.invalid/n1', 'rls n1', 'text', now()),
    (-9002, -9001, 'https://rls.test.invalid/n2', 'rls n2', 'text', now());

INSERT INTO public.favorite (user_id, news_id)
VALUES (-9001, -9001), (-9002, -9002);

INSERT INTO public.subscription_category (user_id, category_id)
VALUES (-9001, -9001), (-9002, -9001);

INSERT INTO public.subscription_source (user_id, source_id)
VALUES (-9001, -9001), (-9002, -9001);

-- 2. Аудит: регистрация пользователя не сохраняет хеш пароля
DO $$
DECLARE
    rec public.audit_log%ROWTYPE;
BEGIN
    SELECT * INTO rec
    FROM public.audit_log
    WHERE table_name = 'app_user' AND operation = 'INSERT'
      AND new_data ->> 'id' = '-9001'
    ORDER BY id DESC LIMIT 1;

    IF rec.id IS NULL THEN
        RAISE EXCEPTION 'FAIL: INSERT в app_user не попал в audit_log';
    END IF;
    IF rec.new_data ? 'password_hash' OR rec.new_data::text LIKE '%hash_a_secret%' THEN
        RAISE EXCEPTION 'FAIL: password_hash попал в audit_log при INSERT';
    END IF;
    IF rec.db_role <> session_user::text THEN
        RAISE EXCEPTION 'FAIL: db_role=%, ожидалось %', rec.db_role, session_user;
    END IF;
    RAISE NOTICE 'PASS: аудит INSERT app_user записан без хеша пароля';
END;
$$;

-- 3. RLS: news_app от имени пользователя A (-9001)
SELECT set_config('app.current_user_id', '-9001', true);
SET LOCAL ROLE news_app;

DO $$
DECLARE
    n bigint;
    affected bigint;
BEGIN
    -- Чтение: видны только строки A (все остальные скрыты политикой).
    SELECT count(*) INTO n FROM public.favorite;
    IF n <> 1 THEN
        RAISE EXCEPTION 'FAIL: A видит % строк favorite, ожидалась 1', n;
    END IF;
    SELECT count(*) INTO n FROM public.subscription_category;
    IF n <> 1 THEN
        RAISE EXCEPTION 'FAIL: A видит % строк subscription_category', n;
    END IF;
    SELECT count(*) INTO n FROM public.subscription_source;
    IF n <> 1 THEN
        RAISE EXCEPTION 'FAIL: A видит % строк subscription_source', n;
    END IF;
    SELECT count(*) INTO n FROM public.favorite WHERE user_id = -9002;
    IF n <> 0 THEN
        RAISE EXCEPTION 'FAIL: A видит избранное пользователя B';
    END IF;
    RAISE NOTICE 'PASS: RLS: A видит только свои favorite и подписки';

    -- Вставка чужой строки отклоняется политикой (WITH CHECK).
    BEGIN
        INSERT INTO public.favorite (user_id, news_id) VALUES (-9002, -9001);
        RAISE EXCEPTION 'FAIL: A смог добавить избранное от имени B';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: RLS: INSERT favorite от имени B отклонён (42501)';
    END;

    BEGIN
        INSERT INTO public.subscription_category (user_id, category_id)
        VALUES (-9002, -9001);
        RAISE EXCEPTION 'FAIL: A смог создать подписку от имени B';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: RLS: INSERT subscription_category от имени B отклонён (42501)';
    END;

    BEGIN
        INSERT INTO public.subscription_source (user_id, source_id)
        VALUES (-9002, -9001);
        RAISE EXCEPTION 'FAIL: A смог создать подписку на источник от имени B';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: RLS: INSERT subscription_source от имени B отклонён (42501)';
    END;

    -- UPDATE у приложения отсутствует в GRANT (вторая линия защиты).
    BEGIN
        UPDATE public.favorite SET news_id = news_id WHERE user_id = -9002;
        RAISE EXCEPTION 'FAIL: news_app неожиданно получил UPDATE на favorite';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: news_app не имеет права UPDATE на favorite (42501)';
    END;

    -- DELETE чужих строк: политика скрывает их, затронуто 0 строк.
    DELETE FROM public.favorite WHERE user_id = -9002;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 0 THEN
        RAISE EXCEPTION 'FAIL: A удалил % чужих строк favorite', affected;
    END IF;
    DELETE FROM public.subscription_category WHERE user_id = -9002;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 0 THEN
        RAISE EXCEPTION 'FAIL: A удалил чужие subscription_category';
    END IF;
    DELETE FROM public.subscription_source WHERE user_id = -9002;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 0 THEN
        RAISE EXCEPTION 'FAIL: A удалил чужие subscription_source';
    END IF;
    RAISE NOTICE 'PASS: RLS: DELETE чужих строк затрагивает 0 строк';

    -- Собственные операции разрешены (и попадут в аудит).
    INSERT INTO public.favorite (user_id, news_id) VALUES (-9001, -9002);
    SELECT count(*) INTO n FROM public.favorite;
    IF n <> 2 THEN
        RAISE EXCEPTION 'FAIL: собственный INSERT favorite не виден (%)', n;
    END IF;
    DELETE FROM public.favorite WHERE user_id = -9001 AND news_id = -9002;
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 1 THEN
        RAISE EXCEPTION 'FAIL: собственный DELETE favorite затронул % строк', affected;
    END IF;
    RAISE NOTICE 'PASS: RLS: собственные INSERT и DELETE разрешены';
END;
$$;

-- 4. RLS: без контекста пользователя приложение не видит ничего
SELECT set_config('app.current_user_id', '', true);

DO $$
DECLARE
    n bigint;
BEGIN
    SELECT count(*) INTO n FROM public.favorite;
    IF n <> 0 THEN
        RAISE EXCEPTION 'FAIL: без app.current_user_id видно % строк favorite', n;
    END IF;
    SELECT count(*) INTO n FROM public.subscription_category;
    IF n <> 0 THEN
        RAISE EXCEPTION 'FAIL: без контекста видны subscription_category';
    END IF;
    SELECT count(*) INTO n FROM public.subscription_source;
    IF n <> 0 THEN
        RAISE EXCEPTION 'FAIL: без контекста видны subscription_source';
    END IF;
    BEGIN
        INSERT INTO public.favorite (user_id, news_id) VALUES (-9001, -9002);
        RAISE EXCEPTION 'FAIL: INSERT без контекста пользователя разрешён';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    RAISE NOTICE 'PASS: RLS: без app.current_user_id данных не видно, INSERT отклонён';
END;
$$;

-- 5. news_app: журнал аудита недоступен
DO $$
DECLARE
    stmt text;
BEGIN
    FOREACH stmt IN ARRAY ARRAY[
        'SELECT count(*) FROM public.audit_log',
        'INSERT INTO public.audit_log (db_role, table_schema, table_name, operation) VALUES (''x'', ''x'', ''x'', ''INSERT'')',
        'UPDATE public.audit_log SET db_role = db_role',
        'DELETE FROM public.audit_log',
        'TRUNCATE public.audit_log',
        'SELECT public.audit_row_change()'
    ] LOOP
        BEGIN
            EXECUTE stmt;
            RAISE EXCEPTION 'FAIL: news_app выполнил: %', stmt;
        EXCEPTION WHEN insufficient_privilege THEN
            NULL;
        END;
    END LOOP;
    RAISE NOTICE 'PASS: news_app не может читать, менять журнал и вызывать функцию аудита';
END;
$$;

-- 6. news_analyst: нет доступа к персональным данным и журналу
RESET ROLE;
SET LOCAL ROLE news_analyst;

DO $$
DECLARE
    stmt text;
    n bigint;
BEGIN
    SELECT count(*) INTO n FROM public.news;  -- публичный контент доступен

    FOREACH stmt IN ARRAY ARRAY[
        'SELECT count(*) FROM public.favorite',
        'SELECT count(*) FROM public.subscription_category',
        'SELECT count(*) FROM public.subscription_source',
        'SELECT password_hash FROM public.app_user',
        'SELECT count(*) FROM public.audit_log',
        'INSERT INTO public.category (name) VALUES (''rls_forbidden'')'
    ] LOOP
        BEGIN
            EXECUTE stmt;
            RAISE EXCEPTION 'FAIL: news_analyst выполнил: %', stmt;
        EXCEPTION WHEN insufficient_privilege THEN
            NULL;
        END;
    END LOOP;
    RAISE NOTICE 'PASS: news_analyst читает новости, но не персональные данные и аудит';
END;
$$;

-- 7. Администратор: действие попадает в аудит под ролью news_admin,
--    журнал защищён от изменения
RESET ROLE;
SET LOCAL ROLE news_admin;

UPDATE public.news_source SET status = 'неактивен' WHERE id = -9001;

DO $$
DECLARE
    stmt text;
    n bigint;
BEGIN
    SELECT count(*) INTO n FROM public.audit_log;
    IF n = 0 THEN
        RAISE EXCEPTION 'FAIL: news_admin не видит журнал аудита';
    END IF;

    FOREACH stmt IN ARRAY ARRAY[
        'UPDATE public.audit_log SET db_role = db_role',
        'DELETE FROM public.audit_log',
        'TRUNCATE public.audit_log'
    ] LOOP
        BEGIN
            EXECUTE stmt;
            RAISE EXCEPTION 'FAIL: news_admin изменил журнал: %', stmt;
        EXCEPTION
            WHEN insufficient_privilege THEN
                NULL;
            WHEN raise_exception THEN
                IF SQLERRM NOT LIKE '%append-only%' THEN
                    RAISE;
                END IF;
        END;
    END LOOP;
    RAISE NOTICE 'PASS: news_admin читает журнал, но не может изменить или очистить его';
END;
$$;

-- 8. Проверка журнала от суперпользователя
RESET ROLE;

DO $$
DECLARE
    n bigint;
    rec public.audit_log%ROWTYPE;
BEGIN
    -- Чужие данные не пострадали от действий A.
    SELECT count(*) INTO n FROM public.favorite WHERE user_id = -9002;
    IF n <> 1 THEN
        RAISE EXCEPTION 'FAIL: избранное B изменено (строк: %)', n;
    END IF;
    SELECT count(*) INTO n FROM public.subscription_category WHERE user_id = -9002;
    IF n <> 1 THEN
        RAISE EXCEPTION 'FAIL: подписки B изменены';
    END IF;
    RAISE NOTICE 'PASS: данные пользователя B после действий A не изменились';

    -- Операции приложения записаны с ролью и id пользователя.
    IF NOT EXISTS (
        SELECT 1 FROM public.audit_log
        WHERE table_name = 'favorite' AND operation = 'INSERT'
          AND db_role = 'news_app' AND app_user_id = -9001
          AND new_data ->> 'user_id' = '-9001' AND new_data ->> 'news_id' = '-9002'
    ) THEN
        RAISE EXCEPTION 'FAIL: INSERT favorite от news_app не найден в аудите';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.audit_log
        WHERE table_name = 'favorite' AND operation = 'DELETE'
          AND db_role = 'news_app' AND app_user_id = -9001
          AND old_data ->> 'user_id' = '-9001' AND old_data ->> 'news_id' = '-9002'
    ) THEN
        RAISE EXCEPTION 'FAIL: DELETE favorite от news_app не найден в аудите';
    END IF;
    RAISE NOTICE 'PASS: аудит: операции news_app записаны с db_role и app_user_id';

    -- Отклонённые попытки (чужие данные) в журнал не попадают.
    IF EXISTS (
        SELECT 1 FROM public.audit_log
        WHERE db_role = 'news_app' AND table_name = 'favorite'
          AND COALESCE(new_data, old_data) ->> 'user_id' = '-9002'
    ) THEN
        RAISE EXCEPTION 'FAIL: отклонённая попытка попала в аудит как выполненная';
    END IF;
    RAISE NOTICE 'PASS: аудит: отклонённые RLS-попытки не записаны как выполненные';

    -- Действие администратора записано под news_admin.
    SELECT * INTO rec FROM public.audit_log
    WHERE table_name = 'news_source' AND operation = 'UPDATE'
      AND new_data ->> 'id' = '-9001' AND db_role = 'news_admin'
    ORDER BY id DESC LIMIT 1;
    IF rec.id IS NULL
       OR rec.old_data ->> 'status' <> 'активен'
       OR rec.new_data ->> 'status' <> 'неактивен' THEN
        RAISE EXCEPTION 'FAIL: UPDATE news_source от news_admin записан неверно';
    END IF;
    RAISE NOTICE 'PASS: аудит: UPDATE news_source записан под news_admin со старым и новым значением';
END;
$$;

-- Журнал защищён триггерами даже от суперпользователя.
DO $$
DECLARE
    stmt text;
BEGIN
    FOREACH stmt IN ARRAY ARRAY[
        'UPDATE public.audit_log SET db_role = db_role',
        'DELETE FROM public.audit_log',
        'TRUNCATE public.audit_log'
    ] LOOP
        BEGIN
            EXECUTE stmt;
            RAISE EXCEPTION 'FAIL: журнал изменён: %', stmt;
        EXCEPTION WHEN raise_exception THEN
            IF SQLERRM NOT LIKE '%append-only%' THEN
                RAISE;
            END IF;
        END;
    END LOOP;
    RAISE NOTICE 'PASS: audit_log append-only: UPDATE, DELETE, TRUNCATE заблокированы триггерами';
END;
$$;


-- 9. Аудит app_user: смена пароля, обычное изменение, no-op, удаление
SELECT set_config('app.current_user_id', '-9002', true);

UPDATE public.app_user
SET password_hash = 'scrypt$test$new_hash_secret'
WHERE id = -9001;

DO $$
DECLARE
    rec public.audit_log%ROWTYPE;
BEGIN
    SELECT * INTO rec FROM public.audit_log
    WHERE table_name = 'app_user' AND operation = 'UPDATE'
      AND new_data ->> 'id' = '-9001'
    ORDER BY id DESC LIMIT 1;

    IF rec.id IS NULL THEN
        RAISE EXCEPTION 'FAIL: смена пароля не попала в аудит';
    END IF;
    IF rec.old_data ? 'password_hash' OR rec.new_data ? 'password_hash'
       OR rec.old_data::text LIKE '%secret%' OR rec.new_data::text LIKE '%secret%' THEN
        RAISE EXCEPTION 'FAIL: хеш пароля попал в audit_log при UPDATE';
    END IF;
    IF rec.new_data ->> 'password_changed' IS DISTINCT FROM 'true' THEN
        RAISE EXCEPTION 'FAIL: нет признака password_changed';
    END IF;
    IF rec.app_user_id IS DISTINCT FROM -9002 THEN
        RAISE EXCEPTION 'FAIL: app_user_id актора записан неверно (%)', rec.app_user_id;
    END IF;
    RAISE NOTICE 'PASS: аудит: смена пароля без хеша, с признаком password_changed и актором';
END;
$$;

UPDATE public.app_user SET email = 'rls.a2@test.invalid' WHERE id = -9001;

DO $$
DECLARE
    before_n bigint;
    after_n bigint;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.audit_log
        WHERE table_name = 'app_user' AND operation = 'UPDATE'
          AND old_data ->> 'email' = 'rls.a@test.invalid'
          AND new_data ->> 'email' = 'rls.a2@test.invalid'
    ) THEN
        RAISE EXCEPTION 'FAIL: смена email не записана со старым и новым значением';
    END IF;
    RAISE NOTICE 'PASS: аудит: смена email записана со старым и новым значением';

    SELECT count(*) INTO before_n FROM public.audit_log
    WHERE table_name = 'app_user' AND COALESCE(new_data, old_data) ->> 'id' = '-9001';

    UPDATE public.app_user SET email = email WHERE id = -9001;

    SELECT count(*) INTO after_n FROM public.audit_log
    WHERE table_name = 'app_user' AND COALESCE(new_data, old_data) ->> 'id' = '-9001';

    IF after_n <> before_n THEN
        RAISE EXCEPTION 'FAIL: UPDATE без изменений попал в аудит';
    END IF;
    RAISE NOTICE 'PASS: аудит: UPDATE без изменения данных не журналируется';
END;
$$;

DELETE FROM public.app_user WHERE id = -9002;

DO $$
DECLARE
    rec public.audit_log%ROWTYPE;
BEGIN
    SELECT * INTO rec FROM public.audit_log
    WHERE table_name = 'app_user' AND operation = 'DELETE'
      AND old_data ->> 'id' = '-9002'
    ORDER BY id DESC LIMIT 1;

    IF rec.id IS NULL THEN
        RAISE EXCEPTION 'FAIL: удаление пользователя не попало в аудит';
    END IF;
    IF rec.old_data ? 'password_hash' OR rec.old_data::text LIKE '%secret%' THEN
        RAISE EXCEPTION 'FAIL: хеш пароля попал в audit_log при DELETE';
    END IF;
    IF rec.old_data ->> 'email' <> 'rls.b@test.invalid' THEN
        RAISE EXCEPTION 'FAIL: в old_data нет email удалённого пользователя';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.audit_log
        WHERE table_name = 'favorite' AND operation = 'DELETE'
          AND old_data ->> 'user_id' = '-9002'
    ) THEN
        RAISE EXCEPTION 'FAIL: каскадное удаление favorite не попало в аудит';
    END IF;
    RAISE NOTICE 'PASS: аудит: удаление пользователя и каскад записаны без хеша пароля';
END;
$$;

DO $$
BEGIN
    RAISE NOTICE 'ALL SECURITY TESTS PASSED';
END;
$$;

-- Все фикстуры и записи аудита откатываются.
ROLLBACK;
\echo '== Транзакция откатана: данные и журнал не изменены =='