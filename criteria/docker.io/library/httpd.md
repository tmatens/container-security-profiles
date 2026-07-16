# httpd — validation criteria

Per-image acceptance criteria for the `docker.io/library/httpd` profile (the
official Apache httpd image). Validated against `…@sha256:305fd832…` (tag
`2.4`), derived by drop-test against the **default invocation**. Capabilities
trim **14 → 3**.

## Representative workload / correctness check
`profiles/workloads/httpd.sh` — `GET /` must return the default page body
("It works!"), fetched from a curl sidecar sharing the target's netns (the
image ships no HTTP client). The drop-test correctness check additionally
asserts a **worker** process (a non-PID-1 `httpd`) runs as the non-root
www-data user (uid 33).

**The uid assert is mandatory, and this derivation proved why:** with SETGID
dropped, httpd logged the failed drop but **kept serving with root workers**
— the evidence line reads `httpd workers running as ROOT: uid=0`. A
content-only check false-passes and would derive the drop as safe while
silently removing Apache's privilege separation. This is the master/worker
variant of the redis sharp edge.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [NET_BIND_SERVICE, SETGID, SETUID].** The
  master stays root and forks workers that setuid/setgid to www-data
  (`httpd.conf` User/Group) — the master/worker split shape, in contrast to
  the gosu images (whole-process drop) and to sibling caddy (single non-root
  cap).
- **SETUID** — dropped, the child fatals and Apache exits (`AH00050`).
- **SETGID** — dropped, httpd *serves anyway* with root workers; only the uid
  assert fails the trial (see above).
- **NET_BIND_SERVICE** — the `:80` bind (`AH00015: Unable to open logs` is
  the surface error; the listener bind is the cause). **Scoped to the pinned
  hardened posture** `net.ipv4.ip_unprivileged_port_start=1024` — docker's
  default is 0, where this cap reads falsely-removable (same scope note as
  traefik; the derivation pins the sysctl).
- **Pass criteria:** default page served **and** a worker runs as uid 33.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [/usr/local/apache2/logs].** httpd writes its pid
  file and logs to `/usr/local/apache2/logs` at startup; under a read-only rootfs
  it fails to start (`AH00099: could not create /usr/local/apache2/logs/httpd.pid`)
  without that dir writable. It is the only required tmpfs — `/tmp` was
  drop-tested and comes out **not required**.
- **Pass criteria:** the default page serves under `read_only:true` with
  `tmpfs:[/usr/local/apache2/logs]`, and dropping that tmpfs breaks startup.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the image default — root master,
  bundled `httpd.conf`, no content mounts, `no-new-privileges`, the pinned
  sysctl above.
- **Variations:** a high-port `Listen` (8080) drops NET_BIND_SERVICE; running
  the whole container as a non-root `user:` with a high port and
  pre-readable content drops all three (worker drop skipped) — the
  `httpd:2.4` unprivileged pattern.
- **Out of band** (not schema fields): Docker's default seccomp baseline; the
  default `httpd-foreground` command; amd64. The minimum is only valid for
  what the workload exercises — static default-page serving; CGI, mod_php,
  SSL, and content bind-mounts (ownership permitting) are out of scope.
