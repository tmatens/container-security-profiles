# syncthing — validation criteria

Per-image acceptance criteria for the `docker.io/syncthing/syncthing`
profile. Validated against `…@sha256:4a961394…` (tag `2.0`), derived by
drop-test against the **default invocation**. Capabilities trim **14 → 4**.

## Representative workload / correctness check
`profiles/workloads/syncthing.sh` — reads the generated API key from
`config.xml` (as the syncthing uid), asserts `system/status` returns a
device ID, adds a folder via the config REST API, and reads it back. In-image
curl; probes exec as `--user 1000`; capture-then-match.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID].** The
  entrypoint starts as root, ensures/chowns the `/var/syncthing` state dir
  (CHOWN + DAC_OVERRIDE — evidence: `ERR Failed to ensure directory
  ownership` / `WRN Failed to acquire open permissions`), then su-execs to
  the default PUID 1000 (SETGID/SETUID — `su-exec: setuid(1000): Operation
  not permitted`). All startup caps.
- **No NET_BIND_SERVICE** — the GUI/API (:8384) and BEP sync protocol
  (:22000) are unprivileged.
- **Pass criteria:** REST status + folder add/readback **and** syncthing at
  uid 1000; each granted cap's drop fails as above.

## Scope (`run_config` + out-of-band conditions)
- **Invocation:** image default (root start, PUID/PGID 1000 via su-exec, a
  `/var/syncthing` VOLUME, `no-new-privileges`).
- **Variations:** `user:` (or PUID matching a pre-owned state dir) skips the
  chown + drop → minimum `[]`. Discovery/relay to the public internet is
  outbound (no caps). NAT-PMP/UPnP port mapping is best-effort and needs no
  container cap.
- **Out of band:** Docker's default seccomp baseline; amd64. The minimum
  covers config REST + folder management; actual file sync between two
  devices, ignore patterns, and versioning are out of scope.
