"""Check deterministic contents, invalid inputs, and optionally the full load mode."""
import argparse
import json

from scripts.db import ROOT, run_sql

TABLES = ('role', 'app_user', 'category', 'news_source', 'news', 'news_category',
          'subscription_category', 'subscription_source', 'favorite', 'scrape_run',
          'import_result', 'scrape_error_log')


def fingerprint():
    queries = []
    for table in TABLES:
        queries.append(f"SELECT '{table}', count(*), md5(string_agg(h, '' ORDER BY h)) FROM (SELECT md5(row_to_json(t)::text) AS h FROM dev.{table} t) rows")
    return run_sql("SET timezone TO 'UTC';\n" + ' UNION ALL '.join(queries) + ';', tuples=True).strip()


def generate(mode, seed):
    print(f'Generating {mode}, seed={seed}', flush=True)
    output = run_sql(f"\\set mode {mode}\n\\set seed {seed}\n\\ir /workspace/generator/generate.sql\n\\ir /workspace/security/grants.sql", timeout=1800, notices=True)
    directory = ROOT / 'artifacts' / 'generator'
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f'{mode}-{seed}.txt').write_text(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--load', action='store_true', help='Also build and validate 3 million publications')
    args = parser.parse_args()
    generate('dev', 42)
    first = fingerprint()
    generate('dev', 42)
    second = fingerprint()
    assert first == second, 'Same seed produced different table contents'
    generate('dev', 43)
    different = fingerprint()
    assert different != first, 'Different seed did not change data'
    generate('dev', 42)
    assert fingerprint() == first, 'Restored seed does not match'
    for mode, seed in (('dev', '-1'), ('dev', '2147483648'), ('other', '42')):
        try:
            run_sql(f"\\set mode {mode}\n\\set seed {seed}\n\\ir /workspace/generator/generate.sql", timeout=30)
        except RuntimeError as error:
            assert 'check constraint' in str(error), error
        else:
            raise AssertionError('Invalid generator input was accepted')
        assert fingerprint() == first, 'Rejected generation changed the dataset'
    results = {'dev': 'PASS: identical contents of all 12 tables for seed 42; seed 43 differs; invalid input preserves data',
               'fingerprints': first.splitlines()}
    if args.load:
        generate('load', 42)
        results['load'] = run_sql("\\set mode load\n\\ir /workspace/generator/verify.sql", timeout=600, notices=True)
    (ROOT / 'artifacts' / 'generator' / 'verification.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
    print('PASS: generator verification; artifacts/generator', flush=True)


if __name__ == '__main__':
    main()
