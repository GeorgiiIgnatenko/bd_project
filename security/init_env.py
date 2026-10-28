#!/usr/bin/env python3
"""Prepare an ignored .env from .env.example without replacing existing passwords."""
import os
from pathlib import Path
import re
import secrets
import shlex


def read_env(path):
    values = {}
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            key, separator, value = line.removeprefix('export ').partition('=')
            if separator:
                value = value.strip()
                if value.startswith(("'", '"')):
                    tokens = shlex.split(value, comments=True)
                    value = tokens[0] if tokens else ''
                else:
                    value = re.split(r'\s+#', value, maxsplit=1)[0].rstrip()
                values[key.strip()] = value
    return values


def main():
    project = Path(__file__).resolve().parents[1]
    path = project / '.env'
    existing = read_env(path)
    values = read_env(project / '.env.example') | existing
    for key in ('POSTGRES_PASSWORD', 'ADMIN_PASSWORD', 'APP_PASSWORD', 'ANALYST_PASSWORD'):
        if not values.get(key):
            values[key] = secrets.token_urlsafe(32)
    values.pop('DB_SECRETS_DIR', None)
    values.pop('POSTGRES_USER', None)  # The bootstrap login is fixed in Compose.
    if not path.exists() or values != existing:
        template = (project / '.env.example').read_text().splitlines()
        lines = []
        written = set()
        for line in template:
            key, separator, _ = line.partition('=')
            if separator and key.strip() in values:
                key = key.strip()
                lines.append(f'{key}={shlex.quote(values[key])}')
                written.add(key)
            else:
                lines.append(line)
        for key, value in values.items():
            if key not in written:
                lines.append(f'{key}={shlex.quote(value)}')
        temporary = path.with_name('.env.tmp')
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, 'w') as stream:
            stream.write('\n'.join(lines) + '\n')
        temporary.replace(path)
        print('.env prepared from .env.example; existing passwords preserved.')
    else:
        print('.env already configured; values unchanged.')
    path.chmod(0o600)


if __name__ == '__main__':
    main()
