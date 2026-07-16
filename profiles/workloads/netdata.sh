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
# chart_nonzero <chart-id> -> 0 if the latest sample has a NON-ZERO value.
# Non-zero, not merely non-null: apps.plugin denied access to a process's /proc
# reports the metric as 0 (not null), so a non-null check passes on broken
# collection. A live process always has open fds > 0.
chart_nonzero() {
    curl -fsS --max-time 4 "${API}/api/v1/data?chart=$1&after=-20&points=1&format=json" 2>/dev/null \
        | python3 -c 'import sys,json
try:
 rows=json.load(sys.stdin).get("data",[])
 sys.exit(0 if [v for r in rows for v in r[1:] if v is not None and v != 0] else 1)
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
# capture then grep — piping the (large) charts dump into `grep -q` can SIGPIPE
# curl and, under pipefail, mark the pipeline failed despite a match.
charts="$(curl -fsS --max-time 5 "${API}/api/v1/charts")" || { echo "charts API down"; exit 1; }
grep -q '"apps\.' <<<"$charts" || { echo "apps.plugin not collecting"; exit 1; }

# 3. CORRECTNESS: the netdata daemon dropped privileges (must NOT be uid 0/root).
pid="$(docker inspect -f '{{.State.Pid}}' "$NDCONTAINER")"
uid="$(awk '/^Uid:/{print $2}' /proc/"$pid"/status)"
[ "$uid" != 0 ] || { echo "daemon is running as ROOT (privilege drop failed)"; exit 1; }

# 4. CORRECTNESS: per-process io/fd metrics are actually COLLECTED (non-zero).
# apps.plugin runs real-uid = the netdata user (setuid gives euid 0, not real uid
# 0), so it needs CAP_SYS_PTRACE to read ANY process's /proc/<pid>/io|fd; without
# it, it reports every per-process metric as 0 (not null). So require a per-process
# fds_open to be NON-ZERO — dropping SYS_PTRACE zeros it. (A prior non-null check
# passed on all-zeros and wrongly derived SYS_PTRACE removable, regressing prod.)
ppok=0
for _ in 1 2 3 4 5 6 7 8; do
    for ch in app.dockerd_fds_open app.netdata_fds_open app.systemd-journald_fds_open app.containerd_fds_open; do
        if chart_nonzero "$ch"; then ppok=1; PPCH="$ch"; break 2; fi
    done
    sleep 3
done
[ "$ppok" = 1 ] || { echo "per-process metrics all zero — apps.plugin can't read /proc/<pid>/fd (SYS_PTRACE gap)"; exit 1; }

echo "netdata correct: healthy, API up, daemon uid=$uid (non-root), per-process metrics collecting non-zero ($PPCH)"
