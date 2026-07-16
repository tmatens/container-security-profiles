# ntfy — validation criteria

Per-image acceptance criteria for the `docker.io/binwiederhier/ntfy` profile.
Validated against `…@sha256:5a051798…` (tag `v2.14.0`), derived by drop-test
against the default `serve` invocation (no config — in-memory store).
Capabilities trim **14 → 1**; the filesystem locks read-only with no tmpfs.
Both dimensions apply as a unit.

## Representative workload / correctness check
`profiles/workloads/ntfy.sh` — health, then a real **publish → poll**
round-trip: POST a message to a topic, poll it back (`json?poll=1&since=all`)
and match the payload. Curl sidecar; capture-then-match; no writes in the
target.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [NET_BIND_SERVICE].** A root-run single Go
  binary whose only load-bearing capability is its default **privileged :80
  listener** — evidence: `listen tcp :80: bind: permission denied`.
- **Scope:** the grant matters only under the pinned
  `net.ipv4.ip_unprivileged_port_start=1024` posture (docker defaults 0). A
  deployment setting `listen-http` to a high port — or running `user:` with
  a high port — is **zero-cap**.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** The default in-memory store writes nothing
  on the publish/poll path; `/tmp` derived not required. Enabling
  `cache-file` or the attachment cache adds a **data volume**, not tmpfs.

## Scope (`run_config` + out-of-band conditions)
- **Invocation**: `serve`, no config file, no volumes, `no-new-privileges`,
  the pinned sysctl.
- **Out of band**: Docker's default seccomp baseline; amd64. The minimum
  covers publish/poll; auth/ACLs, iOS/UnifiedPush upstream pushes (outbound
  HTTPS, no caps expected), and attachments are out of scope.
