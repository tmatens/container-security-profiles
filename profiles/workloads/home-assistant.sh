#!/usr/bin/env bash
# Workload exerciser for the Home Assistant reference image.
#
# HA runs `python3 -m homeassistant` under s6 AS ROOT (no privilege drop). The one
# capability HA core exercises comes from writing into a non-root-owned /config
# bind, so this drives the real write path rather than mere liveness:
#   - reach the onboarding API (HA only gets here after writing its DB + .storage +
#     logs into /config as root);
#   - complete owner onboarding (create the first user) -> HTTP 200 + an auth_code,
#     a further real write to .storage/auth.
# Returns 0 if every step succeeds.
#
# SCOPE: HA *core* on a base config. Capabilities pulled in by specific
# integrations (NET_RAW for ICMP ping, device access for USB/Bluetooth/Zigbee,
# NET_ADMIN for some network integrations) are not exercised here — see the
# criteria doc.
#
# Required env: HACONTAINER (target container name or id). The container's /config
# must be a NON-root-owned bind (matching a real deployment) for DAC_OVERRIDE to be
# exercised.
set -euo pipefail

: "${HACONTAINER:?HACONTAINER must be set}"
C="${HACONTAINER}"

READY='import urllib.request as u,json,sys; d=json.load(u.urlopen("http://127.0.0.1:8123/api/onboarding",timeout=3)); sys.exit(0 if isinstance(d,list) and d and "step" in d[0] else 1)'

deadline=$((SECONDS + 60))
until docker exec "$C" python3 -c "$READY" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
        echo "HA onboarding API never became ready in 60s" >&2
        exit 1
    fi
    sleep 2
done

out="$(docker exec "$C" python3 -c 'import urllib.request as u,json; b=json.dumps({"client_id":"http://localhost:8123/","name":"csd","username":"csd","password":"csdprobe-pw-12345","language":"en"}).encode(); r=u.urlopen(u.Request("http://127.0.0.1:8123/api/onboarding/users",data=b,headers={"Content-Type":"application/json"}),timeout=15); d=json.load(r); print(r.status, "auth_code" in d)' 2>&1)"
if [ "$out" != "200 True" ]; then
    echo "onboarding user-create failed (expected '200 True', got: ${out##*$'\n'})" >&2
    exit 1
fi
