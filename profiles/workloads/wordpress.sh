#!/usr/bin/env bash
# Workload exerciser for the wordpress reference image (in-stack, against a
# mysql database reachable per WORDPRESS_DB_HOST).
#
# Real function, both site states:
#   - fresh database: drive the REAL HTTP install flow (install.php?step=2 —
#     creates the schema through php -> mysql), then assert the homepage
#     serves the configured blog title from the database;
#   - installed database: assert the title-bearing homepage directly (fresh
#     container generates wp-config from env, php reads the site from mysql).
# The install POST retries and the title check polls — the first request
# after boot can land while php/mysql are still settling. Probed from a curl
# sidecar sharing the target's netns. The non-root WORKER uid assert lives in
# the drop-test correctness check (the httpd sharp edge: a broken drop keeps
# serving with root workers).
#
# Required env: WORDPRESSCONTAINER (target container name or id).
set -euo pipefail

: "${WORDPRESSCONTAINER:?WORDPRESSCONTAINER must be set}"
C="${WORDPRESSCONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }
TITLE="csdblog-e7a1"
# capture-then-match, NEVER `curl | grep -q` (pipefail + grep -q early-exit =
# SIGPIPE 141 = false negative on a matching page).
titled() { local b; b="$(sc -sL --max-time 10 http://localhost:80/ 2>/dev/null)"; case "$b" in *"$TITLE"*) return 0;; esac; return 1; }

deadline=$((SECONDS + 90))
while :; do
    code="$(sc -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:80/ 2>/dev/null)"
    case "$code" in 200|30?) break;; esac
    (( SECONDS >= deadline )) && { echo "wordpress never answered" >&2; exit 1; }
    sleep 2
done

if ! titled; then
    ok=""
    for attempt in 1 2 3; do
        sc -s --max-time 30 -X POST \
            --data-urlencode "weblog_title=$TITLE" \
            --data-urlencode "user_name=csdadmin" \
            --data-urlencode "admin_password=CsdProbe-Pw-12345-Strong" \
            --data-urlencode "admin_password2=CsdProbe-Pw-12345-Strong" \
            --data-urlencode "admin_email=csd@example.com" \
            --data-urlencode "blog_public=0" \
            'http://localhost:80/wp-admin/install.php?step=2' >/dev/null 2>&1
        deadline2=$((SECONDS+20))
        until titled; do (( SECONDS >= deadline2 )) && break; sleep 2; done
        titled && { ok=1; break; }
        sleep 3
    done
    if [ -z "$ok" ]; then
        echo "install flow did not produce the titled homepage" >&2
        exit 1
    fi
fi
