#!/usr/bin/env bash
# Workload exerciser for the itzg/minecraft-server reference image.
#
# Waits for the Minecraft server to accept a status ping (`mc-monitor status`, which
# ships in the image) and asserts it runs as the non-root minecraft user (uid 1000)
# — the entrypoint gosu-drops root -> minecraft, and a status ping alone would pass
# while running as root. Returns 0 on success.
#
# Required env: MINECRAFTCONTAINER (target container name or id).
set -euo pipefail

: "${MINECRAFTCONTAINER:?MINECRAFTCONTAINER must be set}"
C="${MINECRAFTCONTAINER}"

deadline=$((SECONDS + 150))
until docker exec "$C" mc-monitor status --host localhost --port 25565 >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
        echo "minecraft server never became ready (mc-monitor status) in 150s" >&2
        exit 1
    fi
    sleep 2
done

uid="$(docker exec "$C" sh -c 'for p in /proc/[0-9]*; do a0=$(tr "\0" "\n" <"$p/cmdline" 2>/dev/null | head -1); case "$a0" in *java) awk "/^Uid:/{print \$2}" "$p/status"; break;; esac; done')"
if [ -z "$uid" ] || [ "$uid" = 0 ]; then
    echo "minecraft server (java) running as ROOT or not found (gosu drop failed): uid=${uid:-none}" >&2
    exit 1
fi
