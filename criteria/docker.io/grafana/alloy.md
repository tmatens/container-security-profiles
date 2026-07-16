# alloy — validation criteria

Per-image acceptance criteria for the `docker.io/grafana/alloy` profile (Grafana
Alloy, the OpenTelemetry collector / agent). Validated against `…@sha256:32913cb…`
(tag `v1.16.2`), derived by drop-test. alloy already runs `cap_drop: ALL` and as a
non-root user (uid 473), so there is no capability reduction to derive — this
profile covers the **filesystem** dimension.

## Representative workload / correctness check
`profiles/workloads/alloy.sh` confirms alloy loads and runs its pipeline under
`--read-only`: `/-/ready` returns 200 **and** `/metrics` exposes `alloy_*` metrics
(components loaded and running). Because alloy **fatals at startup if its
storage.path is not writable**, "ready + a live pipeline" already exercises the
storage.path write path — this is real function, not a bare liveness ping.

**alloy is distroless** (no shell, no curl), so it is probed from a **sidecar**
container sharing alloy's network namespace (`docker run --network container:<alloy>`
+ a pinned multi-arch curl), reaching it on `localhost:12345` — the same reusable
helper loki uses (`testdata/drop-test/correctness/lib/sidecar.sh` in
container-sec-derive). A sidecar (not a host-side probe) works for any target
network mode, independent of daemon location, and never touches alloy's filesystem —
no confound for the fs dimension.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [] (zero-cap).** alloy is a non-root distroless
  service (uid 473) on the unprivileged :12345, writing only to its
  `storage.path` — no capability is load-bearing. All 14 Docker defaults
  dropped in turn (under `read_only: true` + the storage volume); the pipeline
  stayed live every time. **Confidence high.**
- Published explicitly so a user of the stock image (default 14 caps) sees the
  14 → 0 reduction, not just the filesystem dimension.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** Under a read-only rootfs with only its
  storage.path location writable, alloy becomes ready and runs its pipeline — `/tmp`
  was the one plausible ephemeral tmpfs candidate and drop-tested as **NOT
  required**; the run logged zero read-only-fs errors.
- **The storage.path location is a PERSISTENT VOLUME, not tmpfs.** Under the image
  default (`--storage.path=/var/lib/alloy/data`) alloy writes its WAL and component
  state there; it must survive restarts. **Mount the persistent volume at the PARENT
  `/var/lib/alloy`, not the exact `/var/lib/alloy/data`:** alloy creates the `data`
  subdir itself and needs its parent writable — under `--read-only` a volume mounted
  at the exact storage.path fails to initialise (`mkdir /var/lib/alloy/data:
  permission denied`). In the derivation the stand-in is `run.tmpfs` on
  `/var/lib/alloy` with `mode=1777` (alloy runs as non-root uid 473; a real named
  volume is owned by 473). It is never part of the tmpfs minimum.
- **Pass criteria:** alloy reaches `/-/ready` (200) and exposes `alloy_*` metrics
  under `--read-only` with `/var/lib/alloy` writable and no `/tmp`.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the image default —
  `run /etc/alloy/config.alloy --storage.path=/var/lib/alloy/data`, the
  `alloy-data:/var/lib/alloy` volume, `cap_drop: ALL`, `no-new-privileges`, non-root
  uid 473.
- **storage.path dependence:** the minimum is tied to where storage.path points. A
  deployment that overrides **`--storage.path=/tmp/alloy`** instead needs
  **`tmpfs: [/tmp]`** (alloy then writes its WAL under `/tmp`). Point storage.path at
  a persistent volume to keep the tmpfs minimum empty; `/tmp`-as-storage is
  ephemeral (state lost on restart).
- **Out of band** (not schema fields): the default config's components
  (unix-exporter scrape + remote_write WAL + otelcol/tracing exporters, whose remote
  endpoints are unreachable in the test — non-fatal); amd64/arm64; Docker's default
  seccomp baseline. The minimum is only valid for what `profiles/workloads/alloy.sh`
  exercises.
