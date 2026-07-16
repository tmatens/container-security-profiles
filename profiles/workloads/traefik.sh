#!/usr/bin/env bash
# Workload exerciser for the traefik reference image (file-provider
# reverse-proxy invocation).
#
# Drives traefik's real function end-to-end: a request on entrypoint :80 must
# be routed through a traefik router to an upstream named `backend` (in the
# derivation stack, a pinned caddy on the shared network) and answered with
# the backend's content. The dynamic file-provider config is docker-cp'd into
# /tmp (traefik is started with --providers.file.directory=/tmp watch=true and
# hot-loads it) — a daemon-side write that exercises no capability inside the
# target. Probes run from a curl sidecar sharing the target's netns.
#
# Required env: TRAEFIKCONTAINER (target container name or id). Requires an
# HTTP responder reachable from the target as http://backend:80.
set -euo pipefail

: "${TRAEFIKCONTAINER:?TRAEFIKCONTAINER must be set}"
C="${TRAEFIKCONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/dynamic.yml" <<'EOF'
http:
  routers:
    csd:
      rule: PathPrefix(`/`)
      service: backend
  services:
    backend:
      loadBalancer:
        servers:
          - url: http://backend:80
EOF
docker cp "$tmp/dynamic.yml" "$C:/tmp/dynamic.yml" >/dev/null

deadline=$((SECONDS + 45))
while :; do
    body="$(sc -s --max-time 5 http://localhost:80/ 2>/dev/null)"
    case "$body" in *[Cc]addy*|*backend*) break;; esac
    (( SECONDS >= deadline )) && { echo "no routed backend response" >&2; exit 1; }
    sleep 2
done
