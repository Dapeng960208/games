#!/usr/bin/env python3
"""Linux QA workspace: isolated per-run paths, serialized Godot, opt-in cleanup."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).absolute().parents[2]
BIOMES = ('B05', 'B06', 'B08')
RUN_ID = re.compile(r'^\d{8}T\d{12}Z-[a-f0-9]{8}$')
MARKER = '.managed-test-run.json'


def checked(path: Path) -> Path:
    """Reject symlinks and lexical traversal, including ancestor symlinks."""
    path = path.absolute()
    if '..' in path.parts or any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError(f'Unsafe path: {path}')
    return path


def workspace() -> Path:
    root = checked(ROOT)
    if root.name != 'games-recovery' or not (root / 'repository.git').is_dir():
        raise ValueError('This runner requires the existing games-recovery shared checkout')
    return root


def run_path(kind: str, biome: str, run_id: str) -> Path:
    if kind not in ('_test_output', '_tmp') or biome not in BIOMES or not RUN_ID.fullmatch(run_id):
        raise ValueError('Invalid managed run path components')
    return checked(workspace() / kind / biome / run_id)


def ensure_managed(biome: str) -> None:
    """Entrypoint for legacy Python harnesses; re-exec exactly once via wrapper."""
    run_id = os.environ.get('GAMES_TEST_RUN_ID', '')
    if run_id:
        output = run_path('_test_output', biome, run_id)
        temporary = run_path('_tmp', biome, run_id)
        if (os.environ.get('GAMES_TEST_OUTPUT_DIR') != str(output)
                or os.environ.get('TMPDIR') != str(temporary)
                or not (output / MARKER).is_file()
                or (output / '.complete').exists()):
            raise ValueError('Invalid or completed managed run environment')
        return
    os.execv(sys.executable, [sys.executable, str(Path(__file__)), 'run', '--biome', biome,
                            '--', sys.executable, *sys.argv])


def run(biome: str, command: list[str]) -> int:
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        raise ValueError('A command is required after --')
    run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '-' + uuid.uuid4().hex[:8]
    output, temporary = [run_path(kind, biome, run_id) for kind in ('_test_output', '_tmp')]
    for folder in (output, temporary):
        folder.mkdir(parents=True, exist_ok=False)
        (folder / MARKER).write_text(json.dumps({'run_id': run_id, 'biome': biome}), encoding='utf-8')
    env = os.environ.copy()
    env.update(GAMES_TEST_RUN_ID=run_id, GAMES_TEST_OUTPUT_DIR=str(output),
               GAMES_TEST_TMP_DIR=str(temporary), TMPDIR=str(temporary), TMP=str(temporary), TEMP=str(temporary),
               PYTHONDONTWRITEBYTECODE='1')
    for variable, name in [('XDG_DATA_HOME', 'userdata'), ('XDG_CONFIG_HOME', 'config'),
                           ('XDG_CACHE_HOME', 'cache'), ('APPDATA', 'roaming'), ('LOCALAPPDATA', 'local')]:
        folder = output / name
        folder.mkdir()
        env[variable] = str(folder)
    print(f'Test output: {output}\nTemporary files: {temporary}', flush=True)
    # A retained marker without .complete is deliberately never auto-cleanable.
    with (output / '.active.lock').open('w') as active:
        fcntl.flock(active, fcntl.LOCK_EX)
        lock_path = checked(Path('/tmp/games-godot.lock'))
        with lock_path.open('a') as engine_lock:
            fcntl.flock(engine_lock, fcntl.LOCK_EX)
            with (output / 'console.log').open('w', encoding='utf-8') as log:
                process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, text=True,
                                           pass_fds=(active.fileno(), engine_lock.fileno()))
                try:
                    for line in process.stdout:
                        print(line, end='', flush=True)
                        log.write(line)
                        log.flush()
                    code = process.wait()
                except BaseException:
                    process.terminate()
                    process.wait()
                    raise
                finally:
                    process.stdout.close()
            (output / '.complete').write_text(json.dumps({'exit_code': code}), encoding='utf-8')
    return code


def cleanup(biome: str, keep: int, apply: bool) -> list[str]:
    if keep < 0:
        raise ValueError('--keep must be nonnegative')
    parent = checked(workspace() / '_test_output' / biome)
    if not parent.exists():
        return []
    candidates = []
    for folder in parent.iterdir():
        if not RUN_ID.fullmatch(folder.name) or folder.is_symlink() or not folder.is_dir():
            continue
        folder = run_path('_test_output', biome, folder.name)
        if not (folder / '.complete').is_file() or not (folder / MARKER).is_file():
            continue
        candidates.append(folder)
    selected = sorted(candidates, key=lambda p: p.name, reverse=True)[keep:]
    planned = []
    for output in selected:
        temporary = run_path('_tmp', biome, output.name)
        # Fail closed on every link, even links that would stay inside the tree.
        for folder in (output, temporary):
            if not folder.exists():
                continue
            if json.loads(checked(folder / MARKER).read_text()) != {'run_id': output.name, 'biome': biome}:
                raise ValueError(f'Invalid marker: {folder}')
            for base, dirs, files in os.walk(folder, followlinks=False):
                for name in dirs + files:
                    if name in ('.git', 'repository.git'):
                        raise ValueError(f'Protected repository metadata: {Path(base) / name}')
                    checked(Path(base) / name)
        lock = checked(output / '.active.lock')
        if not lock.is_file():
            continue
        with lock.open('r') as active:
            try:
                fcntl.flock(active, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                continue
            for folder in (temporary, output):
                if folder.exists():
                    planned.append(str(folder))
                    print(('DELETE ' if apply else 'WOULD DELETE ') + str(folder))
                    if apply:
                        if not shutil.rmtree.avoids_symlink_attacks:
                            raise RuntimeError('Safe recursive deletion unavailable')
                        shutil.rmtree(folder)
    return planned


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest='mode', required=True)
    launch = modes.add_parser('run')
    launch.add_argument('--biome', choices=BIOMES, required=True)
    launch.add_argument('command', nargs=argparse.REMAINDER)
    clean = modes.add_parser('cleanup', help='Dry-run by default; requires explicit prior deletion approval')
    clean.add_argument('--biome', choices=BIOMES, required=True)
    clean.add_argument('--keep', type=int, default=5)
    clean.add_argument('--apply', action='store_true')
    clean.add_argument('--confirm-delete-managed-runs', action='store_true')
    args = parser.parse_args()
    if args.mode == 'run':
        return run(args.biome, args.command)
    if args.apply and not args.confirm_delete_managed_runs:
        parser.error('--apply requires --confirm-delete-managed-runs after approval of the dry-run list')
    cleanup(args.biome, args.keep, args.apply)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
