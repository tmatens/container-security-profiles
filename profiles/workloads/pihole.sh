#!/usr/bin/env bash
# Workload exerciser for the pihole reference image (DNS-only scope).
#
# Real DNS resolution with no external dependence: dig the `pi.hole` name,
# which pihole-FTL answers authoritatively itself — deterministic, no
# upstream reachability in the loop. Probes exec as --user pihole using the
# in-image dig (a root probe pollutes a caps minimum). The non-root FTL uid
# assert lives in the drop-test correctness check.
#
# Required env: PIHOLECONTAINER (target container name or id).
set -euo pipefail

: "${PIHOLECONTAINER:?PIHOLECONTAINER must be set}"
C="${PIHOLECONTAINER}"

deadline=$((SECONDS + 90))
until docker logs "$C" 2>&1 | grep -q "listening on .* port 53"; do
    (( SECONDS >= deadline )) && { echo "FTL never listened on 53" >&2; exit 1; }
    sleep 2
done

ans="$(docker exec --user pihole "$C" dig +short +time=3 +tries=2 @127.0.0.1 pi.hole 2>/dev/null)"
if [ -z "$ans" ]; then
    echo "dig pi.hole returned no answer" >&2
    exit 1
fi
