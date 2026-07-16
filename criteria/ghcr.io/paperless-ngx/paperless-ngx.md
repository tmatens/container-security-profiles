# paperless-ngx — validation criteria

Per-image acceptance criteria for the `ghcr.io/paperless-ngx/paperless-ngx`
profile. Validated against `…@sha256:3421ebe0…` (tag `2.18`), derived by
drop-test against the **in-stack invocation** (against a redis broker).
Capabilities trim **14 → 3**.

## Representative workload / correctness check
`profiles/workloads/paperless-ngx.sh` — the real document lifecycle: token
auth → POST a document to the consume API → poll until it is fully consumed
(**web → redis task queue → celery worker → media write**), the whole
stack-backed pipeline. A **plain-text** probe document skips OCR, keeping
trials fast (~seconds of consume) while still exercising every tier. The
drop-test correctness check additionally asserts a worker (granian/celery)
runs as the non-root PUID (uid 1000).

## capabilities — derived by drop-test
- **cap_drop: [ALL], cap_add: [CHOWN, SETGID, SETUID].** The s6-overlay init
  starts as root, provisions/chowns the data + media + consume dirs on the
  fresh volumes (**CHOWN**), then drops every worker to PUID 1000
  (**SETGID/SETUID**). Dropping any of the three fatals the s6 `rc.init`
  (`fatal: stopping the container`).
- **No DAC_OVERRIDE** — the chown sets ownership *before* the writes, so the
  post-chown writes are as the owner (contrast wordpress/nextcloud, whose
  root-phase writes into an already-www-data-owned tree need DAC_OVERRIDE,
  and whose source copies need FOWNER). paperless is the leaner member of
  the root-provision-then-drop family.
- **No NET_BIND_SERVICE** — the web tier is the unprivileged :8000.
- **Pass criteria:** the document is consumed through the full pipeline
  **and** a worker is uid 1000; each granted cap's drop fatals s6 init.

## Scope (`run_config` + out-of-band conditions)
- **Invocation** (`derivation.run_config`): the default — root s6 start,
  `PAPERLESS_REDIS` + `PAPERLESS_SECRET_KEY` + `PAPERLESS_ADMIN_*` env, fresh
  consume/data/export/media VOLUMEs, `no-new-privileges`, a reachable redis
  (the derivation used the cataloged `redis:8.2.7` as the in-stack broker).
- **Variations:** `USERMAP_UID`/`user:` against pre-owned volumes skips the
  chown + drop → minimum shrinks toward `[]`. A postgres/mariadb DB backend
  (vs the default sqlite) is a TCP client, no caps. **OCR of image/PDF
  documents** runs Tesseract/Ghostscript as the already-dropped worker — no
  additional container capability expected, but not exercised here (the
  text-doc probe path).
- **Out of band** (not schema fields): Docker's default seccomp baseline;
  the in-stack redis; amd64. The minimum is only valid for what the workload
  exercises — auth + consume + store of a text document; OCR-heavy formats,
  the classifier/ML tagging, and email/IMAP ingestion are out of scope.
