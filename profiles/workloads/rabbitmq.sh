#!/usr/bin/env bash
# Workload exerciser for the rabbitmq reference image.
#
# Real function = a declare -> publish -> consume round-trip over the
# management API. The plain image ships no AMQP client and no curl, so the
# check enables the bundled rabbitmq_management plugin at runtime (the same
# plugin the -management tag pre-enables) and drives the round-trip from a
# SIDECAR container sharing the target's network namespace — which also
# satisfies the default guest user's loopback-only restriction. Returns 0 on
# success. The non-root privilege-drop (gosu root->rabbitmq) is asserted by
# the drop-test correctness check (see the criteria doc), not here.
#
# TWO SHARP EDGES (both reproduced on rabbitmq:4.3; keep them respected in any
# re-derivation):
#   1. Never exec a rabbitmq CLI during boot — an exec'd root Erlang client
#      races the entrypoint for .erlang.cookie creation and crashes the broker.
#      Gate on the "Server startup complete" log line first.
#   2. Exec the CLIs as the rabbitmq user (--user rabbitmq), never root — a
#      root probe needs DAC_OVERRIDE/FOWNER of its own and pollutes a derived
#      minimum.
#
# Required env: RABBITMQCONTAINER (target container name or id).
set -euo pipefail

: "${RABBITMQCONTAINER:?RABBITMQCONTAINER must be set}"
C="${RABBITMQCONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }

deadline=$((SECONDS + 90))
until docker logs "$C" 2>&1 | grep -q "Server startup complete"; do
    (( SECONDS >= deadline )) && { echo "rabbitmq never reached startup complete" >&2; exit 1; }
    sleep 2
done

docker exec --user rabbitmq "$C" rabbitmq-plugins enable --online rabbitmq_management >/dev/null 2>&1 \
    || { echo "could not enable rabbitmq_management" >&2; exit 1; }
deadline=$((SECONDS + 30))
until sc -sf -u guest:guest --max-time 5 http://localhost:15672/api/overview >/dev/null 2>&1; do
    (( SECONDS >= deadline )) && { echo "management API never came up" >&2; exit 1; }
    sleep 1
done

# declare (durable — 4.x rejects transient non-exclusive queues) -> publish -> get.
sc -sf -u guest:guest --max-time 10 -X PUT -H 'content-type: application/json' \
    -d '{"durable":true}' http://localhost:15672/api/queues/%2F/csd-probe >/dev/null \
    || { echo "queue declare failed" >&2; exit 1; }
routed="$(sc -s -u guest:guest --max-time 10 -X POST -H 'content-type: application/json' \
    -d '{"properties":{},"routing_key":"csd-probe","payload":"csd-42","payload_encoding":"string"}' \
    http://localhost:15672/api/exchanges/%2F/amq.default/publish)"
case "$routed" in *'"routed":true'*) ;; *) echo "publish not routed" >&2; exit 1;; esac
got="$(sc -s -u guest:guest --max-time 10 -X POST -H 'content-type: application/json' \
    -d '{"count":1,"ackmode":"ack_requeue_false","encoding":"auto"}' \
    http://localhost:15672/api/queues/%2F/csd-probe/get)"
case "$got" in *'"payload":"csd-42"'*) ;; *) echo "consume failed" >&2; exit 1;; esac
