-- Ошибка на втором шаге откатывает весь импорт. Запускать после demo seed.
\set ON_ERROR_STOP on
SELECT count(*) AS runs_before FROM scrape_run \gset
BEGIN;
INSERT INTO scrape_run (source_id, status)
VALUES ((SELECT id FROM news_source WHERE url = 'https://globalnews.example/feed'), 'запущен');
-- Только ожидаемая ошибка исполняется с ON_ERROR_STOP=off.
\set ON_ERROR_STOP off
INSERT INTO news (source_id, canonical_url, title, content, published_at)
VALUES (NULL, 'https://x.example/rollback', 't', 'c', now());
\set failure_state :SQLSTATE
\set ON_ERROR_STOP on
ROLLBACK;
SELECT :'failure_state' = '23502' AND count(*) = :runs_before AS rollback_ok
FROM scrape_run \gset
\if :rollback_ok
  \echo 'PASS: expected NOT NULL failure; the preceding scrape_run rolled back'
\else
  \echo 'FAIL: unexpected SQLSTATE or partial import survived rollback'
  \quit 1
\endif
