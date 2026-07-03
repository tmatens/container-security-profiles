# postgres — validation criteria

Per-image acceptance criteria for the `docker.io/library/postgres` profile
(compose-lint#359). Validated against `postgres:16@sha256:fe03a760…`.

## Representative workload / correctness predicate
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
