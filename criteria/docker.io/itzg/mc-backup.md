# itzg/mc-backup — validation criteria

Per-image acceptance criteria for the `docker.io/itzg/mc-backup` profile — the
first **dependent-tier** (in-stack) catalog profile. Validated against
`…@sha256:085e2da5…` (tag `latest`), derived by an in-stack drop-test.

## In-stack derivation
mc-backup cannot be exercised in isolation: it RCON-connects to a running minecraft
server (`save-off`/`save-on` to flush the world) and tars minecraft's **shared
/data** volume into `/backups`. With no minecraft it blocks on RCON and produces
nothing, so a standalone test can't tell a real capability requirement from a
dependency-down failure. It is therefore derived with:
- **`deps: [minecraft]`** — an itzg/minecraft-server (VANILLA/FLAT) brought up on a
  shared network, reachable as `minecraft`, held up across every trial;
- **`run.volumes_from: [minecraft]`** — mc-backup shares minecraft's `/data`
  (its world), exactly as the deployment does.

## Representative workload / correctness check
`profiles/workloads/mc-backup.sh` requires a **real** backup: the newest archive in
`/backups` must CONTAIN the world (≥5 entries), not merely exist. This is the
load-bearing check — see below.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [DAC_OVERRIDE].** mc-backup runs as **root** and does
  not drop privileges. minecraft's `/data` is owned by uid 1000, mode 0750; root is
  "other" with no access, so reading it to tar the world requires **DAC_OVERRIDE**.
  Every other Docker default is removable.
- **Empty-backup trap (why the content check matters).** Without DAC_OVERRIDE
  mc-backup still creates the archive FILE but archives nothing — a 0-entry, ~45-byte
  empty tarball. A "backup file exists" check would pass on this broken backup; only
  counting entries gates the read capability. Observed directly: `[DAC_OVERRIDE]` →
  175 entries; `[SETUID,SETGID]` or no caps → 0 entries.
- **The commonly-declared `cap_add: [SETUID, SETGID]` is WRONG for this sidecar.**
  mc-backup performs no privilege drop, so SETUID/SETGID do nothing, and without
  DAC_OVERRIDE the backups are silently empty. A deployment using `[SETUID,SETGID]`
  is backing up nothing.
- **Pass criteria:** a backup archive containing ≥5 world entries is produced;
  dropping DAC_OVERRIDE yields a 0-entry empty tar.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): root (no `user:` override), minecraft's
  shared `/data` + a `/backups` volume, `RCON_*` + `BACKUP_*` env,
  `no-new-privileges`. The in-stack dependency (`minecraft`, shared `/data`) is not
  a run_config schema field; it is recorded here.
- **Invocation dependence:** DAC_OVERRIDE is required because mc-backup reads a
  **foreign-owned** (uid 1000) `/data` as **root**. Running mc-backup as
  `user: "1000"` (matching the world's owner) would let it read `/data` as the
  owner and need **no caps at all** — a smaller, arguably better hardening. This
  profile is the root-invocation minimum for the common shared-`/data`-from-minecraft
  setup.
- **Out of band** (not schema fields): Docker's default cap set + default seccomp;
  a minecraft server reachable over RCON sharing its `/data`; amd64. The minimum is
  only valid for what `profiles/workloads/mc-backup.sh` exercises — a real,
  world-containing backup.
