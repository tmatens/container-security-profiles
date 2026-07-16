#!/usr/bin/env bash
# Workload exerciser for the eclipse-mosquitto reference image.
#
# A real publish/subscribe round-trip via the in-image mosquitto_sub /
# mosquitto_pub clients: the subscriber runs in the foreground printing the
# one expected message to stdout, the publisher fires after a beat from the
# background. Probes exec as --user mosquitto so they cannot pollute a caps
# minimum, and NOTHING is written inside the container — a probe temp file
# under /tmp would derive the filesystem dimension's /tmp candidate
# falsely-required. The broker's own in-process privilege drop is asserted by
# the drop-test correctness check (see the criteria doc).
#
# Required env: MOSQUITTOCONTAINER (target container name or id).
set -euo pipefail

: "${MOSQUITTOCONTAINER:?MOSQUITTOCONTAINER must be set}"
C="${MOSQUITTOCONTAINER}"

deadline=$((SECONDS + 20))
until docker logs "$C" 2>&1 | grep -q "mosquitto version .* running"; do
    (( SECONDS >= deadline )) && { echo "broker never reported running" >&2; exit 1; }
    sleep 1
done

got="$(docker exec --user mosquitto "$C" sh -c '
  (sleep 1; mosquitto_pub -h 127.0.0.1 -t csd/probe -m csd-42 2>/dev/null) &
  mosquitto_sub -h 127.0.0.1 -t csd/probe -C 1 -W 10 2>/dev/null' 2>/dev/null)"
if [ "$got" != "csd-42" ]; then
    echo "pub/sub round-trip failed (got: ${got:-nothing})" >&2
    exit 1
fi
