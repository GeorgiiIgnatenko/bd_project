"""Two live psql sessions: duplicate import, lock diagnostics and deadlock repair."""
import os
from queue import Queue, Empty
import subprocess
from threading import Thread
import time
from uuid import uuid4

from scripts.db import ROOT, psql_command, run_sql
from scripts.migrate import migration_sql


class Session:
    def __init__(self, database, name):
        self.process = subprocess.Popen(psql_command(database=database) + ["-qAt"],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, bufsize=1, cwd=ROOT)
        self.output = Queue()
        self.name = name
        def read():
            for line in self.process.stdout:
                self.output.put(line)
            self.output.put(None)
        self.reader = Thread(target=read, daemon=True)
        self.reader.start()
        self.execute(f"\\set VERBOSITY verbose\nSET application_name = '{name}'; SET statement_timeout = '20s';")

    def send(self, sql):
        self.marker = "done_" + uuid4().hex
        self.process.stdin.write(sql + f"\n\\echo {self.marker}\n")
        self.process.stdin.flush()

    def wait(self):
        lines = []
        deadline = time.monotonic() + 25
        while True:
            try:
                line = self.output.get(timeout=max(0.01, deadline - time.monotonic()))
            except Empty:
                raise TimeoutError(f"Session {self.name} timed out") from None
            if line is None:
                raise RuntimeError("".join(lines))
            if line.strip() == self.marker:
                return "".join(lines)
            lines.append(line)

    def execute(self, sql):
        self.send(sql)
        return self.wait()

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()


def blocked(database, waiter, blocker):
    sql = f"""SELECT a.application_name, a.wait_event_type, a.wait_event,
           b.application_name AS blocking_session
      FROM pg_stat_activity a JOIN pg_stat_activity b ON b.pid = ANY(pg_blocking_pids(a.pid))
      WHERE a.datname = current_database() AND a.application_name = '{waiter}'
        AND b.application_name = '{blocker}';"""
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        result = run_sql(sql, database=database, tuples=True).strip()
        if result:
            return result
        time.sleep(0.05)
    raise AssertionError(f"Expected {waiter} to be blocked by {blocker}")


def main():
    database = f"lab_concurrency_{os.getpid()}"
    sessions, report = [], []
    run_sql(f'CREATE DATABASE "{database}" OWNER news_admin;', role="bootstrap")
    def connect(name):
        session = Session(database, name)
        sessions.append(session)
        return session
    def sql(statement, tuples=False):
        return run_sql(statement, database=database, tuples=tuples)
    try:
        sql(migration_sql())
        sql("\\ir /workspace/run_seed_only.sql")
        before = int(sql("SELECT count(*) FROM import_result;", True))
        a, b = connect('import_A'), connect('import_B')
        body = "\\ir /workspace/sql/transactions/import_body.sql"
        a.execute("BEGIN;\n" + body)
        b.send("BEGIN;\n" + body + "\nCOMMIT;")
        report.append(blocked(database, b.name, a.name))
        a.execute("COMMIT;")
        b.wait()
        assert sql("SELECT count(*) FROM news WHERE canonical_url = 'https://globalnews.example/news/climate-report';", True).strip() == '1'
        assert int(sql("SELECT count(*) FROM import_result;", True)) == before + 2
        assert sql("SELECT string_agg(status, ',' ORDER BY status) FROM (SELECT status FROM import_result ORDER BY id DESC LIMIT 2) x;", True).strip() == 'дубликат,успех'
        assert sql("SELECT count(*) FROM news_category nc JOIN news n ON n.id = nc.news_id WHERE n.canonical_url = 'https://globalnews.example/news/climate-report';", True).strip() == '1'
        report.append('PASS: concurrent import committed one classified publication, one success and one duplicate')
        a.close(); b.close()

        sql("CREATE TABLE deadlock_resource(id int PRIMARY KEY, balance int NOT NULL); INSERT INTO deadlock_resource VALUES (1,1000),(2,2000);")
        a, b = connect('deadlock_A'), connect('deadlock_B')
        a.execute("BEGIN; UPDATE deadlock_resource SET balance = balance + 10 WHERE id=1;")
        b.execute("BEGIN; UPDATE deadlock_resource SET balance = balance - 20 WHERE id=2;")
        a.send("UPDATE deadlock_resource SET balance = balance + 10 WHERE id=2; COMMIT;")
        report.append(blocked(database, a.name, b.name))
        b.send("UPDATE deadlock_resource SET balance = balance - 20 WHERE id=1; COMMIT;")
        errors = []
        for session in (a, b):
            try:
                session.wait()
            except RuntimeError as error:
                errors.append(str(error))
        assert len(errors) == 1 and '40P01' in errors[0], errors
        report += errors + ['PASS: one deadlock victim (40P01), the other transaction committed']
        a.close(); b.close()

        sql("UPDATE deadlock_resource SET balance = CASE id WHEN 1 THEN 1000 ELSE 2000 END;")
        a, b = connect('ordered_A'), connect('ordered_B')
        a.execute("BEGIN; UPDATE deadlock_resource SET balance = balance + 10 WHERE id=1;")
        b.send("BEGIN; UPDATE deadlock_resource SET balance = balance - 20 WHERE id=1; UPDATE deadlock_resource SET balance = balance - 20 WHERE id=2; COMMIT;")
        report.append(blocked(database, b.name, a.name))
        a.execute("UPDATE deadlock_resource SET balance = balance + 10 WHERE id=2; COMMIT;")
        b.wait()
        assert sql("SELECT string_agg(balance::text, ',' ORDER BY id) FROM deadlock_resource;", True).strip() == '990,1990'
        report.append('PASS: ordered locking, both commits and balances 990,1990')
    finally:
        for session in sessions:
            session.close()
        run_sql(f'DROP DATABASE "{database}" WITH (FORCE);', role="bootstrap")
        directory = ROOT / 'artifacts' / 'verification'
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'concurrency.txt').write_text('\n'.join(report) + '\n')
    print('\n'.join(report))


if __name__ == '__main__':
    main()
