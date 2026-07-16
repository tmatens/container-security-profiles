# memcached — validation criteria

Per-image acceptance criteria for the `docker.io/library/memcached` profile.
Validated against `…@sha256:dc561d52…` (tag `1.6`), derived by drop-test
against the **default invocation**. Capabilities trim **14 → 0** — zero-cap,
prometheus's sibling.

## Representative workload / correctness check
`profiles/workloads/memcached.sh` — a real set/get round-trip asserting
`STORED` and the value read back (`VALUE csd 0 5` / `hello` / `END`),
mirroring the official docker-library `memcached-basics` test. The image
ships bash but no client tool, so the round-trip runs over the in-image
**bash `/dev/tcp`** redirection — no sidecar, no extra image. `docker exec`
inherits `USER memcache`, so the probe exercises nothing beyond what the
service itself can do (no probe pollution by construction). The correctness
check also asserts the serving process is non-root.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [] (zero-cap).** The image runs as **USER
  memcache** (uid 11211) from the first instruction — no root phase, no
  entrypoint chown, no privilege drop. It binds only the unprivileged
  `:11211` and persists nothing, so no path in the serve loop touches a
  capability. All 14 Docker defaults dropped in turn; the round-trip stayed
  correct every time.
- **Pass criteria:** `STORED` + exact value read-back + non-root uid, with
  every candidate dropped.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the image default — USER
  memcache, default command (64 MB cache), no mounts, `no-new-privileges`.
- **Variations:** `-m <bigger>` and connection-limit flags change memory use,
  not privileges. SASL auth changes the workload, not the caps. There is no
  low-port or persistence variant to scope.
- **Out of band** (not schema fields): Docker's default seccomp baseline;
  amd64. The minimum is only valid for what the workload exercises — the
  text-protocol set/get path; the binary/meta protocols and UDP are not
  separately driven (no privilege-relevant surface expected there).
