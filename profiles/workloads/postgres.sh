#!/usr/bin/env bash
# Workload exerciser for the postgres reference image.
#
# Connects to a running postgres container and drives a representative set
# of operations — schema create, insert, select, drop — followed by a
# SIGHUP-triggered config reload. Returns 0 if every step succeeded.
#
# Required env: PGCONTAINER (target container name or id).
# Optional env: PGPASSWORD (defaults to "postgres"), PGUSER (defaults to
# "postgres"), PGDATABASE (defaults to "postgres").
set -euo pipefail

: "${PGCONTAINER:?PGCONTAINER must be set}"
: "${PGPASSWORD:=postgres}"
: "${PGUSER:=postgres}"
: "${PGDATABASE:=postgres}"

# Probes exec as the postgres user, never root — a root probe's own needs
# would pollute the derived minimum (the rabbitmq lesson).
psql_in_container() {
    docker exec --user postgres -e "PGPASSWORD=${PGPASSWORD}" "${PGCONTAINER}" \
        psql -v ON_ERROR_STOP=1 -U "${PGUSER}" -d "${PGDATABASE}" "$@"
}

# Wait until pg_isready.
deadline=$((SECONDS + 60))
until docker exec --user postgres "${PGCONTAINER}" pg_isready -U "${PGUSER}" -q; do
    if (( SECONDS >= deadline )); then
        echo "postgres did not become ready in 60s" >&2
        exit 1
    fi
    sleep 1
done

psql_in_container -c 'CREATE TABLE csd_smoke (id INT, label TEXT);'
psql_in_container -c "INSERT INTO csd_smoke VALUES (1, 'a'), (2, 'b'), (3, 'c');"
psql_in_container -c 'SELECT count(*) FROM csd_smoke;'
psql_in_container -c 'DROP TABLE csd_smoke;'

# Trigger a config reload (SIGHUP path).
docker kill --signal=SIGHUP "${PGCONTAINER}"
sleep 1
psql_in_container -c 'SELECT 1;'

# CORRECTNESS: the server (PID 1) completed the root->postgres drop. Load-bearing:
# with SETUID/SETGID dropped the entrypoint's gosu re-exec fails — a query-only
# check must not bless a server still running as root. /proc is parsed tool-free
# (no awk/cut — not guaranteed on minimal bases).
uid="$(docker exec "${PGCONTAINER}" sh -c \
    'while read -r k v _; do [ "$k" = "Uid:" ] && { echo "$v"; break; }; done </proc/1/status')"
if [ "${uid:-0}" = 0 ] || [ -z "${uid}" ]; then
    echo "postgres server is running as ROOT (privilege drop failed; uid='${uid}')" >&2
    exit 1
fi
