# itzg/minecraft-server — validation criteria

Per-image acceptance criteria for the `docker.io/itzg/minecraft-server` profile (the
de-facto self-hosted Minecraft server image). Validated against `…@sha256:2e7c7b7…`
(tag `latest`), derived by drop-test. The default runs on the full Docker default
cap set; this profile trims it **14 → 2**.

## Representative workload / correctness check
`profiles/workloads/minecraft.sh` waits for the server to accept a status ping
(`mc-monitor status`, which ships in the image) **and** asserts the server process
(`java`) runs as the non-root minecraft user (uid 1000): a ping alone would pass
while the server ran as root, so the privilege drop must be confirmed.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [SETGID, SETUID].** Baseline `cap_drop:ALL` + the
  Docker default set on a fresh data volume; each default is dropped in turn and the
  workload re-verified. Only SETGID/SETUID are required — the entrypoint gosu-drops
  root → the minecraft user, and dropping either fails with `error: failed switching
  to 'minecraft:minecraft'`. Both are **startup** caps, invisible to runtime
  observation.
- **CHOWN and DAC_OVERRIDE are NOT required.** The image ships `/data` owned by the
  minecraft user (uid 1000), so a docker-managed volume inherits that ownership: the
  entrypoint performs no datadir chown, and the server writes `/data` as its owner
  (same shape as mariadb). This validates the commonly-declared
  `cap_add: [SETUID, SETGID]` as already optimal.
- **Server-flavour independent.** The minimum is set by the entrypoint's init +
  privilege drop, not by the game server, so it was derived with a fast
  `TYPE=VANILLA` + `LEVEL_TYPE=FLAT` config and applies equally to a
  PURPUR/PAPER/FABRIC deployment (which only changes the downloaded server jar).
- **Pass criteria:** the server answers `mc-monitor status` **and** the `java`
  process is uid 1000; dropping SETUID or SETGID breaks the gosu drop and the
  container exits.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): default entrypoint, no `user:` override,
  a docker-managed `/data` volume, `EULA=TRUE` + server config env,
  `no-new-privileges`. Running with `user:` set to the minecraft uid against a
  pre-owned volume would skip the gosu drop, shrinking the minimum to `[]`.
- **Out of band** (not schema fields): Docker's default cap set + default seccomp
  baseline; a docker-managed `/data` volume (inherits the image's uid-1000
  ownership); amd64. The minimum is only valid for what
  `profiles/workloads/minecraft.sh` exercises — the server reaching a status-ping
  ready state as a non-root process.

## Derivation note
The drop-test must run with **anonymous volumes cleaned per trial** (container-sec-derive's
`drop_test.sh` uses `docker rm -f -v`): this image declares `/data` as a VOLUME and
downloads a server jar + generates a world per trial, so leaked per-trial volumes
would exhaust disk and produce spurious "required" verdicts (a container that can't
write `/data`/download reads as a cap failure). Re-derive on a host with adequate
free disk.
