# forgejo — validation criteria

Per-image acceptance criteria for the `codeberg.org/forgejo/forgejo` profile (the
self-hosted Git forge). Validated against `…@sha256:55bb42be…` (tag `15`), derived
by drop-test against **forgejo's own default s6-init invocation**. The deployment
sets no `cap_drop`, so forgejo runs on the **full Docker default cap set**; this
profile trims it **14 → 5**.

## Representative workload / correctness check
`profiles/workloads/forgejo.sh` drives the whole surface, because the container runs
**two root daemons** under s6 and a faithful minimum must keep both alive:
- web/API up (`/api/v1/version`);
- a real DB + git write: create an admin user (sqlite write **as the git user**),
  create a repo via the API, then **clone + commit + push over HTTP**;
- **sshd reaches authentication**: an unauthenticated SSH connection returns
  `Permission denied (publickey)` only if the pre-auth privilege-separation child
  forked (chroot + setuid). The drop-test correctness check additionally asserts the
  `gitea web` process runs as the **non-root** git user (uid 1000) — a health check
  alone is not enough (forgejo can serve `/api/v1/version` while failing to drop
  root or with git-over-SSH broken).

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID, SYS_CHROOT].**
  Baseline `cap_drop:ALL` + the Docker default set on a **fresh** `/data` volume (the
  image declares `/data` as a VOLUME, so each trial gets a fresh, root-owned volume —
  reproducing a first deploy, so the root→git chown fires); each default is dropped
  in turn and the workload re-verified. All five are **startup** caps — runtime
  observation records them as unused, so drop-test is the authoritative source.
- **The minimum is the UNION across both daemons.** `gitea web` needs CHOWN (chown
  the fresh `/data` to the git user), DAC_OVERRIDE (setup writes it doesn't own as
  root — e.g. `environment-to-ini` rewriting the git-owned `app.ini`), and
  SETUID/SETGID (the `su-exec` root→git drop). `sshd` needs **SYS_CHROOT** for the
  per-connection privsep chroot.
- **SYS_CHROOT is the workload-coverage sharp edge.** Drop it and the web API still
  answers 200 and the git-over-HTTP path still works — but every SSH connection is
  reset (`Connection reset`), so **git-over-SSH is silently dead**. A web-only
  correctness check would derive a 4-cap minimum that breaks SSH. Because the
  deployment publishes `2222:22` for Git SSH, the profile keeps SYS_CHROOT and the
  workload exercises SSH.
- **NET_BIND_SERVICE is a genuine over-grant here.** sshd binds the privileged `:22`
  but runs **as root**, so it needs no capability to do so (and the web binds the
  unprivileged `:3000`). Dropping NET_BIND_SERVICE leaves everything working. This is
  a runtime-posture judgement: it holds because both listeners that bind low ports
  run as root — a non-root process binding `:22` would need it.
- **Pass criteria:** the workload passes (web + git-over-HTTP + sshd-reaches-auth)
  **and** `gitea web` runs as uid 1000; dropping CHOWN, DAC_OVERRIDE, SETUID, SETGID,
  or SYS_CHROOT breaks correctness with the signatures recorded in `drop_test.checks`.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): forgejo's — root (no `user:` override,
  the image drops privileges itself), the `forgejo-data:/data` volume,
  `USER_UID/USER_GID=1000`, sqlite3, `INSTALL_LOCK=true`, `no-new-privileges`. Run
  with an already-initialised, git-owned `/data` the chown is a no-op and CHOWN reads
  as removable — this profile is the first-deploy conservative superset. Disabling
  the built-in SSH server (`DISABLE_SSH=true`) removes the SYS_CHROOT requirement.
- **Out of band** (not schema fields): Docker's default cap set + default seccomp
  baseline; a **fresh** `/data` volume; the built-in sshd enabled; amd64. The minimum
  is only valid for what `profiles/workloads/forgejo.sh` exercises.
- **Coverage caveats:** KILL reads as removable — s6 signals its cross-uid children
  (the git-owned `gitea web`) on shutdown/restart, a path the running-service
  workload does not exercise; it is not needed for steady-state operation. LFS,
  external-DB (`DB_TYPE=postgres`), and mailer paths are not exercised.
