#!/usr/bin/env bash
# Workload exerciser for the valkey / redis reference image.
#
# Connects to a running container and drives a representative round-trip —
# PING, then SET and GET a key. Returns 0 if every step succeeded. The
# non-root privilege-drop is asserted by the drop-test correctness check (see
# the criteria doc), not here.
#
# Required env: REDISCONTAINER (target container name or id).
set -euo pipefail

: "${REDISCONTAINER:?REDISCONTAINER must be set}"

# Probes run as the valkey user (never root — a root probe's own needs would
# pollute the derived minimum) and capture-then-match (never `producer | grep -q`
# under pipefail: grep's early exit SIGPIPEs the producer and a matching
# response reads as failure).
deadline=$((SECONDS + 30))
until grep -qi PONG <<<"$(docker exec --user valkey "${REDISCONTAINER}" redis-cli ping 2>/dev/null)"; do
    if (( SECONDS >= deadline )); then
        echo "valkey did not respond to PING in 30s" >&2
        exit 1
    fi
    sleep 1
done

docker exec --user valkey "${REDISCONTAINER}" redis-cli set csd:probe ok >/dev/null
value="$(docker exec --user valkey "${REDISCONTAINER}" redis-cli get csd:probe | tr -d '[:space:]')"
if [ "$value" != ok ]; then
    echo "GET returned '${value}' (expected 'ok')" >&2
    exit 1
fi
