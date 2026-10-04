#!/usr/bin/env python3
"""Validate a release and prepare its checksum manifest and Homebrew cask."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION_RE = re.compile(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?")


def version_for(tag=None):
    version = (ROOT / "VERSION").read_text().strip()
    if not VERSION_RE.fullmatch(version):
        raise ValueError("VERSION must contain a release version such as 0.1.0-alpha")
    if tag is not None and tag != f"v{version}":
        raise ValueError(f"Tag {tag!r} does not match VERSION v{version}")
    return version


def render(repository, dist, tag=None):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Repository must be owner/name")
    version = version_for(tag)
    name = f"MacFanController_v{version}_aarch64.dmg"
    dmg = dist / name
    if not dmg.is_file() or dmg.stat().st_size == 0:
        raise ValueError(f"Missing or empty release artifact: {dmg}")
    sha = hashlib.sha256(dmg.read_bytes()).hexdigest()
    template = (ROOT / ".github/homebrew/mac-fan-controller.rb.template").read_text()
    cask = template.replace("{{VERSION}}", version).replace("{{SHA256}}", sha).replace("{{REPOSITORY}}", repository)
    # Homebrew expands appdir when executing declarative postflight steps.
    unresolved = cask.replace("{{appdir}}", "")
    if "{{" in unresolved or "}}" in unresolved:
        raise ValueError("Cask contains unresolved template fields")
    (dist / "mac-fan-controller.rb").write_text(cask)
    (dist / "SHA256SUMS").write_text(f"{sha}  {name}\n")
    metadata = {"version": version, "tag": f"v{version}", "dmg_name": name, "sha256": sha,
                "repository": repository, "prerelease": "-" in version}
    (dist / "release.json").write_text(json.dumps(metadata, indent=2) + "\n")
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag")
    parser.add_argument("--repository", default="tasnimzotder/mac-fan-controller")
    parser.add_argument("--dist", type=Path, default=ROOT / "dist")
    parser.add_argument("--check-version", action="store_true")
    args = parser.parse_args()
    try:
        if args.check_version:
            print(version_for(args.tag))
        else:
            print(json.dumps(render(args.repository, args.dist, args.tag)))
    except (ValueError, OSError) as error:
        parser.exit(1, f"Release validation failed: {error}\n")


if __name__ == "__main__":
    main()
