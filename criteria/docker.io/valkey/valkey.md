# valkey — validation criteria

Per-image acceptance criteria for the `docker.io/valkey/valkey` profile (immich's
redis; a redis-compatible server used far beyond immich). Validated against
`valkey:9@sha256:8e8d64b4…`, derived by drop-test against immich's deployment
invocation.

## Representative workload / correctness check
`profiles/workloads/valkey.sh` — PING + a SET/GET round-trip. The drop-test
correctness check additionally asserts the server (PID 1) runs as the **non-root**
valkey user (uid 999): the privilege drop must be confirmed, not just liveness.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [SETGID, SETUID].** Baseline `cap_drop:ALL` + the
  Docker default set; each default cap is dropped in turn and the workload
  re-verified. valkey's entrypoint drops root → the valkey user via **`setpriv`**,
  which needs SETUID/SETGID — dropping either yields
  `setpriv: setresuid/setresgid failed: Operation not permitted` and the container
  exits. Both are **startup** caps, invisible to runtime observation.
- **CHOWN is a genuine over-grant under this invocation.** immich declares it, but
  immich's redis has **no data volume**, so valkey uses the image's own pre-owned
  `/data` and never chowns anything — dropping CHOWN leaves the workload passing.
  A deployment that binds a **foreign-owned** data volume would need CHOWN back
  (the entrypoint would chown it on first boot); this profile is scoped to the
  no-volume invocation in `run_config`.
- **Pass criteria:** the PING + SET/GET round-trip passes **and** PID 1 is uid 999;
  dropping SETUID or SETGID breaks the privilege drop and the container exits.

## App-tier verification
Verified at the service level: immich's released stack was brought up with redis
hardened to this minimum (alongside the hardened DB), and immich's real REST API
(sign-up → login → upload → read-back → search) all passed — so the minimum holds
against immich's actual usage, not only the PING/SET/GET workload. (App-tier
verification is not yet a schema field; recorded here.)

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** valkey's RDB/AOF live in `/data` (not a declared
  VOLUME in this image — a persistent bind/named volume in production, never
  tmpfs). Under `--read-only` with `/data` writable it serves the PING + SET/GET
  round-trip with no additional tmpfs; `/tmp` drop-tests **not required**.
- **Pass criteria:** PING + SET/GET and the non-root uid assert pass under
  `read_only:true` (with `/data` writable) and no rootfs tmpfs.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): immich's — root, **no data volume**,
  `no-new-privileges`, no command override. With a foreign-owned data volume the
  minimum adds CHOWN.
- **Out of band** (not schema fields): Docker's default cap set + default seccomp;
  amd64. The minimum is only valid for what `profiles/workloads/valkey.sh`
  exercises.
- **Re-derivation:** re-derived live by csd's deploy-check job (`compose_derive.sh`
  against immich's committed compose).
