#!/usr/bin/env python3
"""Run the pure B05 state test without production autoloads or player saves."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile


def main() -> int:
    repository = Path(__file__).resolve().parents[1]
    engine = shutil.which("godot") or shutil.which("godot4")
    if not engine:
        raise SystemExit("Godot is required")
    with tempfile.TemporaryDirectory(prefix="games-b05-test-") as directory:
        project = Path(directory)
        for relative in (
            "scripts/world/b05_root_network.gd",
            "tests/test_b05_root_network.gd",
        ):
            destination = project / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(repository / relative, destination)
        (project / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="B05 isolated state test"\n',
            encoding="utf-8",
        )
        environment = os.environ.copy()
        for variable, folder in (
            ("XDG_DATA_HOME", "data"),
            ("XDG_CONFIG_HOME", "config"),
            ("XDG_CACHE_HOME", "cache"),
        ):
            location = project / folder
            location.mkdir()
            environment[variable] = str(location)
        command = [engine, "--headless", "--path", directory,
                   "--script", "res://tests/test_b05_root_network.gd"]
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
        completed = re.search(r"B05 root network: [1-9][0-9]* checks, 0 failures", output)
        return result.returncode or int(
            not completed or "SCRIPT ERROR" in output or "ERROR:" in output
        )


if __name__ == "__main__":
    raise SystemExit(main())
