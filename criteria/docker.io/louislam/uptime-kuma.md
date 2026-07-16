# uptime-kuma — validation criteria

Per-image acceptance criteria for the `docker.io/louislam/uptime-kuma`
profile (v2). Validated against `…@sha256:91e963bf…` (tag `2`), derived by
drop-test against the default invocation with embedded sqlite. Capabilities
trim **14 → 2**. **Confidence: moderate** — a documented workload-coverage
limit (below), not a derivation weakness.

## Representative workload / correctness check
`profiles/workloads/uptime-kuma.sh` — entry-page, embedded-sqlite database
setup via `POST /setup-database` (a real persistent write under `/app/data`),
the server's self-restart, serving again, and the metrics auth layer (401).
Curl sidecar; capture-then-match.

## Why moderate confidence — the coverage limit
uptime-kuma's **admin creation and monitor CRUD are socket.io-only** — there
is no REST surface a drop-test curl probe can drive. So the derivation
exercises boot → sqlite setup → self-restart → the serving/auth stack, but
**not a running monitor**. In particular, **PING-type monitors use raw ICMP
sockets and would require NET_RAW** — a grant this scope cannot measure and
does not include. A deployment relying on ping monitors must add NET_RAW
itself; HTTP/TCP/keyword monitors (the common case) need nothing beyond this
profile. This limit is the honest reason the profile is moderate, not high.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [DAC_OVERRIDE, FOWNER].** node runs as root and
  writes its sqlite database + config under `/app/data` on a fresh rootfs:
  DAC_OVERRIDE to create/write the data tree (`Cannot write to …`), FOWNER
  for the permission fixups (`data dir permission fixup failed`).
- **No NET_BIND_SERVICE** — the web UI is the unprivileged :3001; **no
  privilege drop** (SETUID/SETGID not needed — it stays root).
- **Pass criteria:** sqlite setup + self-restart + serving with auth up, with
  every candidate dropped.

## Scope (`run_config` + out-of-band conditions)
- **Invocation:** v2 default, embedded sqlite chosen at setup, fresh rootfs
  (no volume declared — data under `/app/data`), `no-new-privileges`.
- **Variations:** the mariadb-backed setup moves storage to the DB tier
  (expected to relax the data-dir caps; not derived here). **Ping monitors →
  add NET_RAW** (above).
- **Out of band:** Docker's default seccomp baseline; amd64. The minimum
  covers setup + serving; monitor execution beyond HTTP/TCP, notifications,
  and status pages are out of scope.
