"""Run the public quickstart on a fresh Compose volume, then remove only that stack."""
import os
import subprocess

from scripts.db import ROOT, run_sql


def main():
    # Environment takes precedence over compose.yaml's project name.
    os.environ['COMPOSE_PROJECT_NAME'] = f'bd-news-startup-{os.getpid()}'
    os.environ['POSTGRES_PORT'] = '0'  # Docker allocates a free loopback port.
    report = []
    def command(*args):
        result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, timeout=120)
        report.append(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f'{args}:\n{report[-1]}')
    try:
        command('sh', 'start.sh')
        assert run_sql('SELECT count(*) FROM schema_migration;', tuples=True).strip() == '7'
        command('docker', 'compose', 'run', '--rm', '-T', 'seed_only')
        command('docker', 'compose', 'run', '--rm', '-T', 'queries')
        command('sh', 'security/demo.sh')
        command('bash', 'tests/audit_rls_tests/run_rls_audit_tests.sh')
        command('docker', 'compose', 'restart', 'postgres')
        command('sh', 'start.sh')
        assert run_sql('SELECT count(*) FROM news;', tuples=True).strip() == '5'
        report.append('PASS: fresh volume, quickstart, real TCP role checks, RLS/audit, restart preserving seed\n')
    finally:
        command('docker', 'compose', 'down', '--volumes')
        directory = ROOT / 'artifacts' / 'verification'
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'startup.txt').write_text('\n'.join(report))
    print('PASS: clean Compose startup and restart; artifacts/verification/startup.txt')


if __name__ == '__main__':
    main()
