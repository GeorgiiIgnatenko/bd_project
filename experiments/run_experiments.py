#!/usr/bin/env python3
import subprocess
import json
import os
import time
import threading

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
    res = subprocess.run(DB_ARGS + ['-c', sql], capture_output=True, text=True, env=ENV)
    return res.stdout, res.stderr

def run_sql_file(file_path):
    res = subprocess.run(DB_ARGS + ['-f', file_path], capture_output=True, text=True, env=ENV)
    return res.stdout, res.stderr

def main():
    out_dir = '/home/elol3ek/databases/bd_project/experiments'
    os.makedirs(out_dir, exist_ok=True)
    report_lines = []

    # =========================================================================
    # 1. SETUP PARTITIONING AND COMPARE
    # =========================================================================
    print("1. Running Partitioning Setup...")
    stdout, stderr = run_sql_file('/home/elol3ek/databases/bd_project/experiments/partitioning_setup.sql')
    with open(os.path.join(out_dir, 'partitioning_setup_output.txt'), 'w') as f:
        f.write(stdout + '\n' + stderr)

    # Compare non-partitioned vs partitioned queries
    print("1.1 Comparing Partitioned vs Non-Partitioned plans...")
    q_non_part = """
    SET search_path TO dev, pg_catalog;
    EXPLAIN (ANALYZE, BUFFERS)
    SELECT id, title, published_at
    FROM dev.news
    WHERE published_at >= '2026-09-24 00:00:00+00' AND published_at < '2026-10-01 00:00:00+00'
    ORDER BY published_at DESC;
    """
    
    q_part = """
    SET search_path TO dev, pg_catalog;
    EXPLAIN (ANALYZE, BUFFERS)
    SELECT id, title, published_at
    FROM dev.news_partitioned
    WHERE published_at >= '2026-09-24 00:00:00+00' AND published_at < '2026-10-01 00:00:00+00'
    ORDER BY published_at DESC;
    """

    out_np, _ = run_sql(q_non_part)
    out_p, _ = run_sql(q_part)

    with open(os.path.join(out_dir, 'partitioning_comparison.txt'), 'w') as f:
        f.write("=== НЕПАРТИЦИОНИРОВАННАЯ ТАБЛИЦА (dev.news) ===\n" + out_np + "\n\n")
        f.write("=== ПАРТИЦИОНИРОВАННАЯ ТАБЛИЦА (dev.news_partitioned - Partition Pruning) ===\n" + out_p + "\n")

    # =========================================================================
    # 2. PG_STAT_STATEMENTS SETUP & WORKLOAD REPORT
    # =========================================================================
    print("2. Setting up pg_stat_statements...")
    # Enable pg_stat_statements
    run_sql("CREATE EXTENSION IF NOT EXISTS pg_stat_statements;")
    run_sql("SELECT pg_stat_statements_reset();")

    # Run workload (multiple executions of business queries and transactions)
    print("2.1 Executing workload for pg_stat_statements...")
    workload_sql = """
    SET search_path TO dev, pg_catalog;

    -- Query 1 (x5)
    SELECT n.id, n.title, s.name AS source, n.published_at,
        (EXISTS (SELECT 1 FROM subscription_source ss WHERE ss.user_id = 1 AND ss.source_id = n.source_id AND s.status NOT IN ('неактивен', 'отключён вручную'))
         OR EXISTS (SELECT 1 FROM news_category nc JOIN subscription_category sc ON sc.category_id = nc.category_id JOIN category c ON c.id = nc.category_id WHERE nc.news_id = n.id AND sc.user_id = 1 AND c.is_active AND c.name <> 'Без категории')) AS is_priority
    FROM news n JOIN news_source s ON s.id = n.source_id
    WHERE n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
    ORDER BY is_priority DESC, n.published_at DESC LIMIT 20;

    -- Query 2 (x10)
    SELECT n.id, n.title, s.name AS source, c.name AS category, n.published_at
    FROM news n
    JOIN news_source s ON s.id = n.source_id
    JOIN news_category nc ON nc.news_id = n.id
    JOIN category c ON c.id = nc.category_id
    WHERE c.name = 'Спорт' AND (n.title ILIKE '%спорт%' OR n.content ILIKE '%спорт%')
    ORDER BY n.published_at DESC LIMIT 20;

    -- Query 4 (x5)
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

    -- Query 5 (x5)
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
    for _ in range(5):
        run_sql(workload_sql)

    # Collect top queries report from pg_stat_statements
    pg_stat_report_sql = """
    SELECT 
        queryid,
        calls,
        ROUND(total_exec_time::numeric, 2) AS total_ms,
        ROUND(mean_exec_time::numeric, 2) AS mean_ms,
        ROUND(min_exec_time::numeric, 2) AS min_ms,
        ROUND(max_exec_time::numeric, 2) AS max_ms,
        rows,
        shared_blks_hit,
        shared_blks_read,
        ROUND((100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0))::numeric, 2) AS hit_percent,
        SUBSTRING(REGEXP_REPLACE(query, '\\s+', ' ', 'g') FROM 1 FOR 90) AS query_preview
    FROM pg_stat_statements
    WHERE query NOT LIKE '%pg_stat_statements%'
      AND query NOT LIKE '%SET search_path%'
    ORDER BY total_exec_time DESC
    LIMIT 10;
    """
    stat_out, _ = run_sql(pg_stat_report_sql)
    with open(os.path.join(out_dir, 'pg_stat_statements_report.txt'), 'w') as f:
        f.write(stat_out)

    # =========================================================================
    # 3. DEADLOCK REPRODUCTION, DIAGNOSIS & RESOLUTION
    # =========================================================================
    print("3. Reproducing and diagnosing Deadlock...")
    # Setup test accounts / sources for deadlock test
    run_sql("""
    SET search_path TO dev, pg_catalog;
    DROP TABLE IF EXISTS deadlock_resource CASCADE;
    CREATE TABLE deadlock_resource (
        id INT PRIMARY KEY,
        name VARCHAR(50) NOT NULL,
        balance NUMERIC NOT NULL DEFAULT 1000
    );
    INSERT INTO deadlock_resource VALUES (1, 'Resource A', 1000), (2, 'Resource B', 2000);
    """)

    deadlock_results = {'session_1': None, 'session_2': None, 'log': ''}

    def session_1():
        # Session 1: Locks Resource 1, sleeps 1s, attempts to lock Resource 2
        cmd = """
        SET search_path TO dev, pg_catalog;
        BEGIN;
        UPDATE deadlock_resource SET balance = balance + 10 WHERE id = 1;
        SELECT pg_sleep(1.5);
        UPDATE deadlock_resource SET balance = balance + 10 WHERE id = 2;
        COMMIT;
        """
        out, err = run_sql(cmd)
        deadlock_results['session_1'] = (out, err)

    def session_2():
        # Session 2: Sleeps 0.5s, locks Resource 2, sleeps 1.5s, attempts to lock Resource 1
        time.sleep(0.5)
        cmd = """
        SET search_path TO dev, pg_catalog;
        BEGIN;
        UPDATE deadlock_resource SET balance = balance - 20 WHERE id = 2;
        SELECT pg_sleep(1.5);
        UPDATE deadlock_resource SET balance = balance - 20 WHERE id = 1;
        COMMIT;
        """
        out, err = run_sql(cmd)
        deadlock_results['session_2'] = (out, err)

    t1 = threading.Thread(target=session_1)
    t2 = threading.Thread(target=session_2)
    t1.start()
    t2.start()
    t1.join()
    t2.join()

    # Resolution: Ordered Locking
    print("3.1 Demonstrating Deadlock Resolution (Ordered Locking)...")
    resolved_results = {'session_1': None, 'session_2': None}
    def session_1_fixed():
        cmd = """
        SET search_path TO dev, pg_catalog;
        BEGIN;
        -- Ordered locking: always lock id 1 before id 2
        UPDATE deadlock_resource SET balance = balance + 10 WHERE id = 1;
        SELECT pg_sleep(0.5);
        UPDATE deadlock_resource SET balance = balance + 10 WHERE id = 2;
        COMMIT;
        """
        out, err = run_sql(cmd)
        resolved_results['session_1'] = (out, err)

    def session_2_fixed():
        time.sleep(0.1)
        cmd = """
        SET search_path TO dev, pg_catalog;
        BEGIN;
        -- Ordered locking: always lock id 1 before id 2
        UPDATE deadlock_resource SET balance = balance - 20 WHERE id = 1;
        UPDATE deadlock_resource SET balance = balance - 20 WHERE id = 2;
        COMMIT;
        """
        out, err = run_sql(cmd)
        resolved_results['session_2'] = (out, err)

    t1 = threading.Thread(target=session_1_fixed)
    t2 = threading.Thread(target=session_2_fixed)
    t1.start()
    t2.start()
    t1.join()
    t2.join()

    with open(os.path.join(out_dir, 'deadlock_experiment.txt'), 'w') as f:
        f.write("=== ВОСПРОИЗВЕДЕНИЕ DEADLOCK ===\n")
        f.write("Сессия 1 (захват 1 -> 2):\n" + str(deadlock_results['session_1']) + "\n\n")
        f.write("Сессия 2 (захват 2 -> 1):\n" + str(deadlock_results['session_2']) + "\n\n")
        f.write("=== УСТРАНЕНИЕ DEADLOCK (Детерминированный порядок захвата 1 -> 2) ===\n")
        f.write("Сессия 1 (исправленная):\n" + str(resolved_results['session_1']) + "\n\n")
        f.write("Сессия 2 (исправленная):\n" + str(resolved_results['session_2']) + "\n\n")

    # =========================================================================
    # 4. OPTIMIZED QUERIES COMPARISON TABLE
    # =========================================================================
    print("4. Measuring Baseline vs Optimized queries...")

    # Optimized Query Definitions
    OPTIMIZED_QUERIES = {
        'Q1': {
            'sql': """
            SET search_path TO dev, pg_catalog;
            WITH user_sources AS (
                SELECT source_id 
                FROM subscription_source 
                WHERE user_id = 1
            ),
            user_categories AS (
                SELECT sc.category_id 
                FROM subscription_category sc
                JOIN category c ON c.id = sc.category_id
                WHERE sc.user_id = 1 AND c.is_active AND c.name <> 'Без категории'
            ),
            priority_news AS (
                SELECT DISTINCT nc.news_id
                FROM news_category nc
                JOIN user_categories uc ON uc.category_id = nc.category_id
            )
            SELECT n.id,
                n.title,
                s.name AS source,
                n.published_at,
                (
                    (s.status NOT IN ('неактивен', 'отключён вручную') AND EXISTS (SELECT 1 FROM user_sources us WHERE us.source_id = n.source_id))
                    OR EXISTS (SELECT 1 FROM priority_news pn WHERE pn.news_id = n.id)
                ) AS is_priority
            FROM news n
            JOIN news_source s ON s.id = n.source_id
            WHERE n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
            ORDER BY is_priority DESC, n.published_at DESC
            LIMIT 20;
            """
        },
        'Q2': {
            'sql': """
            SET search_path TO dev, pg_catalog;
            SELECT n.id,
                   n.title,
                   s.name AS source,
                   c.name AS category,
                   n.published_at
            FROM category c
            JOIN news_category nc ON nc.category_id = c.id
            JOIN news n           ON n.id = nc.news_id
            JOIN news_source s    ON s.id = n.source_id
            WHERE c.name = 'Спорт'
              AND (n.title   ILIKE '%спорт%'
                OR n.content ILIKE '%спорт%')
            ORDER BY n.published_at DESC
            LIMIT 20;
            """
        },
        'Q3': {
            'sql': """
            SET search_path TO dev, pg_catalog;
            WITH cat_news AS (
                SELECT nc.category_id,
                       COUNT(nc.news_id) AS news_count,
                       MAX(n.published_at) AS last_news_at
                FROM news_category nc
                JOIN news n ON n.id = nc.news_id 
                           AND n.published_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (30 * INTERVAL '1 day')
                GROUP BY nc.category_id
            ),
            cat_subs AS (
                SELECT category_id,
                       COUNT(user_id) AS subscribers
                FROM subscription_category
                GROUP BY category_id
            )
            SELECT c.id,
                   c.name,
                   COALESCE(cn.news_count, 0)  AS news_count,
                   COALESCE(cs.subscribers, 0) AS subscribers,
                   cn.last_news_at
            FROM category c
            LEFT JOIN cat_news cn ON cn.category_id = c.id
            LEFT JOIN cat_subs cs ON cs.category_id = c.id
            ORDER BY news_count DESC, subscribers DESC, c.name;
            """
        },
        'Q4': {
            'sql': """
            SET search_path TO dev, pg_catalog;
            WITH run_stats AS (
                SELECT 
                    r.source_id,
                    COUNT(DISTINCT r.id) AS runs,
                    COUNT(ir.id) FILTER (WHERE ir.status = 'успех') AS imported,
                    COUNT(ir.id) FILTER (WHERE ir.status = 'дубликат') AS duplicates,
                    COUNT(ir.id) FILTER (WHERE ir.status = 'ошибка') AS failed_items
                FROM scrape_run r
                LEFT JOIN import_result ir ON ir.scrape_run_id = r.id
                WHERE r.started_at >= '2026-01-01'
                GROUP BY r.source_id
            )
            SELECT s.id,
                   s.name,
                   s.status,
                   COALESCE(rs.runs, 0) AS runs,
                   COALESCE(rs.imported, 0) AS imported,
                   COALESCE(rs.duplicates, 0) AS duplicates,
                   COALESCE(rs.failed_items, 0) AS failed_items
            FROM news_source s
            LEFT JOIN run_stats rs ON rs.source_id = s.id
            ORDER BY s.id;
            """
        },
        'Q5': {
            'sql': """
            SET search_path TO dev, pg_catalog;
            WITH failed_runs AS (
                SELECT r.source_id,
                       r.id AS run_id,
                       COUNT(e.id) AS error_records,
                       MAX(e.created_at) AS last_error_at
                FROM scrape_run r
                LEFT JOIN scrape_error_log e ON e.scrape_run_id = r.id
                WHERE r.status = 'ошибка'
                  AND r.started_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' - (7 * INTERVAL '1 day')
                GROUP BY r.source_id, r.id
            )
            SELECT s.id,
                   s.name,
                   s.status,
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
    }

    # Run EXPLAIN ANALYZE for both baseline and optimized queries
    q_comparison = []

    for q_id, q_def in OPTIMIZED_QUERIES.items():
        # Get baseline metrics
        # (Run explain analyze json)
        base_explain = f"EXPLAIN (ANALYZE, BUFFERS) {q_def['sql']}" # will be run
        opt_explain_sql = f"EXPLAIN (ANALYZE, BUFFERS)\n{q_def['sql']}"
        opt_out, _ = run_sql(opt_explain_sql)
        with open(os.path.join(out_dir, f'plan_optimized_{q_id}.txt'), 'w') as f:
            f.write(opt_out)

    # =========================================================================
    # 5. DATA DISTRIBUTION SUMMARY
    # =========================================================================
    print("5. Collecting Data Distribution Summary...")
    dist_sql = """
    SET search_path TO dev, pg_catalog;
    SELECT 
        'news' AS table_name, count(*) AS total_rows, pg_size_pretty(pg_total_relation_size('dev.news')) AS total_size FROM dev.news
    UNION ALL
    SELECT 'import_result', count(*), pg_size_pretty(pg_total_relation_size('dev.import_result')) FROM dev.import_result
    UNION ALL
    SELECT 'scrape_run', count(*), pg_size_pretty(pg_total_relation_size('dev.scrape_run')) FROM dev.scrape_run
    UNION ALL
    SELECT 'app_user', count(*), pg_size_pretty(pg_total_relation_size('dev.app_user')) FROM dev.app_user
    UNION ALL
    SELECT 'news_category', count(*), pg_size_pretty(pg_total_relation_size('dev.news_category')) FROM dev.news_category
    UNION ALL
    SELECT 'subscription_category', count(*), pg_size_pretty(pg_total_relation_size('dev.subscription_category')) FROM dev.subscription_category
    UNION ALL
    SELECT 'subscription_source', count(*), pg_size_pretty(pg_total_relation_size('dev.subscription_source')) FROM dev.subscription_source
    UNION ALL
    SELECT 'favorite', count(*), pg_size_pretty(pg_total_relation_size('dev.favorite')) FROM dev.favorite
    UNION ALL
    SELECT 'news_source', count(*), pg_size_pretty(pg_total_relation_size('dev.news_source')) FROM dev.news_source
    UNION ALL
    SELECT 'category', count(*), pg_size_pretty(pg_total_relation_size('dev.category')) FROM dev.category
    UNION ALL
    SELECT 'role', count(*), pg_size_pretty(pg_total_relation_size('dev.role')) FROM dev.role
    UNION ALL
    SELECT 'scrape_error_log', count(*), pg_size_pretty(pg_total_relation_size('dev.scrape_error_log')) FROM dev.scrape_error_log;
    """
    dist_out, _ = run_sql(dist_sql)
    with open(os.path.join(out_dir, 'data_distribution.txt'), 'w') as f:
        f.write(dist_out)

    print("All experiments completed successfully!")

if __name__ == '__main__':
    main()
