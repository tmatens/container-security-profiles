# You Probably Don't Need `--privileged`: Measuring What Containers *Actually* Require

Open a dozen self-hosting guides and you'll find the same reflex: a service won't
start, someone adds `--privileged` or `user: root` or `cap_add: [SYS_ADMIN]`, it
works, and that line gets copied into every compose file downstream forever. The
privilege sticks around long after anyone remembers why it was added — and
`--privileged` is not a small thing. It hands the container **every** Linux
capability, **every** host device, and drops the seccomp/AppArmor confinement
that stands between a compromised process and the host kernel. A single
remote-code-execution bug in a `--privileged` container is a host takeover.

So how much of that privilege is real? You can't tell by reading — you have to
**measure**. Below are a handful of images that loudly document a need for root
or privileged mode, each with the capability set it *actually* needs, derived
empirically. The results range from "needs literally nothing" to "yes, it really
does need that" — and the only way to know which is which is to remove a
privilege and watch whether the container breaks.

## The method: leave-one-out, and prove it breaks

The technique is deliberately dumb, which is what makes it trustworthy. Start from
the container's full granted privilege. Remove exactly one thing — one
capability, `--privileged`, the root uid. Restart. Run a **correctness check**
that exercises the service's real function, not just a health endpoint (a health
check stays green while the actual work is silently broken). If it still works,
that privilege was never needed. Repeat for each candidate. What's left — the set
whose removal genuinely breaks the service — is the minimum.

This is an *experiment*, not a guess or a static scan: it catches the difference
between "the docs say you need `SYS_ADMIN`" and "the service still works with it
gone." Everything below was run this way against the pinned, digest-identified
image. The tooling is [`container-sec-derive`](https://github.com/tmatens/container-sec-derive);
the derived profiles and their evidence live in
[`container-security-profiles`](https://github.com/tmatens/container-security-profiles).

---

## Case 1 — cAdvisor: `--privileged` → zero capabilities

cAdvisor is the textbook `--privileged` container. Google's own README runs it
with `--privileged`, and that command has been pasted into monitoring stacks for
the better part of a decade.

**Claimed:** `--privileged` (all capabilities, all devices, no confinement).

**Measured:** run it with `--cap-drop ALL` — every one of the 14 default
capabilities removed, no `--privileged` — and keep only the read-only host mounts
(`/`, `/sys`, `/var/lib/docker`, `/var/run`). It comes up healthy and serves
**143 per-container CPU samples** plus per-container memory, filesystem, and
disk-I/O — i.e. it monitors the *whole* container set, not just itself. Push it
further: add `--user 65534` (non-root) on top of `--cap-drop ALL`, and it still
serves the container metrics.

And — having been burned once (see netdata, below) — *compare the feature to the
`--privileged` baseline directly* rather than trusting that "it runs." Run the
same cAdvisor with `--privileged` and diff the metric families: **identical
coverage.** 143 per-container CPU samples either way; the same families present
in both; the couple of metrics that *don't* appear at zero caps (per-container
network) don't appear under `--privileged` either — they need `--net=host`, which
is a networking choice, not a capability. `--privileged` collects nothing that
`cap_drop: ALL` doesn't.

> cAdvisor: `--privileged` → **`cap_drop: ALL` with identical metric coverage,
> and it runs non-root too.**

The privilege cAdvisor genuinely needs turns out not to be *privilege* at all —
it's **read access to host paths**, supplied by read-only bind mounts, plus (for
the kernel-log collector) the single device `/dev/kmsg`. That's the tell: cAdvisor's
own maintainers added the `--device=/dev/kmsg` flag *specifically so that
`--privileged` isn't necessary* — and a decade of copied commands kept the
`--privileged` anyway. The requirement was never "all capabilities plus every
device node." It was some read-only mounts and one device.

---

## Case 2 — Tailscale: the copied cap stack it doesn't use

Search for a Tailscale docker-compose and you'll find the same block every time:
`cap_add: [NET_ADMIN, NET_RAW]`, often `SYS_MODULE`, and
`devices: [/dev/net/tun:/dev/net/tun]`. It's in countless gists and blog posts.

**Claimed:** `NET_ADMIN` + `NET_RAW` (+ `SYS_MODULE`) + the `/dev/net/tun` device.

**Measured:** Tailscale's **userspace networking mode is the default**
(`TS_USERSPACE=true`). Start the container with `--cap-drop ALL` and **no** TUN
device, and `tailscaled` comes up cleanly on `--tun=userspace-networking`,
`tailscale status` → `Logged out` — the daemon and its userspace network stack
are fully initialized and waiting only for an auth key. That's the part that
would otherwise "need" `NET_ADMIN` and the TUN device, running with **zero of
either.** (Scope, stated honestly: I verified the stack *initializes* at zero
privilege, not a full authenticated tunnel end-to-end — that needs a tailnet
auth key. Userspace mode is documented not to require caps or TUN, and the one
privilege-related effect I *did* observe is graceful.)

> Tailscale (default userspace mode): the copied cap stack → **`cap_drop: ALL`, no TUN device.**

The one observable effect of dropping the capabilities is a *graceful* one:
`failed to force-set UDP buffer size … using kernel default values (impacts
throughput only)`. It still works; it just doesn't get the throughput
optimization. `NET_ADMIN` + `/dev/net/tun` are real **only** for *kernel*
networking — subnet routers, exit nodes, or squeezing maximum throughput — which
is a minority of deployments and an opt-in (`TS_USERSPACE=false`). And
`SYS_MODULE`, copied along for the ride, is almost never needed: the `tun` module
is built into essentially every modern kernel. For the common "connect this box
to my tailnet" case, the answer is nothing.

---

## Case 3 — Home Assistant: `privileged: true` → one capability

Home Assistant's official Linux container install documents `privileged: true`
and `network_mode: host`, given as part of the standard command with **no
justification** in the docs. Home Assistant is a Python application.

**Claimed:** `privileged: true` (everything).

**Measured** (both directions, on a `/config` owned by a *different* uid — the
real-world case that makes the cap matter): with `cap_drop: ALL` +
`cap_add: [DAC_OVERRIDE]`, HA completes onboarding and writes its database and
`.storage` into that foreign-owned `/config` (owner-create returns `200`, the DB
file appears). Drop that one capability and HA **fatally exits at startup**:
`Unable to create library directory /config/deps: [Errno 13] Permission denied`.

> Home Assistant: `privileged: true` → **`cap_add: [DAC_OVERRIDE]`.**

It keeps `DAC_OVERRIDE` for exactly one reason: HA runs as root and writes its
state into a `/config` owned by another user, and that cap is what lets root
bypass the permission check. It's genuinely load-bearing — removing it doesn't
degrade HA, it kills it — but it is the *only* thing standing between this and a
completely unprivileged container. All 13 other default capabilities, every
device, and the seccomp profile are recoverable with no loss of function.

**Scope, because it's the honest thing to say:** this is a *base install*. The
blanket `privileged: true` in the docs exists to smooth hardware, USB, and
Bluetooth *integration* discovery, and each of those adds its own requirement — a
Zigbee/Z-Wave stick needs a `--device` mapping, Bluetooth needs D-Bus. Those are
narrow, specific grants (a device, a socket), not `privileged` — but they're real,
and a base-install measurement can't see them. "One capability" is the floor, not
a promise that your particular HA never needs a device node.

---

## Case 4 — Netdata: how measurement catches *its own* mistakes

Netdata's recommended Docker command asks for `--cap-add SYS_PTRACE`,
`--cap-add SYS_ADMIN`, `--security-opt apparmor=unconfined`, and `--pid=host`,
and runs as root. `SYS_ADMIN` is the notorious near-root catch-all — the
capability that does a hundred unrelated things and is a well-worn path to
container escape. It's the most tempting one to declare unnecessary.

**Claimed:** `SYS_PTRACE` + `SYS_ADMIN` + AppArmor unconfined (+ host PID).

**First measurement:** drive netdata's host monitoring — the API up, and a
**non-zero** per-process metric proving `apps.plugin` reads other processes'
`/proc` — and `SYS_ADMIN` looks removable. `SYS_PTRACE` stays (drop it and the
per-process metrics silently collapse to zero); `SYS_ADMIN` seemingly does not.
Tempting headline: "the scary broad cap was fake, the narrow one was real."

**Then challenge the result — and watch the challenge overreach.** That first
check drove per-*process* metrics. But `SYS_ADMIN`'s job in netdata is different:
its `cgroup-network` helper enters each container's **network namespace** — via
`setns()` — to attribute network traffic per container, and a check that never
opened a per-container network chart never exercised that path. So test the
mechanism directly. Under the proposed minimum (no `SYS_ADMIN`), try to enter a
running container's network namespace:

```
# no SYS_ADMIN:  nsenter: reassociate to namespace 'ns/net' failed: Operation not permitted
# + SYS_ADMIN:   1: lo ... 2: eth0@if1985 ...   (interfaces enumerated)
```

`setns(CLONE_NEWNET)` requires `CAP_SYS_ADMIN`. Case closed: the minimum
under-derived, per-container network monitoring needs `SYS_ADMIN`. That's what I
concluded — and I was about to ship it.

**Then check the actual feature on a live box, not the mechanism in a lab.** On a
production netdata running this *exact* cap set with **no `SYS_ADMIN`**, the
per-container network charts (`cgroup_<svc>.net_packets_veth…`) are present and
collecting **live, non-zero data**. The `setns` call does fail — *once, at
startup, non-fatally* — after which netdata falls back to a **host-side** method
(charting the container's host `veth` peer) that needs no privilege. The only
effect of dropping `SYS_ADMIN` is cosmetic: interfaces get labelled by their host
`veth` name instead of the in-container `eth0`.

> Netdata: **`cap_add: [DAC_OVERRIDE, SETGID, SETUID, SYS_PTRACE]` — `SYS_ADMIN`
> genuinely removable, per-container network included.**

So the original derivation was right after all — but the path to being *sure* went
through being confidently wrong twice: first the over-broad vendor default, then
*my* over-eager correction. `setns` needing `SYS_ADMIN` is true at the syscall
level and irrelevant at the feature level, because the software degrades
gracefully. **Testing the mechanism is not testing the feature.** The authority
isn't the isolated primitive or even the drop-test — it's the running deployment.
A measured minimum still has to be stated with its scope, but the deeper lesson is
that "I proved the syscall fails" and "I proved the feature breaks" are different
claims, and only the second one is worth publishing.

---

## Case 5 — Pi-hole: when the answer is "yes, it really does"

Pi-hole deserves credit first: its docs are a model of how to document privilege.
Every capability is listed with an explicit condition — `NET_ADMIN` *only* if
Pi-hole is your DHCP server, `SYS_TIME` *only* for the NTP-client feature,
`SYS_NICE` optional — and the docs **explicitly warn against** `--privileged`.
For plain DNS, the documented requirement is zero capabilities.

But there's a second privilege axis beyond capabilities: the **filesystem**. Can
Pi-hole run on a read-only root filesystem — the hardening that stops an attacker
from modifying the running container? Here measurement returns a firm **no**:

> Pi-hole: a read-only root filesystem is **infeasible** (a derived *negative*).

The reason is concrete and unrelocatable. Pi-hole's entrypoint `chown`s
`/macvendor.db` and `sed`-rewrites `/crontab.txt` **at the filesystem root**, and
the FTL update mechanism writes `/usr/bin/pihole-FTL`. You cannot make those
writable with a tmpfs or a volume — you can't mount over `/` or `/usr/bin`. This
is not "we didn't get to it"; it's "we measured, and it genuinely can't." That's
the counterweight that keeps the whole exercise honest. Sometimes the privilege a
container asks for is real, and the value of measurement is knowing **exactly
which part** — Pi-hole needs a writable root filesystem, but it does *not* need
`--privileged` or a pile of capabilities.

---

## The good citizens, the silent trap, and one important asterisk

**Vendors who do it right.** AdGuard Home documents its DNS server with *no
capabilities at all* — a DNS-on-`:53` service with zero documented privilege,
proof that binding a "privileged" port is not by itself a reason to reach for
root. Prometheus's node-exporter is the same: host PID + a read-only `/:/host`
mount, no `--privileged`, no caps. This is the bar, and it's very reachable.

**The silent trap.** The loud `--privileged` you can `grep` for is actually the
*easy* case. The common one is quieter: Immich, for instance, documents no
capability requirement at all, yet its containers ship running as `uid=0` by
default — root not because anything needs it, but because that's how the image was
built (the maintainers acknowledge it runs non-root with the right volume
ownership). Nobody chose that root on purpose, which is exactly why it survives.

**The asterisk that matters most.** "Zero capabilities" is not the same as "not
powerful." Portainer needs no `--privileged` and no caps — but it mounts
`/var/run/docker.sock`, and access to the Docker socket is **root-equivalent**:
anyone who can talk to it can start a `--privileged` container and own the host.
Capabilities are one axis of privilege; **host mounts and sockets are another**,
and sometimes the more dangerous one. Dropping every cap while bind-mounting the
Docker socket is not a hardened container. Measure both.

---

## What to take from this

- **`--privileged` is almost never the real requirement.** In the two loudest
  cases here (cAdvisor, Tailscale) it reduced to *zero* capabilities; in the next
  (Home Assistant) to *one*. The privilege was standing in for something
  narrower — a read-only mount, a single device, a single capability.
- **Test the feature, not the mechanism — and let the running deployment be the
  authority.** Netdata is the cautionary tale: an isolated test proved `setns`
  needs `SYS_ADMIN`, so I "corrected" the minimum to require it — and the live
  box, running with no `SYS_ADMIN`, proved the per-container network charts
  collect anyway via a graceful fallback. A failing syscall is not a broken
  feature. Verify against real behavior before you publish a privilege verdict,
  or you'll replace the vendor's over-claim with your own under-claim.
- **A "no" is a result, too.** Pi-hole genuinely can't run read-only. Knowing
  that *with evidence* is worth as much as knowing cAdvisor needs nothing — it
  tells you where to spend defense-in-depth effort instead of pretending.
- **Caps aren't the whole story.** A Docker-socket mount beats every capability
  you dropped. Harden the mount surface too.

The practical move is small: before you copy a `--privileged`, a `user: root`, or
a `cap_add:` block into your compose file, drop it and see what actually breaks.
Most of the time, nothing does.

*Every figure above was produced by removing a privilege from the pinned image and
running a function-level correctness check; the cAdvisor and Tailscale results
were derived live for this article, the rest are published with their drop-test
evidence in the [container-security-profiles](https://github.com/tmatens/container-security-profiles)
catalog.*

---

## Verification status

Each headline claim was checked with the rigor the netdata case earned. Current state:

| Image | Claim | Verified how | Status |
|---|---|---|---|
| cAdvisor | `--privileged` → `cap_drop: ALL` | metric families diffed against the `--privileged` baseline — identical coverage | ✅ verified |
| Home Assistant | `privileged: true` → 1 cap | onboarding + config-write succeed with `DAC_OVERRIDE`; fatally fails without it | ✅ verified (base install) |
| Netdata | `SYS_ADMIN` removable | live deployment collects per-container network via a host-side fallback | ✅ verified (corrected once) |
| Pi-hole | read-only rootfs infeasible | writes `/macvendor.db`, `/crontab.txt` at the filesystem root | ✅ verified (derived negative) |
| Tailscale | userspace mode → zero caps, no TUN | daemon + userspace stack **initialize** at zero privilege | ⚠️ **TODO: full authenticated tunnel** — needs an ephemeral tailnet auth key to confirm traffic flows end-to-end at zero caps. Claim is scoped to "initializes" until then. |

---

## Appendix — field guide: images that document elevated privilege

Beyond the case studies, a broader survey of popular self-hostable images that
document a root / `--privileged` / dangerous-capability requirement. "Reality"
is a drop-test-informed assessment; those not marked *verified* are candidates,
not measured results.

**Full `--privileged` / `privileged: true`:**

| Image | Documents | Stated reason | Reality |
|---|---|---|---|
| `ghcr.io/google/cadvisor` | `--privileged` | host cgroups/proc/sysfs + kernel log | **zero caps** + ro mounts + `/dev/kmsg` (verified) |
| `ghcr.io/home-assistant/home-assistant` | `privileged: true` + host net | (unexplained) | **1 cap** (`DAC_OVERRIDE`), base install (verified) |
| `nicolargo/glances` | `--privileged` (sensor mode) | full hardware sensors + host processes | reducible to specific device/mount access |

**Dangerous capabilities / kernel access:**

| Image | Documents | Stated reason | Reality |
|---|---|---|---|
| `netdata/netdata` | `SYS_ADMIN` + `SYS_PTRACE` + apparmor-unconfined | port→process, container-net monitoring | drop `SYS_ADMIN`; keep `SYS_PTRACE` (verified) |
| `tailscale/tailscale` | `NET_ADMIN` + `SYS_MODULE` + `/dev/net/tun` | kernel networking / tunnel | **zero** in default userspace mode (init verified) |
| `lscr.io/linuxserver/wireguard` | `NET_ADMIN` + `SYS_MODULE` | VPN iface / load kernel module | `NET_ADMIN` real; `SYS_MODULE` unneeded (built-in) |
| `ghcr.io/analogj/scrutiny` | `SYS_RAWIO` (+`SYS_ADMIN` for NVMe) | `smartctl` SMART ioctls | **largely genuine** (raw disk access) |

**Device access, root-by-default, or root-equivalent mounts:**

| Image | Documents | Stated reason | Reality |
|---|---|---|---|
| `ghcr.io/koenkk/zigbee2mqtt` | `privileged: true` (community configs) | reach the USB Zigbee dongle | official docs are right: device map + `dialout` group, not privileged |
| `pihole/pihole` | conditional `NET_ADMIN`/`SYS_TIME`; root | DHCP / NTP / scheduling | vendor documents it well; read-only rootfs genuinely infeasible (verified) |
| `portainer/portainer-ce` | `docker.sock` mount (no caps) | manage the Docker engine | **the socket is root-equivalent** — more dangerous than most caps |

Two honest patterns worth naming: several of these (Zigbee2MQTT, Scrutiny,
Glances-sensors) are *well-documented at the source* but get `privileged: true`
bolted on in community/Home-Assistant configs — the over-privilege is downstream.
And the sneakiest form is invisible: images like Immich that run `uid=0` by
default with no documented need — root nobody chose on purpose. Good citizens to
emulate: AdGuard Home and Prometheus node-exporter, which document their DNS /
host-metrics functions with **no** elevated capability at all.

*Sources for the documented claims and the caveats (AdGuard's wiki and Tailscale's
KB page are flagged outdated/JS-rendered — re-check their exact strings before
quoting) are recorded in the research notes behind this article.*
