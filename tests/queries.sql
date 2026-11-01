-- Adversarial cardinalities: empty categories, multiple subscribers/errors,
-- old/future timestamps. Everything is rolled back, including audit records.
-- scripts.verify expands @query from the canonical SQL, without copying queries.
\set ON_ERROR_STOP on
BEGIN;
\ir /workspace/tests/assertions.sql
\set as_of '2026-10-01 00:00:00+00'
\set days 7
\set window_days 30
\set min_failed_runs 2
\ir /workspace/sql/query_parameters.sql
INSERT INTO category(id, name) OVERRIDING SYSTEM VALUE
VALUES (-8101, 'query_empty'), (-8102, 'query_popular');
INSERT INTO news_source(id, name, url) OVERRIDING SYSTEM VALUE
VALUES (-8101, 'query_source', 'https://query.invalid/feed');
INSERT INTO news(id, source_id, canonical_url, title, content, published_at)
OVERRIDING SYSTEM VALUE VALUES
(-8101,-8101,'https://query.invalid/1','A','Text','2026-09-28+00'),
(-8102,-8101,'https://query.invalid/2','B','Text','2026-09-28+00'),
(-8103,-8101,'https://query.invalid/3','Old','Text','2025-01-01+00'),
(-8104,-8101,'https://query.invalid/4','Future','Text','2027-01-01+00');
INSERT INTO news_category VALUES (-8101,-8102),(-8102,-8102),(-8103,-8102),(-8104,-8102);
INSERT INTO subscription_category SELECT id, -8102 FROM app_user ORDER BY id LIMIT 2;
INSERT INTO scrape_run(id, source_id, started_at, status) OVERRIDING SYSTEM VALUE VALUES
(-8101,-8101,'2026-09-29+00','ошибка'),
(-8102,-8101,'2026-09-30+00','ошибка'),
(-8103,-8101,'2027-01-01+00','ошибка');
INSERT INTO scrape_error_log(scrape_run_id,error_message) VALUES (-8101,'first'),(-8101,'second');

CREATE TEMP TABLE q3_actual ON COMMIT DROP AS
-- @query q3_category_popularity.sql
SELECT check_that('Q3 aggregates news and subscribers independently',
  (SELECT news_count=2 AND subscribers=2 AND last_news_at='2026-09-28+00'::timestamptz
   FROM q3_actual WHERE id=-8102));
SELECT check_that('Q3 retains empty categories with zero counts',
  (SELECT news_count=0 AND subscribers=0 AND last_news_at IS NULL
   FROM q3_actual WHERE id=-8101));
CREATE TEMP TABLE q5_actual ON COMMIT DROP AS
-- @query q5_problem_sources.sql
SELECT check_that('Q5 counts failed runs, including runs without log rows, not error messages',
  (SELECT failed_runs=2 AND error_records=2 FROM q5_actual WHERE id=-8101));
CREATE TEMP TABLE q4_actual ON COMMIT DROP AS
-- @query q4_source_import_stats.sql
SELECT check_that('Q4 retains runs without items and excludes future runs',
  (SELECT runs=2 AND imported=0 AND duplicates=0 AND failed_items=0 FROM q4_actual WHERE id=-8101));
ROLLBACK;
