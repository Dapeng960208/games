"""Resolve tool resources through the same registry used by Godot.

Unknown resources fail before writing. Add a registry entry and a destination
in the character/system/level hierarchy when authoring new content.
"""
from __future__ import annotations

import fnmatch
import json
from pathlib import Path

ROOT = next(p for p in Path(__file__).resolve().parents if (p / "project.godot").is_file())
RESOURCES = json.loads((ROOT / "assets/manifest.json").read_text(encoding="utf-8"))["resources"]

def resource(logical: str) -> Path:
    if logical.startswith("res://"):
        relative = logical.removeprefix("res://")
    else:
        key = logical.removeprefix("asset://").lower()
        if key not in RESOURCES:
            raise ValueError(f"Unregistered asset: {logical}")
        relative = RESOURCES[key].removeprefix("res://")
    target = (ROOT / relative).resolve()
    if not target.is_relative_to(ROOT) or not target.is_relative_to(ROOT / "assets"):
        raise ValueError(f"Asset destination outside assets: {relative}")
    return target

class AssetFolder:
    """A logical namespace may span several physical profession/level folders."""
    def __init__(self, prefix: str):
        self.prefix = prefix.removeprefix("asset://").strip("/").lower() + "/"

    def __truediv__(self, name: str) -> Path:
        return resource(self.prefix + name)

    def glob(self, pattern: str):
        match = (self.prefix + pattern).lower()
        return [resource(key) for key in RESOURCES if fnmatch.fnmatchcase(key, match)]
