#!/usr/bin/env bash
# Workload exerciser for the redis reference image.
#
# Connects to a running container and drives a representative round-trip —
# PING, SET and GET a key, then a synchronous SAVE (a real RDB write to the
# /data volume). Returns 0 if every step succeeded. The non-root
# privilege-drop is asserted by the drop-test correctness check (see the
# criteria doc), not here — that assertion is load-bearing: with SETUID or
# SETGID dropped, redis keeps serving correctly AS ROOT, so a workload-only
# check would falsely call both removable.
#
# Required env: REDISCONTAINER (target container name or id).
set -euo pipefail

: "${REDISCONTAINER:?REDISCONTAINER must be set}"

deadline=$((SECONDS + 30))
until docker exec "${REDISCONTAINER}" redis-cli ping 2>/dev/null | grep -qi PONG; do
    if (( SECONDS >= deadline )); then
        echo "redis did not respond to PING in 30s" >&2
        exit 1
    fi
    sleep 1
done

docker exec "${REDISCONTAINER}" redis-cli set csd:probe ok >/dev/null
value="$(docker exec "${REDISCONTAINER}" redis-cli get csd:probe | tr -d '[:space:]')"
if [ "$value" != ok ]; then
    echo "GET returned '${value}' (expected 'ok')" >&2
    exit 1
fi

docker exec "${REDISCONTAINER}" redis-cli save | grep -q OK || {
    echo "SAVE failed (cannot write the RDB to /data)" >&2
    exit 1
}
