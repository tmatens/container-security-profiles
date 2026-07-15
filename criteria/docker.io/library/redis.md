# library/redis — validation criteria

Per-image acceptance criteria for the `docker.io/library/redis` profile.
Validated against `…@sha256:d30960f7…` (tag `8.2.7`), derived by drop-test
under the image's **default root-then-drop invocation**.

## Representative workload / correctness check

`profiles/workloads/redis.sh` — PING readiness gate, a SET/GET round-trip, and
a synchronous `SAVE` (a real RDB write to the `/data` volume). The drop-test
correctness check additionally asserts `redis-server` runs as a **non-root**
uid (999). That assertion is load-bearing here more than anywhere else in the
catalog:

- **With SETUID or SETGID dropped, redis does not fail — it keeps serving
  correctly as root.** PING, SET/GET, and SAVE all pass. A workload-only check
  would derive both caps as removable, and the "hardened" result would be a
  root-running redis in production. The observed evidence for both required
  caps reads `redis-server running as ROOT` — the check catching exactly this.

## capabilities — derived by drop-test

- **cap_drop: [ALL], cap_add: [SETGID, SETUID].** Baseline `cap_drop: ALL` +
  the full Docker default cap set; each candidate dropped in turn, the
  container restarted, the workload + uid assertion re-verified.
- Both are **startup** caps: the entrypoint starts as root and re-execs
  `redis-server` as the redis user. Runtime observation records them as
  unused after the drop; drop-test is the authoritative source.
- **CHOWN is not needed under this invocation**: with no data bind, redis uses
  the image's own anonymous `/data` volume, initialised redis-owned, so the
  entrypoint's ownership fix is a no-op. A deployment binding a
  **foreign-owned host dir** for `/data` re-introduces CHOWN (and possibly
  DAC_OVERRIDE) — same first-deploy pattern as the postgres profile.
- **Pass criteria:** PING + SET/GET + SAVE succeed **and** `redis-server` runs
  as uid 999; dropping SETGID or SETUID leaves the server running as root
  (fail by uid assertion).

## Scope (`run_config` + out-of-band conditions)

- **Invocation**: image default — no `user:` override, no binds, no
  `--requirepass` (the common private-network compose shape). Redis protected
  mode only restricts non-loopback clients; the workload probes over
  `docker exec` loopback, which matches sidecar/same-network consumers.
- Run with `user:` set to a non-root uid from the start, the entrypoint skips
  the drop entirely and the minimum shrinks to `[]`.
- **Out of band**: Docker's default seccomp baseline; amd64; the minimum is
  only valid for what `profiles/workloads/redis.sh` exercises (core KV +
  persistence; modules, cluster mode, and TLS are not exercised).
