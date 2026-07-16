#!/usr/bin/env bash
# Workload exerciser for the adguardhome reference image (DNS-only). Drives the
# REST install/configure (admin + DNS:53 + web:80 in one call), adds a LOCAL
# DNS rewrite (csd.test -> 127.0.0.1) so resolution is answered by AGH itself
# with no upstream in the loop, then asserts nslookup returns 127.0.0.1.
# Required env: ADGUARDHOMECONTAINER (target container name or id).
set -euo pipefail
: "${ADGUARDHOMECONTAINER:?ADGUARDHOMECONTAINER must be set}"
C="${ADGUARDHOMECONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }
deadline=$((SECONDS+45))
while :; do
    code="$(sc -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:3000/ 2>/dev/null)"
    case "$code" in 200|30?) break;; esac
    (( SECONDS >= deadline )) && { echo "setup UI never came up" >&2; exit 1; }
    sleep 2
done
c="$(sc -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST -H 'Content-Type: application/json' -d '{"web":{"ip":"0.0.0.0","port":80},"dns":{"ip":"0.0.0.0","port":53},"username":"csdadmin","password":"CsdProbe-Pw-12345"}' http://localhost:3000/control/install/configure 2>/dev/null)"
[ "$c" = 200 ] || { echo "configure failed: HTTP ${c:-none}" >&2; exit 1; }
r="$(sc -s -o /dev/null -w '%{http_code}' --max-time 10 -u csdadmin:CsdProbe-Pw-12345 -X POST -H 'Content-Type: application/json' -d '{"domain":"csd.test","answer":"127.0.0.1"}' http://localhost:80/control/rewrite/add 2>/dev/null)"
[ "$r" = 200 ] || { echo "rewrite add failed: HTTP ${r:-none}" >&2; exit 1; }
deadline=$((SECONDS+20))
until docker exec "$C" nslookup csd.test 127.0.0.1 2>/dev/null | grep -qE "Address:[[:space:]]*127\.0\.0\.1$"; do
    (( SECONDS >= deadline )) && { echo "AGH never resolved the local rewrite" >&2; exit 1; }
    sleep 2
done
