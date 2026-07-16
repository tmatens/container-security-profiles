#!/usr/bin/env bash
# Workload exerciser for the mysql reference image.
#
# Connects as the configured application user and drives a representative
# round-trip — CREATE a table, INSERT, SELECT it back, DROP — mirroring the
# official docker-library mysql-basics test shape. Returns 0 if every step
# succeeded. The non-root privilege-drop (the entrypoint's gosu root->mysql)
# is asserted by the drop-test correctness check (see the criteria doc), not
# here.
#
# Required env: MYSQLCONTAINER (target container name or id). The container is
# expected to have been started with MYSQL_USER / MYSQL_PASSWORD /
# MYSQL_DATABASE (and MYSQL_ROOT_PASSWORD, which the image requires) set.
set -euo pipefail

: "${MYSQLCONTAINER:?MYSQLCONTAINER must be set}"
C="${MYSQLCONTAINER}"

# mysql 8.x first-boot initialisation is slower than mariadb; allow 90s. The
# app-user connect proves the real server is up and init created the user —
# not the transient bootstrap server.
deadline=$((SECONDS + 90))
until docker exec "$C" sh -c 'MYSQL_PWD=$MYSQL_PASSWORD mysql -u"$MYSQL_USER" -e "SELECT 1" >/dev/null 2>&1'; do
    if (( SECONDS >= deadline )); then
        echo "mysql did not accept an app-user connection in 90s" >&2
        exit 1
    fi
    sleep 1
done

out="$(docker exec "$C" sh -c 'MYSQL_PWD=$MYSQL_PASSWORD mysql -u"$MYSQL_USER" "$MYSQL_DATABASE" -N -e "CREATE TABLE IF NOT EXISTS csd_probe(id INT); INSERT INTO csd_probe VALUES(42); SELECT id FROM csd_probe LIMIT 1; DROP TABLE csd_probe;"' 2>&1)"
if [ "$out" != 42 ]; then
    echo "workload round-trip failed (got: ${out##*$'\n'})" >&2
    exit 1
fi
