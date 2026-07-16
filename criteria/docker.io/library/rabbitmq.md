# rabbitmq — validation criteria

Per-image acceptance criteria for the `docker.io/library/rabbitmq` profile (the
official RabbitMQ image, plain — not `-management`). Validated against
`…@sha256:345dd3c1…` (tag `4.3`), derived by drop-test against the **default
(root-then-drop) invocation**. The default runs on the full Docker default cap
set; this profile trims it **14 → 2**.

## Representative workload / correctness check
`profiles/workloads/rabbitmq.sh` — a real **declare → publish → consume**
round-trip. The plain image ships no AMQP client and no curl (only
`rabbitmqctl` / `rabbitmq-diagnostics`), so the workload enables the bundled
`rabbitmq_management` plugin at runtime — the same plugin the `-management`
tag pre-enables and most deployments run — and drives the round-trip over the
management API from a **sidecar** sharing the target's network namespace,
which also satisfies the default guest user's loopback-only restriction with
no config changes. The drop-test correctness check additionally asserts the
broker (`beam.smp`) runs as the **non-root** rabbitmq user (uid 999).

Two harness sharp edges, reproduced deterministically on 4.3 — any
re-derivation must respect both:

1. **Never exec a rabbitmq CLI into the container during boot.** An exec'd
   root-run Erlang client races the entrypoint for the creation of
   `/var/lib/rabbitmq/.erlang.cookie`; if root wins, the broker (running as
   rabbitmq) cannot read its own cookie and beam crashes (`erl_crash.dump`).
   Gate on the broker's own "Server startup complete" log line first.
2. **Exec CLIs as the rabbitmq user (`--user rabbitmq`), never root.** An
   exec'd process runs inside the target's bounding cap set, so a root probe's
   own needs pollute the derived minimum: root needs DAC_OVERRIDE to read the
   rabbitmq-owned 0600 cookie and FOWNER to rewrite the rabbitmq-owned
   `enabled_plugins` — both derived falsely-required before this fix, while
   the broker itself was healthy.

Also 4.x-specific: queue declares must be **durable** — RabbitMQ 4.x rejects
transient non-exclusive queues (`transient_nonexcl_queues` deprecated).

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [SETGID, SETUID].** Baseline `cap_drop:ALL` +
  the Docker default set on a fresh docker-managed data volume; each default
  dropped in turn, the workload re-verified. The entrypoint re-execs itself as
  the rabbitmq user via **gosu**; dropping either cap fails deterministically
  (`error: failed switching to "rabbitmq": operation not permitted`) and the
  container never starts. Startup caps, invisible to runtime observation.
- **CHOWN is NOT required by default** — `/var/lib/rabbitmq` ships pre-owned
  by the rabbitmq user, so the entrypoint's `find`-chown is a no-op on
  docker-managed volumes. A **foreign-owned bind mount** re-introduces CHOWN.
- **Pass criteria:** the publish/consume round-trip succeeds **and**
  `beam.smp` is uid 999; dropping SETGID or SETUID fails container start.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the default — root (no `user:`
  override), a docker-managed data volume, no env overrides,
  `no-new-privileges`. The management plugin is enabled by the workload at
  runtime; a deployment running the `-management` tag has it pre-enabled with
  the same broker privilege path (minimum expected unchanged).
- **`user:` = the rabbitmq uid against a pre-owned data dir** → the entrypoint
  skips the gosu drop (the official image test itself runs `--user rabbitmq`),
  shrinking the minimum to **[]**.
- **Out of band** (not schema fields): Docker's default cap set + default
  seccomp baseline; a docker-managed data volume; the default
  `rabbitmq-server` command; amd64. The minimum is only valid for what the
  workload exercises — core AMQP-over-management declare/publish/consume;
  clustering, TLS listeners, and federation/shovel plugins are out of scope.
