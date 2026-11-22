"""Keep every GDScript file paired with its Godot .gd.uid sidecar file."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from check_uid_files import check

ROOT = Path(__file__).resolve().parents[1]


class UidFileTests(unittest.TestCase):
    def _init_repo(self, root):
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)

    def test_tracked_gd_requires_tracked_uid(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self._init_repo(root)
            (root / "ok.gd").write_text("extends Node\n", encoding="utf-8")
            (root / "ok.gd.uid").write_text("uid://ok\n", encoding="utf-8")
            (root / "missing.gd").write_text("extends Node\n", encoding="utf-8")
            (root / "untracked_uid.gd").write_text("extends Node\n", encoding="utf-8")
            (root / "untracked_uid.gd.uid").write_text("uid://untracked\n", encoding="utf-8")
            subprocess.run(
                ["git", "add", "ok.gd", "ok.gd.uid", "missing.gd", "untracked_uid.gd"],
                cwd=root,
                check=True,
            )
            self.assertEqual(
                check(root),
                [
                    "missing.gd: 대응하는 missing.gd.uid 파일이 git에 추적되지 않음",
                    "untracked_uid.gd: 대응하는 untracked_uid.gd.uid 파일이 git에 추적되지 않음",
                ],
            )

    def test_untracked_gd_requires_uid_on_disk(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self._init_repo(root)
            (root / "new_ok.gd").write_text("extends Node\n", encoding="utf-8")
            (root / "new_ok.gd.uid").write_text("uid://newok\n", encoding="utf-8")
            (root / "new_missing.gd").write_text("extends Node\n", encoding="utf-8")
            self.assertEqual(
                check(root),
                ["new_missing.gd: 대응하는 new_missing.gd.uid 파일이 없음"],
            )

    def test_staged_gd_missing_uid_fails_even_if_deleted_from_working_tree(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self._init_repo(root)
            staged = root / "staged_only.gd"
            staged.write_text("extends Node\n", encoding="utf-8")
            subprocess.run(["git", "add", "staged_only.gd"], cwd=root, check=True)
            staged.unlink()
            self.assertEqual(
                check(root),
                ["staged_only.gd: 대응하는 staged_only.gd.uid 파일이 git에 추적되지 않음"],
            )
            subprocess.run(["git", "rm", "--cached", "-q", "staged_only.gd"], cwd=root, check=True)
            self.assertEqual(check(root), [])

    def test_repository_gd_files_have_tracked_uids(self):
        self.assertEqual(check(ROOT), [])


if __name__ == "__main__":
    unittest.main()
