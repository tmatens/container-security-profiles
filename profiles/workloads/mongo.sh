#!/usr/bin/env bash
# Workload exerciser for the mongo reference image.
#
# Drives a representative write/read round-trip via mongosh — insertOne,
# countDocuments, findOne read-back, drop — mirroring the official
# docker-library mongo-basics test shape (unauthenticated default invocation).
# Returns 0 if every step succeeded. The non-root privilege-drop (the
# entrypoint's gosu root->mongodb) is asserted by the drop-test correctness
# check (see the criteria doc), not here.
#
# Required env: MONGOCONTAINER (target container name or id).
set -euo pipefail

: "${MONGOCONTAINER:?MONGOCONTAINER must be set}"
C="${MONGOCONTAINER}"

deadline=$((SECONDS + 60))
# capture-then-match — never `producer | grep -q` under pipefail (grep's early
# exit SIGPIPEs the producer and a matching response reads as failure).
until grep -q 1 <<<"$(docker exec "$C" mongosh --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null)"; do
    if (( SECONDS >= deadline )); then
        echo "mongod did not answer ping in 60s" >&2
        exit 1
    fi
    sleep 1
done

out="$(docker exec "$C" mongosh --quiet csdprobe --eval '
  db.probe.insertOne({_id: "csd", v: 42});
  const n = db.probe.countDocuments();
  const v = db.probe.findOne({_id: "csd"}).v;
  db.probe.drop();
  print(n + ":" + v);' 2>&1 | tail -1)"
if [ "$out" != "1:42" ]; then
    echo "workload round-trip failed (got: $out)" >&2
    exit 1
fi
