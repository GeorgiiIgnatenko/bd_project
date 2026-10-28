#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$project_dir"
python3 security/init_env.py
docker compose up -d --wait postgres
sh security/apply.sh
