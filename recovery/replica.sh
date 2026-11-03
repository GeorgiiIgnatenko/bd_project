#!/bin/sh
set -eu
# The connection string stored by -R contains a passfile path, never the password.
umask 077
mkdir -p /var/lib/postgresql
escaped_password=$(printf '%s' "$REPLICATION_PASSWORD" | sed 's/\\/\\\\/g; s/:/\\:/g')
printf 'postgres:5432:replication:news_replicator:%s\n' "$escaped_password" > /var/lib/postgresql/replication.pgpass
chmod 600 /var/lib/postgresql/replication.pgpass
chown postgres:postgres /var/lib/postgresql/replication.pgpass
unset REPLICATION_PASSWORD escaped_password
if [ ! -f "$PGDATA/.basebackup-complete" ]; then
    if [ -d "$PGDATA" ] && [ -n "$(ls -A "$PGDATA")" ]; then
        echo 'Incomplete/unmanaged replica data: recreate only the replica volume as documented.' >&2
        exit 1
    fi
    mkdir -p "$PGDATA"
    chown postgres:postgres "$(dirname "$PGDATA")"
    chown postgres:postgres "$PGDATA"
    chmod 700 "$PGDATA"
    gosu postgres pg_basebackup -d 'host=postgres port=5432 user=news_replicator application_name=news_replica passfile=/var/lib/postgresql/replication.pgpass connect_timeout=5' \
        -D "$PGDATA" -R -X stream --checkpoint=fast -w
    touch "$PGDATA/.basebackup-complete"
    chown postgres:postgres "$PGDATA/.basebackup-complete"
fi
exec /usr/local/bin/docker-entrypoint.sh "$@"
