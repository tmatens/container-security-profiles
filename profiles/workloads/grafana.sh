#!/usr/bin/env bash
# Workload exerciser for the grafana reference image.
#
# Drives grafana's real function under a read-only rootfs (with /var/lib/grafana
# writable — the persistent data volume): the database is reachable, a dashboard
# can be written and read back (a real sqlite write on the data volume), and a
# backend datasource plugin runs. Returns 0 if every step succeeds.
#
# SCOPE: this covers grafana core + datasource querying + DB. A writable /tmp is
# used only by grafana's runtime plugin *installation*, the elasticsearch
# datasource plugin, and image rendering / data export — not exercised here (see
# the criteria doc).
#
# Required env: GRAFANACONTAINER (target container name or id). The container is
# expected to have been started with GF_SECURITY_ADMIN_PASSWORD set.
set -euo pipefail

: "${GRAFANACONTAINER:?GRAFANACONTAINER must be set}"
C="${GRAFANACONTAINER}"
B='http://admin:$GF_SECURITY_ADMIN_PASSWORD@localhost:3000'

deadline=$((SECONDS + 45))
until docker exec "$C" sh -c "curl -sf \"$B/api/health\" 2>/dev/null | grep -q '\"database\": \"ok\"'"; do
    if (( SECONDS >= deadline )); then
        echo "grafana /api/health never reported database ok" >&2
        exit 1
    fi
    sleep 1
done

uid="$(docker exec "$C" sh -c "curl -s -X POST -H 'Content-Type: application/json' -d '{\"dashboard\":{\"title\":\"csd-probe\",\"panels\":[]},\"overwrite\":true}' \"$B/api/dashboards/db\"" 2>/dev/null | sed -n 's/.*\"uid\":\"\([^\"]*\)\".*/\1/p' | head -1)"
if [ -z "$uid" ]; then
    echo "dashboard create failed (DB write path broken)" >&2
    exit 1
fi
docker exec "$C" sh -c "curl -sf -o /dev/null \"$B/api/dashboards/uid/$uid\"" 2>/dev/null || { echo "dashboard read-back failed" >&2; exit 1; }

duid="$(docker exec "$C" sh -c "curl -s -X POST -H 'Content-Type: application/json' -d '{\"name\":\"csd-loki\",\"type\":\"loki\",\"access\":\"proxy\",\"url\":\"http://127.0.0.1:9\"}' \"$B/api/datasources\"" 2>/dev/null | sed -n 's/.*\"uid\":\"\([^\"]*\)\".*/\1/p' | head -1)"
body="$(docker exec "$C" sh -c "curl -s \"$B/api/datasources/uid/$duid/health\"" 2>/dev/null)"
grep -q '"status"' <<<"$body" || { echo "Loki datasource backend plugin not running: ${body:0:120}" >&2; exit 1; }
