# wordpress — validation criteria

Per-image acceptance criteria for the `docker.io/library/wordpress` profile
(apache variant). Validated against `…@sha256:5d2c2125…` (tag `6.9`), derived
by drop-test against the **default in-stack invocation** — `WORDPRESS_DB_*`
env against a mysql database, the first public-catalog profile using the
in-stack dependent-tier model (`deps:`). Capabilities trim **14 → 6**.

## Representative workload / correctness check
`profiles/workloads/wordpress.sh` — real function in both site states: on a
fresh database it drives the **actual HTTP install flow**
(`install.php?step=2`, creating the schema through php → mysql), then asserts
the homepage serves the configured blog title **from the database**; on an
installed database it asserts the titled homepage directly (fresh container,
wp-config generated from env, site read from mysql). Both states exercise the
full entrypoint source-copy → apache worker drop → php → mysql pipeline. The
drop-test correctness check additionally asserts a **worker** runs as
www-data (uid 33).

Two hard-won harness rules encoded here:

1. **Capture-then-match, never `curl | grep -q` under `set -o pipefail`** —
   `grep -q` exits at the first match, curl takes SIGPIPE (exit 141), and the
   pipeline reports failure *on a page that matched*. This false negative
   burned three derivation runs before diagnosis; the check now captures the
   body and string-matches. (Small responses mask the bug — it bites once the
   body outgrows the pipe buffer.)
2. **The install POST retries and the title check polls** — first requests
   after boot can land while php/mysql are settling.

## capabilities — derived by drop-test
Every grant carries distinct evidence:

- **CHOWN + FOWNER** — the entrypoint copies ~70MB of WordPress sources into
  the fresh `/var/www/html` VOLUME via `tar --owner www-data`: setting
  ownership needs CHOWN; restoring permissions/timestamps on files the
  (root) process doesn't own needs FOWNER. Either dropped: `tar: Exiting
  with failure status` and the container exits.
- **DAC_OVERRIDE** — the ROOT-phase entrypoint writes `wp-config.php` into
  the www-data-owned docroot (`wp-config.php: Permission denied` when
  dropped).
- **SETUID** — dropped, apache's MPM fails outright (`AH02818`).
- **SETGID** — dropped, **apache serves anyway with root workers** — the
  httpd sharp edge reproduced in a second image; only the worker uid assert
  fails the trial. Content-only checks must never be trusted for this image
  family.
- **NET_BIND_SERVICE** — the `:80` bind, **only under the pinned**
  `net.ipv4.ip_unprivileged_port_start=1024` posture (docker defaults 0,
  where it reads falsely-removable; the derivation pins the sysctl — same
  scope note as traefik/httpd).
- **Pass criteria:** titled homepage served from the DB **and** a worker at
  uid 33; each granted cap's drop fails with the evidence above.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the default — root start,
  `WORDPRESS_DB_*` env, a docker-managed docroot VOLUME, `no-new-privileges`,
  the pinned sysctl, a reachable mysql (the derivation used the cataloged
  `mysql:8.4` as the in-stack dep).
- **Variations:** a **pre-populated docroot volume** (second boot onward)
  skips the source copy — but the entrypoint still version-checks and may
  re-copy on image upgrade, so CHOWN/FOWNER stay in the deployed minimum. A
  **bind-mounted docroot owned by www-data** with `user: www-data` skips
  everything root-phase → minimum shrinks to `[]` on a high port (the
  wordpress:fpm-alpine + external-server pattern is a different image).
  Plugins/themes that shell out or self-update may need more — out of scope.
- **Out of band** (not schema fields): Docker's default seccomp baseline;
  the in-stack database; amd64. The minimum is only valid for what the
  workload exercises — install flow + anonymous homepage serving; wp-admin
  authoring, media uploads, wp-cron at scale, and plugin installation are
  out of scope.
