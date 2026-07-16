# mysql — validation criteria

Per-image acceptance criteria for the `docker.io/library/mysql` profile (the
official MySQL image). Validated against `…@sha256:c831a0f1…` (tag `8.4`, the
LTS line), derived by drop-test against mysql's **default (root-then-drop)
invocation**. The default runs on the full Docker default cap set; this profile
trims it **14 → 3**.

## Representative workload / correctness check
`profiles/workloads/mysql.sh` — connect as the configured application user and
run CREATE / INSERT / SELECT / DROP, mirroring the official docker-library
`mysql-basics` test shape. The drop-test correctness check additionally asserts
the server (`mysqld`) runs as the **non-root** mysql user (uid 999): mysql
answers pings while the transient bootstrap server is still initialising, and —
the redis/mariadb lesson — a workload-only check passes even when the privilege
drop silently failed, so the uid assert is mandatory for any re-derivation.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [DAC_OVERRIDE, SETGID, SETUID].** Baseline
  `cap_drop:ALL` + the Docker default set on a fresh docker-managed datadir;
  each default dropped in turn, the workload re-verified.
- **SETGID / SETUID** — the entrypoint re-execs itself as the mysql user via
  **gosu**; dropping either aborts the container at startup. Startup caps,
  invisible to runtime observation.
- **DAC_OVERRIDE — the divergence from sibling mariadb.** The image ships
  `/var/lib/mysql-files` **mysql-owned, mode 750**, and the entrypoint's
  ROOT-phase directory walk (`find` in `docker_create_db_directories`) must
  traverse it. Root without DAC_OVERRIDE is subject to normal DAC checks, so
  the trial fails deterministically: `find: '/var/lib/mysql-files': Permission
  denied` and the container exits. mariadb has no such root-phase traversal of
  a group/other-denied directory, which is why it derives to 2 caps and mysql
  to 3 — a per-image difference worth its own evidence, exactly as the coverage
  queue predicted.
- **CHOWN is NOT required by default** — `/var/lib/mysql` and `/var/run/mysqld`
  ship mysql-owned (uid 999, mode 1777), so a docker-managed volume inherits
  that ownership and the `find … -exec chown` is a no-op.
- **A foreign-owned bind mount adds CHOWN.** A fresh host dir not owned by uid
  999 makes the find-chown fire; without CHOWN the container aborts. This is
  the first-deploy-with-a-host-bind case; the default profile covers the
  docker-volume case.
- **Pass criteria:** the app-user round-trip succeeds **and** `mysqld` is uid
  999; dropping any of the three granted caps aborts the container at startup.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the default — root (no `user:`
  override), a docker-managed datadir volume, `MYSQL_*` env,
  `no-new-privileges`. Common variations:
  - **`user:` = the mysql uid against a pre-owned datadir** → the entrypoint
    skips the gosu drop *and* the root-phase find, so the minimum is **[]**.
  - **foreign-owned bind mount** → add **CHOWN** (see above).
- **Out of band** (not schema fields): Docker's default cap set + default
  seccomp baseline; a docker-managed datadir; the default `mysqld` command;
  amd64. The minimum is only valid for what `profiles/workloads/mysql.sh`
  exercises — core SQL round-trip; replication, plugins requiring extra
  privileges, and `local_infile` paths are out of scope.
