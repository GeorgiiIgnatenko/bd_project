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

-- Лабораторная 5: равные места, точные границы, одновременные публикации,
-- пустые сутки и выход первого дня из семидневного окна.
\set window_days 8
\set top_ranks 2
\set page_size 1000
\set source_id -8201
INSERT INTO category(id, name, is_active) OVERRIDING SYSTEM VALUE VALUES
(-8201, 'window_main', true), (-8202, 'window_other', true),
(-8203, 'window_inactive', false);
INSERT INTO news_source(id, name, url) OVERRIDING SYSTEM VALUE VALUES
(-8201, 'window_a', 'https://window.invalid/a'),
(-8202, 'window_b', 'https://window.invalid/b'),
(-8203, 'window_c', 'https://window.invalid/c'),
(-8204, 'window_empty', 'https://window.invalid/empty');
INSERT INTO news(id, source_id, canonical_url, title, content, published_at)
OVERRIDING SYSTEM VALUE VALUES
(-8211, -8201, 'https://window.invalid/a1', 'A1', 'Text', '2026-09-23 00:00:00+00'),
(-8212, -8201, 'https://window.invalid/a2', 'A2', 'Text', '2026-09-24 01:00:00+00'),
(-8213, -8201, 'https://window.invalid/a3', 'A3', 'Text', '2026-09-24 01:00:00+00'),
(-8214, -8201, 'https://window.invalid/old', 'Old', 'Text', '2026-09-22 23:59:59.999999+00'),
(-8215, -8201, 'https://window.invalid/end', 'End', 'Text', '2026-10-01 00:00:00+00'),
(-8216, -8201, 'https://window.invalid/future', 'Future', 'Text', '2026-10-02 00:00:00+00'),
(-8221, -8202, 'https://window.invalid/b1', 'B1', 'Text', '2026-09-24 12:00:00+00'),
(-8222, -8202, 'https://window.invalid/b2', 'B2', 'Text', '2026-09-25 12:00:00+00'),
(-8223, -8202, 'https://window.invalid/b3', 'B3', 'Text', '2026-09-30 23:59:59.999999+00'),
(-8231, -8203, 'https://window.invalid/c1', 'C1', 'Text', '2026-09-25 12:00:00+00'),
(-8232, -8203, 'https://window.invalid/service', 'Service', 'Text', '2026-09-26 12:00:00+00');
INSERT INTO news_category VALUES
(-8211, -8201), (-8212, -8201), (-8213, -8201),
(-8214, -8201), (-8215, -8201), (-8216, -8201),
(-8221, -8201), (-8222, -8201), (-8223, -8201), (-8231, -8201),
(-8211, -8202), (-8221, -8202), (-8222, -8202), (-8211, -8203);
INSERT INTO news_category SELECT -8232, id FROM category WHERE name = 'Без категории';

CREATE TEMP TABLE q6_actual ON COMMIT DROP AS
-- @query q6_category_source_ranking.sql
CREATE TEMP TABLE q6_expected(category_id int, source_id int, news_count bigint, source_rank bigint)
ON COMMIT DROP;
INSERT INTO q6_expected VALUES
(-8201, -8201, 3, 1), (-8201, -8202, 3, 1), (-8201, -8203, 1, 2),
(-8202, -8202, 2, 1), (-8202, -8201, 1, 2);
SELECT check_that('Q6: равные места, независимые категории и границы периода', NOT EXISTS (
  (SELECT category_id, source_id, news_count, source_rank FROM q6_actual
   WHERE category_id IN (-8201, -8202) EXCEPT ALL TABLE q6_expected)
  UNION ALL
  (TABLE q6_expected EXCEPT ALL SELECT category_id, source_id, news_count, source_rank
   FROM q6_actual WHERE category_id IN (-8201, -8202))
));
SELECT check_that('Q6: архивная и служебная категории исключены', NOT EXISTS (
  SELECT 1 FROM q6_actual WHERE category_id = -8203 OR category = 'Без категории'
));
\set top_ranks 1
CREATE TEMP TABLE q6_first ON COMMIT DROP AS
-- @query q6_category_source_ranking.sql
SELECT check_that('Q6: первое место сохраняет оба равных источника',
  (SELECT count(*) = 2 AND bool_and(news_count = 3 AND source_rank = 1)
   FROM q6_first WHERE category_id = -8201));

CREATE TEMP TABLE q7_actual ON COMMIT DROP AS
-- @query q7_source_publication_gaps.sql
SELECT check_that('Q7: первая публикация не получает предшественника вне периода',
  (SELECT previous_published_at IS NULL AND publication_gap IS NULL
   FROM q7_actual WHERE id = -8211));
SELECT check_that('Q7: источники разделены, одинаковые даты упорядочены по ID',
  (SELECT previous_published_at = '2026-09-23+00'::timestamptz
          AND publication_gap = INTERVAL '25 hours' FROM q7_actual WHERE id = -8213)
  AND (SELECT publication_gap = INTERVAL '0 seconds' FROM q7_actual WHERE id = -8212)
  AND (SELECT previous_published_at IS NULL FROM q7_actual WHERE id = -8221));
SELECT check_that('Q7: обе границы периода соблюдены',
  (SELECT count(*) = 3 FROM q7_actual WHERE source_id = -8201)
  AND EXISTS (SELECT 1 FROM q7_actual WHERE id = -8223));
\set page_size 1
\set page_offset 1
CREATE TEMP TABLE q7_page ON COMMIT DROP AS
-- @query q7_source_publication_gaps.sql
SELECT check_that('Q7: пагинация после LAG сохраняет интервал и порядок',
  (SELECT count(*) = 1 AND bool_and(id = -8213 AND publication_gap = INTERVAL '25 hours')
   FROM q7_page));

CREATE TEMP TABLE q8_actual ON COMMIT DROP AS
-- @query q8_source_daily_trend.sql
CREATE TEMP TABLE q8_expected(day date, news_count bigint, cumulative_news numeric, moving_avg_7_days numeric)
ON COMMIT DROP;
INSERT INTO q8_expected VALUES
('2026-09-23', 1, 1, 1.00), ('2026-09-24', 2, 3, 1.50),
('2026-09-25', 0, 3, 1.00), ('2026-09-26', 0, 3, 0.75),
('2026-09-27', 0, 3, 0.60), ('2026-09-28', 0, 3, 0.50),
('2026-09-29', 0, 3, 0.43), ('2026-09-30', 0, 3, 0.29);
SELECT check_that('Q8: календарь, нули, накопительный итог и скользящее окно', NOT EXISTS (
  (SELECT day, news_count, cumulative_news, moving_avg_7_days FROM q8_actual
   EXCEPT ALL TABLE q8_expected)
  UNION ALL
  (TABLE q8_expected EXCEPT ALL SELECT day, news_count, cumulative_news, moving_avg_7_days
   FROM q8_actual)
));
SET LOCAL timezone TO 'America/Los_Angeles';
\set as_of '2026-10-01 12:00:00+00'
CREATE TEMP TABLE q8_timezone ON COMMIT DROP AS
-- @query q8_source_daily_trend.sql
SELECT check_that('Q8: независимость от часового пояса, неполные сутки исключены', NOT EXISTS (
  (TABLE q8_actual EXCEPT ALL TABLE q8_timezone)
  UNION ALL (TABLE q8_timezone EXCEPT ALL TABLE q8_actual)
));
\set source_id -8202
CREATE TEMP TABLE q8_other ON COMMIT DROP AS
-- @query q8_source_daily_trend.sql
SELECT check_that('Q8: другой источник и последняя микросекунда периода',
  (SELECT count(*) = 8 AND sum(news_count) = 3 FROM q8_other)
  AND (SELECT news_count = 1 AND cumulative_news = 3
       FROM q8_other WHERE day = '2026-09-30'));
\set source_id -8204
CREATE TEMP TABLE q8_empty ON COMMIT DROP AS
-- @query q8_source_daily_trend.sql
SELECT check_that('Q8: существующий источник без публикаций получает нулевой календарь',
  (SELECT count(*) = 8 AND bool_and(news_count = 0 AND cumulative_news = 0 AND moving_avg_7_days = 0)
   FROM q8_empty));
\set source_id -8299
CREATE TEMP TABLE q8_missing ON COMMIT DROP AS
-- @query q8_source_daily_trend.sql
SELECT check_that('Q8: неизвестный источник даёт пустой результат', NOT EXISTS (TABLE q8_missing));
ROLLBACK;
