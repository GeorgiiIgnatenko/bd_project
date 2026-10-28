"""libpq settings shared by experiment runners; local credentials come from .env."""
import os
from pathlib import Path
import re
import shlex


def connection():
    env = os.environ.copy()
    settings = {}
    path = Path(__file__).resolve().parents[1] / '.env'
    if path.exists():
        for line in path.read_text().splitlines():
            key, separator, value = line.partition('=')
            if separator and not key.strip().startswith('#'):
                value = value.strip()
                if value.startswith(("'", '"')):
                    tokens = shlex.split(value, comments=True)
                    value = tokens[0] if tokens else ''
                else:
                    value = re.split(r'\s+#', value, maxsplit=1)[0].rstrip()
                settings[key.strip()] = value
    env.setdefault('PGHOST', '127.0.0.1')
    env.setdefault('PGPORT', settings.get('POSTGRES_PORT', '55432'))
    env.setdefault('PGUSER', 'news_admin')
    env.setdefault('PGDATABASE', settings.get('POSTGRES_DB', 'news_aggregator'))
    if 'PGPASSWORD' not in env and 'PGPASSFILE' not in env:
        key = {'news_admin': 'ADMIN_PASSWORD', 'news_app': 'APP_PASSWORD',
               'news_analyst': 'ANALYST_PASSWORD'}.get(env['PGUSER'])
        if not key or not settings.get(key):
            raise RuntimeError('Configure .env with sh start.sh or set PGPASSWORD/PGPASSFILE.')
        env['PGPASSWORD'] = settings[key]
    env['PAGER'] = 'cat'
    return ['psql', '-X', '-w', '-P', 'pager=off'], env
