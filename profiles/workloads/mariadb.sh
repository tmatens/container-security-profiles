#!/usr/bin/env bash
# Workload exerciser for the mariadb reference image.
#
# Connects as the configured application user and drives a representative
# round-trip — CREATE a table, INSERT, SELECT it back, DROP. Returns 0 if every
# step succeeded. The non-root privilege-drop (the entrypoint's gosu root->mysql)
# is asserted by the drop-test correctness check (see the criteria doc), not here.
#
# Required env: MARIADBCONTAINER (target container name or id). The container is
# expected to have been started with MARIADB_USER / MARIADB_PASSWORD /
# MARIADB_DATABASE set (root@localhost is unix_socket-only in MariaDB 11.x).
set -euo pipefail

: "${MARIADBCONTAINER:?MARIADBCONTAINER must be set}"
C="${MARIADBCONTAINER}"

# Probes exec as the mysql user, never root — a root probe's own needs would
# pollute the derived minimum (the rabbitmq lesson).
deadline=$((SECONDS + 45))
until docker exec --user mysql "$C" sh -c 'MYSQL_PWD=$MARIADB_PASSWORD mariadb -u"$MARIADB_USER" -e "SELECT 1" >/dev/null 2>&1'; do
    if (( SECONDS >= deadline )); then
        echo "mariadb did not accept an app-user connection in 45s" >&2
        exit 1
    fi
    sleep 1
done

out="$(docker exec --user mysql "$C" sh -c 'MYSQL_PWD=$MARIADB_PASSWORD mariadb -u"$MARIADB_USER" "$MARIADB_DATABASE" -N -e "CREATE TABLE IF NOT EXISTS csd_probe(id INT); INSERT INTO csd_probe VALUES(42); SELECT id FROM csd_probe LIMIT 1; DROP TABLE csd_probe;"' 2>&1)"
if [ "$out" != 42 ]; then
    echo "workload round-trip failed (got: ${out##*$'\n'})" >&2
    exit 1
fi
