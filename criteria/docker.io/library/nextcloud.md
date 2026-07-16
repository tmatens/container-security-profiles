# nextcloud — validation criteria

Per-image acceptance criteria for the `docker.io/library/nextcloud` profile
(apache variant). Validated against `…@sha256:90fdc9f9…` (tag `32`), derived
by drop-test against the **default in-stack invocation** — `MYSQL_*` env
against a mariadb database, `NEXTCLOUD_ADMIN_*` auto-install. Capabilities
trim **14 → 6**, the same set as sibling wordpress (both are
root-entrypoint-copy + apache-worker images).

## Representative workload / correctness check
`profiles/workloads/nextcloud.sh` — wait for `occ status` to report
installed, then a **WebDAV PUT/GET round-trip** as the auto-installed admin:
a real file write through the full apache → php → storage path, read back
byte-identical. The drop-test correctness check additionally asserts a
worker runs as www-data (uid 33) — the httpd/wordpress sharp edge (a broken
SETGID drop keeps serving with root workers).

**The in-stack trial lifecycle (measured on 32, encoded in the csd
correctness check):** the database dep persists across trials, and a
fresh-docroot nextcloud **cannot adopt an installed database** — it boots
into a running-but-broken `installed: false` limbo. Per-trial recovery:
reset the database (root exec in the dep) and `docker restart` the target;
its entrypoint then performs a clean install **under the trial's cap
posture**. The trial's first boot has already rsync'd the sources into its
fresh volume under that same posture, so the copy phase and the install
phase are both exercised in every trial.

Probe hygiene (all three catalog rules apply): `occ` execs as
`--user www-data`; WebDAV goes through the curl sidecar; responses are
captured then matched (never `curl | grep -q` under pipefail); no probe
writes inside the target.

## capabilities — derived by drop-test
- **CHOWN + DAC_OVERRIDE + FOWNER** — the entrypoint **rsyncs** ~700MB of
  sources into the fresh `/var/www/html` VOLUME preserving www-data
  ownership, permissions, and times: ownership setting (CHOWN), writing
  through non-owned paths (DAC_OVERRIDE), perms/times restore on non-owned
  files (FOWNER). Any of the three dropped: `rsync error … (code 23)` and
  the container exits. (wordpress needs the same trio for its `tar --owner`
  copy — same class, different tool.)
- **SETUID** — dropped, apache's MPM fails (`AH02818`).
- **SETGID** — dropped, the install never completes (`[unixd:alert]` setgid
  failure during the post-reset install).
- **NET_BIND_SERVICE** — the `:80` bind, **only under the pinned**
  `net.ipv4.ip_unprivileged_port_start=1024` posture (docker defaults 0;
  same scope note as traefik/httpd/wordpress).
- **Pass criteria:** WebDAV round-trip byte-identical **and** worker at
  uid 33; each granted cap's drop fails with the evidence above.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the default — root start,
  `MYSQL_*` + `NEXTCLOUD_ADMIN_*` + `NEXTCLOUD_TRUSTED_DOMAINS` env, a
  docker-managed docroot VOLUME, `no-new-privileges`, the pinned sysctl, a
  reachable mariadb (the derivation used the cataloged `mariadb:11.4` as the
  in-stack dep).
- **Variations:** a pre-populated docroot (second boot onward) skips the
  rsync, but upgrades re-run it — keep the copy trio in the deployed
  minimum. The fpm variant + external web server is a different image.
  Background jobs via system cron, external storage mounts, and office
  integration may need more — out of scope.
- **Out of band** (not schema fields): Docker's default seccomp baseline;
  the in-stack database; amd64. The minimum is only valid for what the
  workload exercises — install + WebDAV file round-trip; app store installs,
  previews/thumbnailing, and federation are out of scope.
