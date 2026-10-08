-- ==============================================================================
-- Декларативное партицирование таблицы news по диапазону published_at (RANGE)
-- ==============================================================================

SET search_path TO dev, pg_catalog;

-- 1. Создаем партиционированную таблицу news_partitioned
DROP TABLE IF EXISTS news_category_part CASCADE;
DROP TABLE IF EXISTS news_partitioned CASCADE;

CREATE TABLE news_partitioned (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    source_id INT NOT NULL,
    canonical_url VARCHAR(500) NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    published_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (id, published_at),
    CONSTRAINT chk_news_part_title_not_blank CHECK (length(btrim(title)) > 0),
    CONSTRAINT chk_news_part_content_not_blank CHECK (length(btrim(content)) > 0),
    CONSTRAINT chk_news_part_url_not_blank CHECK (length(btrim(canonical_url)) > 0)
) PARTITION BY RANGE (published_at);

-- 2. Создаем партиции по временным диапазонам
-- Партиция для архива (до 2026 года)
CREATE TABLE news_part_archive PARTITION OF news_partitioned
    FOR VALUES FROM (MINVALUE) TO ('2026-01-01 00:00:00+00');

-- Партиция для 1-го полугодия 2026
CREATE TABLE news_part_2026_h1 PARTITION OF news_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

-- Партиция для 3-го квартала 2026 (июль - август)
CREATE TABLE news_part_2026_q3 PARTITION OF news_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');

-- Партиция за сентябрь 2026 (7-30 дней назад от 2026-10-01)
CREATE TABLE news_part_2026_09 PARTITION OF news_partitioned
    FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

-- Партиция за октябрь 2026 (текущий период / последние 7 дней)
CREATE TABLE news_part_2026_10 PARTITION OF news_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');

-- Партиция по умолчанию (для будущих дат)
CREATE TABLE news_part_default PARTITION OF news_partitioned DEFAULT;

-- 3. Создаем индексы на партиционированной таблице (автоматически создаются на всех партициях)
CREATE INDEX idx_news_part_published_at ON news_partitioned (published_at DESC);
CREATE INDEX idx_news_part_source_id ON news_partitioned (source_id);

-- 4. Переносим данные из dev.news в news_partitioned
INSERT INTO news_partitioned (id, source_id, canonical_url, title, content, published_at)
OVERRIDING SYSTEM VALUE
SELECT id, source_id, canonical_url, title, content, published_at
FROM dev.news;

-- Обновляем статистику планировщика
ANALYZE news_partitioned;

-- Проверяем распределение строк по партициям
SELECT 
    tableoid::regclass AS partition_name,
    COUNT(*) AS rows_count,
    MIN(published_at) AS min_date,
    MAX(published_at) AS max_date
FROM news_partitioned
GROUP BY tableoid::regclass
ORDER BY min_date NULLS LAST;
