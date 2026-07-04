# netdata — validation criteria

Per-image acceptance criteria for the `docker.io/netdata/netdata` capabilities
profile (compose-lint#359 convention).

## Image
`docker.io/netdata/netdata` (validated against
`netdata/netdata:v2.10.3@sha256:bcc822ec…`).

## Derivation: drop-test (observer=drop-test)
netdata is a monitoring agent commonly over-granted capabilities. Runtime
observation is insufficient here — its `SETUID`/`SETGID` fire only once, at
startup, to drop root→`netdata`. The minimum is therefore established by
**drop-test**, run against netdata deployed as a **host monitor**: `pid: host`,
host `/proc`,`/sys`,`/var/run/docker.sock` read-only mounts, host network, and
the full granted cap set present (a denied check is filtered, so an ungranted
cap reads as unused).

## Representative workload / correctness check
`profiles/workloads/netdata.sh` — the drop-and-restart correctness check. "Still works"
means, per candidate cap dropped: container healthy, HTTP API up, `apps.plugin`
(per-process, needs `SYS_PTRACE`) collecting, **and the daemon still dropped to a
non-root uid**. Liveness alone is insufficient — netdata runs "healthy" as root
when the privilege drop fails.

`duration_seconds` records the approximate total drop-test wall-clock; drop-test
is exempt from the observation-window floor (ADR-017 §8).

## Dimension & pass criteria

### capabilities (CL-0006 / CL-0011)
- **drop-test result** (drop each of the 7 originally granted, restart, verify):
  - `SYS_PTRACE`, `DAC_OVERRIDE`, `SYS_ADMIN` — required (exercised at runtime).
  - `SETUID`, `SETGID` — **required**: dropping either makes netdata run as root
    (uid 0); the privilege drop needs them at startup.
  - `CHOWN`, `FOWNER` — removable: netdata stayed healthy and still dropped to
    uid 201 without them (the image ships its data dirs already netdata-owned).
- **Verified minimum:** `cap_add: [DAC_OVERRIDE, SETGID, SETUID, SYS_ADMIN, SYS_PTRACE]`.
