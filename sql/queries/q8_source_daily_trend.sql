-- Q8: как меняется дневное число публикаций выбранного источника?
-- Параметры: source_id, as_of, window_days (положительное число полных суток).
-- Роль: news_analyst / news_admin. UTC-дата as_of исключена как неполный день.
-- Пустые дни = 0; накопительный итог начинается с первого дня периода.
-- Среднее: текущий и шесть предыдущих дней; в начале — только имеющиеся дни.
-- Неизвестный source_id даёт пустой результат.
WITH bounds AS (
    SELECT (:'as_of'::timestamptz AT TIME ZONE 'UTC')::date AS end_day
), daily_counts AS (
    SELECT (n.published_at AT TIME ZONE 'UTC')::date AS day, count(*) AS news_count
    FROM news n CROSS JOIN bounds b
    WHERE n.source_id = :source_id
      AND n.published_at >= ((b.end_day - :window_days)::timestamp AT TIME ZONE 'UTC')
      AND n.published_at < (b.end_day::timestamp AT TIME ZONE 'UTC')
    GROUP BY (n.published_at AT TIME ZONE 'UTC')::date
), calendar AS (
    SELECT b.end_day - :window_days + d.offset_day AS day
    FROM bounds b CROSS JOIN generate_series(0, :window_days - 1) AS d(offset_day)
)
SELECT s.id AS source_id, s.name AS source, c.day,
       coalesce(n.news_count, 0) AS news_count,
       sum(coalesce(n.news_count, 0)) OVER (
           ORDER BY c.day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS cumulative_news,
       round(avg(coalesce(n.news_count, 0)) OVER (
           ORDER BY c.day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS moving_avg_7_days
FROM news_source s CROSS JOIN calendar c
LEFT JOIN daily_counts n ON n.day = c.day
WHERE s.id = :source_id
ORDER BY c.day;
