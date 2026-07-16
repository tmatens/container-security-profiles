# jellyfin — validation criteria

Per-image acceptance criteria for the `docker.io/jellyfin/jellyfin` profile.
Validated against `…@sha256:aefb67e6…` (tag `10.11`). Capabilities and
filesystem derived by drop-test against the **default invocation**:
capabilities trim **14 → 0** and the filesystem locks **read-only with no
tmpfs at all** — the strongest lockdown in the catalog; both apply as a
unit. The devices dimension (below) is derived by **bpf-observation**
against the same digest and answers the conditional question — what a
hardware-transcode deployment must add.

## Representative workload / correctness check
`profiles/workloads/jellyfin.sh` — the real first-run flow end-to-end:
health, the **setup wizard REST sequence** (`Startup/Configuration` →
`Startup/User` → `Startup/Complete`), **token auth** as the created admin,
and an **authorized `System/Info` readback**. A fresh `/config` volume per
trial means the wizard executes in every trial. Probes ride the curl sidecar
(no HTTP client in-image), write nothing inside the container, and
capture-then-match responses.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [] (zero-cap)** — and unlike
  prometheus/memcached (non-root by construction), **jellyfin runs as root**
  with no privilege drop. Zero-cap holds anyway: it binds only the
  unprivileged `:8096` and writes only to its own VOLUMEs, so no capability
  is load-bearing anywhere on the wizard/auth/serve path. All 14 Docker
  defaults dropped in turn; the full flow passed every time.
- **What this means:** the Docker default cap set is pure over-grant for
  this image, and the residual risk is the **root uid itself** (a root
  process at zero caps still owns its volumes' content as root). The
  stronger hardening — `user:` with pre-owned config/cache — composes
  cleanly with this profile.
- **Pass criteria:** wizard completes, admin authenticates, authorized
  System/Info returns a version — with every candidate dropped.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** All writes land in `/config` (state, DB)
  and `/cache` — both declared VOLUMEs, persistent in real deployments, and
  writable under `--read-only`. `/tmp` derived **not required** on the
  wizard/auth/serve path — no tmpfs needed at all.

## devices — derived by bpf-observation (the transcode grant)
- **devices: [/dev/dri, /dev/dri/renderD128], derived_caps: [].** Derived
  with csd's `devices` observer (trace_open on `/dev`) against a
  `--device /dev/dri` run, driving jellyfin's **own bundled ffmpeg**
  (`/usr/lib/jellyfin-ffmpeg/ffmpeg`) through full VAAPI h264 hardware
  encodes for the whole 310s window
  (`profiles/workloads/jellyfin-transcode.sh`) — the same binary and device
  nodes a library-triggered playback transcode uses. `/dev/dri` (the
  directory) is opened for node enumeration, `renderD128` for the encode
  session; **no capability rides along** — the zero-cap story above holds
  even when transcoding.
- **What this means:** a transcode-enabled deployment needs exactly
  `devices: [/dev/dri]` on top of this profile — not `privileged: true`,
  not extra caps. The container runs as root, so `render` group membership
  is not needed; under the `user:` hardening add the render GID
  (`group_add`). Software-only deployments should grant no devices.
- **Portability:** derived on an amdgpu (Mesa/RADV) host; the device-access
  surface is driver-agnostic (`renderD128` is the first render node on
  Intel i915 and amdgpu alike). Multi-GPU hosts may expose the target GPU
  as `renderD129+` — grant the whole `/dev/dri` directory as derived and
  the right node is available either way.
- **Revalidation:** this dimension is **not in `derivation/manifest.yaml`**
  — the csd-derive runner VM has no GPU, so the weekly loop cannot
  re-derive it (grafting a GPU into the VM was judged not worth it,
  homelab decision 2026-07-16). On a digest bump, re-run the derivation
  manually on a GPU host:
  `sudo csd --observe devices --container <jf> --gadget-filter
  --duration 310s --workload profiles/workloads/jellyfin-transcode.sh
  --format compose-lint-profile` with the container started as
  `docker run -d --device /dev/dri jellyfin/jellyfin:<tag>`.
  Requires csd ≥ the build with the opt-in `--gadget-filter` + digest
  normalization (csd#407): without the filter, busy-host trace_open noise
  blows the drop-rate gate (this derivation measured drop_rate 288
  unfiltered vs 0 filtered); without the digest fix, registry-qualified
  names derive un-pinned. The flag is opt-in because in-gadget filtering
  observes zero events on some runtime/ig combinations (e.g. Docker 29's
  containerd image store) — sanity-check `trace_health.events_recorded > 0`
  on the run before trusting its output.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the image default — root, no
  env, docker-managed `/config` + `/cache` volumes, `no-new-privileges`.
- **Variations:** `user:` (the recommended hardening) with pre-owned volumes
  — expected unchanged ([] stays []). Media libraries on bind mounts must be
  readable by the serving uid; a library scan of unreadable mounts fails
  regardless of caps.
- **Out of band** (not schema fields): Docker's default seccomp baseline;
  amd64. The caps/fs minimum is only valid for what its workload exercises —
  wizard, auth, authorized API; library scans over real media and
  playback/streaming remain unexercised. Hardware transcode is covered by
  the devices dimension's own workload (real VAAPI encodes), not by the
  wizard flow.
