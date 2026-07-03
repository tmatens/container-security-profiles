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
schema** (`schema_version`, currently `1.0`). Nothing else:

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

- `catalog/<image>.yaml` — **validated** profiles (cleared the acceptance
  contract *and* the ci-smoke gate).
- `catalog/exploratory/<image>.yaml` — **exploratory** drafts (below the bar;
  advisory only, never used for conformance).
- `profiles/workloads/<name>.sh` — the committed exerciser scripts profiles pin
  by `workload_sha256`.
- `criteria/<image>.md` — per-image scenarios + pass criteria (compose-lint#359).
- `contract/compose-lint.ref` — the pinned compose-lint commit whose schema +
  validator this catalog conforms to.
- `scripts/fetch-contract.sh` — fetches that pinned schema + validator into
  `.contract/` (gitignored).

## Validation

```sh
pip install -r requirements.txt
make validate        # fetches the pinned contract, then validates the catalog
```

CI runs the same on every PR (`.github/workflows/validate.yml`). A `validated`
profile must be schema-valid, digest-pinned, backed by a committed +
hash-verified workload, confidence ≥ moderate, duration ≥ 300s, and assert
`validated_via: [bpf-observation, ci-smoke]`.

## Trust model (ADR-017 §7)

Endorsed profiles are ones maintainer automation derives and can **re-derive**.
External contributions are `exploratory` until reproduced. A representative
workload and committed per-image criteria are required for promotion to
`validated`.

## Deriving a profile

See container-sec-derive's `docs/field-results.md` for worked examples
(postgres, netdata, homepage) and `--format compose-lint-profile`.
