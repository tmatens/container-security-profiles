# uptime-kuma — validation criteria

Per-image acceptance criteria for the `docker.io/louislam/uptime-kuma`
profile (v2). Validated against `…@sha256:91e963bf…` (tag `2`), derived by
drop-test against the default invocation with embedded sqlite. Capabilities
trim **14 → 2**. **Confidence: high** — the workload now drives a running
monitor (#63); the earlier moderate rating reflected a coverage gap that has
since been closed by measurement.

## Representative workload / correctness check
`profiles/workloads/uptime-kuma.sh` — entry-page, embedded-sqlite database
setup via `POST /setup-database` (a real persistent write under `/app/data`),
the server's self-restart, then — over **socket.io** — admin creation, login,
**adding an HTTP monitor, and confirming it reports an UP heartbeat**. Because
uptime-kuma's admin/monitor CRUD is socket.io-only (no REST), the probe runs
from a **sidecar using the uptime-kuma image itself** (node + socket.io-client
are baked in), sharing the target's netns, with the probe script bind-mounted
so nothing is written inside the target.

## Confidence: how the coverage gap was closed
The earlier moderate rating was honest about a real limit: a curl-only probe
could drive setup + serving but **not a running monitor**, so a ping monitor's
raw-ICMP `NET_RAW` requirement was *unmeasured* and excluded. The socket.io
probe closes that:
- **HTTP monitor derivation** → `[DAC_OVERRIDE, FOWNER]`, `NET_RAW` **removable**
  (an HTTP monitor runs correctly without it). This is the published minimum.
- **PING monitor derivation** (paired spec `uptime-kuma-ping-caps.yaml`) →
  `[DAC_OVERRIDE, FOWNER, NET_RAW]`. Dropping `NET_RAW` fails the raw ICMP
  socket and the ping monitor goes **DOWN** — measured, not assumed.

So the base profile is now backed by an actually-running monitor, and the
ping caveat is **measured evidence** rather than an unmeasured gap.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [DAC_OVERRIDE, FOWNER].** node runs as root and
  writes its sqlite database + config under `/app/data` on a fresh rootfs:
  DAC_OVERRIDE to create/write the data tree (`Cannot write to …`), FOWNER
  for the permission fixups on files it does not own by mode.
- **No NET_BIND_SERVICE** — the web UI is the unprivileged :3001; **no
  privilege drop** (SETUID/SETGID not needed — it stays root).
- **Ping monitors: add NET_RAW.** Measured (above). NET_RAW is deliberately
  **not** in the base minimum — it would over-grant the common
  HTTP/TCP/keyword-monitor case. A deployment that runs ping monitors adds it.
- **Pass criteria:** sqlite setup + an HTTP monitor reporting UP, with every
  candidate dropped (base); the ping-spec run additionally requires NET_RAW.

## Scope (`run_config` + out-of-band conditions)
- **Invocation:** v2 default, embedded sqlite chosen at setup, fresh rootfs
  (no volume declared — data under `/app/data`), `no-new-privileges`.
- **Variations:** the mariadb-backed setup moves storage to the DB tier
  (expected to relax the data-dir caps; not derived here). **Ping monitors →
  add NET_RAW** (measured, above).
- **Out of band:** Docker's default seccomp baseline; amd64. The minimum
  covers setup + HTTP/TCP monitor execution; notifications, status pages, and
  push/keyword-specific paths are out of scope.
