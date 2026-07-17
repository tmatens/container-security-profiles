# pihole — validation criteria

Per-image acceptance criteria for the `docker.io/pihole/pihole` profile,
**DNS-only scope**. Validated against `…@sha256:f7d1be83…` (tag `2026.07.2`),
derived by drop-test against the **default invocation**. Capabilities trim
**14 → 6**, and the derivation confirmed the coverage queue's prediction:
upstream guidance suggests a much broader set, and none of the extras are
load-bearing for DNS.

## Representative workload / correctness check
`profiles/workloads/pihole.sh` — real DNS resolution with **no external
dependence**: `dig @127.0.0.1 pi.hole`, a name pihole-FTL answers
authoritatively itself, so no upstream reachability sits in the trial loop.
Probes exec as `--user pihole` using the in-image dig. The drop-test
correctness check also asserts FTL runs as the non-root pihole user
(uid 1000).

## The architecture (the catalog's fourth privilege shape)
The ROOT entrypoint provisions `/etc/pihole` and **setcaps the pihole-FTL
binary**; FTL then starts as the pihole user and receives its runtime
capabilities (the `:53` bind) from those **file capabilities** — not from a
gosu re-exec, not a master/worker fork, not an in-process drop.

Two hard consequences, both measured:

1. **`no-new-privileges` is INCOMPATIBLE with this image** when `:53` is
   privileged: nnp blocks file-capability acquisition on exec, so an nnp'd
   pihole can never bind :53 under the hardened sysctl posture. This is the
   only catalog profile whose `run_config` omits nnp — an architectural
   property of the image, not an oversight. (Deployments that keep docker's
   default `ip_unprivileged_port_start=0` can run nnp, because the file cap
   is then unnecessary.)
2. **SETFCAP derives required** — a rare, honest grant: it exists solely for
   the entrypoint's setcap call. Dropped, pihole's own error message
   suggests running FTL as root (`set DNSMASQ_USER=root`) — i.e., the image
   trades SETFCAP for root-FTL. Granting SETFCAP and keeping FTL non-root is
   the better side of that trade.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [CHOWN, DAC_OVERRIDE, NET_BIND_SERVICE,
  SETFCAP, SETGID, SETUID].**
- CHOWN + DAC_OVERRIDE — the root entrypoint's `/etc/pihole` provisioning
  (fresh rootfs every trial; the image declares no volumes).
- SETGID + SETUID — starting FTL as the pihole user.
- SETFCAP — the setcap call (above).
- NET_BIND_SERVICE — the privileged `:53`; file caps draw from the
  **bounding set**, so dropping it from the bounding set correctly breaks
  the bind. Scoped to the pinned
  `net.ipv4.ip_unprivileged_port_start=1024` posture.
- **The over-grant finding:** NET_RAW, NET_ADMIN (not even in the default
  set), SYS_NICE, FOWNER, MKNOD — all commonly suggested, all derived
  removable for DNS. SYS_NICE/SYS_TIME absence degrades gracefully (FTL
  logs a warning, priority/NTP features off).
- **Pass criteria:** `pi.hole` resolves locally and FTL is uid 1000.

## filesystem — derived by drop-test (NEGATIVE result)
- **read_only: false.** pihole cannot run under a read-only rootfs as shipped.
  Verified: run `--read-only` under pihole's published cap set with generous
  tmpfs on the config/runtime dirs (`/etc/pihole`, `/etc/dnsmasq.d`, `/run`,
  `/tmp`, `/var/log`) and the baseline still fails — the entrypoint `chown`s
  **`/macvendor.db`** and `sed`-rewrites **`/crontab.txt`** at the **filesystem
  root**, and the FTL auto-update mechanism writes **`/usr/bin/pihole-FTL`**.
  None of these is relocatable to a tmpfs or a volume (you cannot tmpfs `/` or
  `/usr/bin`), so no read-only + tmpfs configuration works.
- This is a **derived negative**, not an un-derived gap: the reproducer
  (`csd testdata/drop-test/pihole-fs.yaml`) exits 3 (baseline FAILED). A future
  pihole that relocated these writes to a data dir could be re-derived.
- **Pass criteria:** none — `read_only: true` is infeasible for this image.

## Coverage & confidence (moderate)
Per ADR-018, the capabilities dimension is `moderate` — the workload is DNS-only,
and Pi-hole documents conditional caps for optional features the workload does not
drive: **DHCP** (`NET_ADMIN`), **NTP client** (`SYS_TIME`), and `SYS_NICE`. None is
in the DNS-only minimum, so `coverage: partial`. (The filesystem dimension's
`read_only: false` is a robust negative and stays `high` — it holds regardless of
which optional features are enabled.)

## Scope (`run_config` + out-of-band conditions)
- **DNS-only.** DHCP mode requires NET_ADMIN and raw sockets — out of scope
  by design (the queue's boundary).
- **Invocation** (`derivation.run_config`): image default, fresh rootfs (no
  volumes declared), `FTLCONF_webserver_api_password` set, the pinned
  sysctl, **no nnp** (see above).
- **Out of band** (not schema fields): Docker's default seccomp baseline;
  amd64. The minimum is only valid for what the workload exercises — local
  authoritative resolution; upstream forwarding, blocking-list gravity
  updates (network fetch, same caps expected), the web UI/API, and DHCP are
  out of scope.
