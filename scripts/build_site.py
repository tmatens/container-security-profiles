#!/usr/bin/env python3
"""Build the static catalog-browsing site (GitHub Pages).

Reads catalog/**/*.yaml + criteria/**/*.md + profiles/workloads/*.sh and emits a
self-contained static site (no external assets) into --out. Pure presentation:
the acceptance contract lives in compose-lint's validator (make validate), not
here — this script must never gate or mutate catalog content.

Usage: python scripts/build_site.py [--out _site]
"""

import argparse
import html
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import markdown
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
REPO_URL = "https://github.com/tmatens/container-security-profiles"

CSS = """
:root { --bg:#ffffff; --fg:#1a1f24; --muted:#5b6570; --line:#d9dee3; --accent:#0b5fa5;
        --card:#f5f7f9; --ok:#1a7f37; --warn:#9a6700; --code:#eef1f4; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#0f1418; --fg:#e2e8ee; --muted:#98a4b0; --line:#2b333b; --accent:#5aa9e6;
          --card:#171e24; --ok:#4ac26b; --warn:#d4a72c; --code:#1c242b; }
}
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--fg);
       font:16px/1.55 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 62rem; margin: 0 auto; padding: 1.5rem 1rem 4rem; }
h1 { font-size:1.6rem; margin:.5rem 0 .25rem; }
h2 { font-size:1.2rem; margin:2rem 0 .5rem; border-bottom:1px solid var(--line); padding-bottom:.25rem; }
h3 { font-size:1.05rem; margin:1.25rem 0 .4rem; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
p.lead, .muted { color: var(--muted); }
code, pre { font:.85em/1.5 ui-monospace, "SF Mono", Menlo, Consolas, monospace;
            background: var(--code); border-radius:4px; }
code { padding:.1em .3em; }
pre { padding:.8rem 1rem; overflow-x:auto; }
pre code { background:none; padding:0; }
.tablewrap { overflow-x:auto; }
table { border-collapse: collapse; width:100%; font-size:.92rem; }
th, td { text-align:left; padding:.45rem .6rem; border-bottom:1px solid var(--line);
         vertical-align: top; }
th { color:var(--muted); font-weight:600; white-space:nowrap; }
.badge { display:inline-block; font-size:.75rem; font-weight:600; padding:.05rem .45rem;
         border-radius:99px; border:1px solid var(--line); white-space:nowrap; }
.badge.ok { color:var(--ok); border-color:var(--ok); }
.badge.warn { color:var(--warn); border-color:var(--warn); }
.badge.dim { color:var(--muted); }
.card { background:var(--card); border:1px solid var(--line); border-radius:8px;
        padding: .9rem 1.1rem; margin: .8rem 0; }
input#filter { width:100%; max-width:24rem; padding:.45rem .7rem; margin:.6rem 0 1rem;
               border:1px solid var(--line); border-radius:6px; background:var(--bg);
               color:var(--fg); font-size:.95rem; }
footer { margin-top:3rem; border-top:1px solid var(--line); padding-top:1rem;
         color:var(--muted); font-size:.85rem; }
.copybtn { float:right; font-size:.78rem; padding:.15rem .6rem; margin:.2rem 0 .2rem .6rem;
           border:1px solid var(--line); border-radius:6px; background:var(--card);
           color:var(--fg); cursor:pointer; }
.copybtn:hover { border-color: var(--accent); }
details summary { cursor:pointer; color:var(--accent); margin:.4rem 0; }
.crumb { font-size:.85rem; color:var(--muted); margin-bottom:.5rem; }
"""

FILTER_JS = """
document.getElementById('filter').addEventListener('input', function () {
  var q = this.value.toLowerCase();
  document.querySelectorAll('table.catalog tbody tr').forEach(function (tr) {
    tr.style.display = tr.textContent.toLowerCase().includes(q) ? '' : 'none';
  });
});
"""

COPY_JS = """
document.querySelectorAll('.copybtn').forEach(function (btn) {
  btn.addEventListener('click', function () {
    navigator.clipboard.writeText(document.getElementById(btn.dataset.target).textContent)
      .then(function () { btn.textContent = 'copied';
        setTimeout(function () { btn.textContent = 'copy'; }, 1200); });
  });
});
"""


def esc(value):
    return html.escape(str(value), quote=True)


def page(title, body, root, generated, commit):
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<style>{CSS}</style>
</head>
<body>
<main>
{body}
<footer>
Generated {esc(generated)} from <a href="{REPO_URL}/tree/{esc(commit)}">{esc(commit[:12])}</a>.
Profiles are minimums for the recorded invocation and workload — read each
profile's criteria before adopting. Derived by container-sec-derive (csd, not
yet published — each profile carries the evidence to reproduce it), consumed by
<a href="https://github.com/tmatens/compose-lint">compose-lint</a>.
Wrong for your deployment? <a href="{REPO_URL}/issues/new?template=profile-mismatch.yml">Report a mismatch</a>.
</footer>
</main>
</body>
</html>
"""


def leading_comment(path):
    """The catalog files carry their story in a leading # comment block."""
    lines = []
    for raw in path.read_text().splitlines():
        if raw.startswith("#"):
            lines.append(raw.lstrip("#").strip())
        else:
            break
    return "\n".join(lines).strip()


def load_profiles():
    profiles = []
    for path in sorted((REPO_ROOT / "catalog").rglob("*.yaml")):
        rel = path.relative_to(REPO_ROOT / "catalog")
        data = yaml.safe_load(path.read_text())
        criteria = REPO_ROOT / "criteria" / rel.with_suffix(".md")
        profiles.append({
            "rel": rel,                      # e.g. docker.io/library/postgres.yaml
            "path": path,
            "data": data,
            "notes": leading_comment(path),
            "raw": path.read_text(),
            "criteria": criteria if criteria.exists() else None,
        })
    return profiles


def dim_summary(name, dim):
    if name == "capabilities":
        add = dim.get("cap_add") or []
        return "cap_drop: ALL" + (f" + cap_add: {', '.join(add)}" if add else " (no cap_add)")
    if name == "filesystem":
        tmpfs = dim.get("tmpfs") or []
        ro = "read_only: true" if dim.get("read_only") else "read_only: false"
        return ro + (f" + tmpfs: {', '.join(tmpfs)}" if tmpfs else ", no tmpfs")
    return name


def compose_snippet(profile):
    data = profile["data"]
    image = data["image"]
    tags = (data.get("applies_to") or {}).get("tags") or []
    service = image.rsplit("/", 1)[-1]
    lines = [f"services:", f"  {service}:",
             f"    image: {image}:{tags[0] if tags else '<tag>'}"]
    for name, dim in (data.get("dimensions") or {}).items():
        if name == "capabilities":
            lines.append(f"    cap_drop: [{', '.join(dim.get('cap_drop') or [])}]")
            add = dim.get("cap_add") or []
            if add:
                lines.append(f"    cap_add: [{', '.join(add)}]")
        elif name == "filesystem":
            lines.append(f"    read_only: {'true' if dim.get('read_only') else 'false'}")
            tmpfs = dim.get("tmpfs") or []
            if tmpfs:
                lines.append("    tmpfs:")
                lines.extend(f"      - {t}" for t in tmpfs)
        sec = ((dim.get("derivation") or {}).get("run_config") or {}).get("security_opt")
        if sec and not any(l.startswith("    security_opt") for l in lines):
            lines.append(f"    security_opt: [{', '.join(f'\"{s}\"' for s in sec)}]")
    return "\n".join(lines) + "\n"


def kv_table(pairs):
    rows = "".join(
        f"<tr><th>{esc(k)}</th><td>{v}</td></tr>"
        for k, v in pairs if v not in (None, "", [], {})
    )
    return f'<div class="tablewrap"><table>{rows}</table></div>'


def confidence_badge(confidence):
    cls = {"high": "ok", "moderate": "warn"}.get(confidence, "dim")
    return f'<span class="badge {cls}">{esc(confidence)}</span>'


def status_badge(status):
    cls = "ok" if status == "validated" else "warn"
    return f'<span class="badge {cls}">{esc(status)}</span>'


def freshness_badge(rel, freshness):
    """Pin-freshness badge for a profile, from check_staleness.py --json output.

    Reflects whether the profile's pinned digest still matches the tag's current
    published digest as of the recorded check — NOT whether a newer version tag
    exists (that is Renovate's concern). Returns '' when no freshness data is
    available (e.g. a local build without --freshness), so it degrades cleanly.
    """
    entry = (freshness.get("profiles") or {}).get(rel)
    if not entry:
        return ""
    checked = esc((freshness.get("checked_at") or "")[:10])
    status = entry.get("status")
    if status == "fresh":
        return (f'<span class="badge ok" title="Pinned digest still matches the tag&#39;s '
                f'current published digest (checked {checked}).">pin current</span>')
    if status == "stale":
        return (f'<span class="badge warn" title="Upstream republished this tag since '
                f'derivation (checked {checked}); re-derivation pending.">pin stale</span>')
    reason = esc(entry.get("reason", "freshness not checked"))
    return f'<span class="badge dim" title="{reason}">pin unchecked</span>'


def render_drop_test(drop_test):
    checks = (drop_test or {}).get("checks") or []
    if not checks:
        return ""
    rows = "".join(
        "<tr><td><code>{}</code></td><td>{}</td><td>{}</td></tr>".format(
            esc(c.get("removed")),
            '<span class="badge warn">required</span>' if c.get("required")
            else '<span class="badge ok">removable</span>',
            esc(c.get("observed", "")))
        for c in checks
    )
    return ("<h3>Drop-test evidence</h3>"
            '<p class="muted">Each candidate removed in turn, the container restarted, '
            "and the workload re-verified.</p>"
            '<div class="tablewrap"><table><thead><tr><th>Removed</th><th>Verdict</th>'
            f"<th>Observed</th></tr></thead><tbody>{rows}</tbody></table></div>")


def render_app_tier(atv):
    if not atv:
        return ""
    over = atv.get("over_hardening") or {}
    pairs = [
        ("service", esc(f"{atv.get('service')} {atv.get('service_version', '')}".strip())),
        ("method", f"<code>{esc(atv.get('method'))}</code>"),
        ("check", esc(atv.get("check"))),
        ("result", status_badge("validated") if atv.get("result") == "pass"
         else esc(atv.get("result"))),
        ("verified", esc(atv.get("verified_date"))),
    ]
    if over:
        pairs.append(("over-hardening probe",
                      esc(f"{over.get('applied')} → {over.get('result')}")))
    return ("<h3>App-tier verification</h3>"
            '<p class="muted">The hardening verified at the service level — the full stack '
            "brought up with the minimum applied and driven via its real API.</p>"
            + kv_table(pairs))


def render_derivation(deriv):
    backend = deriv.get("observation_backend") or {}
    digest = deriv.get("validated_image", "")
    if "@sha256:" in digest:
        ref, sha = digest.split("@sha256:")
        digest_html = f'<code title="sha256:{esc(sha)}">{esc(ref)}@sha256:{esc(sha[:12])}…</code>'
    else:
        digest_html = f"<code>{esc(digest)}</code>"
    return kv_table([
        ("tool", f"<code>{esc(deriv.get('tool'))} {esc(deriv.get('tool_version'))}</code>"),
        ("observer", f"<code>{esc(deriv.get('observer'))}</code>"),
        ("validated image", digest_html),
        ("validated date", esc(deriv.get("validated_date"))),
        ("confidence", confidence_badge(deriv.get("confidence"))),
        ("validated via", ", ".join(f"<code>{esc(v)}</code>"
                                    for v in deriv.get("validated_via") or [])),
        ("workload", f"<code>{esc(deriv.get('workload'))}</code>"),
        ("workload sha256", f"<code>{esc((deriv.get('workload_sha256') or '')[:12])}…</code>"),
        ("ig version", f"<code>{esc(backend.get('ig_version'))}</code>"
         if backend.get("ig_version") else None),
    ])


def render_run_config(rc):
    if not rc:
        return ""
    pairs = [(k, "<br>".join(f"<code>{esc(v)}</code>" for v in val)
              if isinstance(val, list) else f"<code>{esc(val)}</code>")
             for k, val in rc.items() if val not in ("", [], None)]
    if not pairs:
        return ""
    return ("<h3>Recorded invocation (run_config)</h3>"
            '<p class="muted">The minimum is valid for this invocation; a different '
            "<code>user:</code>, volume state, or entrypoint can change it.</p>"
            + kv_table(pairs))


def render_profile_page(profile, generated, commit, freshness):
    data = profile["data"]
    rel = profile["rel"]
    depth = len(rel.parts)  # parts incl. filename; page lives under profiles/<rel>.html
    root = "../" * depth
    image = data["image"]
    tags = (data.get("applies_to") or {}).get("tags") or []
    fresh = freshness_badge(rel.as_posix(), freshness)
    body = [f'<div class="crumb"><a href="{root}index.html">catalog</a> / {esc(rel.with_suffix(""))}</div>']
    body.append(f"<h1><code>{esc(image)}</code></h1>")
    body.append('<p class="lead">' + status_badge(data.get("status", ""))
                + (" &nbsp;" + fresh if fresh else "")
                + " &nbsp;tags: " + ", ".join(f"<code>{esc(t)}</code>" for t in tags) + "</p>")

    if profile["notes"]:
        body.append(f'<div class="card"><pre style="white-space:pre-wrap;background:none;'
                    f'padding:0;margin:0">{esc(profile["notes"])}</pre></div>')

    snippet = compose_snippet(profile)
    body.append("<h2>Use it</h2>")
    body.append('<button class="copybtn" data-target="snippet">copy</button>')
    body.append(f'<pre><code id="snippet">{esc(snippet)}</code></pre>')
    if len(data.get("dimensions") or {}) > 1:
        body.append(
            '<p class="muted">This profile has multiple dimensions and is applied '
            "as a unit. Dimensions can interact — a capability can be required "
            "only <em>because</em> of a sibling read-only/tmpfs recommendation — "
            "so where they do, the minimum was derived under the sibling "
            "dimension's context. See the criteria doc and each dimension's "
            "recorded invocation below before applying them separately.</p>")

    for name, dim in (data.get("dimensions") or {}).items():
        deriv = dim.get("derivation") or {}
        body.append(f"<h2>Dimension: {esc(name)}</h2>")
        body.append(f"<p><strong>{esc(dim_summary(name, dim))}</strong></p>")
        body.append(render_derivation(deriv))
        body.append(render_drop_test(deriv.get("drop_test")))
        body.append(render_run_config(deriv.get("run_config")))

        workload = deriv.get("workload")
        wpath = REPO_ROOT / workload if workload else None
        if wpath and wpath.exists():
            body.append(f"<details><summary>Workload script (<code>{esc(workload)}</code>)"
                        f"</summary><pre><code>{esc(wpath.read_text())}</code></pre></details>")

    body.append(render_app_tier(data.get("app_tier_verified")))

    body.append("<h2>Evidence &amp; provenance</h2><ul>")
    if profile["criteria"]:
        body.append(f'<li><a href="{root}criteria/{esc(rel.with_suffix(".html"))}">'
                    "Validation criteria</a> — per-image scenarios and pass criteria</li>")
    body.append(f'<li><a href="{REPO_URL}/blob/main/catalog/{esc(rel)}">Profile source</a>'
                " in the repository</li></ul>")
    body.append(f'<details><summary>Raw profile YAML</summary>'
                f"<pre><code>{esc(profile['raw'])}</code></pre></details>")
    body.append(f"<script>{COPY_JS}</script>")
    return page(f"{image} — container security profile", "\n".join(body), root,
                generated, commit)


def render_criteria_page(profile, generated, commit):
    rel = profile["rel"]
    root = "../" * len(rel.parts)
    md = markdown.markdown(profile["criteria"].read_text(),
                           extensions=["fenced_code", "tables"])
    body = (f'<div class="crumb"><a href="{root}index.html">catalog</a> / '
            f'<a href="{root}profiles/{esc(rel.with_suffix(".html"))}">'
            f'{esc(profile["data"]["image"])}</a> / criteria</div>\n' + md)
    return page(f"{profile['data']['image']} — validation criteria", body, root,
                generated, commit)


def render_index(profiles, generated, commit, freshness):
    n_validated = sum(1 for p in profiles if p["data"].get("status") == "validated")
    checked = (freshness.get("checked_at") or "")[:10]
    fresh_legend = (
        '<p class="muted"><strong>Pin</strong> column — '
        '<span class="badge ok">pin current</span> the pinned digest still matches the '
        "tag&#39;s latest published digest; "
        '<span class="badge warn">pin stale</span> upstream republished the tag, re-derivation '
        "pending; "
        '<span class="badge dim">pin unchecked</span> registry not queried. Tracks '
        "<em>digest drift on the pinned tag</em>, not whether a newer version tag exists."
        + (f" Checked {esc(checked)}." if checked else "")
        + "</p>"
    ) if freshness.get("profiles") else ""
    rows = []
    for p in profiles:
        data = p["data"]
        rel = p["rel"]
        href = f"profiles/{rel.with_suffix('.html')}"
        tags = ", ".join((data.get("applies_to") or {}).get("tags") or [])
        # One row per image; each dimension is a line in the minimum cell (a
        # profile's dimensions are one artifact, applied as a unit).
        fresh = freshness_badge(rel.as_posix(), freshness)
        dim_lines = []
        dates = []
        for name, dim in (data.get("dimensions") or {}).items():
            deriv = dim.get("derivation") or {}
            dim_lines.append(
                f"<div>{esc(name)} — <code>{esc(dim_summary(name, dim))}</code> "
                f"{confidence_badge(deriv.get('confidence'))}</div>")
            if deriv.get("validated_date"):
                dates.append(str(deriv["validated_date"]))
        rows.append(
            "<tr>"
            f'<td><a href="{esc(href)}"><code>{esc(data["image"])}</code></a></td>'
            f"<td><code>{esc(tags)}</code></td>"
            f"<td>{''.join(dim_lines)}</td>"
            f"<td>{'<span class=\"badge ok\">app-tier</span>' if data.get('app_tier_verified') else ''}</td>"
            f"<td>{esc(max(dates) if dates else '')}</td>"
            f"<td>{fresh}</td>"
            "</tr>")
    body = f"""
<h1>Container security profiles</h1>
<p class="lead">Evidence-backed <strong>minimum-security profiles for container images</strong> —
the capabilities and read-only-filesystem config each image actually needs, derived by
drop-test and live eBPF observation (container-sec-derive) and consumed by
<a href="https://github.com/tmatens/compose-lint">compose-lint</a> as fix-guidance enrichment.</p>
<p class="muted">{n_validated} validated profiles. Every profile is digest-pinned, backed by a
committed workload, and carries its full derivation evidence — click through for the
drop-test table, recorded invocation, and validation criteria. Confidence:
<span class="badge ok">high</span> = the workload deterministically exercises the derived
surface; <span class="badge warn">moderate</span> = the image's feature surface is larger
than any workload can bound — read the criteria for what's covered.
Missing an image? <a href="{REPO_URL}/issues/new?template=profile-request.yml">Request a profile</a>.</p>
{fresh_legend}
<input id="filter" type="search" placeholder="Filter — image, capability, dimension…" aria-label="Filter profiles">
<div class="tablewrap">
<table class="catalog">
<thead><tr><th>Image</th><th>Tags</th><th>Derived minimum (per dimension)</th>
<th></th><th>Validated</th><th>Pin</th></tr></thead>
<tbody>{''.join(rows)}</tbody>
</table>
</div>
<h2>Reading a profile</h2>
<p>A profile is the <em>minimum</em> for the <strong>recorded invocation</strong> (the
<code>run_config</code> block) exercised by the <strong>committed workload</strong> — not a
universal truth about the image. Startup-only needs (a data-dir <code>chown</code>, a
root→user privilege drop) are derived by drop-test, which catches what runtime
observation is blind to. Read the criteria doc before adopting a profile — and if it
breaks your deployment, that's signal:
<a href="{REPO_URL}/issues/new?template=profile-mismatch.yml">report the mismatch</a>.</p>
<script>{FILTER_JS}</script>
"""
    return page("Container security profiles — catalog", body, "", generated, commit)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="_site")
    parser.add_argument("--freshness", type=Path, default=None,
                        help="optional freshness JSON from check_staleness.py --json")
    args = parser.parse_args()
    out = Path(args.out)

    freshness = {}
    if args.freshness and args.freshness.exists():
        try:
            freshness = json.loads(args.freshness.read_text())
        except (ValueError, OSError) as exc:  # enrichment only — never fail the build
            print(f"warning: ignoring unreadable freshness {args.freshness}: {exc}",
                  file=sys.stderr)

    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    try:
        commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT,
                                capture_output=True, text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        commit = "unknown"

    profiles = load_profiles()
    if not profiles:
        print("no profiles found under catalog/", file=sys.stderr)
        return 1

    (out).mkdir(parents=True, exist_ok=True)
    (out / ".nojekyll").write_text("")
    (out / "index.html").write_text(render_index(profiles, generated, commit, freshness))
    for p in profiles:
        dest = out / "profiles" / p["rel"].with_suffix(".html")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(render_profile_page(p, generated, commit, freshness))
        if p["criteria"]:
            cdest = out / "criteria" / p["rel"].with_suffix(".html")
            cdest.parent.mkdir(parents=True, exist_ok=True)
            cdest.write_text(render_criteria_page(p, generated, commit))

    pages = sum(1 for _ in out.rglob("*.html"))
    print(f"built {pages} pages for {len(profiles)} profiles into {out}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
