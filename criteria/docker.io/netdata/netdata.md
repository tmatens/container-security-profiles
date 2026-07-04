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
collecting, **the daemon still dropped to a non-root uid**, **and per-process
io/fd metrics still collect for a NON-root process group** (`app.netdata_*`, uid
201). Liveness alone is insufficient — netdata runs "healthy" as root when the
privilege drop fails. The non-root per-process assertion is what makes
`DAC_OVERRIDE`/`SYS_PTRACE` honestly testable: reading another uid's
`/proc/<pid>/io|fd` is the sensitive path, and a root target process would be
readable for free (hiding whether the cap is needed).

`duration_seconds` records the approximate total drop-test wall-clock; drop-test
is exempt from the observation-window floor (ADR-017 §8).

## Dimension & pass criteria

### capabilities (CL-0006 / CL-0011)
- **drop-test result** (drop each of the 7 originally granted, restart, verify):
  - `DAC_OVERRIDE` — **required**: dropping it makes the container exit at startup
    (API/apps.plugin never come up).
  - `SETUID`, `SETGID` — **required**: dropping either makes netdata run as root
    (uid 0); the privilege drop needs them at startup.
  - `SYS_PTRACE` — **removable**: `apps.plugin` is setuid-root, so it reads other
    processes' `/proc/<pid>/io|fd` as root without the cap. Verified: per-process
    metrics still collect for a non-root group (uid 201) with it removed.
  - `SYS_ADMIN` — **removable**: the image ships **no `ebpf.plugin`**, so
    `netdata.conf`'s `ebpf=yes` is a no-op and `SYS_ADMIN` gates nothing (no
    `ebpf.*` charts; removing it changes nothing).
  - `CHOWN`, `FOWNER` — removable: netdata stayed correct without them.
- **Verified minimum:** `cap_add: [DAC_OVERRIDE, SETGID, SETUID]`
  (combination-verified: netdata run with exactly these three passes the
  correctness check). Was `[…, SYS_ADMIN, SYS_PTRACE]` before this honest
  re-derivation on a posture-matched host.
