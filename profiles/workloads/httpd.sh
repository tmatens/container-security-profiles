#!/usr/bin/env bash
# Workload exerciser for the httpd (Apache) reference image.
#
# GET / must return the default page body, fetched from a curl sidecar sharing
# the target's network namespace (the image ships no curl/wget). The
# master/worker uid assert lives in the drop-test correctness check (see the
# criteria doc) and is MANDATORY there: with SETUID/SETGID dropped, httpd
# keeps serving with ROOT workers — the content check alone false-passes.
#
# Required env: HTTPDCONTAINER (target container name or id).
set -euo pipefail

: "${HTTPDCONTAINER:?HTTPDCONTAINER must be set}"
C="${HTTPDCONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }

deadline=$((SECONDS + 30))
while :; do
    body="$(sc -s --max-time 5 http://localhost:80/ 2>/dev/null)"
    case "$body" in *"It works!"*) break;; esac
    (( SECONDS >= deadline )) && { echo "default page never served" >&2; exit 1; }
    sleep 1
done
