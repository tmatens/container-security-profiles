# home-assistant — validation criteria

Per-image acceptance criteria for the `ghcr.io/home-assistant/home-assistant`
profile (Home Assistant Core, the container install). Validated against
`…@sha256:f73512ba…` (tag `stable`), derived by drop-test against HA's **own default
invocation**. The deployment sets no `cap_drop` (its compose comment: *"tighten
further only after verifying HA still boots"*), so HA runs on the **full Docker
default cap set**; this profile trims it **14 → 1**.

## Representative workload / correctness check
`profiles/workloads/home-assistant.sh` drives HA core's real write path, not just
liveness:
- reach the onboarding API (`/api/onboarding`) — HA only gets here after it has
  parsed config and written `home-assistant_v2.db` + `.storage` + logs into
  `/config`;
- complete owner onboarding (create the first user) → HTTP 200 + an `auth_code`, a
  further real write to `.storage/auth`.

HA runs **as root** by design (no privilege drop), so — unlike forgejo/postgres —
there is no non-root-uid assertion to make.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [DAC_OVERRIDE].** Baseline `cap_drop:ALL` + the Docker
  default set; each default is dropped in turn and the workload re-verified. Only
  DAC_OVERRIDE is required. All others (CHOWN, FSETID, FOWNER, MKNOD, NET_RAW,
  SETGID, SETUID, SETFCAP, SETPCAP, NET_BIND_SERVICE, SYS_CHROOT, KILL, AUDIT_WRITE)
  are removable — HA core exercises none of them.
- **DAC_OVERRIDE is a config-ownership artifact, not intrinsic.** HA writes its DB /
  `.storage` / logs into `/config` as **root**. In the deployment `/config` is a
  bind owned by the **deploy user (non-root)**, so root (an "other" on the dir) needs
  DAC_OVERRIDE to write it. The derivation reproduces this with a fresh,
  non-root-owned `/config`. **Against a root-owned `/config`** (e.g. a Docker named
  volume, or a bind chowned to root) HA needs **no caps at all** (`cap_add: []`) —
  the value here depends on the mount, which is why `run_config.mounts` records the
  `./config` bind.
- **Pass criteria:** the workload passes (onboarding API + owner user created);
  dropping DAC_OVERRIDE makes HA unable to write `/config` and the container exits.

## Scope — this is HA *core*, integrations extend the minimum
This is the sharp edge for Home Assistant: its capability needs are a function of the
**enabled integrations**, and a base instance exercises none of them. Capabilities a
real install may pull in, NOT covered by this profile:
- **NET_RAW** — the `ping` integration's ICMP, and some discovery paths.
- **NET_ADMIN** — a few network-management integrations.
- **device access** (a `devices:`/CL-0016 concern, not caps) — USB / Bluetooth /
  Zigbee / Z-Wave dongles, and `/dev/dri` for hardware-accelerated media.
- **NET_BIND_SERVICE** — only if HA is configured to serve on a privileged port
  (the default `:8123` is unprivileged).

So `cap_add: [DAC_OVERRIDE]` is the **base-config floor**, and the honest consumption
model for an integration-heavy install is to **re-derive against the real `./config`**
(a deploy-check follow-up), not to treat this floor as complete.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): HA's — root (no `user:` override; HA runs
  as root), the `./config` bind, `TZ` env, `no-new-privileges`. A root-owned config
  shrinks the minimum to `[]` (see above).
- **Out of band** (not schema fields): Docker's default cap set + default seccomp
  baseline; a base config with no integrations configured; the unprivileged `:8123`
  listener; amd64. The minimum is only valid for what
  `profiles/workloads/home-assistant.sh` exercises — HA core, no integrations.
