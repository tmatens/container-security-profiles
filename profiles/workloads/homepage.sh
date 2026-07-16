#!/usr/bin/env bash
# Workload exerciser for the gethomepage/homepage reference image.
#
# Drives the dashboard (GET /) and Next.js image optimization (GET /_next/image,
# which writes /app/.next/cache), via docker exec so no host ports need
# publishing. Returns 0 if the dashboard serves and the image-optimization cache
# is writable (no read-only / ENOENT error), which is the correctness bar the
# filesystem profile is judged against.
#
# Required env: HOMEPAGE_CONTAINER (target container name or id).
set -euo pipefail

: "${HOMEPAGE_CONTAINER:?HOMEPAGE_CONTAINER must be set}"
C="${HOMEPAGE_CONTAINER}"

# Wait until the dashboard responds.
deadline=$((SECONDS + 40))
until docker exec "${C}" wget -qO- http://localhost:3000/ >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
        echo "homepage did not become ready in 40s" >&2
        exit 1
    fi
    sleep 2
done

# Dashboard happy path.
docker exec "${C}" wget -qO- http://localhost:3000/ >/dev/null

# Image optimization — exercises the /app/.next/cache write.
docker exec "${C}" wget -qO- "http://localhost:3000/_next/image?url=%2Ficon.png&w=64&q=75" >/dev/null 2>&1 || true
sleep 2

# Correct only if the cache write did not fail on a read-only filesystem.
# capture-then-match — `docker logs | grep -q` under pipefail SIGPIPEs the
# producer on a match, which here would read the error as ABSENT (false pass).
if grep -qiE "mkdir '/app/.next/cache'|EROFS|read-only file system" <<<"$(docker logs "${C}" 2>&1)"; then
    echo "homepage could not write /app/.next/cache" >&2
    exit 1
fi
