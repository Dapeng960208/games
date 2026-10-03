#!/usr/bin/env python3
"""Run only B06 pure foundation suites in a disposable no-autoload project.

The managed wrapper obtains /tmp/games-godot.lock and isolates output and
temporary files. Do not wrap this entrypoint in a second external flock.
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from test_workspace import ensure_managed

SUITES = ("content", "enemy_numbers", "equipment_catalog", "tide_state", "boss_state", "room_geometry", "tide_runtime")
SHARED_INPUTS = (
    "scripts/domain/equipment/equipment_class_policy.gd",
    "scripts/domain/combat/combat_status.gd",
    "scripts/infrastructure/content/runtime_rules.gd",
    "data/rules/numerical.json",
)


def main() -> int:
    ensure_managed("B06")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--suites", nargs="+", choices=SUITES, default=SUITES)
    args = parser.parse_args()
    engine = args.godot.resolve(strict=True)
    root = next(p for p in Path(__file__).resolve().parents if (p / 'project.godot').is_file())
    # Querying the engine is part of the caller's already-held engine lease.
    version = subprocess.run([str(engine), "--version"], text=True, capture_output=True, timeout=10)
    if version.returncode or not version.stdout.strip().startswith("4.6.3.stable.official."):
        print("Expected current verified official engine 4.6.3; found: " + version.stdout + version.stderr, file=sys.stderr)
        return 2
    print(version.stdout.strip(), flush=True)
    failed = False
    with tempfile.TemporaryDirectory(prefix="games-b06-foundation-") as directory:
        stage = Path(directory)
        project = stage / "project"
        inputs = [root / name for name in SHARED_INPUTS]
        for pattern in ("scripts/world/b06*.gd", "scripts/combat/b06*.gd", "scripts/core/b06*.gd", "data/b06*.json", "tests/test_b06*.gd"):
            inputs.extend(root.glob(pattern))
        for source in inputs:
            target = project / source.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="B06FoundationQA"\n'
            'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="B06FoundationQA-isolated"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
        env = os.environ.copy()
        for variable, folder in (("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache"), ("XDG_CONFIG_HOME", "config")):
            (stage / folder).mkdir()
            env[variable] = str(stage / folder)
        prefix = ["nice", "-n", "10"] if os.name == "posix" and shutil.which("nice") else []
        for suite in args.suites:
            command = prefix + [str(engine), "--headless", "--path", str(project), "--script", f"res://tests/test_b06_{suite}.gd"]
            try:
                result = subprocess.run(command, text=True, capture_output=True, timeout=25, env=env)
                output = result.stdout + result.stderr
                print(output, end="" if output.endswith("\n") else "\n", flush=True)
                bad = result.returncode != 0 or "SCRIPT ERROR" in output or "ERROR:" in output or "0 failures" not in output
                print(f"{suite}: {'FAIL' if bad else 'PASS'} (exit {result.returncode})", flush=True)
                failed |= bad
            except subprocess.TimeoutExpired as exc:
                print(f"{suite}: FAIL (25-second timeout)", file=sys.stderr)
                for output in (exc.stdout, exc.stderr):
                    if output:
                        print(output.decode(errors="replace") if isinstance(output, bytes) else output, file=sys.stderr)
                failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
