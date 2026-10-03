#!/usr/bin/env python3
"""Focused path/retention guards; no real workspace cleanup or Godot execution."""
import fcntl
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import test_workspace as target


class WorkspaceGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='workspace-guards-')
        self.root = Path(self.temporary.name) / 'games-recovery'
        (self.root / 'repository.git').mkdir(parents=True)
        self.patch = patch.object(target, 'ROOT', self.root)
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.temporary.cleanup()

    def fixture(self, index, completed=True):
        run_id = f'20261002T14000000000{index}Z-1234abcd'
        paths = [target.run_path(kind, 'B05', run_id) for kind in ('_test_output', '_tmp')]
        for folder in paths:
            folder.mkdir(parents=True)
            (folder / target.MARKER).write_text(json.dumps({'run_id': run_id, 'biome': 'B05'}))
        (paths[0] / '.active.lock').touch()
        if completed:
            (paths[0] / '.complete').touch()
        return paths

    def test_invalid_components(self):
        for kind, biome, run_id in [('_tmp', '../B05', 'bad'), ('repository.git','B05','bad'), ('_tmp','B05','../')]:
            with self.assertRaises(ValueError): target.run_path(kind, biome, run_id)

    def test_symlink_ancestor(self):
        (self.root / '_tmp').symlink_to(self.root / 'repository.git', target_is_directory=True)
        with self.assertRaises(ValueError): target.run_path('_tmp','B05','20261002T140000000000Z-1234abcd')

    def test_dry_run_retention(self):
        older = self.fixture(1)
        newer = self.fixture(2)
        planned = target.cleanup('B05', 1, False)
        self.assertEqual(set(planned), set(map(str, older)))
        self.assertTrue(all(p.exists() for p in older + newer))

    def test_active_and_incomplete_skipped(self):
        paths = self.fixture(1)
        self.fixture(2, completed=False)
        with (paths[0] / '.active.lock').open() as active:
            fcntl.flock(active, fcntl.LOCK_EX)
            self.assertEqual(target.cleanup('B05', 0, False), [])

    def test_internal_symlink_refused(self):
        paths = self.fixture(1)
        (paths[1] / 'outside').symlink_to(self.root / 'repository.git', target_is_directory=True)
        with self.assertRaises(ValueError): target.cleanup('B05', 0, False)
        self.assertTrue(paths[0].exists())

    def test_unmarked_directory_preserved(self):
        folder = self.root / '_test_output' / 'B05' / 'manual-evidence'
        folder.mkdir(parents=True)
        self.assertEqual(target.cleanup('B05', 0, False), [])
        self.assertTrue(folder.exists())

    def test_repository_metadata_refused(self):
        paths = self.fixture(1)
        (paths[1] / ".git").mkdir()
        with self.assertRaises(ValueError): target.cleanup("B05", 0, False)
        self.assertTrue(paths[0].exists())

    def test_negative_retention(self):
        with self.assertRaises(ValueError): target.cleanup('B05', -1, False)


if __name__ == '__main__':
    unittest.main()
