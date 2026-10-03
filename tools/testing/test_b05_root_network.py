#!/usr/bin/env python3
"""Run the pure B05 state test without production autoloads or player saves."""
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
import tempfile
from test_workspace import ensure_managed


def main() -> int:
    ensure_managed("B05")
    suites = {
        "root_network": ("root network", ["scripts/levels/b05/world/root_network.gd"]),
        "content": ("content", ["scripts/levels/b05/world/content.gd", "data/levels/b05/content.json"]),
        "room_geometry": ("room geometry", ["scripts/levels/b05/world/room_geometry.gd", "data/levels/b05/room_geometry.json"]),
        "enemy_numbers": ("enemy numbers", ["scripts/levels/b05/combat/enemy_numbers.gd",
                           "scripts/levels/b05/world/content.gd", "data/levels/b05/content.json"]),
        "mechanism_runtime": ("mechanism runtime", ["scripts/levels/b05/world/mechanism_runtime.gd",
                              "scripts/levels/b05/world/root_network.gd", "scripts/domain/combat/combat_status.gd",
                              "scripts/infrastructure/content/runtime_rules.gd", "data/rules/numerical.json"]),
        "equipment_catalog": ("equipment catalog", ["scripts/levels/b05/equipment/equipment_catalog.gd",
                              "data/levels/b05/equipment.json", "scripts/infrastructure/content/runtime_rules.gd",
                              "scripts/domain/equipment/equipment_class_policy.gd", "data/rules/numerical.json"]),
    }
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=suites, default="root_network")
    arguments = parser.parse_args()
    label, dependencies = suites[arguments.suite]
    test_script = f"tests/test_b05_{arguments.suite}.gd"
    repository = next(p for p in Path(__file__).resolve().parents if (p / 'project.godot').is_file())
    engine = shutil.which("godot") or shutil.which("godot4")
    if not engine:
        raise SystemExit("Godot is required")
    with tempfile.TemporaryDirectory(prefix="games-b05-test-") as directory:
        project = Path(directory)
        for relative in [*dependencies, test_script]:
            destination = project / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(repository / relative, destination)
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="B05 isolated state test"\n',
            encoding="utf-8",
        )
        environment = os.environ.copy()
        for variable, folder in (
            ("XDG_DATA_HOME", "isolated-user-data"),
            ("XDG_CONFIG_HOME", "isolated-user-config"),
            ("XDG_CACHE_HOME", "isolated-user-cache"),
        ):
            location = project / folder
            location.mkdir()
            environment[variable] = str(location)
        command = [engine, "--headless", "--path", directory,
                   "--script", f"res://{test_script}"]
        if os.name == "posix" and shutil.which("nice"):
            command = ["nice", "-n", "10", *command]
        try:
            result = subprocess.run(command, cwd=project, env=environment,
                                    capture_output=True, text=True, timeout=45)
        except subprocess.TimeoutExpired as error:
            for captured in (error.stdout, error.stderr):
                if captured:
                    print(captured.decode() if isinstance(captured, bytes) else captured)
            print("ERROR: B05 isolated test timed out")
            return 1
        output = result.stdout + result.stderr
        print(output, end="")
        completed = re.search(rf"B05 {re.escape(label)}: [1-9][0-9]* checks, 0 failures", output)
        return result.returncode or int(
            not completed or "SCRIPT ERROR" in output or "ERROR:" in output
        )


if __name__ == "__main__":
    raise SystemExit(main())
