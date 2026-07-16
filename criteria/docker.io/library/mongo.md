# mongo — validation criteria

Per-image acceptance criteria for the `docker.io/library/mongo` profile (the
official MongoDB image). Validated against `…@sha256:3ce3de7f…` (tag `8.0`),
derived by drop-test against MongoDB's **default (root-then-drop) invocation**.
The default runs on the full Docker default cap set; this profile trims it
**14 → 2**.

## Representative workload / correctness check
`profiles/workloads/mongo.sh` — a mongosh write/read round-trip (insertOne,
countDocuments, findOne read-back, drop), mirroring the official docker-library
`mongo-basics` test shape under the unauthenticated default invocation. The
drop-test correctness check additionally asserts `mongod` runs as the
**non-root** mongodb user (uid 999): the redis/mariadb sharp edge — a
workload-only check passes even when the privilege drop silently failed, so the
uid assert is mandatory for any re-derivation.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [SETGID, SETUID].** Baseline `cap_drop:ALL` + the
  Docker default set on fresh docker-managed volumes (the image declares
  `/data/db` and `/data/configdb` VOLUMEs); each default dropped in turn, the
  workload re-verified. The entrypoint re-execs itself as the mongodb user via
  **gosu**; dropping either cap fails deterministically (`error: failed
  switching to 'mongodb': operation not permitted`) and the container never
  starts. Startup caps, invisible to runtime observation.
- **CHOWN is NOT required by default** — both data dirs ship pre-owned by uid
  999, so the entrypoint's `find … -exec chown` is a no-op on docker-managed
  volumes. The entrypoint also best-effort chowns its stdio fds (`|| :`), which
  is never load-bearing. A **foreign-owned bind mount** (fresh host dir not
  owned by uid 999) makes the find-chown fire and re-introduces CHOWN.
- **SYS_NICE is NOT needed** — the official image test grants `--cap-add
  SYS_NICE` for NUMA hosts (a MongoDB 3.6-era note); it is not in the Docker
  default set, and modern mongod treats a failed `setpriority` as a warning.
  Nothing beyond the gosu drop is load-bearing under this invocation.
- **Pass criteria:** the mongosh round-trip returns the inserted document
  **and** `mongod` is uid 999; dropping SETGID or SETUID fails container start.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [/tmp].** The data dirs `/data/db` and `/data/configdb`
  are declared VOLUMEs (persistent). Under `--read-only` mongod additionally
  requires `/tmp` writable — it creates its unix socket (`/tmp/mongodb-27017.sock`)
  there (drop-test **required**).
- **Pass criteria:** the insert/count round-trip passes under `read_only:true` with
  `tmpfs:[/tmp]` (and the data dirs writable volumes).

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the default — root (no `user:`
  override), docker-managed data volumes, no auth env, `no-new-privileges`.
  Variations:
  - **`MONGO_INITDB_ROOT_USERNAME/PASSWORD` (auth mode)** changes the workload
    (authenticated mongosh) but not the entrypoint's privilege path; the
    minimum is expected unchanged. Not derived here.
  - **`user:` = the mongodb uid against pre-owned data dirs** → skips the gosu
    drop; minimum shrinks to **[]**.
  - **foreign-owned bind mount** → add **CHOWN**.
- **Out of band** (not schema fields): Docker's default cap set + default
  seccomp baseline; docker-managed data volumes; the default `mongod` command;
  amd64; a non-NUMA host (the entrypoint only wraps mongod in `numactl` when
  NUMA is present — an untested path here). The minimum is only valid for what
  `profiles/workloads/mongo.sh` exercises — core document write/read; replica
  sets, sharding, and TLS are out of scope.
