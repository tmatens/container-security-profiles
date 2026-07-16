# prometheus — validation criteria

Per-image acceptance criteria for the `docker.io/prom/prometheus` profile.
Validated against `…@sha256:3c42b892…` (tag `v3.13.1`), derived by drop-test
against the **default invocation**. The catalog's first fully **zero-privilege
profile**: capabilities trim **14 → 0** and the filesystem locks read-only with
no tmpfs. Both dimensions validated together; they apply as a unit.

## Representative workload / correctness check
`profiles/workloads/prometheus.sh` — readiness, then the query API must show
the bundled config's **self-scrape** actually landed (`up == 1` for
`localhost:9090`), then a non-zero
`prometheus_tsdb_head_samples_appended_total`, which proves the TSDB **write
path** under `--storage.tsdb.path=/prometheus` was exercised — a ready check
alone passes before the first scrape and would not validate the storage path
at all. Two timing subtleties encoded in the workload: the first scrape takes
up to one scrape interval (~15s), and the appended-samples counter reads 0 on
the scrape that first reports it (appends land after the scrape), so both
checks poll.

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [] (zero-cap).** The image runs as **USER
  nobody** (uid 65534) from the first instruction — no root phase, no
  entrypoint chown, no privilege drop, nothing in the serve/scrape/TSDB path
  needs a capability. All 14 Docker defaults dropped in turn; the full
  workload stayed correct every time.
- Probes exec via the in-image busybox `wget` and inherit USER nobody, so the
  probe cannot pollute the minimum with root-probe needs (the rabbitmq
  lesson, avoided by construction).
- **Pass criteria:** ready + self-scrape `up==1` + TSDB appending, with every
  candidate dropped.

## filesystem — derived by drop-test
- **read_only: true, tmpfs: [].** prometheus writes only under
  `--storage.tsdb.path=/prometheus` — a declared VOLUME, shipped nobody-owned,
  and a PERSISTENT volume in real deployments (TSDB blocks + WAL must survive
  restarts; never tmpfs). Docker mounts the anonymous volume writable even
  under `--read-only`, so no writable stand-in is needed and the volume is
  never counted in the minimum. `/tmp` derived **not required**.
- This completes the covered observability stack: grafana / loki / alloy /
  prometheus all run `read_only: true` with at most a data volume.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the image default — USER nobody,
  the bundled `/etc/prometheus/prometheus.yml` (self-scrape only), a
  docker-managed data volume, `no-new-privileges`.
- **Variations:** a custom config that scrapes remote targets changes nothing
  about privileges (outbound HTTP needs no caps); `--web.enable-lifecycle` or
  admin APIs don't either. A deployment binding the TSDB to a **foreign-owned
  host dir** fails at startup regardless of caps (prometheus is nobody and has
  no CHOWN path of its own) — fix the bind ownership, don't add caps.
- **Out of band** (not schema fields): Docker's default seccomp baseline; a
  docker-managed data volume; the default command; amd64. The minimum is only
  valid for what the workload exercises — serve + self-scrape + TSDB append;
  remote-write, alerting rules, and service discovery are out of scope.
