#!/usr/bin/env bash
# Correctness predicate for netdata cap_add bisection (docker.io/netdata/netdata).
#
# netdata is run as a host monitor — pid:host, host /proc,/sys,/var/run/docker.sock
# read-only mounts, host network, and the granted cap set present — then each
# candidate capability is dropped, the container restarted, and this predicate
# decides "still works CORRECTLY". Correctness is not just liveness: netdata must
# still drop root -> the unprivileged `netdata` user, or the derivation is wrong.
#
# Required env: NDCONTAINER (target container name or id).
# Exit 0 = correct; non-zero = the dropped capability was required.
set -euo pipefail
: "${NDCONTAINER:?NDCONTAINER must be set}"

# 1. Healthy within the container's own healthcheck window.
deadline=$((SECONDS + 75))
until [ "$(docker inspect -f '{{.State.Health.Status}}' "$NDCONTAINER" 2>/dev/null)" = healthy ]; do
    [ "$(docker inspect -f '{{.State.Status}}' "$NDCONTAINER" 2>/dev/null)" != running ] && { echo "not running"; exit 1; }
    (( SECONDS >= deadline )) && { echo "did not become healthy"; exit 1; }
    sleep 3
done

# 2. HTTP API up and a per-process collector (apps.plugin, needs SYS_PTRACE) active.
curl -fsS --max-time 5 http://localhost:19999/api/v1/info >/dev/null || { echo "API down"; exit 1; }
curl -fsS --max-time 5 http://localhost:19999/api/v1/charts | grep -q '"apps\.' || { echo "apps.plugin not collecting"; exit 1; }

# 3. CORRECTNESS: the netdata daemon dropped privileges (must NOT be uid 0/root).
pid="$(docker inspect -f '{{.State.Pid}}' "$NDCONTAINER")"
uid="$(awk '/^Uid:/{print $2}' /proc/"$pid"/status)"
[ "$uid" != 0 ] || { echo "daemon is running as ROOT (privilege drop failed)"; exit 1; }

echo "netdata correct: healthy, API up, apps.plugin collecting, daemon uid=$uid (non-root)"
