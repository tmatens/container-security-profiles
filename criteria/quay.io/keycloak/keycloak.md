# keycloak — validation criteria

Per-image acceptance criteria for the `quay.io/keycloak/keycloak` profile.
Validated against `…@sha256:9409c59b…` (tag `26.4`), derived by drop-test
against the **`start-dev` invocation** (embedded H2 dev database, bootstrap
admin via env). Capabilities trim **14 → 0**.

## Representative workload / correctness check
`profiles/workloads/keycloak.sh` — real IdP function: ready → obtain an admin
token via the OpenID **password grant** (admin-cli) → **create a realm**
through the admin API → read it back. An authenticated write through the full
JAX-RS + persistence stack. Curl sidecar; capture-then-match.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [] (zero-cap)** — **non-root by construction**
  (the image is USER 1000), unprivileged `:8080`, all state in the H2 file
  under the image's data dir. All 14 Docker defaults dropped in turn; the
  token + realm round-trip passed every time. (A harness note worth keeping:
  the keycloak base image is UBI-micro and has **no `awk`** — the uid probe
  must read `/proc/1/status` with pure shell, not `awk`.)
- **Pass criteria:** admin token issued, realm created and read back, with
  every candidate dropped; PID 1 is uid 1000.

## Scope (`run_config` + out-of-band conditions)
- **Invocation:** `start-dev` (dev H2 store), `KC_BOOTSTRAP_ADMIN_*` env,
  `no-new-privileges`. This is the dev/eval invocation.
- **The production variation** — `start` against an external **postgres** —
  is a documented follow-up. Its DB access is a **TCP client** (no
  capability), and keycloak still runs as USER 1000 on :8080, so the minimum
  is **expected to stay []**; not yet independently derived here.
- **Out of band:** Docker's default seccomp baseline; amd64. The minimum
  covers token issuance + realm/admin API writes; clustering (Infinispan/JGroups),
  TLS with a low-port bind, and custom providers are out of scope.
