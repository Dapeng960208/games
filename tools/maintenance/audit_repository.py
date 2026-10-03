"""Check repository paths, asset naming, suite registrations and local doc links."""
from __future__ import annotations

import json
import posixpath
import re
import subprocess
from pathlib import Path, PurePosixPath
from urllib.parse import unquote

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "project.godot").is_file())


def repository_files(root: Path) -> set[str]:
    # Git records portable spelling and excludes local ignored test output. Include
    # new non-ignored files so the check also works before staging a change.
    output = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root,
    ).decode("utf-8")
    return {name for name in output.split("\0") if name and (root / name).is_file()}


def without_fenced_code(body: str) -> str:
    return re.sub(r"```[\s\S]*?```|~~~[\s\S]*?~~~", "", body)


def markdown_anchors(body: str) -> set[str]:
    body = without_fenced_code(body)
    anchors = set(re.findall(r'\b(?:id|name)=["\']([^"\']+)["\']', body))
    for heading in re.findall(r"^#{1,6}\s+(.+)$", body, re.MULTILINE):
        heading = re.sub(r"\s+#+\s*$", "", heading)
        heading = re.sub(r"<[^>]+>", "", heading)
        heading = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", heading)
        slug = re.sub(r"\s", "-", re.sub(r"[^\w\s-]", "", heading.lower().strip()))
        anchor, suffix = slug, 0
        while anchor in anchors:
            suffix += 1
            anchor = f"{slug}-{suffix}"
        anchors.add(anchor)
    return anchors


def audit(root: Path = ROOT) -> list[str]:
    errors = []
    files = repository_files(root)
    entries = files | {parent.as_posix() for name in files for parent in PurePosixPath(name).parents}
    registry = json.loads((root / "assets/manifest.json").read_text(encoding="utf-8"))["resources"]
    for logical, physical in registry.items():
        if not physical.startswith("res://assets/") or physical.removeprefix("res://") not in files:
            errors.append(f"Asset {logical}: missing {physical}")
    for relative in sorted(files):
        if not relative.startswith("assets/"): continue
        path = PurePosixPath(relative)
        if path.name != path.name.lower() or re.search(r"[\s-]", path.name):
            errors.append(f"Asset naming: {relative}")
        if relative != "assets/manifest.json" and path.parts[1] not in {"characters", "system", "levels"}:
            errors.append(f"Asset category: {relative}")
    suites = json.loads((root / "tools/testing/suites.json").read_text(encoding="utf-8"))
    for suite, spec in suites.items():
        for kind, path in spec.items():
            if path not in files: errors.append(f"Suite {suite} {kind}: missing {path}")
    for folder in ("scripts", "scenes", "data", "shaders"):
        for relative in sorted(files):
            path = root / relative
            if not relative.startswith(folder + "/") or path.suffix not in {".gd", ".tscn", ".json", ".gdshader"}: continue
            body = path.read_text(encoding="utf-8")
            for target in re.findall(r'["\'](asset://[^"\'\n]+)["\']', body):
                logical = target.removeprefix("asset://").lower()
                if any(x in logical for x in ("%", "__index__")) or logical.endswith("/") or "." not in logical.rsplit("/", 1)[-1]: continue
                if logical not in registry:
                    errors.append(f"Logical resource {relative}: unregistered {target}")
            for target in re.findall(r'["\'](res://[^"\'\n]+)["\']', body):
                resource = target.removeprefix("res://")
                # A concatenated namespace or format template is checked in the
                # corresponding resource suite rather than as a literal file.
                if target.endswith("/") or any(x in resource for x in ("%", "{", "__missing__")): continue
                if resource not in entries: errors.append(f"Resource {relative}: missing {target}")
    anchor_cache = {}
    for relative in sorted(files):
        if relative != "README.md" and not (relative.startswith("docs/") and relative.endswith(".md")): continue
        body = without_fenced_code((root / relative).read_text(encoding="utf-8"))
        for target in re.findall(r"\]\(([^)]+)\)", body):
            target = target.strip().strip("<>")
            if not target or re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target): continue
            address, _, fragment = target.partition("#")
            destination = posixpath.normpath(posixpath.join(posixpath.dirname(relative), unquote(address))) if address else relative
            if "\\" in destination or destination not in entries:
                errors.append(f"Doc {relative}: missing {target}")
                continue
            if fragment and destination.endswith(".md"):
                if destination not in anchor_cache:
                    anchor_cache[destination] = markdown_anchors((root / destination).read_text(encoding="utf-8"))
                if unquote(fragment) not in anchor_cache[destination]:
                    errors.append(f"Doc {relative}: missing anchor {target}")
    return sorted(set(errors))

if __name__ == "__main__":
    errors = audit()
    print("\n".join(errors) if errors else "Repository paths, asset registry/names, suites and documentation links passed.")
    raise SystemExit(bool(errors))
