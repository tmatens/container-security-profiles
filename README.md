# container-security-profiles

[![validate](https://github.com/tmatens/container-security-profiles/actions/workflows/validate.yml/badge.svg)](https://github.com/tmatens/container-security-profiles/actions/workflows/validate.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Evidence-backed minimum-security profiles for container images** — the
capabilities and read-only-filesystem config each image *actually needs*,
derived by removing privileges one at a time and proving the container breaks
without them. Not guidance copied from a blog post: every profile is
digest-pinned, backed by a committed workload script, and carries its full
derivation evidence in the file.

For example, immich ships its postgres with `cap_add` including `FOWNER` — the
derived, drop-tested minimum is four capabilities, and `FOWNER` is a genuine
over-grant:

```yaml
services:
  postgres:
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
    cap_drop: [ALL]
    cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID]
    security_opt: ["no-new-privileges:true"]
```

## The catalog

| Image | Tags | Minimum (all dimensions apply as a unit) | Confidence |
|---|---|---|---|
| `codeberg.org/forgejo/forgejo` | `15` | `capabilities: cap_add: [CHOWN, DAC_OVERRIDE, NET_BIND_SERVICE, SETGID, SETUID, SYS_CHROOT] (NET_BIND_SERVICE under ip_unprivileged_port_start=1024)` | high |
| `docker.io/grafana/alloy` | `v1.16.2` | `capabilities: cap_drop: [ALL] (zero-cap)` · `filesystem: read_only: true` | high |
| `docker.io/grafana/grafana` | `13.0.2` | `capabilities: cap_drop: [ALL] (zero-cap)` · `filesystem: read_only: true` | high (caps) · moderate (fs) |
| `docker.io/grafana/loki` | `3.7.2` | `capabilities: cap_drop: [ALL] (zero-cap)` · `filesystem: read_only: true` | high |
| `docker.io/jellyfin/jellyfin` | `10.11` | `capabilities: cap_drop: [ALL] (zero-cap)` · `filesystem: read_only: true` | high |
| `docker.io/binwiederhier/ntfy` | `v2.14.0` | `capabilities: cap_add: [NET_BIND_SERVICE] (under ip_unprivileged_port_start=1024)` · `filesystem: read_only: true` | high |
| `docker.io/library/caddy` | `2` | `capabilities: cap_add: [NET_BIND_SERVICE]` · `filesystem: read_only: true` | high |
| `docker.io/library/haproxy` | `3.2` | `capabilities: cap_drop: [ALL] (zero-cap, non-root)` | high |
| `docker.io/library/httpd` | `2.4` | `capabilities: cap_add: [NET_BIND_SERVICE, SETGID, SETUID] (under ip_unprivileged_port_start=1024)` · `filesystem: read_only: true, tmpfs: [/usr/local/apache2/logs]` | high |
| `docker.io/library/eclipse-mosquitto` | `2.0` | `capabilities: cap_add: [SETGID, SETUID]` · `filesystem: read_only: true` | high |
| `docker.io/library/mariadb` | `11.4` | `capabilities: cap_add: [SETGID, SETUID]` | high |
| `docker.io/adguard/adguardhome` | `v0.107.78` | `capabilities: cap_add: [DAC_OVERRIDE, NET_BIND_SERVICE] (DNS-only, under ip_unprivileged_port_start=1024)` · `filesystem: read_only: true` | high |
| `docker.io/library/memcached` | `1.6` | `capabilities: cap_drop: [ALL] (zero-cap)` · `filesystem: read_only: true` | high |
| `docker.io/louislam/uptime-kuma` | `2` | `capabilities: cap_add: [DAC_OVERRIDE, FOWNER]` (ping monitors add `NET_RAW`) · `filesystem: read_only: true, tmpfs: [/tmp]` | high |
| `docker.io/minio/minio` | `RELEASE.2025-09-07…` | `capabilities: cap_drop: [ALL] (zero-cap)` · `filesystem: read_only: true` | high |
| `docker.io/library/mongo` | `8.0` | `capabilities: cap_add: [SETGID, SETUID]` | high |
| `quay.io/keycloak/keycloak` | `26.4` | `capabilities: cap_drop: [ALL] (zero-cap, non-root)` | high |
| `docker.io/library/mysql` | `8.4` | `capabilities: cap_add: [DAC_OVERRIDE, SETGID, SETUID]` | high |
| `docker.io/library/nextcloud` | `32` | `capabilities: cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, NET_BIND_SERVICE, SETGID, SETUID] (under ip_unprivileged_port_start=1024)` | high |
| `docker.io/library/postgres` | `16` | `capabilities: cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID]` · `filesystem: read_only: true, tmpfs: [/run/postgresql]` | high |
| `docker.io/library/traefik` | `v3.7` | `capabilities: cap_add: [NET_BIND_SERVICE] (under ip_unprivileged_port_start=1024)` | high |
| `docker.io/library/wordpress` | `6.9` | `capabilities: cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, NET_BIND_SERVICE, SETGID, SETUID] (under ip_unprivileged_port_start=1024)` | high |
| `docker.io/library/rabbitmq` | `4.3` | `capabilities: cap_add: [SETGID, SETUID]` | high |
| `docker.io/syncthing/syncthing` | `2.0` | `capabilities: cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID]` · `filesystem: read_only: true` | high |
| `docker.io/library/redis` | `8.2.7` | `capabilities: cap_add: [SETGID, SETUID]` · `filesystem: read_only: true` | high |
| `docker.io/prom/prometheus` | `v3.13.1` | `capabilities: cap_drop: [ALL] (zero-cap)` · `filesystem: read_only: true` | high |
| `docker.io/pihole/pihole` | `2026.07.2` | `capabilities: cap_add: [CHOWN, DAC_OVERRIDE, NET_BIND_SERVICE, SETFCAP, SETGID, SETUID] (DNS-only; NO no-new-privileges — see criteria)` | high |
| `docker.io/netdata/netdata` | `v2.10.3` | `capabilities: cap_add: [DAC_OVERRIDE, SETGID, SETUID, SYS_PTRACE]` | high |
| `docker.io/valkey/valkey` | `9` | `capabilities: cap_add: [SETGID, SETUID]` | high · app-tier ✓ |
| `ghcr.io/gethomepage/homepage` | `v1.13.2` | `filesystem: read_only: true, tmpfs: [/app/.next/cache]` | high |
| `ghcr.io/home-assistant/home-assistant` | `2026.7.1` | `capabilities: cap_add: [DAC_OVERRIDE]` | high |
| `ghcr.io/paperless-ngx/paperless-ngx` | `2.18` | `capabilities: cap_add: [CHOWN, SETGID, SETUID]` | high |
| `ghcr.io/immich-app/postgres` | `14-vectorchord…` | `capabilities: cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID]` · `filesystem: read_only: true, tmpfs: [/etc/postgresql, /var/run/postgresql]` | high · app-tier ✓ |

All capability profiles are `cap_drop: [ALL]` plus the listed `cap_add`.
A dimension missing from a row (most commonly `filesystem`) has **not yet been
derived** for that image — absence means not tested, not that the image can't
run read-only. Each profile's header comment calls this out explicitly.
The **[browsable catalog site](https://tmatens.github.io/container-security-profiles/)**
renders every profile with its copy-paste snippet, drop-test evidence table,
recorded invocation, and criteria — or read the YAML directly under
[`catalog/`](catalog/).

Want an image added? [Request a profile](../../issues/new?template=profile-request.yml).

## Using a profile

**Directly:** copy the dimension into your compose file (each profile page on
the site has a ready snippet). One caveat that matters: a profile is the
minimum **for the recorded invocation** — the `run_config` block in the
profile. A different `user:`, a pre-initialised vs fresh data volume, or an
entrypoint override changes the minimum. Read the profile's `criteria/` doc
before adopting; if a profile breaks your deployment,
[report the mismatch](../../issues/new?template=profile-mismatch.yml).

**Via compose-lint** (opt-in, experimental preview): point
[compose-lint](https://github.com/tmatens/compose-lint) ≥ 0.13 at a clone of
this catalog and its findings gain image-specific guidance:

```yaml
# .compose-lint.yml
profiles:
  enabled: true
  path: /path/to/container-security-profiles/catalog
```

```
CL-0006  Service does not drop all capabilities. …
    fix: …
    profile hint (csd-derived, confidence high, from docker.io/library/postgres@sha256:fe03a76…,
    tag match — compose-lint can't see your runtime, confirm it fits your setup):
    observed minimum is cap_drop: [ALL] + cap_add: [CHOWN, DAC_OVERRIDE, SETGID, SETUID]
```

Enrichment is advisory only — it never creates, drops, or reclassifies a
finding, and only `validated` profiles are consumed.

## Why trust these profiles

Every `validated` profile clears a machine-checked bar (CI runs it on every
change; `make validate` runs the same locally):

- **Schema-valid** against the versioned compose-lint profile schema, fetched
  from a pinned compose-lint commit (`contract/compose-lint.ref`) at
  validation time — no vendored copy to drift.
- **Digest-pinned**: `validated_image` records the exact `…@sha256:…` the
  evidence was produced against, and `applies_to.tags` may pin only
  **immutable version tags** — a profile derived against `latest` is
  meaningless.
- **Workload-backed**: the exerciser script is committed under
  [`profiles/workloads/`](profiles/workloads/) and hash-verified
  (`workload_sha256`). Workloads exercise the image's real function and assert
  privilege drops (a health check alone is not enough).
- **Evidence in-file**, per derivation method:
  - **drop-test** — every granted element removed in turn, the container
    restarted, the workload re-verified; the per-element results are the
    `drop_test.checks` table in the profile. This catches *startup-only*
    minimums (a data-dir `chown`, a root→user privilege drop) that runtime
    observation is structurally blind to. The whole current catalog is derived
    this way.
  - **bpf-observation** — live eBPF observation over a running workload,
    ≥ 300 s.
- **App-tier verified** (where marked): the hardening was additionally proven
  at the *service* level — the full stack brought up with the minimum applied
  and driven through its real API, including an over-hardening probe showing
  the check catches a too-tight config.
- **Freshness-tracked**: a weekly `staleness` workflow compares each pinned
  digest to the tag's currently published digest and opens a tracking issue on
  drift, flagging the profile for re-derivation.

**Trust model:** endorsed (`validated`) profiles are ones maintainer
automation derives and can re-derive. External contributions land as
`exploratory` (advisory only, never used for enrichment) until reproduced —
see [CONTRIBUTING.md](CONTRIBUTING.md).

## Layout

Catalog and criteria paths are registry-namespaced
(`<registry>/<org>/<image>`), mirroring the fully-qualified image reference.

- `catalog/….yaml` — validated profiles; `catalog/exploratory/…` — drafts
  below the promotion bar.
- `criteria/….md` — per-image scenarios and pass criteria.
- `profiles/workloads/*.sh` — the committed exerciser scripts.
- `derivation/manifest.yaml` — the re-derivation spec: how to re-derive each
  profile representatively (image, dimension, method, workload).
- `contract/compose-lint.ref` + `scripts/fetch-contract.sh` — the pinned
  schema/validator contract (fetched into `.contract/`, gitignored).
- `scripts/check_staleness.py` — the registry-only digest-drift check.
- `scripts/build_site.py` — the static catalog-site generator
  (`make site`; deployed by `.github/workflows/pages.yml`).

## Validation

```sh
pip install -r requirements.txt
make validate        # fetches the pinned contract, then validates the catalog
```

CI runs the same on every PR and push to main, plus a smoke build of the
catalog site.

## Relationship to compose-lint

This is the external profile catalog described in compose-lint
[ADR-017](https://github.com/tmatens/compose-lint/blob/main/docs/adr/017-security-profile-catalog.md):
the two are tied by exactly one thing — the versioned profile schema.
compose-lint ships the schema, loader, and validator but **no profiles**; this
catalog ships profiles but no code dependency. Data flows one way (catalog →
consumer), and consumption is opt-in. The name is consumer-neutral on purpose:
compose-lint is the first consumer, not the only possible one.

## How profiles are derived

Profiles are derived by **container-sec-derive (csd)** — a runtime tool that
observes a running container via eBPF (capabilities, filesystem writes,
devices, egress) and drop-tests candidate minimums against a real workload.
csd is not yet published; until it is, every profile carries enough evidence
(`run_config`, workload script, per-element drop-test results) to reproduce
the derivation with any harness: apply the profile, run the workload, remove
one element, watch it break.

## Contributing

Profile requests, mismatch reports, and profile contributions are all
welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Security policy:
[SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Profiles are data — reuse them freely with attribution.
