# minio — validation criteria

Per-image acceptance criteria for the `docker.io/minio/minio` profile.
Validated against `…@sha256:14cea493…` (immutable tag
`RELEASE.2025-09-07T16-13-09Z`), derived by drop-test against the **default
single-node invocation** (`server /data`). Capabilities trim **14 → 0**.

## Representative workload / correctness check
`profiles/workloads/minio.sh` — a real S3 **make-bucket → put → get**
round-trip, byte-identical readback, via the pinned `mc` client run as a
sidecar in the target's netns (the server image ships no client). The
`MC_HOST_` env alias keeps mc config-free, so the probe writes nothing
anywhere except the object store itself.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [] (zero-cap)** — the jellyfin-class shape: a
  single static Go binary running **as root** with no privilege drop,
  serving the unprivileged `:9000`, writing only inside its `/data` VOLUME.
  All 14 Docker defaults dropped in turn; the S3 round-trip passed every
  time. The entire default cap set is over-grant for this image.
- **Residual risk is the root uid** — objects land root-owned in the volume.
  minio supports `user:` cleanly (any uid against a pre-owned data dir);
  that hardening composes with this profile.
- **Pass criteria:** the S3 round-trip returns the exact payload with every
  candidate dropped.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** minio's only writes are to its object store
  `/data`, a **persistent VOLUME** (never tmpfs — objects must survive restarts).
  Under `--read-only` with `/data` a writable volume it serves the S3
  make-bucket + put + get round-trip with no additional tmpfs; `/tmp` was
  drop-tested and comes out **not required**.
- **Pass criteria:** the S3 round-trip passes under `read_only:true` (with `/data`
  a writable volume) and no rootfs tmpfs.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): `server /data`, root credentials
  via env, a docker-managed data volume, `no-new-privileges` (no file-cap
  tricks here, unlike pihole — nnp is compatible).
- **Variations:** multi-node/distributed mode changes clustering, not local
  privileges (expected unchanged, not derived). `--console-address` on a
  fixed port changes nothing. TLS termination adds cert reads, no caps.
- **Out of band** (not schema fields): Docker's default seccomp baseline;
  amd64. The minimum is only valid for what the workload exercises — bucket
  create + object put/get; erasure-coded multi-drive setups, ILM/replication,
  and IAM/STS flows are out of scope.
