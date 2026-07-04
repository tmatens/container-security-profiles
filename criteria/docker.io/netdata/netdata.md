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
collecting, **the daemon still dropped to a non-root uid**, **and a per-process
`fds_open` is NON-ZERO** (`app.dockerd_*` etc.). Liveness alone is insufficient —
netdata runs "healthy" as root when the privilege drop fails. The **non-zero**
per-process assertion is what makes `DAC_OVERRIDE`/`SYS_PTRACE` honestly testable:
`apps.plugin` runs real-uid = the netdata user, so it needs `CAP_SYS_PTRACE` to
read any process's `/proc/<pid>/io|fd`; without it it reports every per-process
metric as **0 (not null)**, so a mere non-null check passes on broken collection
(and once wrongly derived `SYS_PTRACE` removable, regressing production).

`duration_seconds` records the approximate total drop-test wall-clock; drop-test
is exempt from the observation-window floor (ADR-017 §8).

## Dimension & pass criteria

### capabilities (CL-0006 / CL-0011)
- **drop-test result** (drop each of the 7 originally granted, restart, verify):
  - `DAC_OVERRIDE` — **required**: dropping it makes the container exit at startup
    (API/apps.plugin never come up).
  - `SETUID`, `SETGID` — **required**: dropping either makes netdata run as root
    (uid 0); the privilege drop needs them at startup.
  - `SYS_PTRACE` — **required**: `apps.plugin` runs real-uid = the netdata user,
    so it needs `CAP_SYS_PTRACE` to read any process's `/proc/<pid>/io|fd`.
    Dropping it makes every per-process metric collect as **0** — the drop-test
    detects this via the non-zero `fds_open` check. (An earlier non-null check
    missed it and wrongly derived it removable, regressing production.)
  - `SYS_ADMIN` — **removable**: the image ships **no `ebpf.plugin`**, so
    `netdata.conf`'s `ebpf=yes` is a no-op and `SYS_ADMIN` gates nothing (no
    `ebpf.*` charts; removing it changes nothing).
  - `CHOWN`, `FOWNER` — removable: netdata stayed correct (per-process metrics
    non-zero) without them. `CHOWN`'s absence only produced cosmetic startup log
    noise from a stale alarm-notify cache (a leak, since cleared), not a
    functional loss.
- **Verified minimum:** `cap_add: [DAC_OVERRIDE, SETGID, SETUID, SYS_PTRACE]`
  (drop `SYS_ADMIN` only from the 5-cap grant). Matches the live deploy.
