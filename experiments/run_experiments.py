"""Optional lab 3 experiments: fair partition comparison and statement statistics."""
import json
from statistics import median

from experiments.benchmark import setup
from scripts.db import ROOT, run_sql


def main():
    directory = ROOT / 'artifacts' / 'experiments'
    directory.mkdir(parents=True, exist_ok=True)
    run_sql('\\ir /workspace/experiments/01_partitioning.sql')
    try:
        equal = run_sql('''SELECT NOT EXISTS (
          (TABLE lab_partitioning.news_heap EXCEPT ALL TABLE lab_partitioning.news_range)
          UNION ALL (TABLE lab_partitioning.news_range EXCEPT ALL TABLE lab_partitioning.news_heap));''', tuples=True).strip()
        assert equal == 't', 'Partition copies differ'
        plans = {}
        for table in ('news_heap', 'news_range'):
            sql = f'''EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
                SELECT id, title, published_at FROM lab_partitioning.{table}
                WHERE published_at >= '2026-09-24 00:00:00+00'
                  AND published_at < '2026-10-01 00:00:00+00'
                ORDER BY published_at DESC, id DESC;'''
            run_sql(sql, tuples=True)  # warmup
            plans[table] = [json.loads(run_sql(sql, tuples=True))[0] for _ in range(3)]
        (directory / 'partitioning.json').write_text(json.dumps(plans, ensure_ascii=False, indent=2) + '\n')
        def relations(node):
            names = {node['Relation Name']} if 'Relation Name' in node else set()
            for child in node.get('Plans', []):
                names.update(relations(child))
            return names
        assert all(relations(p['Plan']) == {'news_recent'} for p in plans['news_range']), 'Expected partition pruning'
        lines = ['# Партицирование', '', 'Одинаковые данные и индексы в обеих копиях; результаты равны.',
                 'Один прогрев и три измерения. Это экспериментальная проекция, не новая схема приложения.', '']
        for table, samples in plans.items():
            lines.append(f"- {table}: медиана {median(p['Execution Time'] for p in samples):.3f} мс")
        lines += ['', 'В news_range план обращается только к news_recent: остальные диапазоны отсечены.',
                  'Глобальная уникальность canonical_url исходной модели этой проекцией не заменяется.']
        (directory / 'partitioning.md').write_text('\n'.join(lines) + '\n')
    finally:
        run_sql('DROP SCHEMA lab_partitioning CASCADE;')
    # Do not reset cluster-wide statistics. Report cumulative calls honestly.
    run_sql('SELECT count(*) FROM public.pg_stat_statements;', tuples=True)
    for _ in range(3):
        sql = setup('dev') + '\n'.join(p.read_text() for p in sorted((ROOT / 'sql/queries').glob('q*.sql'))) + '\nROLLBACK;'
        run_sql(sql)
    output = run_sql('\\ir /workspace/experiments/02_pg_stat_statements.sql')
    if '(0 rows)' in output:
        raise AssertionError('No workload was recorded by pg_stat_statements')
    (directory / 'pg_stat_statements.txt').write_text('Cumulative statistics since the last server reset; workload executed three times.\n\n' + output)
    print('PASS: partition comparison and pg_stat_statements; artifacts/experiments')


if __name__ == '__main__':
    main()
