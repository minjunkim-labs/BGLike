"""Keep scenes/ and tests/ file and folder names in lowercase snake_case."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from check_naming import check

ROOT = Path(__file__).resolve().parents[1]


class NamingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)

    def _write(self, rel):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("", encoding="utf-8")

    def test_valid_snake_case_passes(self):
        self._write("scenes/combat/hit_effects.gd")
        self._write("scenes/combat/hit_effects.gd.uid")
        self._write("tests/combat_ai_test.gd")
        self.assertEqual(check(self.root), [])

    def test_uppercase_hyphen_and_space_fail(self):
        self._write("scenes/combat/BadName.gd")
        self._write("scenes/combat/bad-name.png")
        self._write("tests/SubDir/ok.gd")
        self.assertEqual(
            check(self.root),
            [
                "scenes/combat/BadName.gd: 소문자 snake_case가 아닌 경로 요소 'BadName.gd'",
                "scenes/combat/bad-name.png: 소문자 snake_case가 아닌 경로 요소 'bad-name.png'",
                "tests/SubDir/ok.gd: 소문자 snake_case가 아닌 경로 요소 'SubDir'",
            ],
        )

    def test_third_party_sources_fonts_and_gdignore_are_excluded(self):
        self._write("scenes/combat/art/sources/units/archer-seed.png")
        self._write("scenes/combat/art/sources/.gdignore")
        self._write("scenes/combat/audio/sources/kenney/impactMetal_heavy_000.ogg")
        self._write("scenes/ui/fonts/Galmuri11.ttf")
        self.assertEqual(check(self.root), [])

    def test_repository_names_are_snake_case(self):
        self.assertEqual(check(ROOT), [])


if __name__ == "__main__":
    unittest.main()
