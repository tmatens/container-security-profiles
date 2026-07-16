#!/usr/bin/env bash
# Workload exerciser for the keycloak reference image (start-dev, embedded H2).
# Real IdP function: ready -> admin token via the OpenID password grant
# (admin-cli) -> create a realm through the admin API -> read it back. Curl
# sidecar; capture-then-match.
# Required env: KEYCLOAKCONTAINER (target container name or id). Container is
# expected to run with KC_BOOTSTRAP_ADMIN_USERNAME=csdadmin /
# KC_BOOTSTRAP_ADMIN_PASSWORD=CsdProbe-Pw-12345.
set -euo pipefail
: "${KEYCLOAKCONTAINER:?KEYCLOAKCONTAINER must be set}"
C="${KEYCLOAKCONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }
deadline=$((SECONDS + 120))
until [ "$(sc -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8080/realms/master 2>/dev/null)" = 200 ]; do
    (( SECONDS >= deadline )) && { echo "keycloak never ready" >&2; exit 1; }
    sleep 3
done
tokresp="$(sc -s --max-time 10 -d 'grant_type=password&client_id=admin-cli&username=csdadmin&password=CsdProbe-Pw-12345' http://localhost:8080/realms/master/protocol/openid-connect/token 2>/dev/null)"
tok="$(printf '%s' "$tokresp" | grep -oE '"access_token":"[^"]+' | cut -d'"' -f4)"
[ -n "$tok" ] || { echo "admin token failed" >&2; exit 1; }
code="$(sc -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' -d '{"realm":"csd","enabled":true}' http://localhost:8080/admin/realms 2>/dev/null)"
case "$code" in 201|409) ;; *) echo "realm create failed: HTTP ${code:-none}" >&2; exit 1;; esac
back="$(sc -s --max-time 10 -H "Authorization: Bearer $tok" http://localhost:8080/admin/realms/csd 2>/dev/null)"
case "$back" in *'"realm":"csd"'*) ;; *) echo "realm readback failed" >&2; exit 1;; esac
