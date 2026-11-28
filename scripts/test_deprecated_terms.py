"""Ensure removed terms do not grow above their ratchet baseline."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from check_deprecated_terms import BASELINE, check

ROOT = Path(__file__).resolve().parents[1]


class DeprecatedTermsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)

    def _write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_zero_baseline_term_fails_when_introduced(self):
        self._write("docs/design/sample.md", "이 항목은 시험 아이템입니다.\n")
        problems = check(self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("시험 아이템", problems[0])
        self.assertIn("docs/design/sample.md:1", problems[0])

    def test_negative_tests_avoid_lines_and_planning_are_ignored(self):
        self._write("GLOSSARY.md", "_Avoid_: 독 장판\n")
        self._write("tests/sample_test.gd", 'assert(not create_ground("poison"), "삭제된 독 장판은 거부")\n')
        self._write("docs/planning/old.md", "시험 아이템 위임 초기 권장안 독 장판\n")
        self.assertEqual(check(self.root), [])

    def test_ratchet_allows_below_or_equal_and_rejects_above(self):
        self._write("docs/a.md", "독 장판\n" * BASELINE["독 장판"])
        self.assertEqual(check(self.root), [])
        self._write("docs/b.md", "독 장판\n")
        self.assertEqual(len(check(self.root)), 1)

    def test_repository_within_ratchet_baseline(self):
        self.assertEqual(check(ROOT), [])


if __name__ == "__main__":
    unittest.main()
