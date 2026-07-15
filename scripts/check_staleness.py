#!/usr/bin/env python3
"""Flag catalog profiles whose pinned digest no longer matches the tag's current
published digest — the "re-derive on digest bump" trigger (compose-lint#360 step 4).

For each profile with an ``applies_to.tags`` scope, this resolves the current
digest of ``image:<first concrete tag>`` from the registry and compares it to
each dimension's ``derivation.validated_image`` digest. A mismatch means upstream
republished the tag: the profile was derived against a now-superseded artifact
and should be re-derived on the BPF runner.

Pure stdlib + public-registry anonymous auth — no docker, no secret, runs on any
runner. Docker Hub (``docker.io``) images are supported; other registries are
reported as unchecked rather than failing.

    python scripts/check_staleness.py --catalog-dir catalog
    python scripts/check_staleness.py --catalog-dir catalog --json freshness.json

Exit 0 = all fresh (or unchecked). Exit 1 = at least one stale profile.

``--json`` additionally writes a per-profile freshness record (fresh / stale /
unchecked + digests + ``checked_at``) for the site build to render — the exit
code and stdout are unchanged, so it stays a drop-in for the tracking-issue job.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import yaml

_ACCEPT = ", ".join(
    [
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
        "application/vnd.oci.image.manifest.v1+json",
    ]
)


def _dockerhub_repo(image: str) -> str | None:
    """Return the Docker Hub repository path for a normalized image ref, or None
    if it is not a docker.io image (other registries are not queried here)."""
    if image.startswith("docker.io/"):
        return image[len("docker.io/") :]
    return None


def current_digest(repo: str, tag: str) -> str:
    """Current manifest-list digest of docker.io ``repo:tag`` (anonymous pull)."""
    token_url = (
        "https://auth.docker.io/token?service=registry.docker.io"
        f"&scope=repository:{repo}:pull"
    )
    token = json.load(urllib.request.urlopen(token_url, timeout=20))["token"]
    req = urllib.request.Request(
        f"https://registry-1.docker.io/v2/{repo}/manifests/{tag}", method="HEAD"
    )
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", _ACCEPT)
    with urllib.request.urlopen(req, timeout=20) as resp:
        return resp.headers.get("Docker-Content-Digest", "")


def _concrete_tag(doc: dict) -> str | None:
    for tag in (doc.get("applies_to") or {}).get("tags", []):
        if "*" not in tag:
            return tag
    return None


def _pinned_digests(doc: dict) -> set[str]:
    digests = set()
    for dim in doc.get("dimensions", {}).values():
        vi = dim.get("derivation", {}).get("validated_image", "")
        if "@" in vi:
            digests.add(vi.split("@", 1)[1])
    return digests


def check(catalog_dir: Path, json_path: Path | None = None) -> int:
    stale = 0
    results: dict[str, dict] = {}
    for path in sorted(catalog_dir.rglob("*.y*ml")):
        label = path.relative_to(catalog_dir).as_posix()
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        if not isinstance(doc, dict):
            continue
        image = doc.get("image", "")
        repo = _dockerhub_repo(image)
        tag = _concrete_tag(doc)
        entry = {"image": image, "tag": tag}
        if repo is None:
            print(f"SKIP {label}: {image} is not a docker.io image (not checked)")
            results[label] = {**entry, "status": "unchecked",
                              "reason": "registry not queried (only docker.io is checked)"}
            continue
        if tag is None:
            print(f"SKIP {label}: no concrete applies_to.tags to check against")
            results[label] = {**entry, "status": "unchecked",
                              "reason": "no concrete applies_to.tags to check against"}
            continue
        try:
            current = current_digest(repo, tag)
        except Exception as exc:  # network / auth / not-found
            print(f"WARN {label}: could not resolve {image}:{tag}: {exc}")
            results[label] = {**entry, "status": "unchecked",
                              "reason": f"could not resolve {image}:{tag}: {exc}"}
            continue
        pinned = sorted(_pinned_digests(doc))
        entry.update(current_digest=current, pinned=pinned)
        if current in pinned:
            print(f"OK   {label}: {image}:{tag} still {current[:19]}…")
            results[label] = {**entry, "status": "fresh"}
        else:
            stale += 1
            print(
                f"STALE {label}: {image}:{tag} is now {current[:19]}…, "
                f"profile pinned {', '.join(d[:19] + '…' for d in pinned)} — re-derive"
            )
            results[label] = {**entry, "status": "stale"}
    print(f"\n{stale} stale profile(s).")
    if json_path is not None:
        payload = {
            "checked_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "profiles": results,
        }
        json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {json_path} ({len(results)} profiles)")
    return 1 if stale else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog-dir", type=Path, default=Path("catalog"))
    parser.add_argument("--json", type=Path, default=None,
                        help="also write per-profile freshness (fresh/stale/unchecked) here")
    args = parser.parse_args(argv)
    if not args.catalog_dir.is_dir():
        print(f"no catalog dir at {args.catalog_dir}")
        return 0
    return check(args.catalog_dir, args.json)


if __name__ == "__main__":
    sys.exit(main())
