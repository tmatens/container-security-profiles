#!/usr/bin/env bash
# Workload exerciser for the jellyfin reference image.
#
# Drives the REAL first-run flow end-to-end: health, the setup wizard REST
# sequence (Startup/Configuration -> Startup/User -> Startup/Complete), token
# auth as the created admin, and an authorized System/Info readback. A fresh
# /config volume means the wizard path executes on first boot.
#
# Probes go through a curl sidecar (the image ships no curl/wget), write
# nothing inside the container, and capture-then-match responses (never
# `curl | grep -q` under pipefail). jellyfin serves as root by default with
# no privilege drop — the hardening lever is `user:`, see the criteria doc.
#
# Required env: JELLYFINCONTAINER (target container name or id).
set -euo pipefail

: "${JELLYFINCONTAINER:?JELLYFINCONTAINER must be set}"
C="${JELLYFINCONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }

deadline=$((SECONDS + 120))
until [ "$(sc -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8096/health 2>/dev/null)" = 200 ]; do
    (( SECONDS >= deadline )) && { echo "jellyfin never healthy" >&2; exit 1; }
    sleep 3
done

for step in \
    'POST /Startup/Configuration {"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' \
    'GET /Startup/User -' \
    'POST /Startup/User {"Name":"csdadmin","Password":"CsdProbe-Pw-12345"}' \
    'POST /Startup/Complete -'; do
    m="${step%% *}"; rest="${step#* }"; path="${rest%% *}"; body="${rest#* }"
    args=(-s -o /dev/null -w '%{http_code}' --max-time 10 -X "$m")
    [ "$body" != "-" ] && args+=(-H 'Content-Type: application/json' -d "$body")
    code="$(sc "${args[@]}" "http://localhost:8096$path" 2>/dev/null)"
    case "$code" in 2??) ;; *) echo "wizard step $m $path failed: HTTP ${code:-none}" >&2; exit 1;; esac
done

auth="$(sc -s --max-time 10 -X POST -H 'Content-Type: application/json' \
    -H 'Authorization: MediaBrowser Client="csd", Device="csd", DeviceId="csd", Version="1.0"' \
    -d '{"Username":"csdadmin","Pw":"CsdProbe-Pw-12345"}' \
    http://localhost:8096/Users/AuthenticateByName 2>/dev/null)"
tok="$(printf '%s' "$auth" | grep -oE '"AccessToken":"[a-f0-9]+"' | cut -d'"' -f4)"
[ -n "$tok" ] || { echo "admin auth failed" >&2; exit 1; }
info="$(sc -s --max-time 10 -H "Authorization: MediaBrowser Token=\"$tok\"" \
    http://localhost:8096/System/Info 2>/dev/null)"
case "$info" in *'"Version":"'*) ;; *) echo "authorized System/Info failed" >&2; exit 1;; esac
