"""Локальная демонстрация и изолированная проверка MongoDB для лабораторной 5."""
import argparse
import json
from pathlib import Path
import subprocess
import uuid

from scripts.db import psql_command

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / "mongo" / "compose.yaml"
PROJECT = "bd-news-mongo"


def compare_notes(mongo_output):
    fixture = (ROOT / "mongo/reading_lists_case.json").read_text()
    sql = (ROOT / "experiments/reading_lists.sql").read_text()
    result = subprocess.run([*psql_command(), "-qAt", "-v", f"fixture={fixture}"],
                            cwd=ROOT, input=sql, capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise RuntimeError(f"PostgreSQL: {result.stderr}")
    postgres = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    mongo = [json.loads(line.removeprefix("SNAPSHOT ")) for line in mongo_output.splitlines()
             if line.startswith("SNAPSHOT ")]
    data = json.loads(fixture)
    before = sorted([entry["userId"], entry["id"], item["articleId"], item["note"]]
                    for entry in data["lists"] for item in entry["items"])
    edit = data["edit"]
    target = [edit["userId"], edit["listId"], edit["articleId"]]
    after = [[*row[:3], edit["note"]] if row[:3] == target else row for row in before]
    if after == before or postgres != [before, after] or mongo != postgres:
        raise ValueError(f"Результат сравнения расходится с ожиданиями: PG={postgres}, Mongo={mongo}")
    return "\n".join([
        "PostgreSQL до: " + json.dumps(postgres[0], ensure_ascii=False),
        "PostgreSQL после: " + json.dumps(postgres[1], ensure_ascii=False),
        "PASS: PostgreSQL и MongoDB совпали до и после изменения заметки.",
    ])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("up", "demo", "verify", "compare", "down"))
    args = parser.parse_args()
    token = uuid.uuid4().hex[:8]
    temporary = args.action in ("verify", "compare")
    project = f"{PROJECT}-check-{token}" if temporary else PROJECT
    database = f"lab5_check_{token}" if temporary else "lab5_demo"
    report = []
    directory = ROOT / "artifacts" / "mongo"
    directory.mkdir(parents=True, exist_ok=True)

    def command(*arguments, expected_error=None):
        cmd = ["docker", "compose", "-f", str(COMPOSE), "-p", project, *arguments]
        print(f"Выполняется: {' '.join(arguments)}", flush=True)
        result = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, timeout=600)
        output = result.stdout + result.stderr
        report.append(f"$ {' '.join(cmd)}\nexit={result.returncode}\n{output}")
        if expected_error is not None:
            if result.returncode == 0 or expected_error not in output:
                raise RuntimeError(f"Ожидался ненулевой exit и {expected_error!r}:\n{output}")
            message = f"PASS: ожидаемый отказ процесса: {expected_error} (exit={result.returncode})"
            report.append(message + "\n")
            print(message, flush=True)
        else:
            if output:
                print(output, end="" if output.endswith("\n") else "\n", flush=True)
            if result.returncode:
                raise RuntimeError(f"Команда завершилась с exit={result.returncode}")
        return output

    def shell(file, *, name=database, probe=None, expected_error=None):
        arguments = ["exec", "-T", "-e", f"LAB_MONGO_DB={name}"]
        if probe:
            arguments += ["-e", f"LAB_MONGO_PROBE={probe}"]
        return command(*arguments, "mongo", "mongosh", "--quiet", "--norc",
                       "--file", f"/workspace/mongo/{file}", expected_error=expected_error)

    try:
        if args.action == "down":
            command("down")  # Именованный том демонстрации сохраняется.
        else:
            command("up", "-d", "--wait", "--wait-timeout", "90", "mongo")
            if args.action == "demo":
                shell("demo.js")
            elif args.action == "compare":
                message = compare_notes(shell("compare.js"))
                report.append(message)
                print(message)
            elif args.action == "verify":
                shell("verify.js")
                shell("failure_probe.js", probe="validation", expected_error="Document failed validation")
                shell("failure_probe.js", probe="unexpected_success", expected_error="FAIL: контроль неожиданного успеха")
                shell("failure_probe.js", name="public", expected_error="Запрещена неучебная БД")
    finally:
        try:
            if temporary:
                # Только случайный проект этой проверки, никогда основной demo/SQL.
                command("down", "--volumes", "--remove-orphans")
        finally:
            path = directory / (f"{args.action}-{token}.txt" if temporary else f"{args.action}.txt")
            path.write_text("\n".join(report))
            print(f"Журнал: {path.relative_to(ROOT)}", flush=True)
    print(f"PASS: MongoDB {args.action}")


if __name__ == "__main__":
    main()
