# adguardhome — validation criteria

Per-image acceptance criteria for the `docker.io/adguard/adguardhome`
profile, **DNS-only scope**. Validated against `…@sha256:1ea34eaf…` (tag
`v0.107.78`), derived by drop-test against the default invocation.
Capabilities trim **14 → 2**.

## Representative workload / correctness check
`profiles/workloads/adguardhome.sh` — drive the REST **install/configure**
(admin + DNS:53 + web:80 in one call, a real persistent config write), add a
**local DNS rewrite** (`csd.test → 127.0.0.1`) so resolution is answered by
AGH itself with **no upstream in the trial loop** (the pihole lesson), then
assert `nslookup csd.test` returns `127.0.0.1` (matching the *answer* line,
not the `:53` server line). Curl sidecar for the API; in-image nslookup for
resolution.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [DAC_OVERRIDE, NET_BIND_SERVICE].**
- DAC_OVERRIDE — the root process creates/writes its config + data on the
  fresh rootfs (`[fatal] creating …` when dropped).
- NET_BIND_SERVICE — the privileged `:53` (and `:80` web); dropped, the
  binary can't even start its listeners (`exec … operation not permitted`).
  Scoped to the pinned `net.ipv4.ip_unprivileged_port_start=1024` posture.

## The clean contrast with pihole (both DNS, different architecture)
AdGuardHome is a single Go binary that **stays root** — no FTL-style
file-capability + user drop. Consequences vs pihole's 6-cap profile:
- **No SETFCAP** (no setcap step), **no SETUID/SETGID** (no privilege drop).
- **`no-new-privileges` stays compatible** — pihole must omit nnp because its
  file-cap acquisition needs it; AdGuard has no such step, so this profile
  keeps nnp. Two DNS servers, two low-port strategies, side by side.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** AdGuard writes its config to
  `/opt/adguardhome/conf` and its data (query log, statistics, downloaded filter
  lists) to `/opt/adguardhome/work` — neither is a declared VOLUME, so in
  production both are persistent bind-mounts / named volumes (never tmpfs). Under
  a read-only rootfs with those two writable it serves DNS with no additional
  tmpfs; `/tmp` was drop-tested and comes out **not required**.
- **Pass criteria:** the REST install + a local DNS rewrite + nslookup pass under
  `read_only:true` (with `conf` and `work` writable) and no rootfs tmpfs.

## Scope (`run_config` + out-of-band conditions)
- **DNS-only.** DHCP mode requires NET_ADMIN + raw sockets — out of scope
  (the pihole boundary).
- **Invocation:** image default, fresh rootfs (persist a `/opt/adguardhome`
  volume in production), the pinned sysctl, `no-new-privileges`.
- **Out of band:** Docker's default seccomp baseline; amd64. The minimum
  covers install + local resolution via a rewrite; upstream forwarding
  (outbound, same caps expected), filter-list updates, and the DHCP server
  are out of scope.
