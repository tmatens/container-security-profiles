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
  - `SYS_ADMIN` — **removable for this profile's exercised scope (host +
    per-process monitoring)**, but see the coverage caveat below: it is NOT
    removable if you rely on per-container **network-interface** metrics. The
    ebpf angle is moot here (the image ships **no `ebpf.plugin`**, so
    `netdata.conf`'s `ebpf=yes` is a no-op), but `SYS_ADMIN` has a second use the
    workload does not drive — see below.
  - `CHOWN`, `FOWNER` — removable: netdata stayed correct (per-process metrics
    non-zero) without them. `CHOWN`'s absence only produced cosmetic startup log
    noise from a stale alarm-notify cache (a leak, since cleared), not a
    functional loss.
- **Verified minimum:** `cap_add: [DAC_OVERRIDE, SETGID, SETUID, SYS_PTRACE]`
  (drop `SYS_ADMIN` only from the 5-cap grant). Matches the live deploy.

### Note — SYS_ADMIN, per-container network monitoring, and the setns fallback
`SYS_ADMIN` is genuinely removable, **including for per-container
network-interface metrics** — verified on the live deployment (this exact cap
set, no `SYS_ADMIN`): the per-container network charts (e.g.
`cgroup_<svc>.net_packets_veth…`) are present and collecting **live, non-zero
data**.

The subtlety that makes this true is worth recording, because it is easy to get
wrong. netdata's `cgroup-network` helper *prefers* to enter each container's
network namespace via `setns(CLONE_NEWNET)`, which **does** require
`CAP_SYS_ADMIN` — and under this profile's cap set that call fails once at
startup (`Cannot switch to network namespace of pid …: Operation not permitted`).
But that failure is **non-fatal**: netdata falls back to a **host-side** method
(matching the container's host-side `veth` peer) that needs no privilege, and the
per-container network charts collect normally through it. The only observable
effect of dropping `SYS_ADMIN` is cosmetic — interfaces are labelled by their
host `veth` name rather than the in-container `eth0` — not a loss of data.

Methodology note: an isolated test showed `setns` into a container netns needs
`SYS_ADMIN`, which is true at the *syscall* level — but the *feature* does not,
because the software degrades gracefully. Testing the mechanism is not the same
as testing the feature; the live deployment is the authority, and it confirms the
original `SYS_ADMIN`-removable derivation.
