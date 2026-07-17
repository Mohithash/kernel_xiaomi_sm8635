#!/usr/bin/env python3
"""Compare the pins in upstreams.json against the real upstreams.

Prints a markdown report to stdout and writes machine-readable results to
$GITHUB_OUTPUT (drift=true|false, ack_drift=true|false, summary=<one-liner>).

Deliberately read-only: it never bumps a pin, opens a PR, or triggers a build.
Discovering an upstream and deciding to ship it are different acts — the second
one needs a human who has booted the result.
"""
import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def short(v):
    """Abbreviate a 40-char SHA; leave tags and versions intact."""
    return v[:12] if re.fullmatch(r"[0-9a-f]{40}", v or "") else (v or "?")


def http_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "theettam-upstream-watch"})
    tok = os.environ.get("GITHUB_TOKEN")
    if tok and "api.github.com" in url:
        req.add_header("Authorization", f"token {tok}")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def ver_key(tag):
    """android14-6.1.175_r00 -> (175, 0); sorts numerically, not lexically."""
    m = re.search(r"android14-6\.1\.(\d+)_r(\d+)", tag)
    return (int(m.group(1)), int(m.group(2))) if m else (-1, -1)


def latest_ack(spec):
    out = subprocess.run(
        ["git", "ls-remote", "--tags", spec["url"], spec["tag_glob"]],
        capture_output=True, text=True, timeout=120,
    )
    tags = {
        t.split("refs/tags/")[1].replace("^{}", "")
        for t in out.stdout.splitlines() if "refs/tags/" in t
    }
    return max(tags, key=ver_key) if tags else None


def latest_github_tag(spec):
    tags = http_json(f"https://api.github.com/repos/{spec['repo']}/tags?per_page=100")
    names = [t["name"] for t in tags]
    # Prefer real version tags; fall back to whatever the repo's newest tag is.
    sem = [n for n in names if re.fullmatch(r"v?\d+(\.\d+)+", n)]
    if sem:
        return max(sem, key=lambda n: tuple(int(x) for x in n.lstrip("v").split(".")))
    return names[0] if names else None


def latest_github_branch(spec):
    d = http_json(f"https://api.github.com/repos/{spec['repo']}/branches/{spec['branch']}")
    return d["commit"]["sha"]


def latest_gitlab_branch(spec):
    proj = spec["project"].replace("/", "%2F")
    d = http_json(f"https://gitlab.com/api/v4/projects/{proj}/repository/branches/{spec['branch']}")
    return d["commit"]["id"]


RESOLVERS = {
    "git-tags": latest_ack,
    "github-tags": latest_github_tag,
    "github-branch": latest_github_branch,
    "gitlab-branch": latest_gitlab_branch,
}


def main():
    cfg = json.load(open(os.path.join(ROOT, "upstreams.json")))
    rows, drifted, ack_drift, errors = [], [], False, []

    for key, spec in cfg.items():
        if key.startswith("_"):
            continue
        try:
            latest = RESOLVERS[spec["kind"]](spec)
        except Exception as e:                       # network/API hiccup must not read as "no drift"
            errors.append(f"{spec['name']}: {type(e).__name__}: {e}")
            rows.append((spec["name"], short(spec["current"]), "ERROR", "⚠️"))
            continue

        if latest is None:
            errors.append(f"{spec['name']}: no versions found")
            rows.append((spec["name"], short(spec["current"]), "none found", "⚠️"))
            continue

        cur = spec["current"]
        same = latest == cur
        rows.append((spec["name"], short(cur), short(latest), "✅" if same else "🔔"))
        if not same:
            drifted.append((key, spec, cur, latest))
            if key == "ack":
                ack_drift = True

    print("## Upstream check\n")
    print("| Upstream | Pinned | Latest | |")
    print("|---|---|---|---|")
    for name, cur, latest, mark in rows:
        print(f"| {name} | `{cur}` | `{latest}` | {mark} |")

    if errors:
        print("\n### Could not check\n")
        for e in errors:
            print(f"- {e}")
        print("\n*(Treated as unknown, not as up-to-date.)*")

    if drifted:
        print("\n### New upstream available\n")
        for key, spec, cur, latest in drifted:
            print(f"- **{spec['name']}**: `{cur}` → `{latest}`")
            if spec.get("note"):
                print(f"  - {spec['note']}")
        print("\n### What to do\n")
        if ack_drift:
            print("- **ACK LTS bump** — merge `android14-6.1-lts` with a real 3-way merge from a "
                  "full-history clone of the device base; resolve conflicts toward the device side. "
                  "Do not apply mainline incrementals, and do not release without booting it.")
        if any(k != "ack" for k, _, _, _ in drifted):
            print("- **Driver/SUSFS bump** — update the pin in `.github/workflows/build-theettam-20.yml`, "
                  "run that workflow, and boot-test before promoting. The SUSFS hand-port grafts onto "
                  "driver internals, so a bump can move the anchors: if `integrate*.sh` asserts, the "
                  "anchor moved and the graft needs updating (this is the assert doing its job).")
    else:
        print("\nAll pins current.")

    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        names = ", ".join(s["name"] for _, s, _, _ in drifted) or "none"
        with open(out, "a") as f:
            f.write(f"drift={'true' if drifted else 'false'}\n")
            f.write(f"ack_drift={'true' if ack_drift else 'false'}\n")
            f.write(f"errors={'true' if errors else 'false'}\n")
            f.write(f"summary={names}\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
