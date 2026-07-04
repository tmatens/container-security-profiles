#!/usr/bin/env bash
# Workload exerciser for the itzg/mc-backup reference image — a DEPENDENT tier.
#
# mc-backup RCON-flushes a running minecraft server and tars its SHARED /data into
# /backups, so it can only be exercised IN-STACK: the target container must be
# running alongside a minecraft server it RCONs (RCON_HOST) and sharing minecraft's
# /data (docker-compose volumes_from / a shared named volume). container-sec-derive
# derives it with a `deps: [minecraft]` + `run.volumes_from: [minecraft]` spec.
#
# A REAL backup CONTAINS the world (many entries); mc-backup runs as root and can
# create the archive FILE even when it cannot READ the uid-1000 /data, producing a
# 0-entry empty tarball. So this counts entries, which is what actually gates the
# read capability (DAC_OVERRIDE) — not mere file existence.
#
# Required env: MCBACKUPCONTAINER (a running, in-stack mc-backup container).
set -euo pipefail
: "${MCBACKUPCONTAINER:?MCBACKUPCONTAINER must be set}"
C="${MCBACKUPCONTAINER}"

entries() {
  local f; f="$(docker exec "$C" sh -c 'ls -t /backups/*.tgz /backups/*.tar.gz /backups/*.tar 2>/dev/null | head -1' 2>/dev/null)"
  [ -n "$f" ] || { echo 0; return; }
  docker exec "$C" sh -c "tar tzf '$f' 2>/dev/null | wc -l" 2>/dev/null | tr -dc 0-9
}

deadline=$((SECONDS+90))
while :; do
  n="$(entries)"; n="${n:-0}"
  [ "$n" -ge 5 ] && exit 0
  (( SECONDS >= deadline )) && { echo "no real backup: newest archive has ${n} entries (empty tar -> mc-backup could not read the shared /data)" >&2; exit 1; }
  sleep 2
done
