"""Check repository paths, asset naming, suite registrations and local doc links."""
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import unquote

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "project.godot").is_file())

def audit() -> list[str]:
    errors = []
    registry = json.loads((ROOT / "assets/manifest.json").read_text(encoding="utf-8"))["resources"]
    for logical, physical in registry.items():
        if not physical.startswith("res://assets/") or not (ROOT / physical.removeprefix("res://")).is_file():
            errors.append(f"Asset {logical}: missing {physical}")
    for path in (ROOT / "assets").rglob("*"):
        if not path.is_file(): continue
        relative = path.relative_to(ROOT).as_posix()
        if path.name != path.name.lower() or re.search(r"[\s-]", path.name):
            errors.append(f"Asset naming: {relative}")
        if path != ROOT / "assets/manifest.json" and path.relative_to(ROOT / "assets").parts[0] not in {"characters", "system", "levels"}:
            errors.append(f"Asset category: {relative}")
    suites = json.loads((ROOT / "tools/testing/suites.json").read_text(encoding="utf-8"))
    for suite, spec in suites.items():
        for kind, path in spec.items():
            if not (ROOT / path).is_file(): errors.append(f"Suite {suite} {kind}: missing {path}")
    for folder in ("scripts", "scenes", "data", "shaders"):
        for path in (ROOT / folder).rglob("*"):
            if not path.is_file() or path.suffix not in {".gd", ".tscn", ".json", ".gdshader"}: continue
            body = path.read_text(encoding="utf-8")
            for target in re.findall(r'["\'](asset://[^"\'\n]+)["\']', body):
                logical = target.removeprefix("asset://").lower()
                if any(x in logical for x in ("%", "__index__")) or logical.endswith("/") or "." not in logical.rsplit("/", 1)[-1]: continue
                if logical not in registry:
                    errors.append(f"Logical resource {path.relative_to(ROOT)}: unregistered {target}")
            for target in re.findall(r'["\'](res://[^"\'\n]+)["\']', body):
                relative = target.removeprefix("res://")
                # A concatenated namespace or format template is checked in the
                # corresponding resource suite rather than as a literal file.
                if target.endswith("/") or any(x in relative for x in ("%", "{", "__missing__")): continue
                if not (ROOT / relative).exists(): errors.append(f"Resource {path.relative_to(ROOT)}: missing {target}")
    for path in [ROOT / "README.md", *(ROOT / "docs").rglob("*.md")]:
        body = path.read_text(encoding="utf-8")
        body = re.sub(r"```[\s\S]*?```", "", body)
        for target in re.findall(r"\]\(([^)]+)\)", body):
            target = target.strip().strip("<>").split("#", 1)[0]
            if not target or re.match(r"[a-zA-Z]+:", target): continue
            if not (path.parent / unquote(target)).exists():
                errors.append(f"Doc {path.relative_to(ROOT)}: missing {target}")
    return sorted(set(errors))

if __name__ == "__main__":
    errors = audit()
    print("\n".join(errors) if errors else "Repository paths, asset registry/names, suites and documentation links passed.")
    raise SystemExit(bool(errors))
