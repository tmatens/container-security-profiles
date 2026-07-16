#!/usr/bin/env bash
# Workload for the jellyfin devices dimension (docker.io/jellyfin/jellyfin):
# exercise the hardware-transcode device-access path.
#
# Drives jellyfin's own bundled ffmpeg (the binary the server spawns for every
# hardware transcode) through a full VAAPI hardware ENCODE on the container's
# granted /dev/dri render node. This is the device-access surface of hw
# transcoding — the same /dev/dri opens a library-triggered playback transcode
# performs — without needing a media library and a playback session; a real
# playback would spawn the identical binary against the identical nodes.
# Correctness: the VAAPI encode must SUCCEED — if the device grant is missing
# or broken, ffmpeg fails to open the hw device and this exits non-zero.
#
# Required env: JFCONTAINER (target container name or id).
set -euo pipefail
: "${JFCONTAINER:?JFCONTAINER must be set}"

# Wait for the container process tree to accept execs (server boot is not
# required for the transcode path, but the container must be running).
deadline=$((SECONDS + 60))
until [ "$(docker inspect -f '{{.State.Status}}' "$JFCONTAINER" 2>/dev/null)" = running ]; do
    (( SECONDS >= deadline )) && { echo "container not running"; exit 1; }
    sleep 2
done

# Full VAAPI pipeline: hwupload -> h264_vaapi encode. testsrc keeps the
# workload self-contained (no media fixture to ship or license).
docker exec "$JFCONTAINER" /usr/lib/jellyfin-ffmpeg/ffmpeg -v error \
    -init_hw_device vaapi=va:/dev/dri/renderD128 \
    -f lavfi -i testsrc=duration=8:size=1920x1080:rate=30 \
    -vf format=nv12,hwupload -c:v h264_vaapi -f null - \
    || { echo "VAAPI hardware encode failed"; exit 1; }

echo "jellyfin transcode correct: VAAPI h264 encode on /dev/dri/renderD128 succeeded"
