# eclipse-mosquitto — validation criteria

Per-image acceptance criteria for the `docker.io/library/eclipse-mosquitto`
profile. Validated against `…@sha256:212f89e1…` (tag `2.0`), derived by
drop-test against the **default invocation** (the image's bundled config:
listener 1883, anonymous local use). Capabilities trim **14 → 2**; the
filesystem locks read-only with no tmpfs. Both dimensions apply as a unit.

## Representative workload / correctness check
`profiles/workloads/mosquitto.sh` — a real publish/subscribe round-trip via
the in-image `mosquitto_sub` / `mosquitto_pub` clients: the subscriber runs
foreground printing the one expected message to stdout, the publisher fires a
beat later from the background. Two probe-hygiene rules encoded:

1. **Probes exec as `--user mosquitto`** so they cannot pollute the caps
   minimum (the rabbitmq lesson).
2. **The probe writes nothing inside the container** — an earlier draft
   captured the subscriber into `/tmp/…`, which would have derived the
   filesystem dimension's `/tmp` candidate falsely-required (probe pollution,
   filesystem edition). Any re-derivation must stay write-free.

The drop-test correctness check also asserts the broker runs non-root
(uid 1883) — the drop is the broker's own, and a broken drop must not pass
while serving as root.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [SETGID, SETUID]** — the catalog's **third
  privilege-drop shape**: mosquitto setuid/setgids to its own user
  **in-process** when started as root (contrast: the gosu re-exec of
  mysql/mongo/rabbitmq, the master/worker fork of httpd). Dropping either cap
  fails startup deterministically with mosquitto's own message (`Error
  setting uid/groups whilst dropping privileges`) — the broker refuses to
  serve as root, so unlike httpd there is no silent-root failure mode, but
  the uid assert stays as belt-and-suspenders.
- **No NET_BIND_SERVICE** — the listener is the unprivileged `:1883`, so the
  cap is unnecessary under any sysctl posture.
- **Pass criteria:** the pub/sub round-trip delivers the payload **and** the
  broker is uid 1883.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** `/mosquitto/data` (persistence) and
  `/mosquitto/log` are declared VOLUMEs — persistent in real deployments,
  never tmpfs, and docker mounts them writable under `--read-only`. `/tmp`
  derived **not required**.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the image default — root start,
  bundled `mosquitto.conf`, docker-managed volumes, `no-new-privileges`.
- **Variations:** `user: mosquitto` (or uid 1883) skips the in-process drop →
  minimum **[]** (the config's `user` directive is ignored when not root). A
  TLS listener on :8883 changes nothing (still unprivileged); a listener
  below 1024 would add NET_BIND_SERVICE under a hardened sysctl posture. A
  foreign-owned bind mount for `/mosquitto/data` fails as the non-root broker
  can't write it — fix ownership, don't add caps.
- **Out of band** (not schema fields): Docker's default seccomp baseline; the
  bundled config; amd64. The minimum is only valid for what the workload
  exercises — QoS-0 pub/sub on the plain listener; TLS, auth plugins,
  bridges, and websockets are out of scope.
