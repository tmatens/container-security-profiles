# Security policy

This repository publishes **security configuration data** (minimum-privilege
profiles for container images) plus small build/validation scripts that run
only in CI. Nothing here executes in your runtime — but wrong data can still
hurt, so the policy is scoped to the data:

## What counts as a security issue

- **An over-permissive profile**: a `validated` profile granting something the
  image demonstrably does not need under the recorded `run_config` (the
  evidence in the profile contradicts its own conclusion), or evidence that a
  granted capability/path is exploitable and avoidable.
- **A provenance break**: a profile whose pinned digest, workload hash, or
  evidence block doesn't match what the derivation actually produces.
- **Script vulnerabilities** in `scripts/` (they run in CI with a read-only
  token; the site generator renders catalog content into HTML — escaping bugs
  qualify).

An **under-permissive** profile (it breaks your deployment) is a correctness
bug, not a vulnerability — please use the
[profile mismatch template](../../issues/new?template=profile-mismatch.yml).

## Reporting

Use **GitHub private vulnerability reporting** (Security tab → "Report a
vulnerability") for anything you'd rather not disclose publicly; anything else
can be a regular issue. You'll get an acknowledgement within a week.

## Hardening notes for consumers

- Profiles are minimums **for the recorded invocation and workload** — read
  the profile's criteria doc before adopting, and treat a different `user:`,
  volume state, or entrypoint as a different derivation.
- Every `validated` profile is digest-pinned; the `staleness` workflow tracks
  upstream digest drift and flags profiles needing re-derivation.
