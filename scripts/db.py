"""psql through the project's container; passwords stay in its environment."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def psql_command(role="admin", database=None):
    if role == "bootstrap":
        login = 'exec psql -U news_bootstrap -d "$POSTGRES_DB" "$@"'
    else:
        password = {"admin": "ADMIN_PASSWORD", "app": "APP_PASSWORD",
                    "analyst": "ANALYST_PASSWORD"}[role]
        login = (f'PGPASSWORD="${password}" exec psql -h 127.0.0.1 '
                 f'-U news_{role} -d "$POSTGRES_DB" "$@"')
    command = ["docker", "compose", "exec", "-T", "postgres", "sh", "-c",
               login, "sh", "-X", "-w", "-v", "ON_ERROR_STOP=1", "-P", "pager=off"]
    if database:
        command += ["-d", database]
    return command


def run_sql(sql, *, role="admin", database=None, tuples=False, timeout=300, notices=False):
    command = psql_command(role, database)
    if tuples:
        command += ["-qAt"]
    result = subprocess.run(command, input=sql, text=True, capture_output=True,
                            cwd=ROOT, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"psql failed ({result.returncode}):\n{result.stderr}")
    return result.stdout + (result.stderr if notices else "")
