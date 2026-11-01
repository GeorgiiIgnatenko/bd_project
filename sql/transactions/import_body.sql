-- Общий импорт демо-публикации; вызывающий сценарий управляет BEGIN/COMMIT.
-- Требуется seed. Используется также двумя сессиями конкурентного теста.
DO $$
DECLARE
    v_source_id integer;
    v_run_id bigint;
    v_news_id bigint;
    v_category_id integer;
BEGIN
    SELECT id INTO STRICT v_source_id
    FROM news_source WHERE url = 'https://globalnews.example/feed';

    INSERT INTO scrape_run (source_id, status)
    VALUES (v_source_id, 'запущен') RETURNING id INTO v_run_id;

    INSERT INTO news (source_id, canonical_url, title, content, published_at)
    VALUES (v_source_id, 'https://globalnews.example/news/climate-report',
            'Доклад о климате: ключевые выводы',
            'Эксперты представили новый климатический доклад...',
            now() - INTERVAL '10 minutes')
    ON CONFLICT (canonical_url) DO NOTHING
    RETURNING id INTO v_news_id;

    IF v_news_id IS NULL THEN
        INSERT INTO import_result (scrape_run_id, status)
        VALUES (v_run_id, 'дубликат');
    ELSE
        SELECT id INTO v_category_id FROM category
        WHERE name = 'Экономика' AND is_active;
        IF v_category_id IS NULL THEN
            SELECT id INTO STRICT v_category_id FROM category
            WHERE name = 'Без категории' AND is_active;
        END IF;
        INSERT INTO news_category (news_id, category_id)
        VALUES (v_news_id, v_category_id);
        INSERT INTO import_result (scrape_run_id, news_id, status)
        VALUES (v_run_id, v_news_id, 'успех');
    END IF;

    UPDATE scrape_run SET status = 'завершен' WHERE id = v_run_id;
    -- Успешный импорт не снимает ручное отключение источника.
    UPDATE news_source SET status = 'активен'
    WHERE id = v_source_id AND status = 'ошибка подключения';
END;
$$;
