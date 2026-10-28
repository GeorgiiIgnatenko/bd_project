#!/bin/sh
# Usage: sh generator/run.sh dev|load seed
set -eu

if [ "$#" -ne 2 ]; then
  echo 'Usage: sh generator/run.sh dev|load seed' >&2
  exit 64
fi
mode=$1
seed=$2
case "$mode" in
  dev|load) ;;
  *) echo 'Mode must be dev or load.' >&2; exit 64 ;;
esac
case "$seed" in
  ''|*[!0-9]*) echo 'Seed must be an integer from 0 to 2147483647.' >&2; exit 64 ;;
esac

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
exec docker compose run --rm -T admin \
  -v mode="$mode" -v seed="$seed" \
  -f /workspace/generator/generate.sql -f /workspace/security/grants.sql
