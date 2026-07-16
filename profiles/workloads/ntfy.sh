#!/usr/bin/env bash
# Workload exerciser for the ntfy reference image (`serve`, default config —
# in-memory store). Real function = publish a message to a topic and poll it
# back, matching the payload. Probes ride a curl sidecar, write nothing in
# the target, capture-then-match.
# Required env: NTFYCONTAINER (target container name or id).
set -euo pipefail
: "${NTFYCONTAINER:?NTFYCONTAINER must be set}"
C="${NTFYCONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }
deadline=$((SECONDS + 30))
until [ "$(sc -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:80/v1/health 2>/dev/null)" = 200 ]; do
    (( SECONDS >= deadline )) && { echo "ntfy never healthy" >&2; exit 1; }
    sleep 1
done
code="$(sc -s -o /dev/null -w '%{http_code}' --max-time 5 -d "csd-msg-42" http://localhost:80/csdtopic 2>/dev/null)"
[ "$code" = 200 ] || { echo "publish failed: HTTP ${code:-none}" >&2; exit 1; }
got="$(sc -s --max-time 5 "http://localhost:80/csdtopic/json?poll=1&since=all" 2>/dev/null)"
case "$got" in *'"message":"csd-msg-42"'*) ;; *) echo "poll missing message" >&2; exit 1;; esac
