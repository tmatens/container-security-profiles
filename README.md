# container-security-profiles

Evidence-backed **minimum-security profiles for container images** — the observed
capabilities, read-only-filesystem, device, and egress config each image
actually needs. Profiles are derived by
[container-sec-derive](https://github.com/tmatens/container-sec-derive) (csd)
from live eBPF observation (and, for `cap_add`, bisection) and are consumed by
[compose-lint](https://github.com/tmatens/compose-lint) as fix-guidance
enrichment.

This is the **external, automation-maintained catalog** described in compose-lint
ADR-017 §7 — deliberately *not* bundled in the compose-lint wheel.

## Relationship to compose-lint (contract-only)

This catalog is tied to compose-lint by **one thing: the versioned profile
schema** (`schema_version`; profiles in this catalog currently declare
`1.2`–`1.3`). Nothing else:

- **Not bundled** — compose-lint ships the schema + loader + validator; it does
  not ship profiles. A user opts in by pointing compose-lint's `profiles.path`
  at a catalog they trust (off by default).
- **Not vendored** — this repo does not keep a copy of the schema or validator.
  CI fetches them from a **pinned compose-lint commit** (`contract/compose-lint.ref`)
  at validation time, so there is no silent drift and no code dependency. Bump
  the ref to adopt a new schema version, deliberately.
- **One-directional** — data flows csd *derives* → this catalog *stores* →
  compose-lint (or any schema-conforming tool) *consumes*. compose-lint has no
  dependency on this repo.

The name is consumer-neutral on purpose: these are container security profiles,
and compose-lint is the first consumer, not the only possible one.

## Layout

Catalog and criteria paths are **registry-namespaced**
(`<registry>/<org>/<image>`), mirroring the fully-qualified image reference.

- `catalog/<registry>/<org>/<image>.yaml` — **validated** profiles (cleared the
  acceptance contract *and* the ci-smoke gate), e.g.
  `catalog/docker.io/library/postgres.yaml`.
- `catalog/exploratory/<registry>/<org>/<image>.yaml` — **exploratory** drafts
  (below the bar; advisory only, never used for conformance). The tier exists
  for external contributions awaiting reproduction; none are committed yet.
- `criteria/<registry>/<org>/<image>.md` — per-image scenarios + pass criteria
  (compose-lint#359), mirroring the catalog path.
- `profiles/workloads/<name>.sh` — the committed exerciser scripts profiles pin
  by `workload_sha256`.
- `derivation/manifest.yaml` — the re-derivation spec (compose-lint#360): how to
  re-derive each profile representatively (image, tag, dimension, `method`,
  workload). Consumed by container-sec-derive's derive loop on the self-hosted
  BPF runner (see Freshness below).
- `contract/compose-lint.ref` — the pinned compose-lint commit whose schema +
  validator this catalog conforms to.
- `scripts/fetch-contract.sh` — fetches that pinned schema + validator into
  `.contract/` (gitignored).
- `scripts/check_staleness.py` — the registry-only digest-drift check that backs
  the `staleness` workflow (see Freshness below).

## Validation

```sh
pip install -r requirements.txt
make validate        # fetches the pinned contract, then validates the catalog
```

CI runs the same on every PR and push to main
(`.github/workflows/validate.yml`). Every `validated` profile must be
schema-valid, digest-pinned (`validated_image: …@sha256:…`), backed by a
committed + hash-verified workload (`workload_sha256`), have confidence ≥
moderate, and pin only **immutable version tags** in `applies_to.tags` — a
mutable rolling tag (`latest`, `stable`, `edge`, `main`, `nightly`, …) points at
a different image over time, so a profile derived against it is meaningless. The
remaining evidence bar depends on how the minimum was observed:

- **`drop-test`** (remove each candidate, restart, verify the container breaks
  without it) — asserts `validated_via: [drop-test, ci-smoke]` and must carry a
  `derivation.drop_test` evidence block; no duration floor, since it is not a
  timed observation. This is how the whole current catalog is derived: it catches
  the startup-only minimums (a socket dir's tmpfs, a root→user privilege drop's
  SETUID/SETGID) that live runtime observation is blind to.
- **`bpf-observation`** (live eBPF observation over a running workload) — asserts
  `validated_via: [bpf-observation, ci-smoke]` and requires
  `duration_seconds ≥ 300`.

## Trust model (ADR-017 §7)

Endorsed profiles are ones maintainer automation derives and can **re-derive**.
External contributions are `exploratory` until reproduced. A representative
workload and committed per-image criteria are required for promotion to
`validated`.

## Deriving a profile

See container-sec-derive's `docs/field-results.md` for worked examples
(postgres, netdata, homepage) and `--format compose-lint-profile`.

## Freshness & re-derivation (compose-lint#360)

Profiles are pinned to an exact `image@sha256:…`; when upstream republishes the
tag, the profile is derived against a superseded artifact and must be re-derived.
This runs in two parts, split by cost:

- **Trigger — `staleness` workflow (this repo, hosted, weekly).** Registry-only
  (no docker, no BPF, no secret): compares each profile's pinned digest to the
  tag's current published digest and opens a tracking issue on drift. Seconds of
  runtime — negligible Actions minutes. Run it ad-hoc via `workflow_dispatch` or
  `python scripts/check_staleness.py`.
- **Re-derivation — the heavy loop (self-hosted BPF runner).** Spinning the
  container, `csd` eBPF observation, and cap bisection need root + `--pid=host` +
  `ig`, so this runs on the **self-hosted BPF runner** — where GitHub bills **no
  Actions minutes** (self-hosted runners are free). It belongs **in this repo**,
  on a shared/org-level self-hosted runner, so it updates profiles **in place**
  (no cross-repo token). It reproduces each image's representative runtime config
  (per `derivation/manifest.yaml`), re-derives, re-validates, and bumps the
  pinned digest + `validated_date`. The re-derivation spec is committed; the
  runner loop that consumes it is not yet wired — the trigger above is part 1.

Cost note: only hosted runners consume this private repo's Actions-minute quota,
and only the light `validate` + `staleness` jobs use them (both seconds-scale).
The expensive derivation is free on the self-hosted runner. (Making the repo
public would remove the hosted-minute cost entirely.)
