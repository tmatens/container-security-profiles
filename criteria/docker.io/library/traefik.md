# traefik — validation criteria

Per-image acceptance criteria for the `docker.io/library/traefik` profile.
Validated against `…@sha256:0bd09a37…` (tag `v3.7`), derived by drop-test
against the **file-provider reverse-proxy invocation** — static config via
command flags, one routed upstream. Capabilities trim **14 → 1**.

## Representative workload / correctness check
`profiles/workloads/traefik.sh` — a request on entrypoint `:80` must be routed
through a traefik router to an upstream named `backend` (in the derivation
stack, a pinned caddy on the shared in-stack network) and answered with the
backend's content: **entrypoint → router → service → proxied upstream
response**, the full proxy path. The dynamic file-provider config is
docker-cp'd into `/tmp` after start (traefik runs with
`--providers.file.directory=/tmp --providers.file.watch=true` and hot-loads
it) — a daemon-side write that exercises no capability inside the target, so
it cannot pollute the minimum. Probes run from a curl sidecar sharing the
target's netns.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [NET_BIND_SERVICE].** traefik runs as root with
  **no privilege drop**; the one load-bearing capability is binding `:80`.
  Dropping it exits deterministically at startup: `listen tcp :80: bind:
  permission denied`. Every other Docker default dropped clean with the full
  routed round-trip passing.
- **The sysctl scope condition (read this before adopting):** the requirement
  exists **only under** `net.ipv4.ip_unprivileged_port_start=1024`, which the
  derivation pins (`run_config` sysctl). Docker's default for container
  network namespaces is `0` — all ports unprivileged — under which even
  NET_BIND_SERVICE is droppable. So: hardened-sysctl deployments need exactly
  this one cap; default-docker deployments can run traefik **zero-cap**; and a
  high-port entrypoint (`:8080`) needs no cap under either posture.
- **Pass criteria:** the routed backend response on `:80`; dropping
  NET_BIND_SERVICE fails container start under the pinned sysctl.

## Scope — the docker-socket variant is deliberately OUT
The popular alternative wiring — `--providers.docker` with
`/var/run/docker.sock` mounted — is **not covered and cannot be**: the socket
grants root-equivalent control of the host, which is the dominant risk of that
deployment shape. **No capability minimum addresses it**, and this profile
must not be read as making a socket-mounted traefik safe. (Socket-scope
observation is tracked upstream in csd#110 and is signal-blocked at the
pinned gadget set.) If you run the docker provider, treat the socket — not
caps — as the thing to mitigate (socket-proxy, read-only API filters, or the
file/HTTP providers instead).

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): static config entirely via flags
  (`--entrypoints.web.address=:80`, file provider on `/tmp`, watch, no API),
  `no-new-privileges`, the pinned sysctl above, one HTTP upstream. TLS/ACME
  adds outbound HTTPS + cert storage writes (a data volume), not caps —
  expected unchanged, but not derived here.
- **Out of band** (not schema fields): Docker's default seccomp baseline; the
  in-stack `backend` upstream; amd64. The minimum is only valid for what the
  workload exercises — HTTP entrypoint → router → service proxying; TCP/UDP
  routers, TLS termination, ACME issuance, and every non-file provider are
  out of scope.
