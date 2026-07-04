# homepage — validation criteria

Per-image acceptance criteria for the `ghcr.io/gethomepage/homepage` profile
(compose-lint#359). Validated against `homepage:v1.13.2@sha256:a0b71c8e…`, the
default dashboard.

## Representative workload / correctness check
`profiles/workloads/homepage.sh` — wait for readiness, serve the dashboard
`GET /`, and trigger Next.js image optimization (`GET /_next/image`, which writes
`/app/.next/cache`). Correct iff the dashboard serves **and** the image cache is
writable (no read-only / ENOENT error). The drop-test correctness check
(`container-sec-derive testdata/drop-test/correctness/homepage.sh`) is the same
signal.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [/app/.next/cache].** homepage serves under a
  read-only root filesystem; its one runtime tmpfs need is `/app/.next/cache`.
- **Why the cache is required — and why a naive check misses it:** a bare
  dashboard `GET` serves fine read-only, so `/app/.next/cache` looks unnecessary.
  But Next.js **image optimization** (used for service/bookmark icons) `mkdir`s
  `/app/.next/cache` on the first `/_next/image` request and throws
  (`unhandledRejection: ENOENT mkdir`) when it can't. The correctness check exercises
  image optimization so the requirement surfaces. `/tmp` was drop-tested and is
  **not** required.
- **`/app/config` is a persistent VOLUME, not tmpfs.** homepage's configuration
  (and logs) live under `/app/config`, which real deployments mount as a named
  volume; this profile assumes that (the drop-test supplies it as a writable
  stand-in, not part of the tmpfs minimum). Do not put `/app/config` on tmpfs —
  configuration would not persist across restarts.
- **Pass criteria:** the workload passes under `read_only:true` +
  `tmpfs:[/app/.next/cache]` (with `/app/config` as a writable volume), and
  removing the cache tmpfs breaks image optimization.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the default run — no `user:` override
  (homepage runs as root and does not drop privileges), `HOMEPAGE_ALLOWED_HOSTS`
  set, no command/entrypoint override.
- **Out of band** (not schema fields): derived on amd64; the minimum is only
  valid for what `profiles/workloads/homepage.sh` exercises (dashboard + image
  optimization). A homepage instance that uses additional server-side features
  may write elsewhere.
