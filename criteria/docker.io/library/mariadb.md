# mariadb — validation criteria

Per-image acceptance criteria for the `docker.io/library/mariadb` profile (the
official MariaDB image). Validated against `…@sha256:a794d9eb…` (tag `11.4`),
derived by drop-test against mariadb's **default (root-then-drop) invocation**. The
default runs on the full Docker default cap set; this profile trims it **14 → 2**.

## Representative workload / correctness check
`profiles/workloads/mariadb.sh` — connect as the configured application user and run
CREATE / INSERT / SELECT / DROP. The drop-test correctness check additionally asserts
the server (`mariadbd`) runs as the **non-root** mysql user (uid 999): a ping/health
check alone is not enough — MariaDB answers a ping while the bootstrap server is
still root or mid-init, so the privilege drop must be confirmed. (root@localhost is
`unix_socket`-only in MariaDB 11.x, hence the app-user round-trip.)

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [SETGID, SETUID].** Baseline `cap_drop:ALL` + the
  Docker default set on a fresh datadir; each default is dropped in turn and the
  workload re-verified. Only SETGID/SETUID are required — the entrypoint re-execs
  itself as the mysql user via **gosu** (`exec gosu mysql …`), and dropping either
  fails with `error: failed switching to 'mysql': operation not permitted`. Both are
  **startup** caps, invisible to runtime observation.
- **CHOWN and DAC_OVERRIDE are NOT required by default** — the important contrast
  with postgres. The image ships `/var/lib/mysql` already owned by the mysql user, so
  a **docker-managed volume** (named or anonymous) inherits that ownership: the
  entrypoint's `find "$DATADIR" \! -user mysql -exec chown mysql:` is a no-op, and
  because it re-execs as mysql *early*, initialisation writes are as the datadir's
  owner — no DAC_OVERRIDE.
- **A foreign-owned bind mount adds CHOWN (only).** If `/var/lib/mysql` is a fresh
  host dir **not** owned by uid 999, the find-chown fires and, without CHOWN, the
  container aborts (`chown: changing ownership of '/var/lib/mysql/': Operation not
  permitted`). Verified: on such a bind the minimum is `[CHOWN, SETGID, SETUID]` —
  DAC_OVERRIDE is still not needed (post-chown, writes are as mysql the owner). This
  is the first-deploy-with-a-host-bind case; the default profile is for the common
  docker-volume case.
- **Pass criteria:** the workload round-trip succeeds **and** `mariadbd` is uid 999;
  dropping SETUID or SETGID breaks the gosu privilege drop and the container exits.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [/run/mysqld, /tmp].** The data dir `/var/lib/mysql`
  is a declared VOLUME (persistent). Under `--read-only` mariadbd requires
  `/run/mysqld` (its unix socket + pid dir) and `/tmp` (temp files during init /
  operation) writable — both drop-test **required**.
- **Pass criteria:** the app-user query round-trip + non-root uid assert pass under
  `read_only:true` with both tmpfs paths (and `/var/lib/mysql` a writable volume).

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the default — root (no `user:` override),
  a docker-managed datadir volume, `MARIADB_*` env, `no-new-privileges`. Two common
  variations shrink or grow this:
  - **`user:` = the mysql uid against a pre-owned datadir** → the entrypoint skips
    the gosu drop and the datadir fix, so the minimum is **[]**. (This is exactly how
    a hardened deployment runs it — e.g. `user: "999:999"` + `cap_drop: ALL`, no
    cap_add — precisely to avoid the root entrypoint's datadir `find` needing
    DAC_OVERRIDE when re-created over existing 0700 mysql-owned data.)
  - **foreign-owned bind mount** → add **CHOWN** (see above).
- **Out of band** (not schema fields): Docker's default cap set + default seccomp
  baseline; a docker-managed datadir; the default `mariadbd` command; amd64. The
  minimum is only valid for what `profiles/workloads/mariadb.sh` exercises.
