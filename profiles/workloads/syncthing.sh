#!/usr/bin/env bash
# Workload exerciser for the syncthing reference image. Reads the generated
# API key from config.xml (as the syncthing uid), asserts system/status
# returns a device ID, adds a folder via the config REST API and reads it
# back. In-image curl; capture-then-match.
# Required env: SYNCTHINGCONTAINER (target container name or id).
set -euo pipefail
: "${SYNCTHINGCONTAINER:?SYNCTHINGCONTAINER must be set}"
C="${SYNCTHINGCONTAINER}"
deadline=$((SECONDS + 60))
until docker exec "$C" test -s /var/syncthing/config/config.xml 2>/dev/null; do
    (( SECONDS >= deadline )) && { echo "config.xml never appeared" >&2; exit 1; }
    sleep 2
done
KEY="$(docker exec "$C" sh -c 'grep -oE "<apikey>[^<]*" /var/syncthing/config/config.xml | cut -d">" -f2')"
[ -n "$KEY" ] || { echo "no API key" >&2; exit 1; }
deadline=$((SECONDS + 45))
while :; do
    st="$(docker exec --user 1000 "$C" curl -s --max-time 5 -H "X-API-Key: $KEY" http://localhost:8384/rest/system/status 2>/dev/null)"
    case "$st" in *'"myID"'*) break;; esac
    (( SECONDS >= deadline )) && { echo "system/status never answered" >&2; exit 1; }
    sleep 2
done
code="$(docker exec --user 1000 "$C" curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X PUT -H "X-API-Key: $KEY" -H 'Content-Type: application/json' -d '{"id":"csd","label":"csd","path":"/var/syncthing/csd-folder"}' http://localhost:8384/rest/config/folders/csd 2>/dev/null)"
case "$code" in 2??) ;; *) echo "folder add failed: HTTP ${code:-none}" >&2; exit 1;; esac
back="$(docker exec --user 1000 "$C" curl -s --max-time 5 -H "X-API-Key: $KEY" http://localhost:8384/rest/config/folders/csd 2>/dev/null)"
case "$back" in *csd*) ;; *) echo "folder readback failed" >&2; exit 1;; esac
