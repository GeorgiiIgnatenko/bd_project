"""Save small result examples for all five canonical business queries."""
from experiments.benchmark import setup
from scripts.db import ROOT, run_sql


def main():
    directory = ROOT / "artifacts" / "queries"
    directory.mkdir(parents=True, exist_ok=True)
    for path in sorted((ROOT / "sql" / "queries").glob('q*.sql')):
        body = path.read_text().strip().rstrip(';')
        # The report shows only the first five rows; production Q2 has no forced limit.
        output = run_sql(setup('dev') + f"SELECT * FROM (\n{body}\n) AS example LIMIT 5;\nROLLBACK;")
        (directory / f'{path.stem}.txt').write_text(output)
    print('PASS: five result examples saved in artifacts/queries')


if __name__ == "__main__":
    main()
