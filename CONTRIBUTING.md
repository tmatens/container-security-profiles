# Contributing

Thanks for your interest. This catalog accepts two kinds of contribution:
**profile requests** (open an issue — the easiest way to help) and **profile
contributions** (a PR with the derived profile and its evidence).

## Requesting a profile

Open a [profile request](../../issues/new?template=profile-request.yml) with the
image, an immutable tag, and how you run it (compose snippet). Popular,
widely-deployed images are prioritized.

## Reporting a profile that broke your deployment

A profile is a *minimum for the recorded invocation* — if it broke yours, that's
signal we want. Open a
[profile mismatch report](../../issues/new?template=profile-mismatch.yml) with
the failing capability/path and how your invocation differs from the profile's
`run_config`. Known cause #1: a different `user:`, volume ownership, or
entrypoint changes the minimum.

## Contributing a profile

External contributions land as **exploratory** first
(`catalog/exploratory/<registry>/<org>/<image>.yaml`) and are promoted to
`validated` once maintainer automation reproduces the derivation — see the
trust model in the README. A contribution PR needs:

1. **The profile YAML**, conforming to the pinned compose-lint profile schema
   (`make validate` must pass). Digest-pinned `validated_image`
   (`…@sha256:…`), **immutable** tags in `applies_to.tags` (no `latest` /
   `stable` / major-only rolling tags for new profiles), confidence ≥ moderate.
2. **Evidence** in the `derivation` block:
   - `drop-test`: a `drop_test.checks` list — every granted element removed in
     turn, the workload re-verified, the break observed; or
   - `bpf-observation`: `duration_seconds ≥ 300` of live observation.
3. **A committed workload script** under `profiles/workloads/`, referenced by
   `workload` + `workload_sha256`. The workload must exercise the image's real
   function (a health check alone is not enough) and assert any privilege drop
   (e.g. PID 1 runs non-root).
4. **A criteria doc** at `criteria/<registry>/<org>/<image>.md` mirroring the
   catalog path: what the workload covers, what it doesn't, and the pass
   criteria — including the honest scope limits.
5. **A row in the README catalog table** and, if you changed the generator or
   site, a passing `make site`.

## Conventions

- One logical change per commit; imperative subject ≤ 72 chars; explain the
  *why* in the body.
- Commits are signed and carry a DCO `Signed-off-by` trailer (`git commit -s`).
- No AI authorship attribution (no `Co-Authored-By` for tools, no "generated
  by" notices).
- CI (`validate`) must be green: schema validation plus the site-generator
  smoke build.

## Validation locally

```sh
pip install -r requirements.txt
make validate
```
