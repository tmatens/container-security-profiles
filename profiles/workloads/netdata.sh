#!/usr/bin/env bash
# Correctness check for netdata cap_add bisection (docker.io/netdata/netdata).
#
# netdata is run as a host monitor — pid:host, host /proc,/sys,/var/run/docker.sock
# read-only mounts, host network, and the granted cap set present — then each
# candidate capability is dropped, the container restarted, and this correctness check
# decides "still works CORRECTLY". Correctness is not just liveness: netdata must
# still drop root -> the unprivileged `netdata` user AND still collect per-process
# metrics for non-root processes, or the derivation is wrong.
#
# Required env: NDCONTAINER (target container name or id).
# Exit 0 = correct; non-zero = the dropped capability was required.
set -euo pipefail
: "${NDCONTAINER:?NDCONTAINER must be set}"

API=http://localhost:19999
# chart_has_data <chart-id> -> 0 if the latest sample has a non-null value.
chart_has_data() {
    curl -fsS --max-time 4 "${API}/api/v1/data?chart=$1&after=-20&points=1&format=json" 2>/dev/null \
        | python3 -c 'import sys,json
try:
 rows=json.load(sys.stdin).get("data",[])
 sys.exit(0 if [v for r in rows for v in r[1:] if v is not None] else 1)
except Exception:
 sys.exit(1)'
}

# 1. Healthy within the container's own healthcheck window.
deadline=$((SECONDS + 75))
until [ "$(docker inspect -f '{{.State.Health.Status}}' "$NDCONTAINER" 2>/dev/null)" = healthy ]; do
    [ "$(docker inspect -f '{{.State.Status}}' "$NDCONTAINER" 2>/dev/null)" != running ] && { echo "not running"; exit 1; }
    (( SECONDS >= deadline )) && { echo "did not become healthy"; exit 1; }
    sleep 3
done

# 2. HTTP API up and apps.plugin collecting.
curl -fsS --max-time 5 "${API}/api/v1/info" >/dev/null || { echo "API down"; exit 1; }
curl -fsS --max-time 5 "${API}/api/v1/charts" | grep -q '"apps\.' || { echo "apps.plugin not collecting"; exit 1; }

# 3. CORRECTNESS: the netdata daemon dropped privileges (must NOT be uid 0/root).
pid="$(docker inspect -f '{{.State.Pid}}' "$NDCONTAINER")"
uid="$(awk '/^Uid:/{print $2}' /proc/"$pid"/status)"
[ "$uid" != 0 ] || { echo "daemon is running as ROOT (privilege drop failed)"; exit 1; }

# 4. CORRECTNESS: per-process io/fd metrics collect for a NON-ROOT process group
# (netdata's own uid-201 processes). Reading another uid's /proc/<pid>/io|fd is
# what DAC_OVERRIDE / SYS_PTRACE would gate — asserting a non-root group's data
# (not a root process, seen for free) is what makes those caps honestly testable.
ppdata=0
for _ in 1 2 3 4 5 6 7 8; do
    for ch in app.netdata_fds_open app.netdata_disk_logical_io app.polkitd_fds_open; do
        if chart_has_data "$ch"; then ppdata=1; PPCH="$ch"; break 2; fi
    done
    sleep 3
done
[ "$ppdata" = 1 ] || { echo "no per-process metrics for a non-root group (DAC_OVERRIDE/SYS_PTRACE gap)"; exit 1; }

echo "netdata correct: healthy, API up, daemon uid=$uid (non-root), per-process metrics collecting for non-root group ($PPCH)"
