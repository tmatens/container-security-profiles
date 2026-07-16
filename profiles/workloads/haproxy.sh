#!/usr/bin/env bash
# Workload exerciser for the haproxy reference image (reverse-proxy
# invocation: frontend :8080 -> an upstream named `backend`). Real function =
# a request proxied through and answered with the backend's content, plus the
# non-root assert (the image is USER haproxy by construction).
# Required env: HAPROXYCONTAINER (target container name or id). Requires an
# HTTP responder reachable from the target as http://backend:80.
set -euo pipefail
: "${HAPROXYCONTAINER:?HAPROXYCONTAINER must be set}"
C="${HAPROXYCONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }
deadline=$((SECONDS + 30))
while :; do
    body="$(sc -s --max-time 5 http://localhost:8080/ 2>/dev/null)"
    case "$body" in *[Cc]addy*|*backend*) break;; esac
    (( SECONDS >= deadline )) && { echo "no proxied backend response" >&2; exit 1; }
    sleep 1
done
uid="$(docker exec "$C" sh -c 'awk "/^Uid:/{print \$2}" /proc/1/status')"
[ "${uid:-0}" != 0 ] || { echo "haproxy running as ROOT" >&2; exit 1; }
