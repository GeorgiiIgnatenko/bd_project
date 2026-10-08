#!/usr/bin/env python3
import subprocess
import os
import re
import time

ENV = os.environ.copy()
ENV['PGPASSWORD'] = 'news_local_password'
ENV['PAGER'] = 'cat'
ENV['PATH'] = '/usr/bin:/bin:/usr/local/bin'

DB_ARGS = [
    'psql', '-h', '127.0.0.1', '-p', '55432',
    '-U', 'news_app', '-d', 'news_aggregator',
    '-X', '-P', 'pager=off'
]

def run_sql(sql):
    t0 = time.time()
    res = subprocess.run(DB_ARGS + ['-c', sql], capture_output=True, text=True, env=ENV)
    dt = time.time() - t0
    return res.stdout, res.stderr, dt

BASELINE_QUERIES = {
    'Q1': """
    SELECT n.id, n.title, s.name AS source, n.published_at,
        (EXISTS (SELECT 1 FROM subscription_source ss WHERE ss.user_id = 1 AND ss.source_id = n.source_id AND s.status NOT IN ('неактивен', 'отключён вручную'))
         OR EXISTS (SELECT 1 FROM news_category nc JOIN subscription_category sc ON sc.category_id = nc.category_id JOIN category c ON c.id = nc.category_id WHERE nc.news_id = n.id AND sc.user_id = 1 AND c.is_active AND c.name <> 'Без категории')) AS is_priority
    FROM news n JOIN news_source s ON s.id = n.source_id
    WHERE n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
    ORDER BY is_priority DESC, n.published_at DESC LIMIT 20 OFFSET 0;
    """,
    'Q2': """
    SELECT n.id, n.title, s.name AS source, c.name AS category, n.published_at
    FROM news n
    JOIN news_source s ON s.id = n.source_id
    JOIN news_category nc ON nc.news_id = n.id
    JOIN category c ON c.id = nc.category_id
    WHERE c.name = 'Спорт' AND (n.title ILIKE '%спорт%' OR n.content ILIKE '%спорт%')
    ORDER BY n.published_at DESC LIMIT 20;
    """,
    'Q3': """
    SELECT c.id, c.name,
           COUNT(DISTINCT n.id) AS news_count,
           COUNT(DISTINCT sc.user_id) AS subscribers,
           MAX(n.published_at) AS last_news_at
    FROM category c
    LEFT JOIN news_category nc ON nc.category_id = c.id
    LEFT JOIN news n ON n.id = nc.news_id AND n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
    LEFT JOIN subscription_category sc ON sc.category_id = c.id
    GROUP BY c.id, c.name
    ORDER BY news_count DESC, subscribers DESC, c.name;
    """,
    'Q4': """
    SELECT s.id, s.name, s.status,
           COUNT(DISTINCT r.id) AS runs,
           COUNT(ir.id) FILTER (WHERE ir.status = 'успех') AS imported,
           COUNT(ir.id) FILTER (WHERE ir.status = 'дубликат') AS duplicates,
           COUNT(ir.id) FILTER (WHERE ir.status = 'ошибка') AS failed_items
    FROM news_source s
    LEFT JOIN scrape_run r ON r.source_id = s.id AND r.started_at >= '2026-01-01'
    LEFT JOIN import_result ir ON ir.scrape_run_id = r.id
    GROUP BY s.id, s.name, s.status
    ORDER BY s.id;
    """,
    'Q5': """
    SELECT s.id, s.name, s.status,
           COUNT(DISTINCT r.id) AS failed_runs,
           COUNT(e.id) AS error_records,
           MAX(e.created_at) AS last_error_at
    FROM news_source s
    JOIN scrape_run r ON r.source_id = s.id AND r.status = 'ошибка' AND r.started_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (7 * INTERVAL '1 day')
    LEFT JOIN scrape_error_log e ON e.scrape_run_id = r.id
    GROUP BY s.id, s.name, s.status
    HAVING COUNT(DISTINCT r.id) >= 1
    ORDER BY failed_runs DESC, s.id;
    """
}

OPTIMIZED_QUERIES = {
    'Q1': """
    WITH user_sources AS (
        SELECT source_id FROM subscription_source WHERE user_id = 1
    ),
    user_categories AS (
        SELECT sc.category_id FROM subscription_category sc
        JOIN category c ON c.id = sc.category_id
        WHERE sc.user_id = 1 AND c.is_active AND c.name <> 'Без категории'
    ),
    priority_news AS (
        SELECT DISTINCT nc.news_id FROM news_category nc
        JOIN user_categories uc ON uc.category_id = nc.category_id
    )
    SELECT n.id, n.title, s.name AS source, n.published_at,
        ((s.status NOT IN ('неактивен', 'отключён вручную') AND EXISTS (SELECT 1 FROM user_sources us WHERE us.source_id = n.source_id))
         OR EXISTS (SELECT 1 FROM priority_news pn WHERE pn.news_id = n.id)) AS is_priority
    FROM news n
    JOIN news_source s ON s.id = n.source_id
    WHERE n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
    ORDER BY is_priority DESC, n.published_at DESC LIMIT 20;
    """,
    'Q2': """
    SELECT n.id, n.title, s.name AS source, c.name AS category, n.published_at
    FROM category c
    JOIN news_category nc ON nc.category_id = c.id
    JOIN news n ON n.id = nc.news_id
    JOIN news_source s ON s.id = n.source_id
    WHERE c.name = 'Спорт' AND (n.title ILIKE '%спорт%' OR n.content ILIKE '%спорт%')
    ORDER BY n.published_at DESC LIMIT 20;
    """,
    'Q3': """
    WITH cat_news AS (
        SELECT nc.category_id, COUNT(nc.news_id) AS news_count, MAX(n.published_at) AS last_news_at
        FROM news_category nc
        JOIN news n ON n.id = nc.news_id AND n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
        GROUP BY nc.category_id
    ),
    cat_subs AS (
        SELECT category_id, COUNT(user_id) AS subscribers
        FROM subscription_category
        GROUP BY category_id
    )
    SELECT c.id, c.name,
           COALESCE(cn.news_count, 0) AS news_count,
           COALESCE(cs.subscribers, 0) AS subscribers,
           cn.last_news_at
    FROM category c
    LEFT JOIN cat_news cn ON cn.category_id = c.id
    LEFT JOIN cat_subs cs ON cs.category_id = c.id
    ORDER BY news_count DESC, subscribers DESC, c.name;
    """,
    'Q4': """
    WITH run_stats AS (
        SELECT r.source_id,
               COUNT(DISTINCT r.id) AS runs,
               COUNT(ir.id) FILTER (WHERE ir.status = 'успех') AS imported,
               COUNT(ir.id) FILTER (WHERE ir.status = 'дубликат') AS duplicates,
               COUNT(ir.id) FILTER (WHERE ir.status = 'ошибка') AS failed_items
        FROM scrape_run r
        LEFT JOIN import_result ir ON ir.scrape_run_id = r.id
        WHERE r.started_at >= '2026-01-01'
        GROUP BY r.source_id
    )
    SELECT s.id, s.name, s.status,
           COALESCE(rs.runs, 0) AS runs,
           COALESCE(rs.imported, 0) AS imported,
           COALESCE(rs.duplicates, 0) AS duplicates,
           COALESCE(rs.failed_items, 0) AS failed_items
    FROM news_source s
    LEFT JOIN run_stats rs ON rs.source_id = s.id
    ORDER BY s.id;
    """,
    'Q5': """
    WITH failed_runs AS (
        SELECT r.source_id, r.id AS run_id,
               COUNT(e.id) AS error_records, MAX(e.created_at) AS last_error_at
        FROM scrape_run r
        LEFT JOIN scrape_error_log e ON e.scrape_run_id = r.id
        WHERE r.status = 'ошибка' AND r.started_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (7 * INTERVAL '1 day')
        GROUP BY r.source_id, r.id
    )
    SELECT s.id, s.name, s.status,
           COUNT(fr.run_id) AS failed_runs,
           COALESCE(SUM(fr.error_records), 0) AS error_records,
           MAX(fr.last_error_at) AS last_error_at
    FROM news_source s
    JOIN failed_runs fr ON fr.source_id = s.id
    GROUP BY s.id, s.name, s.status
    HAVING COUNT(fr.run_id) >= 1
    ORDER BY failed_runs DESC, s.id;
    """
}

def parse_metrics(plan_text):
    exec_time = "N/A"
    cost = "N/A"
    shared_hit = "N/A"
    
    m_time = re.search(r'Execution Time:\s+([\d\.]+)\s+ms', plan_text)
    if m_time:
        exec_time = f"{float(m_time.group(1)):.2f} ms"
    
    m_cost = re.search(r'cost=[\d\.]+\.\.([\d\.]+)', plan_text)
    if m_cost:
        cost = f"{float(m_cost.group(1)):.2f}"
        
    m_hit = re.search(r'shared hit=(\d+)', plan_text)
    if m_hit:
        shared_hit = m_hit.group(1)
        
    return exec_time, cost, shared_hit

def main():
    out_dir = '/home/elol3ek/databases/bd_project/experiments'
    results = []

    # Let's run each query
    for q_id in ['Q1', 'Q2', 'Q3', 'Q4', 'Q5']:
        print(f"[{q_id}] Running Baseline...")
        base_sql = f"SET search_path TO dev, pg_catalog;\nEXPLAIN (ANALYZE, BUFFERS)\n{BASELINE_QUERIES[q_id]}"
        base_plan, _, b_dt = run_sql(base_sql)
        b_time, b_cost, b_hit = parse_metrics(base_plan)
        if b_time == "N/A":
            b_time = f"{b_dt * 1000:.2f} ms"
        with open(os.path.join(out_dir, f'plan_baseline_{q_id}.txt'), 'w') as f:
            f.write(base_plan)

        print(f"[{q_id}] Running Optimized...")
        opt_sql = f"SET search_path TO dev, pg_catalog;\nEXPLAIN (ANALYZE, BUFFERS)\n{OPTIMIZED_QUERIES[q_id]}"
        opt_plan, _, o_dt = run_sql(opt_sql)
        o_time, o_cost, o_hit = parse_metrics(opt_plan)
        if o_time == "N/A":
            o_time = f"{o_dt * 1000:.2f} ms"
        with open(os.path.join(out_dir, f'plan_optimized_{q_id}.txt'), 'w') as f:
            f.write(opt_plan)

        results.append({
            'query': q_id,
            'b_time': b_time,
            'b_cost': b_cost,
            'b_hit': b_hit,
            'o_time': o_time,
            'o_cost': o_cost,
            'o_hit': o_hit
        })
        print(f"[{q_id}] Done! Baseline: {b_time}, Optimized: {o_time}")

    table = "| Запрос | Базовое время | Оптимизир. время | Базовый Cost | Оптимизир. Cost | Базовые Shared Hit | Оптимизир. Shared Hit | Ускорение |\n"
    table += "|---|---|---|---|---|---|---|---|\n"
    for r in results:
        try:
            bt = float(r['b_time'].replace(' ms', ''))
            ot = float(r['o_time'].replace(' ms', ''))
            speedup = f"{(bt / ot):.1f}x" if ot > 0 else "-"
        except Exception:
            speedup = "-"
            
        table += f"| **{r['query']}** | {r['b_time']} | {r['o_time']} | {r['b_cost']} | {r['o_cost']} | {r['b_hit']} | {r['o_hit']} | **{speedup}** |\n"

    with open(os.path.join(out_dir, 'comparison_table.md'), 'w') as f:
        f.write("# Таблица сравнения производительности (до и после оптимизации)\n\n")
        f.write(table)

    print("ALL DONE SUCCESSFULLY!")

if __name__ == '__main__':
    main()
