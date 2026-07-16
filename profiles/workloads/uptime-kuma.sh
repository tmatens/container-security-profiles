#!/usr/bin/env bash
# Workload exerciser for the uptime-kuma reference image (v2). Drives real
# function end-to-end: HTTP database setup, then — over socket.io, the only
# transport for admin/monitor CRUD — admin creation, login, adding an HTTP
# monitor, and confirming it reports an UP heartbeat. The socket.io probe runs
# from a sidecar using the uptime-kuma image itself (node + socket.io-client
# baked in) sharing the target's netns, so nothing is written inside the target.
#
# A PING monitor additionally requires NET_RAW (raw ICMP) — measured
# separately; see the criteria doc. This workload covers the common
# HTTP/TCP-monitor case, which needs only the profile's [DAC_OVERRIDE, FOWNER].
#
# Required env: UPTIMEKUMACONTAINER (target container name or id).
set -euo pipefail
: "${UPTIMEKUMACONTAINER:?UPTIMEKUMACONTAINER must be set}"
C="${UPTIMEKUMACONTAINER}"
PROBE="${CSD_PROBE_CURL_IMAGE:-curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69}"
# The uptime-kuma image doubles as the socket.io probe image (pinned by digest).
UK_IMAGE="${CSD_PROBE_UK_IMAGE:-louislam/uptime-kuma@sha256:91e963bfda569ba115206e843febb446f473ab525add4e08b2b9e3beffa16985}"
sc() { docker run --rm --network "container:${C}" "$PROBE" "$@"; }

want() { local dl=$((SECONDS+$1)); while :; do case "$(sc -s --max-time 5 http://localhost:3001/api/entry-page 2>/dev/null)" in *"$2"*) return 0;; esac; (( SECONDS >= dl )) && return 1; sleep 3; done; }
want 90 "setup-database" || { echo "no setup-database page" >&2; exit 1; }
code="$(sc -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST -H 'Content-Type: application/json' -d '{"dbConfig":{"type":"sqlite"}}' http://localhost:3001/setup-database 2>/dev/null)"
[ "$code" = 200 ] || { echo "setup-database failed: HTTP ${code:-none}" >&2; exit 1; }
sleep 3
want 90 "entryPage" || { echo "server did not serve after setup" >&2; exit 1; }

probe="$(mktemp)"; trap 'rm -f "$probe"' EXIT
cat > "$probe" <<'JS'
const { io } = require("socket.io-client");
const s = io("http://localhost:3001", { reconnection: false });
const emit = (ev, ...a) => new Promise((res, rej) => { const t=setTimeout(()=>rej(new Error(ev+" timeout")),15000); s.emit(ev, ...a, r=>{clearTimeout(t);res(r);}); });
(async () => {
  await new Promise((res,rej)=>{ s.on("connect",res); s.on("connect_error",rej); });
  await emit("setup","csdadmin","CsdProbe-Pw-12345").catch(()=>{});
  await emit("login",{username:"csdadmin",password:"CsdProbe-Pw-12345",token:""});
  const r = await emit("add",{ type:"http", name:"csd-http", url:"http://localhost:3001/api/entry-page", method:"GET",
    interval:20, maxretries:1, retryInterval:20, conditions:[], notificationIDList:{}, accepted_statuscodes:["200-299"], timeout:10 });
  if (!r || !r.ok) { console.error("add failed", JSON.stringify(r)); process.exit(1); }
  for (let i=0;i<20;i++){ const l=await emit("getMonitorBeats",r.monitorID,168).catch(()=>null); const b=l&&Array.isArray(l.data)?l.data:[]; if (b.length && b[b.length-1].status===1){ console.log("http monitor UP"); process.exit(0);} await new Promise(x=>setTimeout(x,3000)); }
  process.exit(3);
})().catch(e=>{ console.error("ERR",e.message); process.exit(2); });
JS
docker run --rm --network "container:${C}" -w /app -v "$probe:/app/csd-uk-probe.cjs:ro" "$UK_IMAGE" node /app/csd-uk-probe.cjs \
  || { echo "socket.io HTTP monitor did not run" >&2; exit 1; }
