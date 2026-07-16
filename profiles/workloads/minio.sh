#!/usr/bin/env bash
# Workload exerciser for the minio reference image (single-node
# `server /data`).
#
# A real S3 round-trip via the pinned `mc` client run as a sidecar in the
# target's netns (the server image ships no client): make-bucket, pipe an
# object in, cat it back byte-identical. The MC_HOST_ env alias keeps mc
# config-free — the only writes are the object store's own.
#
# Required env: MINIOCONTAINER (target container name or id). The container
# is expected to run with MINIO_ROOT_USER=csdadmin /
# MINIO_ROOT_PASSWORD=CsdProbe-Pw-12345 (the derivation credentials).
set -euo pipefail

: "${MINIOCONTAINER:?MINIOCONTAINER must be set}"
C="${MINIOCONTAINER}"
MC_IMAGE="${CSD_PROBE_MC_IMAGE:-minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727}"
mcx() { docker run --rm --entrypoint /bin/sh --network "container:${C}" \
        -e MC_HOST_csd=http://csdadmin:CsdProbe-Pw-12345@localhost:9000 "$MC_IMAGE" -c "$*"; }

deadline=$((SECONDS + 45))
until mcx 'mc ls csd/ >/dev/null 2>&1'; do
    (( SECONDS >= deadline )) && { echo "minio never answered" >&2; exit 1; }
    sleep 2
done

got="$(mcx 'mc mb -p csd/csdbucket >/dev/null 2>&1; echo csd-payload-42 | mc pipe csd/csdbucket/probe.txt >/dev/null 2>&1 && mc cat csd/csdbucket/probe.txt 2>/dev/null')"
if [ "$got" != "csd-payload-42" ]; then
    echo "S3 round-trip failed (got: ${got:0:60})" >&2
    exit 1
fi
