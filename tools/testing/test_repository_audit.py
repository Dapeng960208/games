"""Regression checks for portable paths and reproducible documentation links."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import quote

MODULE_PATH = Path(__file__).resolve().parents[1] / "maintenance/audit_repository.py"
SPEC = importlib.util.spec_from_file_location("audit_repository", MODULE_PATH)
target = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(target)


class RepositoryAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="repository-audit-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.files = set()
        self.write("assets/manifest.json", '{"resources": {}}')
        self.write("tools/testing/suites.json", "{}")
        self.write("README.md", "# Fixture\n")
        self.git_output = patch.object(
            target.subprocess, "check_output",
            side_effect=lambda *args, **kwargs: ("\0".join(sorted(self.files)) + "\0").encode("utf-8"),
        )
        self.git_output.start()
        self.addCleanup(self.git_output.stop)

    def write(self, name, body, *, included=True):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding="utf-8")
        if included:
            self.files.add(name)
        return path

    def resource(self, physical):
        self.write("assets/manifest.json", json.dumps({"resources": {"ui/panel.json": physical}}))

    def test_valid_paths_and_encoded_chinese_anchor(self):
        self.write("assets/system/ui/panel.json", "{}")
        self.resource("res://assets/system/ui/panel.json")
        self.write("scripts/main.gd", 'const PANEL = "res://assets/system/ui/panel.json"\n')
        self.write("tools/testing/suites.json", '{"main": {"script": "scripts/main.gd"}}')
        self.write("docs/README.md", "# 文档\n\n## 4. 普通怪与首领\n")
        self.write("README.md", f"[文档](docs/README.md#{quote('4-普通怪与首领')})\n")
        self.assertEqual(target.audit(self.root), [])

    def test_wrong_case_is_rejected_even_on_windows(self):
        self.write("assets/system/ui/panel.json", "{}")
        self.resource("res://assets/system/ui/PANEL.json")
        self.write("scripts/main.gd", 'const PANEL = "res://assets/system/ui/PANEL.json"\n')
        self.write("tools/testing/suites.json", '{"main": {"script": "scripts/Main.gd"}}')
        self.write("docs/README.md", "# 文档\n")
        self.write("README.md", "[文档](docs/readme.md)\n")
        errors = target.audit(self.root)
        self.assertEqual(len(errors), 4)
        self.assertEqual({error.split(" ", 1)[0] for error in errors}, {"Asset", "Resource", "Suite", "Doc"})

    def test_backslashes_are_rejected_even_on_windows(self):
        self.write("assets/system/ui/panel.json", "{}")
        self.resource("res://assets/system\\ui/panel.json")
        self.write("scripts/main.gd", 'const PANEL = "res://assets/system\\ui/panel.json"\n')
        self.write("README.md", "[面板](assets/system\\ui/panel.json)\n")
        errors = target.audit(self.root)
        self.assertEqual(len(errors), 3)
        self.assertEqual({error.split(" ", 1)[0] for error in errors}, {"Asset", "Resource", "Doc"})

    def test_ignored_local_screenshot_is_not_a_repository_link(self):
        self.write("tools/godot/test-runs/frame.png", "fixture", included=False)
        self.write("README.md", "[截图](tools/godot/test-runs/frame.png)\n")
        self.assertEqual(target.audit(self.root), ["Doc README.md: missing tools/godot/test-runs/frame.png"])

    def test_deleted_tracked_file_is_not_a_repository_link(self):
        self.write("docs/README.md", "# 文档\n").unlink()
        self.write("README.md", "[文档](docs/README.md)\n")
        self.assertEqual(target.audit(self.root), ["Doc README.md: missing docs/README.md"])

    def test_missing_heading_is_rejected(self):
        self.write("docs/README.md", "# 文档\n\n## 4. 普通怪与首领\n")
        self.write("README.md", "[数值](docs/README.md#9-野怪首领与难度标尺)\n")
        self.assertEqual(target.audit(self.root), ["Doc README.md: missing anchor docs/README.md#9-野怪首领与难度标尺"])

    def test_duplicate_headings_explicit_anchors_and_fenced_examples(self):
        body = '# 普通怪\n\n## 普通怪\n\n<a id="custom"></a>\n```md\n# 示例\n```\n~~~md\n# 示例二\n~~~\n'
        self.assertEqual(target.markdown_anchors(body), {"普通怪", "普通怪-1", "custom"})


if __name__ == "__main__":
    unittest.main()
