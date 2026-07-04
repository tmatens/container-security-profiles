# postgres — validation criteria

Per-image acceptance criteria for the `docker.io/library/postgres` profile
(compose-lint#359). Validated against `postgres:16@sha256:fe03a760…`.

## Representative workload / correctness check
`profiles/workloads/postgres.sh` — connect + CREATE/INSERT/SELECT/DROP + a SIGHUP
reload. Under the derived config it must complete cleanly.

## filesystem (CL-0007) — derived by drop-test
- **read_only: true** — fs observation showed every runtime write landing on the
  postgres data VOLUME (`/var/lib/postgresql/data`); nothing needs a writable
  rootfs at runtime.
- **tmpfs: [/run/postgresql]** — established by verification, because the socket
  write is startup-only (attach-window-blind to observation):
  - `read_only:true` + `tmpfs:[/run/postgresql]` → the workload passes, no errors.
  - `read_only:true` + no tmpfs → **FAILS** at startup: "could not create lock
    file /var/run/postgresql/.s.PGSQL.5432.lock: Read-only file system".
- **Pass criteria:** the workload passes under the derived config, and removing
  the tmpfs breaks startup (confirming it is required and minimal).

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID].** Baseline
  `cap_drop:ALL` + the Docker default set on a **fresh** data dir (so initdb and
  the root→postgres `gosu` privilege drop run); each default cap is dropped in
  turn and the workload re-verified. All four are **startup** caps — runtime
  observation records them as unused, so drop-test is the authoritative source.
- **Derived under the filesystem dimension's recommendation** (`read_only:true` +
  `tmpfs:[/run/postgresql]`), because the profile is applied as a unit. That
  context adds **CHOWN**: the root-owned tmpfs socket dir must be chowned to the
  postgres user at startup — a requirement invisible when caps are derived on a
  writable rootfs (there the socket dir is pre-owned). Deriving the capability
  minimum without the sibling fs recommendation would omit CHOWN and produce a
  profile that breaks postgres under its own read-only recommendation.
- **Pass criteria:** the workload passes **and** the server (PID 1) runs as the
  non-root postgres user (uid 999) — a health check alone is not enough; postgres
  must have completed the privilege drop. Removing SETUID/SETGID (gosu),
  DAC_OVERRIDE, or CHOWN breaks it.

## Combined verification
The two dimensions are verified **together**: the workload passes under
`read_only:true` + `tmpfs:[/run/postgresql]` + `cap_drop:ALL` +
`cap_add:[CHOWN, DAC_OVERRIDE, SETGID, SETUID]` applied simultaneously, with the
server running as uid 999.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the **default** run — no `user:`
  override (so the root→postgres drop happens), `POSTGRES_PASSWORD` set, no
  command/entrypoint override. Run with `user:` set, postgres skips the privilege
  drop and the capability minimum does **not** apply.
- **Out of band** (not schema fields): the baseline is Docker's default cap set +
  default seccomp; derived on a **fresh** data dir (an already-initialized volume
  skips initdb and needs fewer startup caps — this is the conservative superset)
  and on amd64. The minimum is only valid for what
  `profiles/workloads/postgres.sh` exercises.
