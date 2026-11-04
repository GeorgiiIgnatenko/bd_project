"""Локальная демонстрация и изолированная проверка MongoDB для лабораторной 5."""
import argparse
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / "mongo" / "compose.yaml"
PROJECT = "bd-news-mongo"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("up", "demo", "verify", "down"))
    args = parser.parse_args()
    token = uuid.uuid4().hex[:8]
    project = f"{PROJECT}-check-{token}" if args.action == "verify" else PROJECT
    database = f"lab5_check_{token}" if args.action == "verify" else "lab5_demo"
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
            elif args.action == "verify":
                shell("verify.js")
                shell("failure_probe.js", probe="validation", expected_error="Document failed validation")
                shell("failure_probe.js", probe="unexpected_success", expected_error="FAIL: контроль неожиданного успеха")
                shell("failure_probe.js", name="public", expected_error="Запрещена неучебная БД")
    finally:
        try:
            if args.action == "verify":
                # Только случайный проект этой проверки, никогда основной demo/SQL.
                command("down", "--volumes", "--remove-orphans")
        finally:
            path = directory / (f"verify-{token}.txt" if args.action == "verify" else f"{args.action}.txt")
            path.write_text("\n".join(report))
            print(f"Журнал: {path.relative_to(ROOT)}", flush=True)
    print(f"PASS: MongoDB {args.action}")


if __name__ == "__main__":
    main()
