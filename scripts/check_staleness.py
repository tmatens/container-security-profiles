#!/usr/bin/env python3
"""Flag catalog profiles whose pinned digest no longer matches the tag's current
published digest — the "re-derive on digest bump" trigger (compose-lint#360 step 4).

For each profile with an ``applies_to.tags`` scope, this resolves the current
digest of ``image:<first concrete tag>`` from the registry and compares it to
each dimension's ``derivation.validated_image`` digest. A mismatch means upstream
republished the tag: the profile was derived against a now-superseded artifact
and should be re-derived on the BPF runner.

Pure stdlib + public-registry anonymous auth — no docker, no secret, runs on any
runner. Any registry speaking the OCI distribution API with an anonymous-pull
Bearer challenge is supported (docker.io, ghcr.io, codeberg.org, ...); an image
whose registry cannot be resolved is reported as unchecked rather than failing.

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
import re
import sys
import urllib.error
import urllib.parse
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


def _registry_repo(image: str) -> tuple[str, str] | None:
    """Split a normalized image ref into (registry API host, repository path),
    or None when there is no registry-qualified prefix to query.

    Catalog images are registry-qualified by contract (``docker.io/library/redis``,
    ``ghcr.io/owner/repo``). Docker Hub's API host differs from its image prefix."""
    host, _, repo = image.partition("/")
    if "." not in host or not repo:
        return None
    if host == "docker.io":
        host = "registry-1.docker.io"
    return host, repo


def _manifest_head(url: str, token: str | None) -> str:
    req = urllib.request.Request(url, method="HEAD")
    req.add_header("Accept", _ACCEPT)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=20) as resp:
        return resp.headers.get("Docker-Content-Digest", "")


def current_digest(host: str, repo: str, tag: str) -> str:
    """Current manifest-list digest of ``host/repo:tag`` via anonymous pull.

    Standard OCI distribution flow: HEAD the manifest; on 401, follow the
    ``WWW-Authenticate`` Bearer challenge to the registry's token endpoint for an
    anonymous pull token and retry. Works for docker.io, ghcr.io, codeberg.org."""
    url = f"https://{host}/v2/{repo}/manifests/{tag}"
    try:
        return _manifest_head(url, None)
    except urllib.error.HTTPError as exc:
        if exc.code != 401:
            raise
        challenge = dict(
            re.findall(r'(\w+)="([^"]*)"', exc.headers.get("WWW-Authenticate", ""))
        )
        realm = challenge.get("realm", "")
        if not realm.startswith("https://"):
            raise
        params = {"scope": f"repository:{repo}:pull"}
        if challenge.get("service"):
            params["service"] = challenge["service"]
        token_url = f"{realm}?{urllib.parse.urlencode(params)}"
        token = json.load(urllib.request.urlopen(token_url, timeout=20))["token"]
        return _manifest_head(url, token)


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
        registry = _registry_repo(image)
        tag = _concrete_tag(doc)
        entry = {"image": image, "tag": tag}
        if registry is None:
            print(f"SKIP {label}: {image} has no registry-qualified prefix (not checked)")
            results[label] = {**entry, "status": "unchecked",
                              "reason": "image is not registry-qualified"}
            continue
        if tag is None:
            print(f"SKIP {label}: no concrete applies_to.tags to check against")
            results[label] = {**entry, "status": "unchecked",
                              "reason": "no concrete applies_to.tags to check against"}
            continue
        try:
            current = current_digest(*registry, tag)
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
