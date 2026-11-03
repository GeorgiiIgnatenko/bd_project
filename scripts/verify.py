"""Core integration checks in an automatically removed, isolated database."""
import os
import hashlib

from scripts.db import ROOT, run_sql
from scripts.migrate import migration_sql


def main():
    database = f"lab_verify_{os.getpid()}"
    report = []

    def sql(statement, role="admin"):
        output = run_sql(statement, role=role, database=database, notices=True)
        report.append(output)
        return output

    def expected_failure(statement, message):
        try:
            sql(statement)
        except RuntimeError as error:
            if message not in str(error):
                raise
            report.append(f"PASS: expected failure: {message}\n")
        else:
            raise AssertionError(f"Expected failure: {message}")

    run_sql(f'CREATE DATABASE "{database}" OWNER news_admin;', role="bootstrap")
    try:
        sql(migration_sql(4))
        sql("\\ir /workspace/run_seed_only.sql")
        sql(migration_sql(5))
        expected_failure(migration_sql().replace("COMMIT;", "CREATE TABLE rollback_probe(id int); SELECT 1/0; COMMIT;"), "division by zero")
        assert run_sql("SELECT max(version) = 5 AND to_regclass('public.audit_log') IS NULL AND to_regclass('public.rollback_probe') IS NULL FROM schema_migration;",
                       database=database, tuples=True).strip() == "t"
        sql(migration_sql())
        sql(migration_sql())
        assert run_sql("SELECT count(*) FROM news", database=database, tuples=True).strip() == "5"
        report.append("PASS: clean install, upgrade with preserved seed, repeat, failed migration rollback\n")
        sql("UPDATE schema_migration SET checksum = 'tampered' WHERE version = 1;")
        expected_failure(migration_sql(), "modified after application")
        # Restore test metadata only; production migrations are never rewritten.
        first = sorted((ROOT / "migrations").glob('*.up.sql'))[0]
        checksum = hashlib.sha256(first.read_bytes()).hexdigest()
        sql(f"UPDATE schema_migration SET checksum = '{checksum}' WHERE version = 1;")
        sql("INSERT INTO schema_migration(version, filename, checksum) VALUES (999, 'unknown.up.sql', 'unknown');")
        expected_failure(migration_sql(), "unknown to this checkout")
        sql("DELETE FROM schema_migration WHERE version=999;")
        sql("\\ir /workspace/run_checks.sql")
        query_tests = (ROOT / 'tests/queries.sql').read_text()
        for path in (ROOT / 'sql/queries').glob('q*.sql'):
            query_tests = query_tests.replace(f'-- @query {path.name}', path.read_text())
        sql(query_tests)
        body = (ROOT / 'sql/queries/q1_personal_feed.sql').read_text().strip().rstrip(';')
        for user_id in (1, 2):
            statement = f"""BEGIN READ ONLY;
\\set user_id {user_id}
\\ir /workspace/sql/query_parameters.sql
SET LOCAL app.current_user_id = '{user_id}';
SELECT jsonb_agg(row_to_json(feed)) FROM ({body}) feed;
COMMIT;"""
            expected = run_sql(statement, database=database, tuples=True)
            actual = run_sql(statement, database=database, role='app', tuples=True)
            assert actual == expected, 'Q1 differs under real application RLS'
        # Same connection after COMMIT must not inherit the prior user's context.
        assert run_sql("""BEGIN; SET LOCAL app.current_user_id = '1'; COMMIT;
SELECT NULLIF(current_setting('app.current_user_id', true), '') IS NULL
  AND NOT EXISTS (SELECT 1 FROM favorite);""", role='app', database=database, tuples=True).strip() == 't'
        report.append('PASS: Q1 result under real news_app login equals the intended user feed\n')
        # Полные UTC-сутки включают свежий seed и дают непустые примеры Q6–Q8.
        analytics_as_of = run_sql("""SELECT
          (date_trunc('day', now() AT TIME ZONE 'UTC') + INTERVAL '1 day')
          AT TIME ZONE 'UTC';""", database=database, tuples=True).strip()
        for name in ('q6_category_source_ranking.sql', 'q7_source_publication_gaps.sql',
                     'q8_source_daily_trend.sql'):
            body = (ROOT / 'sql/queries' / name).read_text().strip().rstrip(';')
            statement = f"""BEGIN READ ONLY;
\\set as_of '{analytics_as_of}'
\\ir /workspace/sql/query_parameters.sql
SELECT jsonb_agg(row_to_json(result)) FROM (\n{body}\n) result;
COMMIT;"""
            expected = run_sql(statement, database=database, tuples=True)
            actual = run_sql(statement, database=database, role='analyst', tuples=True)
            assert actual == expected and actual.strip(), f'{name}: analyst result differs or is empty'
            report.append(f'PASS: {name} — одинаковый непустой результат news_admin/news_analyst\n')
        for role in ("admin", "app", "analyst"):
            sql(f"\\ir /workspace/security/demo_{role}.sql", role)
        sql("\\ir /workspace/tests/audit_rls_tests/security_rls_audit.sql", "bootstrap")
        sql("\\ir /workspace/sql/transactions/01_import_publication.sql", "app")
        sql("\\ir /workspace/sql/transactions/01_import_publication.sql", "app")
        sql("\\ir /workspace/sql/transactions/02_rollback.sql", "app")
        assert run_sql("""SELECT count(*) = 1 FROM news
          WHERE canonical_url = 'https://globalnews.example/news/climate-report';""",
                       database=database, tuples=True).strip() == "t"
        sql("DELETE FROM news WHERE canonical_url='https://globalnews.example/news/climate-report'; UPDATE category SET is_active=false WHERE name='Экономика';")
        sql("\\ir /workspace/sql/transactions/01_import_publication.sql", "app")
        assert run_sql("""SELECT c.name FROM news n
          JOIN news_category nc ON nc.news_id=n.id JOIN category c ON c.id=nc.category_id
          WHERE n.canonical_url='https://globalnews.example/news/climate-report';""",
                       database=database, tuples=True).strip() == 'Без категории'
        sql("UPDATE category SET is_active=true WHERE name='Экономика';")
        report.append('PASS: inactive category falls back to the active service category\n')
        sql("\\ir /workspace/run_queries.sql")
        down = "\n".join(f"\\ir /workspace/migrations/{p.name}" for p in
                         sorted((ROOT / "migrations").glob('*.down.sql'), reverse=True))
        sql("BEGIN;\n" + down + "\nROLLBACK;")
        assert run_sql("SELECT count(*) FROM news", database=database, tuples=True).strip() == "6"
        sql("BEGIN;\n" + down + "\nDELETE FROM schema_migration; COMMIT;")
        sql(migration_sql())
        sql("\\ir /workspace/run_seed_only.sql")
        report.append("PASS: all down migrations rollback together; full down/up and seed succeed\n")
    finally:
        run_sql(f'DROP DATABASE "{database}" WITH (FORCE);', role="bootstrap")
        directory = ROOT / "artifacts" / "verification"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "core.txt").write_text("\n".join(report))
    print("PASS: migrations, constraints, lifecycles, roles, RLS/audit, transactions and queries")
    print("Evidence: artifacts/verification/core.txt")


if __name__ == "__main__":
    main()
