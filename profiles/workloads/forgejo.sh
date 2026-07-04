#!/usr/bin/env bash
# Workload exerciser for the forgejo reference image.
#
# The forgejo container runs two root daemons under s6 — `gitea web` (drops
# root -> git via su-exec) and `sshd` (root, with OpenSSH privilege separation) —
# and a faithful minimum must keep BOTH working. This drives a representative
# round-trip across the whole surface:
#   - web/API up (/api/v1/version);
#   - a real DB + git write: create an admin user (sqlite write as the git user),
#     create a repo via the API, then clone + commit + push over HTTP;
#   - sshd REACHES authentication: an unauthenticated connection returns
#     "Permission denied (publickey)" only if the pre-auth privsep child forked
#     (chroot + setuid) — the signal that git-over-SSH is alive.
# Returns 0 if every step succeeds. The non-root privilege-drop is asserted by the
# drop-test correctness check (see the criteria doc), not here.
#
# Required env: FORGEJOCONTAINER (target container name or id).
set -euo pipefail

: "${FORGEJOCONTAINER:?FORGEJOCONTAINER must be set}"
C="${FORGEJOCONTAINER}"

# Throwaway fixture credentials (ephemeral container, destroyed after the run).
U=csdprobe; P=csdprobe-pw-12345; E=csd@probe.local

deadline=$((SECONDS + 45))
until [ "$(docker exec "$C" curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/api/v1/version 2>/dev/null)" = 200 ]; do
    if (( SECONDS >= deadline )); then
        echo "forgejo API /api/v1/version never returned 200" >&2
        exit 1
    fi
    sleep 1
done

docker exec "$C" su-exec git /usr/local/bin/gitea admin user create \
    --username "$U" --password "$P" --email "$E" --admin --must-change-password=false >/dev/null

rc="$(docker exec "$C" curl -s -o /dev/null -w '%{http_code}' -u "$U:$P" \
    -H 'Content-Type: application/json' -d '{"name":"probe","auto_init":true}' \
    http://localhost:3000/api/v1/user/repos)"
if [ "$rc" != 201 ]; then
    echo "repo create via API returned HTTP $rc (expected 201)" >&2
    exit 1
fi

docker exec "$C" sh -c "set -e; export GIT_TERMINAL_PROMPT=0; cd /tmp && rm -rf p && \
    git clone -q http://$U:$P@localhost:3000/$U/probe.git p && cd p && \
    git -c user.email=$E -c user.name=$U commit --allow-empty -q -m probe && \
    git push -q http://$U:$P@localhost:3000/$U/probe.git"

sshout="$(docker exec "$C" ssh -p 22 -o StrictHostKeyChecking=no -o BatchMode=yes \
    -o ConnectTimeout=6 -o PreferredAuthentications=publickey git@localhost true 2>&1 || true)"
if ! grep -q 'Permission denied' <<<"$sshout"; then
    echo "sshd never reached auth (privsep failed -> git-over-SSH dead): ${sshout##*$'\n'}" >&2
    exit 1
fi
