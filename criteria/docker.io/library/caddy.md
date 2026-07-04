# caddy — validation criteria

Per-image acceptance criteria for the `docker.io/library/caddy` profile
(compose-lint#359). Validated against `caddy:2@sha256:af5fdcd7…`, the default
file-server configuration.

## Representative workload / correctness check
`profiles/workloads/caddy.sh` — wait for readiness, serve a file-server `GET /`
on `:80`, send `SIGUSR1` to reload the Caddyfile, and serve again. Under the
derived config it must complete cleanly. The drop-test correctness check
(`container-sec-derive testdata/drop-test/correctness/caddy.sh`) is the same
correctness signal: caddy serves a `GET` on `:80`.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [NET_BIND_SERVICE].** Baseline is `cap_drop:ALL` +
  the full Docker-default cap set; each default cap is dropped in turn and the
  file server re-verified.
- Only **NET_BIND_SERVICE** is required — caddy binds the privileged port `:80`,
  and without the cap it cannot listen (the container exits / the `GET` fails).
  Every other default cap (CHOWN, DAC_OVERRIDE, FSETID, FOWNER, MKNOD, NET_RAW,
  SETGID, SETUID, SETFCAP, SETPCAP, SYS_CHROOT, KILL, AUDIT_WRITE) is dropped
  with the file server still serving.
- Matches the independently bisected ground truth in `container-sec-derive`
  (`testdata/caddy/ground_truth.json`).
- **Pass criteria:** the file server serves under `cap_drop:ALL` +
  `cap_add:[NET_BIND_SERVICE]`, and dropping NET_BIND_SERVICE breaks it
  (confirming the cap is required and minimal).

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** caddy serves correctly with a read-only root
  filesystem and **no** tmpfs. Verified live: under `--read-only` the file
  server responds, logging only non-fatal errors that it cannot persist certs or
  autosave config.
- caddy's only writes are **`/data`** (TLS certificates + storage locks) and
  **`/config`** (config autosave). Both were drop-tested as tmpfs candidates and
  come out **not required** for serving.
- **These paths belong on PERSISTENT VOLUMES, not tmpfs.** `/data` holds ACME/TLS
  certificates that MUST survive restarts — backing it with tmpfs would silently
  discard certs on every restart and risk ACME rate limits. caddy's standard
  deployment mounts named volumes (`caddy_data:/data`, `caddy_config:/config`),
  and this profile assumes that. tmpfs is deliberately empty: nothing here is
  ephemeral (contrast postgres, whose `/run/postgresql` socket dir *is*
  ephemeral and so is genuinely tmpfs).
- **Pass criteria:** the workload passes under `read_only:true` (with `/data` and
  `/config` as writable volumes), and the file server serves even with neither
  path writable (confirming the rootfs itself needs no writes).

## Scope
Covers the **default file server**. A caddy configured as a reverse proxy with
automatic HTTPS exercises the same capability minimum (`NET_BIND_SERVICE`, plus
`:443`) and the same filesystem posture, but makes `/data` load-bearing — it is
then strictly required as a persistent volume for certificate storage.
