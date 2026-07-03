# postgres — validation criteria

Per-image acceptance criteria for the `docker.io/library/postgres` profile
(compose-lint#359 convention). A `validated` profile for this image must have
been derived against a run meeting the scenarios and pass criteria below.

## Image
`docker.io/library/postgres` (validated against `postgres:16@sha256:fe03a760…`).

## Representative workload
`profiles/workloads/postgres.sh` — connects to a running postgres container and
drives a representative set of operations, not a liveness poke:

- `CREATE TABLE` / `INSERT` / `SELECT` / `DROP`
- a `SIGHUP` configuration reload

Required env: `PGCONTAINER`. Defaults: user/db/password `postgres`.

## Dimensions & pass criteria

### filesystem (CL-0007)
- **Scenario:** run the workload against the container for ≥ 300s with
  `csd --observe fs`.
- **Pass criteria:** every observed write correlates to the postgres data volume
  (`/var/lib/postgresql/data`); no rootfs write requires a tmpfs mount. Derived
  recommendation is `read_only: true`, `tmpfs: []`. Confidence ≥ moderate,
  `trace_health.drop_rate` < 1%, digest-pinned.
- **Observed result:** 147+ write events, 0 dropped, all volume-covered.
