#!/usr/bin/env python3
"""Freeze current sources in a detached worktree; tune only a test archive 901+.

Example: --source /tmp/frozen-baseline --destination /tmp/s11-candidate-901
         --version 901 --factor B01:boss:hp=1.15 --factor B01:boss:attack=1.5
The source/release archive is never edited. Candidate outputs must remain outside
the source checkout, and final published coefficients need their own version.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CHAPTERS = ("B01", "B02", "B03", "B04")
RANKS = ("normal", "elite", "boss")
FACTORS = ("hp", "attack", "skill")
SOURCE_DIRS = {"config", "data", "scripts", "scenes", "shaders", "tests", "tools", "docs", "localization", "assets"}


def git(source: Path, *args):
    return subprocess.check_output(["git", *args], cwd=source).decode().strip()


def digest(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--version", type=int)
    parser.add_argument("--factor", action="append", default=[])
    parser.add_argument("--cache", choices=("copy", "link-imports", "none"), default="copy")
    args = parser.parse_args()
    source, destination = args.source.resolve(), args.destination.resolve()
    if destination.exists() or destination == source or source in destination.parents:
        parser.error("Destination must be a new directory outside the source checkout")
    if args.factor and (args.version is None or not 901 <= args.version <= 1000):
        parser.error("Candidate factors require a unique test-only version in 901..1000")
    if args.version is not None and not 901 <= args.version <= 1000:
        parser.error("This utility must never edit a release archive version")
    if args.cache == "link-imports" and not (source / "s11_snapshot_overlay.json").exists():
        parser.error("Import hardlinks are only allowed from an already frozen S11 snapshot")
    changes = []
    for supplied in args.factor:
        try:
            address, raw = supplied.split("=", 1)
            chapter, rank, factor = address.split(":")
            amount = float(raw)
        except ValueError:
            parser.error("Factors use CHAPTER:rank:factor=number")
        if chapter not in CHAPTERS or rank not in RANKS or factor not in FACTORS or not math.isfinite(amount) or not .05 <= amount <= 10:
            parser.error("Invalid static chapter/rank factor")
        if (chapter, rank, factor) in [x[:3] for x in changes]:
            parser.error("Do not repeat a factor")
        changes.append((chapter, rank, factor, amount))

    archive_relative = "scripts/combat/enemy_calibration.gd"
    parameters_relative = "data/numerical_v2.json"
    source_proof = {p: digest(source / p) for p in [archive_relative, parameters_relative]}
    base = git(source, "rev-parse", "HEAD")
    subprocess.run(["git", "worktree", "add", "--quiet", "--detach", str(destination), base], cwd=source, check=True)
    # Compare to the captured base, not a moving HEAD: a concurrent source
    # commit cannot hide tracked working-tree changes from this overlay.
    changed = subprocess.check_output(["git", "diff", "--name-only", base, "-z"], cwd=source).decode().split("\0")
    untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "-z"], cwd=source).decode().split("\0")
    overlay = {}
    for name in sorted(set(changed + untracked)):
        if not name:
            continue
        relative = Path(name)
        if relative.parts[0] not in SOURCE_DIRS and name not in ("AGENTS.md", "README.md", "project.godot", "export_presets.cfg"):
            continue
        original, copied = source / relative, destination / relative
        if original.is_file():
            before = digest(original)
            copied.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, copied)
            if before != digest(copied) or before != digest(original):
                raise RuntimeError(f"Source changed while copying {name}; discard this candidate")
            overlay[name] = before
        elif copied.is_file():
            copied.unlink()
            overlay[name] = "deleted"
    if args.cache != "none" and (source / ".godot").exists():
        if args.cache == "copy":
            shutil.copytree(source / ".godot", destination / ".godot")
        else:
            shutil.copytree(source / ".godot", destination / ".godot", ignore=shutil.ignore_patterns("imported"))
            shutil.copytree(source / ".godot/imported", destination / ".godot/imported", copy_function=os.link)

    candidate = None
    if args.version is not None:
        params_path = destination / parameters_relative
        data = json.loads(params_path.read_text())
        candidate = json.loads(json.dumps(data["enemy_calibration"]))
        candidate["version"] = args.version
        for chapter, rank, factor, amount in changes:
            candidate["chapters"][chapter][rank][factor] = amount
        archive_path = destination / archive_relative
        archive = archive_path.read_text()
        found = re.search(r"(?ms)^const ARCHIVES := \{\n.*?^\}", archive)
        if not found:
            raise RuntimeError("Unsupported archive layout; do not guess a rewrite")
        block = found.group(0)
        if re.search(rf"(?m)^\s*{args.version}\s*:", block):
            raise RuntimeError("Archive version already exists; choose another test-only version")
        prefix = block[:-1].rstrip()
        if not prefix.endswith(","):
            prefix += ","
        appended = prefix + f"\n\t# Isolated S11 experiment only; release entries above are unchanged.\n\t{args.version}: " + json.dumps(candidate["chapters"], separators=(",", ":")) + "\n}"
        archive_path.write_text(archive[:found.start()] + appended + archive[found.end():])
        data["enemy_calibration"] = candidate
        params_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    if source_proof != {p: digest(source / p) for p in source_proof}:
        raise RuntimeError("Source calibration changed during freeze; do not use this candidate")
    record = {"source": str(source), "snapshot_git_base": base,
              "source_head_after_copy": git(source, "rev-parse", "HEAD"),
              "overlay_sha256": overlay, "candidate": candidate,
              "source_calibration_sha256": source_proof,
              "snapshot_calibration_sha256": {p: digest(destination / p) for p in source_proof},
              "cache_mode": args.cache}
    (destination / "s11_snapshot_overlay.json").write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"snapshot": str(destination), "base": base, "candidate_version": args.version,
                      "source_unchanged": True, "factors": changes}, indent=2))


if __name__ == "__main__":
    main()
