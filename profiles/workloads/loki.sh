#!/usr/bin/env bash
# Workload exerciser for the loki reference image.
#
# loki is DISTROLESS (no shell/curl), so it is probed from a SIDECAR container that
# shares loki's network namespace (`docker run --network container:<target>`) and
# reaches it on localhost:3100 — rather than `docker exec`, which has nothing to run
# inside a distroless image. The probe image is a pinned, multi-arch curl.
#
# Drives loki's real read+write path under a read-only rootfs (with /loki writable —
# the persistent data volume): push a log line and query it back. Returns 0 on
# success.
#
# Required env: LOKICONTAINER (target container name or id).
set -euo pipefail

: "${LOKICONTAINER:?LOKICONTAINER must be set}"
C="${LOKICONTAINER}"
# curlimages/curl:8.11.1 — multi-arch, digest-pinned (test-only probe image).
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }

deadline=$((SECONDS + 60))
until [ "$(sc -s http://localhost:3100/ready 2>/dev/null)" = ready ]; do
    if (( SECONDS >= deadline )); then
        echo "loki /ready never reported ready in 60s" >&2
        exit 1
    fi
    sleep 2
done

ts="$(date +%s%N)"
code="$(sc -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    --data "{\"streams\":[{\"stream\":{\"job\":\"csd\"},\"values\":[[\"$ts\",\"csd-probe-line\"]]}]}" \
    http://localhost:3100/loki/api/v1/push 2>/dev/null)"
if [ "$code" != 204 ]; then
    echo "loki push returned HTTP $code (expected 204)" >&2
    exit 1
fi

start=$((ts - 300000000000)); end=$((ts + 300000000000))
for _ in 1 2 3 4 5; do
    if sc -s "http://localhost:3100/loki/api/v1/query_range?query=%7Bjob%3D%22csd%22%7D&start=$start&end=$end&limit=5" 2>/dev/null | grep -q csd-probe-line; then
        exit 0
    fi
    sleep 1
done
echo "pushed log line not returned by query (loki read/write path broken)" >&2
exit 1
