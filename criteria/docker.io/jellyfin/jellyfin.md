# jellyfin — validation criteria

Per-image acceptance criteria for the `docker.io/jellyfin/jellyfin` profile.
Validated against `…@sha256:aefb67e6…` (tag `10.11`), derived by drop-test
against the **default invocation**. Capabilities trim **14 → 0** and the
filesystem locks **read-only with no tmpfs at all** — the strongest lockdown
in the catalog. Both dimensions apply as a unit.

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

## Scope — GPU/transcoding is OUT
Hardware transcoding (`/dev/dri`, VAAPI/QSV) is the **devices dimension**
and is explicitly out of scope — the same deferral as immich's GPU (tracked
upstream as csd#266). A transcode-enabled deployment adds `devices:` grants
and likely `render` group membership; nothing in this profile speaks to
that. Software playback of already-compatible media goes through the serve
path this profile covers.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the image default — root, no
  env, docker-managed `/config` + `/cache` volumes, `no-new-privileges`.
- **Variations:** `user:` (the recommended hardening) with pre-owned volumes
  — expected unchanged ([] stays []). Media libraries on bind mounts must be
  readable by the serving uid; a library scan of unreadable mounts fails
  regardless of caps.
- **Out of band** (not schema fields): Docker's default seccomp baseline;
  amd64. The minimum is only valid for what the workload exercises — wizard,
  auth, authorized API; library scans over real media, playback/streaming,
  and hardware transcode are out of scope.
