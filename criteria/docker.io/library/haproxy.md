# haproxy — validation criteria

Per-image acceptance criteria for the `docker.io/library/haproxy` profile.
Validated against `…@sha256:e271912a…` (tag `3.2`), derived by drop-test
against a **reverse-proxy invocation** — frontend `:8080`, one upstream (an
in-stack caddy dep). Capabilities trim **14 → 0**.

## Representative workload / correctness check
`profiles/workloads/haproxy.sh` — a request on the frontend proxied through
to the `backend` upstream and answered with its content, plus the non-root
assert (uid 99). The image ships **no default config** and a committed spec
cannot carry a bind mount, so the derivation's command writes the minimal
config to `/tmp` and execs haproxy on it — recorded honestly in
`run_config.command`; a real deployment bind-mounts its config read-only,
which changes nothing about capabilities.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [] (zero-cap)** — non-root by construction
  (USER haproxy since 2.4).
- **The teaching:** a non-root process in docker receives **no effective
  capabilities from `cap_add`** (docker sets no ambient capabilities), so a
  privileged `:80` frontend is *impossible* in this image regardless of
  grants — don't fight it with caps; publish an unprivileged frontend port
  behind a port mapping (`8080:80`), which needs nothing. (Contrast pihole,
  whose entrypoint bridges this gap with file capabilities — and pays
  SETFCAP plus nnp-incompatibility for it.)
- **Pass criteria:** the proxied round-trip returns backend content and
  PID 1 is non-root, with every candidate dropped.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** haproxy is a static-binary reverse proxy that
  writes nothing to its rootfs — under `--read-only` it proxies `:8080` to the
  in-stack caddy backend with no tmpfs. Its config is supplied by a **read-only
  config mount** at haproxy's default config path, so `/tmp` — which the
  capabilities derivation's entrypoint writes the config into — drop-tests as
  **not required** here.
- **Pass criteria:** the proxied backend response succeeds and the process runs
  non-root under `read_only:true` (config on a read-only mount) and no rootfs tmpfs.

## Scope (`run_config` + out-of-band conditions)
- **Invocation**: one HTTP frontend :8080 → one backend, `no-new-privileges`.
- **Out of band**: Docker's default seccomp baseline; the in-stack upstream;
  amd64. The minimum covers HTTP proxying; TCP mode, TLS termination,
  stats/runtime API sockets, and seamless reloads are out of scope.
