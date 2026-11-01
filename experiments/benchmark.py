"""Compare real business SQL, save JSON plans and median server execution times."""
import argparse
from datetime import datetime, timezone
import json
from statistics import median

from scripts.db import ROOT, run_sql

QUERIES = ("q3_category_popularity.sql", "q5_problem_sources.sql")


def setup(schema):
    if schema not in ("dev", "load"):
        raise ValueError("Experiments require dev or load")
    return f"""BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL search_path TO {schema}, public, pg_catalog;
SET LOCAL timezone TO 'UTC';
SET LOCAL statement_timeout TO '180s';
\\set as_of '2026-10-01 00:00:00+00'
\\set user_id 1
\\set search_text спорт
\\ir /workspace/sql/query_parameters.sql
"""


def query(name, baseline=False):
    directory = "experiments/baseline" if baseline else "sql/queries"
    return (ROOT / directory / name).read_text().strip().rstrip(";")


def explain(name, baseline, schema):
    sql = setup(schema)
    if name.startswith("q5") and baseline:
        # Transactional DDL: restore production indexes even on query failure.
        sql += "DROP INDEX IF EXISTS idx_failed_runs_started_at; DROP INDEX IF EXISTS idx_scrape_error_run;\n"
    sql += "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)\n" + query(name, baseline) + ";\nROLLBACK;"
    return json.loads(run_sql(sql, tuples=True, timeout=240))[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", choices=("dev", "load"), default="dev")
    parser.add_argument("--repeats", type=int, default=3)
    args = parser.parse_args()
    if args.repeats < 3:
        parser.error("At least three measured runs are required")
    directory = ROOT / "artifacts" / "benchmark" / args.schema
    directory.mkdir(parents=True, exist_ok=True)
    metadata = run_sql(f"SELECT obj_description(oid, 'pg_namespace') FROM pg_namespace WHERE nspname = '{args.schema}';", tuples=True).strip()
    if not metadata:
        raise RuntimeError("Generate the dataset first")
    report = {"at": datetime.now(timezone.utc).isoformat(), "dataset": json.loads(metadata),
              "server": run_sql("SELECT version();", tuples=True).strip(),
              "repeats": args.repeats, "warmups": 1, "queries": {}}
    for name in QUERIES:
        label = name[:2]
        print(f"{label}: checking results, warming up, measuring {args.repeats} runs", flush=True)
        equal = run_sql(setup(args.schema) + f"""
CREATE TEMP TABLE before_result ON COMMIT DROP AS {query(name, True)};
CREATE TEMP TABLE after_result ON COMMIT DROP AS {query(name)};
SELECT NOT EXISTS (
  (TABLE before_result EXCEPT ALL TABLE after_result)
  UNION ALL (TABLE after_result EXCEPT ALL TABLE before_result)
);
ROLLBACK;
""", tuples=True, timeout=240).strip()
        if equal != "t":
            raise AssertionError(f"{label}: optimization changed the result")
        plans = {"before": [], "after": []}
        explain(name, True, args.schema)
        explain(name, False, args.schema)
        for repeat in range(args.repeats):
            print(f"{label}: measured round {repeat + 1}/{args.repeats}", flush=True)
            # Alternate order to reduce a systematic cache/order advantage.
            order = ("before", "after") if repeat % 2 == 0 else ("after", "before")
            for variant in order:
                plans[variant].append(explain(name, variant == "before", args.schema))
        metrics = {"results_equal": True}
        for variant, samples in plans.items():
            times = [sample["Execution Time"] for sample in samples]
            metrics[variant] = {"times_ms": times, "median_ms": median(times)}
            (directory / f"{label}_{variant}.json").write_text(json.dumps(samples, ensure_ascii=False, indent=2) + "\n")
        report["queries"][label] = metrics
        print(f"{label}: {metrics['before']['median_ms']:.3f} -> {metrics['after']['median_ms']:.3f} ms", flush=True)
    (directory / "measurements.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    lines = ["# Измерения запросов", "", f"Набор: {args.schema}, seed={report['dataset']['seed']}; as_of=2026-10-01 UTC.",
             f"Один прогрев, {args.repeats} измеряемых запуска; время PostgreSQL Execution Time, не запуска Docker.",
             "Результаты до/после проверены через EXCEPT ALL в обе стороны. Планы: соседние JSON.", "",
             "| Запрос | Медиана до, мс | Медиана после, мс | Отношение до/после |", "| --- | ---: | ---: | ---: |"]
    for label, values in report["queries"].items():
        before, after = values["before"]["median_ms"], values["after"]["median_ms"]
        lines.append(f"| {label} | {before:.3f} | {after:.3f} | {before / after:.2f} |")
    (directory / "report.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
