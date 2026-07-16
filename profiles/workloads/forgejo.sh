#!/usr/bin/env bash
# Workload exerciser for the forgejo reference image.
#
# The forgejo container runs two root daemons under s6 — `gitea web` (drops
# root -> git via su-exec) and `sshd` (root, with OpenSSH privilege separation) —
# and a faithful minimum must keep BOTH working. This drives a representative
# round-trip across the whole surface:
#   - web/API up (/api/v1/version);
#   - a real DB + git write: create an admin user (sqlite write as the git user),
#     create a repo via the API, commit a file through the contents API (a real
#     server-side git write as the git user), then read the packfile path back
#     with git ls-remote over smart HTTP;
#   - sshd REACHES authentication: an unauthenticated connection returns
#     "Permission denied (publickey)" only if the pre-auth privsep child forked
#     (chroot + setuid) — the signal that git-over-SSH is alive.
# Returns 0 if every step succeeds. The non-root privilege-drop is asserted by the
# drop-test correctness check (see the criteria doc), not here.
#
# Probes exec as the git user (never root — a root probe's own needs would
# pollute the derived minimum) and write nothing outside forgejo's own store
# (no probe clone into /tmp: a probe temp file would false-require a tmpfs
# candidate if the filesystem dimension is ever derived).
#
# Required env: FORGEJOCONTAINER (target container name or id).
set -euo pipefail

: "${FORGEJOCONTAINER:?FORGEJOCONTAINER must be set}"
C="${FORGEJOCONTAINER}"

# Throwaway fixture credentials (ephemeral container, destroyed after the run).
U=csdprobe; P=csdprobe-pw-12345; E=csd@probe.local

deadline=$((SECONDS + 45))
until [ "$(docker exec --user git "$C" curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/api/v1/version 2>/dev/null)" = 200 ]; do
    if (( SECONDS >= deadline )); then
        echo "forgejo API /api/v1/version never returned 200" >&2
        exit 1
    fi
    sleep 1
done

docker exec --user git "$C" /usr/local/bin/gitea admin user create \
    --username "$U" --password "$P" --email "$E" --admin --must-change-password=false >/dev/null

rc="$(docker exec --user git "$C" curl -s -o /dev/null -w '%{http_code}' -u "$U:$P" \
    -H 'Content-Type: application/json' -d '{"name":"probe","auto_init":true}' \
    http://localhost:3000/api/v1/user/repos)"
if [ "$rc" != 201 ]; then
    echo "repo create via API returned HTTP $rc (expected 201)" >&2
    exit 1
fi

# Server-side git write: the contents API makes forgejo itself commit the file
# (git plumbing runs as the git user inside the target — no client clone, no
# probe writes outside forgejo's own store).
rc="$(docker exec --user git "$C" curl -s -o /dev/null -w '%{http_code}' -u "$U:$P" \
    -X POST -H 'Content-Type: application/json' \
    -d '{"content":"Y3NkLXByb2JlCg==","message":"probe"}' \
    http://localhost:3000/api/v1/repos/$U/probe/contents/probe.txt)"
if [ "$rc" != 201 ]; then
    echo "contents API commit returned HTTP $rc (expected 201)" >&2
    exit 1
fi

# Smart-HTTP git read path (upload-pack advertisement), no on-disk checkout.
refs="$(docker exec --user git "$C" env GIT_TERMINAL_PROMPT=0 \
    git ls-remote "http://$U:$P@localhost:3000/$U/probe.git" 2>&1)" || {
    echo "git ls-remote over HTTP failed: ${refs##*$'\n'}" >&2
    exit 1
}
if ! grep -q 'refs/heads/' <<<"$refs"; then
    echo "ls-remote returned no heads (git smart HTTP broken)" >&2
    exit 1
fi

sshout="$(docker exec --user git "$C" ssh -p 22 -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
    -o ConnectTimeout=6 -o PreferredAuthentications=publickey git@localhost true 2>&1 || true)"
if ! grep -q 'Permission denied' <<<"$sshout"; then
    echo "sshd never reached auth (privsep failed -> git-over-SSH dead): ${sshout##*$'\n'}" >&2
    exit 1
fi
