# loki — validation criteria

Per-image acceptance criteria for the `docker.io/grafana/loki` profile.
Validated against `…@sha256:191d4fd…` (tag `3.7.2`), derived by drop-test. loki
already runs `cap_drop: ALL` and as a non-root user (uid 10001), so there is no
capability reduction to derive — this profile covers the **filesystem** dimension.

## Representative workload / correctness check
`profiles/workloads/loki.sh` drives loki's real read+write path, not liveness:
push a log line to `/loki/api/v1/push` (HTTP 204) and query it back from
`/loki/api/v1/query_range` (the line is returned from the ingester).

**loki is distroless** (no shell, no curl), so `docker exec <loki>` has nothing to
run. It is probed from a **sidecar** container that shares loki's network namespace
(`docker run --network container:<loki>` + a pinned multi-arch curl) and reaches it
on `localhost:3100`. This is why a sidecar and not a host-side probe: it works
uniformly for any target network mode and independent of where the docker daemon
runs, and it never touches loki's filesystem — no confound for the fs dimension. The
reusable helper lives in container-sec-derive at
`testdata/drop-test/correctness/lib/sidecar.sh`.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [] (zero-cap).** loki is a non-root distroless
  service (uid 10001) on the unprivileged :3100, writing only to its `/loki`
  data store — no capability is load-bearing. All 14 Docker defaults dropped
  in turn (under `read_only: true` + the `/loki` volume); the push/query
  round-trip stayed correct every time. **Confidence high.**
- Published explicitly so a user of the stock image (which carries Docker's
  default 14 caps) sees the 14 → 0 reduction, not just the filesystem
  dimension.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** Under a read-only rootfs with only the `/loki`
  data dir writable, loki initialises all of its modules (ingester, querier, ruler
  storage, compactor), becomes ready, ingests a pushed log, and serves it back —
  with a read-only `/tmp`. `/tmp` was the one plausible ephemeral tmpfs candidate and
  drop-tested as **NOT required**; the run logged zero read-only-fs errors.
- **`/loki` is a PERSISTENT VOLUME, not tmpfs.** loki's default (filesystem-storage)
  config keeps everything under `path_prefix: /loki` — chunks, WAL, the
  index/boltdb-shipper, and rules — which must survive restarts. It is supplied in
  the derivation as a writable stand-in (`run.tmpfs` with `mode=1777`, since loki
  runs as the non-root uid 10001 and a root-owned tmpfs would be unwritable — the
  real named volume inherits the image's 10001 ownership of `/loki`) and is never
  part of the tmpfs minimum. Do **not** put it on tmpfs.
- **Pass criteria:** loki reaches `/ready`, a push returns 204, and the pushed line
  is returned by a query — under `--read-only` with `/loki` writable and no `/tmp`.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the image default —
  `-config.file=/etc/loki/local-config.yaml` (single-binary, filesystem storage
  under `/loki`), the `loki-data:/loki` data volume, `cap_drop: ALL`,
  `no-new-privileges`, non-root uid 10001.
- **Config dependence:** the minimum holds for any filesystem-storage config, whose
  writes stay under `path_prefix`. A config that relocates storage (a different
  `path_prefix`, or object storage like S3) changes which paths must be writable —
  re-derive for a materially different config. Background jobs not exercised in the
  window (compaction, retention deletion, WAL replay on restart) also write under
  `/loki`, not `/tmp`.
- **Out of band** (not schema fields): amd64/arm64; Docker's default seccomp
  baseline. The minimum is only valid for what `profiles/workloads/loki.sh`
  exercises.
