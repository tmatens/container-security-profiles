#!/usr/bin/env bash
# Workload exerciser for the memcached reference image.
#
# A real set/get round-trip (STORED + the value read back), mirroring the
# official docker-library memcached-basics test, driven over the in-image bash
# /dev/tcp — the image ships bash but no client tool. docker exec inherits
# USER memcache (uid 11211), so the probe exercises nothing beyond what the
# service itself can do.
#
# Required env: MEMCACHEDCONTAINER (target container name or id).
set -euo pipefail

: "${MEMCACHEDCONTAINER:?MEMCACHEDCONTAINER must be set}"
C="${MEMCACHEDCONTAINER}"

deadline=$((SECONDS + 20))
until docker exec "$C" bash -c 'exec 3<>/dev/tcp/127.0.0.1/11211' 2>/dev/null; do
    (( SECONDS >= deadline )) && { echo "memcached never accepted a connection" >&2; exit 1; }
    sleep 1
done

out="$(docker exec "$C" bash -c '
  exec 3<>/dev/tcp/127.0.0.1/11211
  printf "set csd 0 0 5\r\nhello\r\n" >&3
  IFS=$'"'"'\r'"'"' read -r stored <&3
  printf "get csd\r\n" >&3
  IFS=$'"'"'\r'"'"' read -r hdr <&3; IFS=$'"'"'\r'"'"' read -r val <&3; IFS=$'"'"'\r'"'"' read -r end <&3
  printf "quit\r\n" >&3
  echo "$stored|$hdr|$val|$end"')"
if [ "$out" != "STORED|VALUE csd 0 5|hello|END" ]; then
    echo "set/get round-trip failed (got: $out)" >&2
    exit 1
fi
