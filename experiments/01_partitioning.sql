-- Read-only experimental projection: identical data and indexes on both copies.
-- It is not a replacement for the news model: global canonical_url uniqueness
-- cannot be preserved by a simple UNIQUE on a date-partitioned table.
\set ON_ERROR_STOP on
BEGIN;
DROP SCHEMA IF EXISTS lab_partitioning CASCADE;
CREATE SCHEMA lab_partitioning;
CREATE TABLE lab_partitioning.news_heap (
    id bigint NOT NULL, title text NOT NULL, published_at timestamptz NOT NULL,
    PRIMARY KEY (id, published_at)
);
CREATE TABLE lab_partitioning.news_range (
    LIKE lab_partitioning.news_heap INCLUDING ALL
) PARTITION BY RANGE (published_at);
CREATE TABLE lab_partitioning.news_archive PARTITION OF lab_partitioning.news_range
    FOR VALUES FROM (MINVALUE) TO ('2026-09-01 00:00:00+00');
CREATE TABLE lab_partitioning.news_september PARTITION OF lab_partitioning.news_range
    FOR VALUES FROM ('2026-09-01 00:00:00+00') TO ('2026-09-24 00:00:00+00');
CREATE TABLE lab_partitioning.news_recent PARTITION OF lab_partitioning.news_range
    FOR VALUES FROM ('2026-09-24 00:00:00+00') TO ('2026-10-01 00:00:00+00');
CREATE TABLE lab_partitioning.news_other PARTITION OF lab_partitioning.news_range DEFAULT;
CREATE INDEX ON lab_partitioning.news_heap(published_at);
CREATE INDEX ON lab_partitioning.news_range(published_at);
INSERT INTO lab_partitioning.news_heap SELECT id, title, published_at FROM dev.news;
INSERT INTO lab_partitioning.news_range SELECT * FROM lab_partitioning.news_heap;
ANALYZE lab_partitioning.news_heap;
ANALYZE lab_partitioning.news_range;
COMMIT;
