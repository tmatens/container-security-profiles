# compose-lint profile catalog

Evidence-backed minimum-security profiles for container images, derived by
[container-sec-derive](https://github.com/tmatens/container-sec-derive) (csd)
and consumed by [compose-lint](https://github.com/tmatens/compose-lint) as
fix-guidance enrichment. This is the **external, automation-maintained catalog**
described in compose-lint ADR-017 §7 — it is deliberately *not* bundled in the
compose-lint wheel.

## Layout

- `catalog/<image>.yaml` — **validated** profiles (cleared the acceptance
  contract *and* the ci-smoke gate).
- `catalog/exploratory/<image>.yaml` — **exploratory** drafts (below the bar;
  advisory only, never used for conformance).
- `profiles/workloads/<name>.sh` — the committed exerciser scripts profiles pin
  by `workload_sha256`.
- `criteria/<image>.md` — per-image scenarios + pass criteria (compose-lint#359).
- `schema/profile.schema.json`, `scripts/validate_profiles.py` — **vendored**
  from compose-lint (source of truth there; keep in sync on schema changes).

## Validation

```sh
pip install -r requirements.txt
python scripts/validate_profiles.py --catalog-dir catalog \
  --schema schema/profile.schema.json --repo-root .
```

CI runs this on every PR (`.github/workflows/validate.yml`). A `validated`
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
