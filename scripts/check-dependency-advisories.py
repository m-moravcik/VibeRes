#!/usr/bin/env python3
"""Fails when a pinned dependency is covered by a published security advisory.

VibeRes has exactly one third-party dependency, Sparkle, and it is pinned by
exact version — which is the right call for an updater, and also the reason
nothing tells you when an advisory lands against the pin. 2.9.4 sat three
advisories deep for over a month before a manual audit noticed.

Reads the pin out of project.yml, asks GitHub for that repository's advisories,
and compares. No dependencies beyond the standard library so it runs the same
way locally and in CI.

Usage:
  scripts/check-dependency-advisories.py           # check every pin
  GITHUB_TOKEN=... scripts/check-dependency-advisories.py   # higher rate limit
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Package pin in project.yml -> the GitHub repo whose advisories cover it.
# Explicit rather than derived from the URL so that a dependency added without
# a thought about this file shows up as a KeyError, not as silence.
ADVISORY_SOURCES = {
    "https://github.com/sparkle-project/Sparkle": "sparkle-project/Sparkle",
}


def parse_version(text: str) -> tuple[int, ...]:
    """'2.10.0' -> (2, 10, 0). Pre-release suffixes are dropped; a pin that
    carries one is not something this project ships."""
    core = re.split(r"[-+]", text.strip(), maxsplit=1)[0]
    return tuple(int(part) for part in core.split(".") if part.isdigit())


def satisfies(version: tuple[int, ...], clause: str) -> bool:
    """One comparator clause from a GitHub vulnerable_version_range."""
    match = re.match(r"\s*(>=|<=|>|<|=)?\s*([0-9][0-9A-Za-z.\-+]*)\s*$", clause)
    if not match:
        # An unparseable clause must not be read as "safe".
        raise ValueError(f"cannot parse version clause: {clause!r}")
    operator, bound_text = match.group(1) or "=", match.group(2)
    bound = parse_version(bound_text)
    if operator == ">=":
        return version >= bound
    if operator == "<=":
        return version <= bound
    if operator == ">":
        return version > bound
    if operator == "<":
        return version < bound
    return version == bound


def covers(version: tuple[int, ...], version_range: str) -> bool:
    """GitHub ranges are comma-separated clauses, all of which must hold."""
    return all(satisfies(version, clause) for clause in version_range.split(","))


def pinned_packages() -> dict[str, str]:
    """{package url: exact version} straight out of project.yml.

    Deliberately a narrow regex walk rather than a YAML parse: the repo has no
    third-party Python dependencies and this file is not worth adding one for.
    """
    text = (REPO_ROOT / "project.yml").read_text()
    packages_block = re.search(
        r"^packages:\n(.*?)(?=^\S)", text, re.MULTILINE | re.DOTALL
    )
    if not packages_block:
        return {}

    pins: dict[str, str] = {}
    url = None
    for line in packages_block.group(1).splitlines():
        if url_match := re.match(r"\s*url:\s*(\S+)", line):
            url = url_match.group(1)
        elif version_match := re.match(r"\s*exactVersion:\s*\"?([^\"\s]+)", line):
            if url:
                pins[url] = version_match.group(1)
                url = None
    return pins


def fetch_advisories(repo: str) -> list[dict]:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/security-advisories",
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "viberes-dependency-audit",
        },
    )
    if token := os.environ.get("GITHUB_TOKEN"):
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main() -> int:
    pins = pinned_packages()
    if not pins:
        print("no exact-version pins found in project.yml", file=sys.stderr)
        return 1

    hits: list[str] = []
    for url, version_text in sorted(pins.items()):
        repo = ADVISORY_SOURCES.get(url)
        if repo is None:
            print(f"error: no advisory source configured for {url}", file=sys.stderr)
            print("  add it to ADVISORY_SOURCES in this script", file=sys.stderr)
            return 1

        version = parse_version(version_text)
        try:
            advisories = fetch_advisories(repo)
        except (urllib.error.URLError, TimeoutError) as error:
            # A rate limit or a network blip must not read as "all clear".
            print(f"error: could not fetch advisories for {repo}: {error}", file=sys.stderr)
            return 1

        print(f"{repo} pinned at {version_text}: {len(advisories)} advisories published")
        for advisory in advisories:
            for vulnerability in advisory.get("vulnerabilities") or []:
                version_range = vulnerability.get("vulnerable_version_range")
                if not version_range:
                    continue
                if covers(version, version_range):
                    hits.append(
                        f"  {advisory.get('ghsa_id')} "
                        f"[{advisory.get('severity') or 'unrated'}] "
                        f"{version_range}\n"
                        f"    {(advisory.get('summary') or '').strip()}"
                    )

    if hits:
        print(f"\nerror: the pinned version is covered by {len(hits)} advisory range(s):")
        print("\n".join(hits))
        print("\nBump the pin in project.yml to a version outside every range,")
        print("rebuild, and re-run the release so the published appcast carries it.")
        return 1

    print("\nno advisory covers any pinned version")
    return 0


if __name__ == "__main__":
    sys.exit(main())
