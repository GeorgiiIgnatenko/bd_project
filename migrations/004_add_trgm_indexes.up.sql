CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_news_title_trgm
ON news USING gin (title gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_news_content_trgm
ON news USING gin (content gin_trgm_ops);
