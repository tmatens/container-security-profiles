#!/usr/bin/env bash
# Workload exerciser for the prometheus reference image.
#
# Drives real function end-to-end: readiness, then the query API must show the
# default config's SELF-SCRAPE produced samples (up == 1 for localhost:9090),
# then a non-zero prometheus_tsdb_head_samples_appended_total — which
# exercises the TSDB write path under --storage.tsdb.path=/prometheus. A ready
# check alone passes before the first scrape completes, and the appended
# counter reads 0 on the scrape that first reports it, so both are polled.
#
# Probes use the in-image busybox wget; the image runs as USER nobody, so
# docker exec inherits nobody and cannot pollute a derived caps minimum.
#
# Required env: PROMETHEUSCONTAINER (target container name or id).
set -euo pipefail

: "${PROMETHEUSCONTAINER:?PROMETHEUSCONTAINER must be set}"
C="${PROMETHEUSCONTAINER}"

deadline=$((SECONDS + 45))
until docker exec "$C" wget -qO- http://localhost:9090/-/ready 2>/dev/null | grep -qi ready; do
    (( SECONDS >= deadline )) && { echo "prometheus never ready" >&2; exit 1; }
    sleep 1
done

deadline=$((SECONDS + 45))
until docker exec "$C" wget -qO- 'http://localhost:9090/api/v1/query?query=up' 2>/dev/null | grep -q '"value":\[[0-9.]*,"1"\]'; do
    (( SECONDS >= deadline )) && { echo "self-scrape never produced up==1" >&2; exit 1; }
    sleep 2
done

deadline=$((SECONDS + 60))
until docker exec "$C" wget -qO- 'http://localhost:9090/api/v1/query?query=prometheus_tsdb_head_samples_appended_total' 2>/dev/null | grep -qE '"value":\[[0-9.]*,"[1-9][0-9]*"'; do
    (( SECONDS >= deadline )) && { echo "TSDB never appended samples" >&2; exit 1; }
    sleep 2
done
