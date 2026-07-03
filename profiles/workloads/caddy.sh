#!/usr/bin/env bash
# Workload exerciser for the caddy reference image (default file server).
#
# Drives caddy's default configuration — serve a file-server GET on :80, survive
# a SIGUSR1 config reload, serve again — all via `docker exec` so no host ports
# need publishing. Returns 0 if every step succeeded.
#
# Required env: CADDY_CONTAINER (target container name or id).
set -euo pipefail

: "${CADDY_CONTAINER:?CADDY_CONTAINER must be set}"

serve() { docker exec "${CADDY_CONTAINER}" wget -qO- http://localhost/ >/dev/null; }

# Wait until the file server responds.
deadline=$((SECONDS + 30))
until serve 2>/dev/null; do
    if (( SECONDS >= deadline )); then
        echo "caddy did not become ready in 30s" >&2
        exit 1
    fi
    sleep 1
done

# GET — file server happy path.
serve

# SIGUSR1 — reload the configuration from the Caddyfile.
docker kill --signal=SIGUSR1 "${CADDY_CONTAINER}" >/dev/null
sleep 1

# Still serving after the reload.
serve
