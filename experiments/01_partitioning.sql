-- ==============================================================================
-- 1. ДЕКЛАРАТИВНОЕ ПАРТИЦИРОВАНИЕ ТАБЛИЦЫ NEWS (RANGE по published_at)
-- ==============================================================================

SET search_path TO dev, pg_catalog;

-- Создание партиционированной таблицы
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

-- Создание партиций по временным интервалам
CREATE TABLE news_part_archive PARTITION OF news_partitioned
    FOR VALUES FROM (MINVALUE) TO ('2026-01-01 00:00:00+00');

CREATE TABLE news_part_2026_h1 PARTITION OF news_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE news_part_2026_q3 PARTITION OF news_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');

CREATE TABLE news_part_2026_09 PARTITION OF news_partitioned
    FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

CREATE TABLE news_part_2026_10 PARTITION OF news_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');

CREATE TABLE news_part_default PARTITION OF news_partitioned DEFAULT;

-- Индексы на партиционированной таблице
CREATE INDEX idx_news_part_published_at ON news_partitioned (published_at DESC);
CREATE INDEX idx_news_part_source_id ON news_partitioned (source_id);

-- Перенос данных
INSERT INTO news_partitioned (id, source_id, canonical_url, title, content, published_at)
OVERRIDING SYSTEM VALUE
SELECT id, source_id, canonical_url, title, content, published_at
FROM dev.news;

ANALYZE news_partitioned;

-- Проверка Partition Pruning (запрос диапазона 2026-09-24 .. 2026-10-01)
-- 1. На непартиционированной таблице:
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, published_at
FROM dev.news
WHERE published_at >= '2026-09-24 00:00:00+00' AND published_at < '2026-10-01 00:00:00+00'
ORDER BY published_at DESC;

-- 2. На партиционированной таблице (сканируется только news_part_2026_09):
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, published_at
FROM dev.news_partitioned
WHERE published_at >= '2026-09-24 00:00:00+00' AND published_at < '2026-10-01 00:00:00+00'
ORDER BY published_at DESC;
