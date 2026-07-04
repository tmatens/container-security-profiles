#!/usr/bin/env bash
# Workload exerciser for the alloy (Grafana Alloy) reference image.
#
# alloy is DISTROLESS (no shell/curl), so it is probed from a SIDECAR container
# sharing alloy's network namespace (`docker run --network container:<target>`) and
# reaching it on localhost:12345 — not `docker exec`. The probe image is a pinned,
# multi-arch curl.
#
# Under the image default invocation alloy loads its pipeline and writes its data
# under --storage.path; alloy fatals at startup if that path isn't writable, so
# "ready + a live pipeline" exercises the storage.path write. Returns 0 on success.
#
# Required env: ALLOYCONTAINER (target container name or id).
set -euo pipefail

: "${ALLOYCONTAINER:?ALLOYCONTAINER must be set}"
C="${ALLOYCONTAINER}"
# curlimages/curl:8.11.1 — multi-arch, digest-pinned (test-only probe image).
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }

deadline=$((SECONDS + 45))
until [ "$(sc -s -o /dev/null -w '%{http_code}' http://localhost:12345/-/ready 2>/dev/null)" = 200 ]; do
    if (( SECONDS >= deadline )); then
        echo "alloy /-/ready never returned 200 in 45s" >&2
        exit 1
    fi
    sleep 1
done

n="$(sc -s http://localhost:12345/metrics 2>/dev/null | grep -c '^alloy_')"
if [ "${n:-0}" -lt 1 ]; then
    echo "no alloy_ metrics — pipeline not running" >&2
    exit 1
fi
