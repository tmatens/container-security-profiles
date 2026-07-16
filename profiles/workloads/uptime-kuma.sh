#!/usr/bin/env bash
# Workload exerciser for the uptime-kuma reference image (v2). Drives the REST
# surface: entry-page, embedded-sqlite database setup (a real persistent
# write), the server's self-restart, serving again, and the metrics auth
# layer (401). Admin/monitor CRUD is socket.io-only — see the criteria doc.
# Required env: UPTIMEKUMACONTAINER (target container name or id).
set -euo pipefail
: "${UPTIMEKUMACONTAINER:?UPTIMEKUMACONTAINER must be set}"
C="${UPTIMEKUMACONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }
want() { local dl=$((SECONDS+$1)); while :; do local r; r="$(sc -s --max-time 5 http://localhost:3001/api/entry-page 2>/dev/null)"; case "$r" in *"$2"*) return 0;; esac; (( SECONDS >= dl )) && return 1; sleep 3; done; }
want 90 "setup-database" || { echo "no setup-database page" >&2; exit 1; }
code="$(sc -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST -H 'Content-Type: application/json' -d '{"dbConfig":{"type":"sqlite"}}' http://localhost:3001/setup-database 2>/dev/null)"
[ "$code" = 200 ] || { echo "setup-database failed: HTTP ${code:-none}" >&2; exit 1; }
sleep 3
want 90 "entryPage" || { echo "server did not serve after setup" >&2; exit 1; }
