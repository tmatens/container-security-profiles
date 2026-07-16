#!/usr/bin/env bash
# Workload exerciser for the paperless-ngx reference image (in-stack, against
# a redis broker per PAPERLESS_REDIS). The full document lifecycle: token
# auth -> POST a plain-text document -> poll until consumed (web -> redis
# task queue -> celery worker -> media write). A text doc skips OCR so this
# stays fast. Curl sidecar; capture-then-match. The non-root worker uid
# assert (the s6 PUID drop) lives in the drop-test correctness check.
# Required env: PAPERLESSNGXCONTAINER (target container name or id).
set -euo pipefail
: "${PAPERLESSNGXCONTAINER:?PAPERLESSNGXCONTAINER must be set}"
C="${PAPERLESSNGXCONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }
deadline=$((SECONDS+240))
until case "$(sc -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8000/api/ 2>/dev/null)" in 200|30?|40?) true;; *) false;; esac; do
    (( SECONDS >= deadline )) && { echo "paperless web never answered" >&2; exit 1; }
    sleep 4
done
tok="$(sc -s --max-time 10 -X POST -H 'Content-Type: application/json' -d '{"username":"csdadmin","password":"CsdProbe-Pw-12345"}' http://localhost:8000/api/token/ 2>/dev/null | grep -oE '"token":"[a-f0-9]+"' | cut -d'"' -f4)"
[ -n "$tok" ] || { echo "token auth failed" >&2; exit 1; }
code="$(sc -s -o /dev/null -w '%{http_code}' --max-time 20 -H "Authorization: Token $tok" -F 'document=@/etc/hostname;filename=csd-probe.txt;type=text/plain' -F 'title=csdprobe' http://localhost:8000/api/documents/post_document/ 2>/dev/null)"
[ "$code" = 200 ] || { echo "document post failed: HTTP ${code:-none}" >&2; exit 1; }
deadline=$((SECONDS+90))
while :; do
    cnt="$(sc -s --max-time 5 -H "Authorization: Token $tok" http://localhost:8000/api/documents/ 2>/dev/null | grep -oE '"count":[0-9]+' | cut -d: -f2)"
    [ "${cnt:-0}" -ge 1 ] && break
    (( SECONDS >= deadline )) && { echo "document never consumed" >&2; exit 1; }
    sleep 4
done
