# Filesystem-dimension coverage backlog

The catalog has **23 caps-only profiles** with no `filesystem` dimension (each
carries a `# filesystem: not yet derived` header). This backlog ranks them for
read-only-rootfs + tmpfs derivation, **grounded in an empirical read-only probe**
of every image (run `--read-only` with its published cap set + minimal config,
capturing the paths it fails to write) — not guessed. Method reference:
`container-sec-derive/testdata/drop-test/README.md` (research-first + the
`*-fs.yaml` specs). Each item becomes one csd `*-fs.yaml` spec +
`correctness/*.sh` + catalog `filesystem` dimension + criteria doc.

## Two cross-cutting patterns the probe surfaced

1. **Stateful services: data on a persistent VOLUME, never tmpfs.** A `--tmpfs`
   data dir is fresh + root-owned, so the entrypoint's `chown` to the service
   user fails under a caps-minimum lacking CHOWN — the *valkey false-CHOWN
   lesson*, and an artifact of the probe, not a read-only blocker. Derive the fs
   dimension with the data dir as a real volume (service-owned); confirmed:
   valkey and mariadb both run cleanly `--read-only` that way, tmpfs surface =
   just the socket/pid dir. This is exactly the shape the existing `postgres`
   fs profile already models (`read_only:true, tmpfs:[/run/postgresql]`).
2. **s6-supervised images need `/run` writable.** forgejo and home-assistant
   fail read-only at `s6-svscan: .s6-svscan/lock` / `/run/s6/.../init` — s6
   writes its supervision tree under `/run`. tmpfs `/run` is the first candidate.

## Backlog (ranked; do top-down)

### Wave 1 — Trivial / Easy (zero-to-one tmpfs, ran clean or single write path)

| Image | Expected fs recommendation | Probe evidence | Value |
|---|---|---|---|
| `docker.io/library/memcached` | `read_only:true, tmpfs:[]` | ran read-only clean, no writes | low (cache) |
| `docker.io/minio/minio` | `read_only:true, tmpfs:[]` (+`/data` vol) | ran read-only clean | med (object store) |
| `docker.io/library/traefik` | `read_only:true, tmpfs:[]` or small | ran read-only clean | **high (edge proxy)** |
| `docker.io/library/haproxy` | `read_only:true, tmpfs:[]` | static binary, writes nothing (needs a config file to start — probe it with a minimal cfg) | **high (edge proxy)** |
| `docker.io/library/httpd` | `read_only:true, tmpfs:[/usr/local/apache2/logs]` | EROFS on `.../logs/httpd.pid` — single dir | **high (web server)** |
| `ghcr.io/immich-app/postgres` | `read_only:true, tmpfs:[/var/run/postgresql]` | EROFS on `/var/run/postgresql` lock — **mirror of the derived library `postgres` fs profile** | med |
| `docker.io/library/redis` | `read_only:true, tmpfs:[]` (+`/data` vol) | ran read-only with data volume | med |
| `docker.io/adguard/adguardhome` | `read_only:true` + `work`/`conf` vols | ran read-only clean | med (DNS) |
| `docker.io/syncthing/syncthing` | `read_only:true` (+`/var/syncthing` vol) | ran read-only clean | med |
| `docker.io/louislam/uptime-kuma` | `read_only:true` (+`/app/data` vol) | ran read-only clean | med |

### Wave 2 — Medium (named-volume data + socket/`/run` tmpfs; runs read-only, confirmed for the representatives)

| Image | Expected fs recommendation | Probe evidence | Value |
|---|---|---|---|
| `docker.io/valkey/valkey` | `read_only:true, tmpfs:[]` (+`/data` vol) | **confirmed** runs read-only w/ named-vol data | med |
| `docker.io/library/mariadb` | `read_only:true, tmpfs:[/run/mysqld]` (+`/var/lib/mysql` vol) | **confirmed** "ready for connections" read-only | med |
| `docker.io/library/mysql` | `read_only:true, tmpfs:[/var/run/mysqld]` (+data vol) | same family/entrypoint as mariadb | med |
| `docker.io/library/mongo` | `read_only:true, tmpfs:[/tmp]` (+`/data/db` vol) | chown-on-fresh-dir only; named-vol path expected clean | med |
| `docker.io/library/rabbitmq` | `read_only:true, tmpfs:[/tmp,?/etc/rabbitmq]` (+`/var/lib/rabbitmq` vol) | erlang writes `/tmp`; confirm `/etc/rabbitmq` rewrite (the enabled_plugins path) | med |
| `codeberg.org/forgejo/forgejo` | `read_only:true, tmpfs:[/run,/tmp]` (+`/data` vol) | s6 lock EROFS → `/run`; git tmp writes → `/tmp` | **high (git host)** |
| `ghcr.io/home-assistant/home-assistant` | `read_only:true, tmpfs:[/run,?/tmp]` (+`/config` vol) | s6 `/run/s6/.../init` EPERM → `/run` | med |

### Wave 3 — Medium-Hard (larger or scattered write surface)

| Image | Expected shape | Probe evidence | Value |
|---|---|---|---|
| `quay.io/keycloak/keycloak` | `read_only:true, tmpfs:[/tmp]` — **derive against production `start`, not `start-dev`** | `start-dev` re-augments the quarkus jar → `ReadOnlyFileSystemException`; the optimized `start` build writes far less | **high (IdP)** |
| `docker.io/netdata/netdata` | `read_only:true` + several vols (`/var/lib/netdata`,`/var/cache/netdata`,`/var/log/netdata`) + tmpfs (`/run`,`/tmp`,?`/etc/netdata`) | host-monitor writes many dirs; broadest tmpfs surface of the group | med |
| `docker.io/pihole/pihole` | **uncertain — investigate first** | probe showed rootfs-adjacent writes (`/macvendor.db`, near `/usr/bin/pihole-FTL`) beyond the `/etc/pihole`,`/etc/dnsmasq.d` vols; may need many tmpfs or not cleanly support read-only. Already the no-`nnp` special case. | med (DNS) |

### Wave 4 — Hard (in-stack dependencies and/or first-run source-copy)

| Image | Why hard | Value |
|---|---|---|
| `docker.io/library/wordpress` | PHP source-copy to `/var/www/html` (a volume) on first run + needs a live DB + runtime uploads/cache writes; the in-stack dependent-tier model (like its caps profile) applies | **high (CMS)** |
| `docker.io/library/nextcloud` | rsync source-copy to `/var/www/html` + needs a DB + `config`/`data`/`apps` writes; the largest write surface in the catalog | **high (cloud suite)** |
| `ghcr.io/paperless-ngx/paperless-ngx` | needs redis + postgres up (in-stack) + `data`/`media`/`consume`/`tmp` writes | med |

## Recommended sequence & value overlay

- **Do Wave 1 first** — ten quick wins that take the catalog from 10→20 profiles
  with a filesystem dimension; several are `tmpfs:[]` and `immich-postgres` is a
  near-copy of an existing derivation. Lead with the **edge/web tier**
  (traefik, haproxy, httpd) — highest hardening value, lowest effort.
- **Wave 2** is one repeatable pattern (named-vol data + socket/`/run` tmpfs);
  batch the DB/KV family together, then the two s6 images.
- **Wave 3** each needs a focused decision (keycloak: pin `start`; pihole:
  decide if read-only is even claimable) — don't batch blindly.
- **Wave 4** should reuse the in-stack dependent-tier harness (`deps:` +
  `run.volumes_from`) already built for the caps derivations; treat each as its
  own mini-project.

Publishing **negative results** is in-scope where read-only proves infeasible
(e.g. if pihole can't be bounded): a derived `read_only:false` with evidence is
a real finding — the schema allows it, and it makes absence unambiguous.
