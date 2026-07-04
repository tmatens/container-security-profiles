# grafana — validation criteria

Per-image acceptance criteria for the `docker.io/grafana/grafana` profile.
Validated against `…@sha256:5dad0df…` (tag `13.0.2`), derived by drop-test.
grafana already runs `cap_drop: ALL` in the reference deployment, so there is no
capability reduction to derive — this profile covers the **filesystem** dimension.

## Representative workload / correctness check
`profiles/workloads/grafana.sh` drives real function under `--read-only`, not
liveness:
- `/api/health` reports the database is **"ok"**;
- create a dashboard **and read it back** — a real sqlite write on the data volume;
- add a **Loki** datasource and hit its plugin health endpoint — a running backend
  (go-plugin) returns a JSON verdict with a `status` field even when the target Loki
  is unreachable; a backend that failed to start does not.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** Under a read-only rootfs with only the
  `/var/lib/grafana` data volume writable, grafana serves the UI, reads/writes its
  sqlite DB, and runs backend datasource plugins (prometheus/Loki). `/tmp` was the
  one plausible ephemeral tmpfs candidate and drop-tested as **NOT required** for
  this.
- **`/var/lib/grafana` is a PERSISTENT VOLUME, not tmpfs.** It holds grafana's
  sqlite DB and any installed plugins, which must survive restarts. It is supplied
  in the derivation as a writable stand-in (`run.tmpfs`) purely so the read-only
  rootfs is exercised; it is never part of the tmpfs minimum. Do **not** put it on
  tmpfs in a real deployment.
- **Pass criteria:** the workload passes (health db ok + dashboard write/read-back +
  a backend datasource plugin running) under `--read-only` with `/var/lib/grafana`
  writable and no `/tmp`.

## Scope — when to add `tmpfs: [/tmp]` (confidence: moderate)
grafana's feature surface is large and this workload cannot exercise all of it, so
the minimum is the **core + datasource-querying** floor. A writable `/tmp` is
required by features **not** covered here — verified as real read-only-fs errors at
boot without it:
- **runtime plugin installation** — grafana's background installer downloads
  bundled app plugins (e.g. pyroscope, exploretraces) to `/tmp` at startup;
- the **elasticsearch** datasource plugin (writes `/tmp` during init);
- **image rendering** (the renderer plugin) and **CSV / report export**.
A deployment that installs plugins at runtime or uses those features should add
`tmpfs: [/tmp]` — which is cheap and what the reference compose does conservatively.
Core dashboards + prometheus/Loki datasource querying do **not** need it.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): root (grafana drops to uid 472
  internally), the `grafana-data:/var/lib/grafana` data volume, `GF_*` env,
  `no-new-privileges`, `cap_drop: ALL`.
- **Out of band** (not schema fields): the reference deployment mounts provisioning
  + dashboards read-only and logs to console (`mode=console`), so no writable
  `/var/log/grafana` is needed; amd64. The minimum is only valid for what
  `profiles/workloads/grafana.sh` exercises (see the moderate-confidence scope note).
