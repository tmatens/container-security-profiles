#!/usr/bin/env bash
# Workload exerciser for the nextcloud reference image (apache variant,
# in-stack against a mariadb database per MYSQL_* env, admin auto-installed
# via NEXTCLOUD_ADMIN_*).
#
# Real function: wait for `occ status` to report installed, then a WebDAV
# PUT/GET round-trip as the admin — a real file write into nextcloud's data
# dir through the full apache -> php -> storage path — asserting the payload
# reads back byte-identical.
#
# Probe hygiene: occ runs as --user www-data (a root probe pollutes a caps
# minimum); WebDAV goes through a curl sidecar; responses are captured then
# matched (never `curl | grep -q` under pipefail — SIGPIPE false-negatives).
# Derivation-time only: a fresh-docroot container cannot adopt an installed
# database (it boots "installed: false"); the csd drop-test correctness check
# resets the dep database and restarts the target — see the criteria doc.
#
# Required env: NEXTCLOUDCONTAINER (target container name or id).
set -euo pipefail

: "${NEXTCLOUDCONTAINER:?NEXTCLOUDCONTAINER must be set}"
C="${NEXTCLOUDCONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }

deadline=$((SECONDS + 180))
until docker exec --user www-data "$C" php occ status 2>/dev/null | grep -q "installed: true"; do
    (( SECONDS >= deadline )) && { echo "nextcloud never reported installed (fresh-docroot + installed DB needs a DB reset — see criteria)" >&2; exit 1; }
    sleep 5
done

sc -sf --max-time 15 -u csdadmin:CsdProbe-Pw-12345 -X PUT \
    --data-binary "csd-payload-42" \
    http://localhost:80/remote.php/dav/files/csdadmin/csd-probe.txt >/dev/null
got="$(sc -s --max-time 15 -u csdadmin:CsdProbe-Pw-12345 \
    http://localhost:80/remote.php/dav/files/csdadmin/csd-probe.txt 2>/dev/null)"
if [ "$got" != "csd-payload-42" ]; then
    echo "WebDAV round-trip mismatch (got: ${got:0:60})" >&2
    exit 1
fi
