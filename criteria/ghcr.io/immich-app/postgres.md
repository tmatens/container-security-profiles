# immich-app/postgres — validation criteria

Per-image acceptance criteria for the `ghcr.io/immich-app/postgres` profile (the
custom pgvector/vectorchord image immich ships as its database). Validated against
`…@sha256:bcf63357…`, derived by drop-test against **immich's own deployment
invocation**.

## Representative workload / correctness check
`profiles/workloads/postgres.sh` — connect + CREATE/INSERT/SELECT/DROP + a SIGHUP
reload. The drop-test correctness check additionally asserts the server (PID 1)
runs as the **non-root** postgres user (uid 999): a health check alone is not
enough — postgres can stay "up" while failing to drop root, so the privilege drop
must be confirmed.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID].** Baseline
  `cap_drop:ALL` + the Docker default set on a **fresh, foreign-owned** data dir
  (so initdb, the data-dir chown, and the root→postgres `gosu` drop all run); each
  default cap is dropped in turn and the workload re-verified. All four are
  **startup** caps — runtime observation records them as unused, so drop-test is
  the authoritative source.
- **The data dir must be foreign-owned to derive CHOWN.** immich binds
  `${DB_DATA_LOCATION}` — on a real first deploy that host dir is not yet owned by
  uid 999, so the entrypoint chowns it (CHOWN) and writes it (DAC_OVERRIDE). The
  derivation reproduces this with a fresh dir owned by a different uid; against the
  image's own pre-owned `/data`, the chown is a no-op and CHOWN reads as removable
  (the conservative, first-deploy-safe minimum keeps it).
- **FOWNER is a genuine over-grant.** immich's compose declares it, but it is not
  exercised even on a fresh foreign-owned data dir (dropping it leaves the workload
  passing). The derived minimum omits it.
- **Pass criteria:** the workload passes **and** PID 1 is uid 999; dropping
  SETUID/SETGID (the drop), DAC_OVERRIDE, or CHOWN breaks startup.

## App-tier verification
Beyond the per-container drop-test, this hardening was verified at the **service**
level: immich's released stack (immich-server v2.7.5 + valkey + this postgres) was
brought up with the DB hardened to this minimum, and immich's **real REST API**
drove admin sign-up → login → upload a photo → read it back → search — all passing.
An over-hardening (drop SETUID) makes the DB unhealthy and immich never starts. So
the minimum is confirmed against immich's actual usage, not only the drop-test
workload. (App-tier verification is not yet a schema field; recorded here.)

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [/etc/postgresql, /var/run/postgresql].** Two startup
  writes must land on a writable path: postgres creates its unix socket + lock in
  `/var/run/postgresql`, and immich's entrypoint copies a tuned `postgresql.conf`
  into `/etc/postgresql`. Both drop-test **required**. The data dir
  `/var/lib/postgresql/data` is a **persistent VOLUME** (never tmpfs); `/tmp` was
  drop-tested and comes out **not required**. This is the library-`postgres` fs
  shape plus the `/etc/postgresql` config-copy immich's image adds.
- **Pass criteria:** the CREATE/INSERT/SELECT workload + SIGHUP reload pass under
  `read_only:true` with both tmpfs paths, and dropping either breaks startup.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): immich's — root (no `user:` override),
  the `${DB_DATA_LOCATION}` data-dir bind, `POSTGRES_*` env, `no-new-privileges`.
  Run with `user:` set (skipping the drop) or against a pre-owned volume, the
  minimum is smaller — this profile is the first-deploy conservative superset.
- **Out of band** (not schema fields): Docker's default cap set + default seccomp
  baseline; a **fresh** data dir; amd64. The minimum is only valid for what
  `profiles/workloads/postgres.sh` exercises.
- **Re-derivation:** this image is re-derived live by csd's deploy-check job
  (`compose_derive.sh` against immich's committed compose), which reproduces the
  fresh foreign-owned data dir.
