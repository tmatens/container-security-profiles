#!/usr/bin/env bash
# Fetch the profile schema + validator from the pinned compose-lint commit into
# .contract/ (gitignored). The catalog is tied to compose-lint ONLY by this
# versioned schema contract — never vendored, never a code dependency.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
ref="$(grep -oiE '[0-9a-f]{40}' "$here/contract/compose-lint.ref" | head -1 || true)"
[ -n "$ref" ] || { echo "no pinned 40-char SHA in contract/compose-lint.ref" >&2; exit 1; }
dest="$here/.contract"; mkdir -p "$dest"
base="https://raw.githubusercontent.com/tmatens/compose-lint/${ref}"
curl -fsSL "$base/src/compose_lint/profiles/schema/profile.schema.json" -o "$dest/profile.schema.json"
curl -fsSL "$base/scripts/validate_profiles.py" -o "$dest/validate_profiles.py"
echo "fetched contract from compose-lint@${ref:0:12}"
