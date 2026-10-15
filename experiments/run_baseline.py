import subprocess
import json
import os

DB_CONFIG = {
    'host': '127.0.0.1',
    'port': '55432',
    'user': 'news_app',
    'dbname': 'news_aggregator',
    'password': 'news_local_password'
}

QUERIES = {
    'Q1': {
        'name': 'Персонализированная лента пользователя (SC-03)',
        'data_sql': """
SET search_path TO dev, pg_catalog;
SELECT n.id,
    n.title,
    s.name AS source,
    n.published_at,
    (
        EXISTS (
            SELECT 1
            FROM subscription_source ss
            WHERE ss.user_id = 1
                AND ss.source_id = n.source_id
                AND s.status NOT IN ('неактивен', 'отключён вручную')
        )
        OR
        EXISTS (
            SELECT 1
            FROM news_category nc
                JOIN subscription_category sc ON sc.category_id = nc.category_id
                JOIN category c ON c.id = nc.category_id
            WHERE nc.news_id = n.id
                AND sc.user_id = 1
                AND c.is_active
                AND c.name <> 'Без категории'
        )
    ) AS is_priority
FROM news n
    JOIN news_source s ON s.id = n.source_id
WHERE n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
ORDER BY is_priority DESC,
    n.published_at DESC
LIMIT 5 OFFSET 0;
""",
        'explain_sql': """
SET search_path TO dev, pg_catalog;
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT n.id,
    n.title,
    s.name AS source,
    n.published_at,
    (
        EXISTS (
            SELECT 1
            FROM subscription_source ss
            WHERE ss.user_id = 1
                AND ss.source_id = n.source_id
                AND s.status NOT IN ('неактивен', 'отключён вручную')
        )
        OR
        EXISTS (
            SELECT 1
            FROM news_category nc
                JOIN subscription_category sc ON sc.category_id = nc.category_id
                JOIN category c ON c.id = nc.category_id
            WHERE nc.news_id = n.id
                AND sc.user_id = 1
                AND c.is_active
                AND c.name <> 'Без категории'
        )
    ) AS is_priority
FROM news n
    JOIN news_source s ON s.id = n.source_id
WHERE n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
ORDER BY is_priority DESC,
    n.published_at DESC
LIMIT 20 OFFSET 0;
""",
        'explain_text_sql': """
SET search_path TO dev, pg_catalog;
EXPLAIN (ANALYZE, BUFFERS)
SELECT n.id,
    n.title,
    s.name AS source,
    n.published_at,
    (
        EXISTS (
            SELECT 1
            FROM subscription_source ss
            WHERE ss.user_id = 1
                AND ss.source_id = n.source_id
                AND s.status NOT IN ('неактивен', 'отключён вручную')
        )
        OR
        EXISTS (
            SELECT 1
            FROM news_category nc
                JOIN subscription_category sc ON sc.category_id = nc.category_id
                JOIN category c ON c.id = nc.category_id
            WHERE nc.news_id = n.id
                AND sc.user_id = 1
                AND c.is_active
                AND c.name <> 'Без категории'
        )
    ) AS is_priority
FROM news n
    JOIN news_source s ON s.id = n.source_id
WHERE n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
ORDER BY is_priority DESC,
    n.published_at DESC
LIMIT 20 OFFSET 0;
"""
    },
    'Q2': {
        'name': 'Поиск новостей по ключевому слову с фильтром по категории (SC-02)',
        'data_sql': """
SET search_path TO dev, pg_catalog;
SELECT n.id,
       n.title,
       s.name AS source,
       c.name AS category,
       n.published_at
FROM news n
JOIN news_source s    ON s.id = n.source_id
JOIN news_category nc ON nc.news_id = n.id
JOIN category c       ON c.id = nc.category_id
WHERE c.name = 'Спорт'
  AND (n.title   ILIKE '%спорт%'
    OR n.content ILIKE '%спорт%')
ORDER BY n.published_at DESC
LIMIT 5;
""",
        'explain_sql': """
SET search_path TO dev, pg_catalog;
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT n.id,
       n.title,
       s.name AS source,
       c.name AS category,
       n.published_at
FROM news n
JOIN news_source s    ON s.id = n.source_id
JOIN news_category nc ON nc.news_id = n.id
JOIN category c       ON c.id = nc.category_id
WHERE c.name = 'Спорт'
  AND (n.title   ILIKE '%спорт%'
    OR n.content ILIKE '%спорт%')
ORDER BY n.published_at DESC
LIMIT 20;
""",
        'explain_text_sql': """
SET search_path TO dev, pg_catalog;
EXPLAIN (ANALYZE, BUFFERS)
SELECT n.id,
       n.title,
       s.name AS source,
       c.name AS category,
       n.published_at
FROM news n
JOIN news_source s    ON s.id = n.source_id
JOIN news_category nc ON nc.news_id = n.id
JOIN category c       ON c.id = nc.category_id
WHERE c.name = 'Спорт'
  AND (n.title   ILIKE '%спорт%'
    OR n.content ILIKE '%спорт%')
ORDER BY n.published_at DESC
LIMIT 20;
"""
    },
    'Q3': {
        'name': 'Популярность категорий (SC-02, SC-07)',
        'data_sql': """
SET search_path TO dev, pg_catalog;
SELECT c.id,
       c.name,
       COUNT(DISTINCT n.id)       AS news_count,
       COUNT(DISTINCT sc.user_id) AS subscribers,
       MAX(n.published_at)        AS last_news_at
FROM category c
LEFT JOIN news_category nc        ON nc.category_id = c.id
LEFT JOIN news n                  ON n.id = nc.news_id
                                 AND n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
LEFT JOIN subscription_category sc ON sc.category_id = c.id
GROUP BY c.id, c.name
ORDER BY news_count DESC, subscribers DESC, c.name;
""",
        'explain_sql': """
SET search_path TO dev, pg_catalog;
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT c.id,
       c.name,
       COUNT(DISTINCT n.id)       AS news_count,
       COUNT(DISTINCT sc.user_id) AS subscribers,
       MAX(n.published_at)        AS last_news_at
FROM category c
LEFT JOIN news_category nc        ON nc.category_id = c.id
LEFT JOIN news n                  ON n.id = nc.news_id
                                 AND n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
LEFT JOIN subscription_category sc ON sc.category_id = c.id
GROUP BY c.id, c.name
ORDER BY news_count DESC, subscribers DESC, c.name;
""",
        'explain_text_sql': """
SET search_path TO dev, pg_catalog;
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id,
       c.name,
       COUNT(DISTINCT n.id)       AS news_count,
       COUNT(DISTINCT sc.user_id) AS subscribers,
       MAX(n.published_at)        AS last_news_at
FROM category c
LEFT JOIN news_category nc        ON nc.category_id = c.id
LEFT JOIN news n                  ON n.id = nc.news_id
                                 AND n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
LEFT JOIN subscription_category sc ON sc.category_id = c.id
GROUP BY c.id, c.name
ORDER BY news_count DESC, subscribers DESC, c.name;
"""
    },
    'Q4': {
        'name': 'Статистика сбора по источникам (SC-05, SC-06)',
        'data_sql': """
SET search_path TO dev, pg_catalog;
SELECT s.id,
       s.name,
       s.status,
       COUNT(DISTINCT r.id)                               AS runs,
       COUNT(ir.id) FILTER (WHERE ir.status = 'успех')    AS imported,
       COUNT(ir.id) FILTER (WHERE ir.status = 'дубликат') AS duplicates,
       COUNT(ir.id) FILTER (WHERE ir.status = 'ошибка')   AS failed_items
FROM news_source s
LEFT JOIN scrape_run r     ON r.source_id = s.id
                          AND r.started_at >= '2026-01-01'
LEFT JOIN import_result ir ON ir.scrape_run_id = r.id
GROUP BY s.id, s.name, s.status
ORDER BY s.id
LIMIT 5;
""",
        'explain_sql': """
SET search_path TO dev, pg_catalog;
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT s.id,
       s.name,
       s.status,
       COUNT(DISTINCT r.id)                               AS runs,
       COUNT(ir.id) FILTER (WHERE ir.status = 'успех')    AS imported,
       COUNT(ir.id) FILTER (WHERE ir.status = 'дубликат') AS duplicates,
       COUNT(ir.id) FILTER (WHERE ir.status = 'ошибка')   AS failed_items
FROM news_source s
LEFT JOIN scrape_run r     ON r.source_id = s.id
                          AND r.started_at >= '2026-01-01'
LEFT JOIN import_result ir ON ir.scrape_run_id = r.id
GROUP BY s.id, s.name, s.status
ORDER BY s.id;
""",
        'explain_text_sql': """
SET search_path TO dev, pg_catalog;
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.id,
       s.name,
       s.status,
       COUNT(DISTINCT r.id)                               AS runs,
       COUNT(ir.id) FILTER (WHERE ir.status = 'успех')    AS imported,
       COUNT(ir.id) FILTER (WHERE ir.status = 'дубликат') AS duplicates,
       COUNT(ir.id) FILTER (WHERE ir.status = 'ошибка')   AS failed_items
FROM news_source s
LEFT JOIN scrape_run r     ON r.source_id = s.id
                          AND r.started_at >= '2026-01-01'
LEFT JOIN import_result ir ON ir.scrape_run_id = r.id
GROUP BY s.id, s.name, s.status
ORDER BY s.id;
"""
    },
    'Q5': {
        'name': 'Проблемные источники (HAVING) (SC-06, БП-7)',
        'data_sql': """
SET search_path TO dev, pg_catalog;
SELECT s.id,
       s.name,
       s.status,
       COUNT(DISTINCT r.id) AS failed_runs,
       COUNT(e.id)          AS error_records,
       MAX(e.created_at)    AS last_error_at
FROM news_source s
JOIN scrape_run r            ON r.source_id = s.id
                            AND r.status = 'ошибка'
                            AND r.started_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (7 * INTERVAL '1 day')
LEFT JOIN scrape_error_log e ON e.scrape_run_id = r.id
GROUP BY s.id, s.name, s.status
HAVING COUNT(DISTINCT r.id) >= 1
ORDER BY failed_runs DESC, s.id;
""",
        'explain_sql': """
SET search_path TO dev, pg_catalog;
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT s.id,
       s.name,
       s.status,
       COUNT(DISTINCT r.id) AS failed_runs,
       COUNT(e.id)          AS error_records,
       MAX(e.created_at)    AS last_error_at
FROM news_source s
JOIN scrape_run r            ON r.source_id = s.id
                            AND r.status = 'ошибка'
                            AND r.started_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (7 * INTERVAL '1 day')
LEFT JOIN scrape_error_log e ON e.scrape_run_id = r.id
GROUP BY s.id, s.name, s.status
HAVING COUNT(DISTINCT r.id) >= 1
ORDER BY failed_runs DESC, s.id;
""",
        'explain_text_sql': """
SET search_path TO dev, pg_catalog;
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.id,
       s.name,
       s.status,
       COUNT(DISTINCT r.id) AS failed_runs,
       COUNT(e.id)          AS error_records,
       MAX(e.created_at)    AS last_error_at
FROM news_source s
JOIN scrape_run r            ON r.source_id = s.id
                            AND r.status = 'ошибка'
                            AND r.started_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (7 * INTERVAL '1 day')
LEFT JOIN scrape_error_log e ON e.scrape_run_id = r.id
GROUP BY s.id, s.name, s.status
HAVING COUNT(DISTINCT r.id) >= 1
ORDER BY failed_runs DESC, s.id;
"""
    }
}

def run_psql(sql):
    env = os.environ.copy()
    env['PGPASSWORD'] = DB_CONFIG['password']
    env['PAGER'] = 'cat'
    res = subprocess.run([
        'psql', '-h', DB_CONFIG['host'], '-p', DB_CONFIG['port'],
        '-U', DB_CONFIG['user'], '-d', DB_CONFIG['dbname'],
        '-X', '-P', 'pager=off', '-c', sql
    ], capture_output=True, text=True, env=env)
    return res.stdout, res.stderr

def main():
    report = []
    summary_data = []

    for q_id, q_info in QUERIES.items():
        print(f"Running {q_id}: {q_info['name']}...")
        data_out, data_err = run_psql(q_info['data_sql'])
        plan_out, plan_err = run_psql(q_info['explain_text_sql'])
        
        # Get JSON plan for exact metrics
        json_out, _ = run_psql(q_info['explain_sql'])
        exec_time = "N/A"
        cost = "N/A"
        shared_hit = "N/A"
        try:
            # find start of JSON
            start = json_out.find('[')
            end = json_out.rfind(']') + 1
            if start != -1 and end != -1:
                plan_json = json.loads(json_out[start:end])
                root = plan_json[0]['Plan']
                exec_time = f"{plan_json[0].get('Execution Time', plan_json[0].get('Plan', {}).get('Actual Total Time', 0)):.3f} ms"
                cost = f"{root.get('Total Cost', 0):.2f}"
                shared_hit = root.get('Shared Hit Blocks', 0)
        except Exception as e:
            print(f"Error parsing JSON for {q_id}: {e}")

        summary_data.append({
            'Query': q_id,
            'Name': q_info['name'],
            'Exec Time': exec_time,
            'Cost': cost,
            'Shared Hit': shared_hit
        })

        report.append(f"## {q_id}: {q_info['name']}\n")
        report.append("### Пример результата выполнения:\n```text\n" + data_out.strip() + "\n```\n")
        report.append("### План выполнения (EXPLAIN ANALYZE, BUFFERS):\n```text\n" + plan_out.strip() + "\n```\n")
        report.append("-" * 80 + "\n")

    with open('/home/elol3ek/databases/bd_project/experiments/01_baseline_report.md', 'w') as f:
        f.write("# Базовые планы выполнения 5 бизнес-запросов (до оптимизации)\n\n")
        f.write("| Запрос | Описание | Время выполнения | Оценка стоимости (Cost) | Shared Hit Blocks |\n")
        f.write("|---|---|---|---|---|\n")
        for row in summary_data:
            f.write(f"| {row['Query']} | {row['Name']} | {row['Exec Time']} | {row['Cost']} | {row['Shared Hit']} |\n")
        f.write("\n\n")
        f.write("\n".join(report))

    print("Baseline report generated successfully!")

if __name__ == '__main__':
    main()
