"""Keep GameSave.FORMAT_VERSION synchronized when monster dice shrink or stage rosters change."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from check_save_version import check_repo, check_texts

ROOT = Path(__file__).resolve().parents[1]

BASE_DEFS = '''class_name CombatEnemyDefinitions
extends RefCounted

static var SPIDERLING: Dictionary = {
\t"abilities": [4, 8, 8, 4, 4, 4], "defense_bonus": 0,
}
'''

BASE_STAGE = '''[gd_scene load_steps=2 format=3]

[node name="Enemies" type="Node2D"]

[node name="Spiderling1" parent="." instance=ExtResource("1_unit")]
kind = 2
is_ally = false
start_cell = Vector2i(10, 3)
'''

BASE_SAVE = '''class_name GameSave
const FORMAT_VERSION: int = 16
'''


class SaveVersionTests(unittest.TestCase):
    def test_shrunk_die_without_bump_fails_and_with_bump_passes(self):
        shrunk_defs = BASE_DEFS.replace("[4, 8, 8, 4, 4, 4]", "[4, 4, 8, 4, 4, 4]")
        problems = check_texts(
            BASE_DEFS,
            shrunk_defs,
            {"scenes/combat/stages/act1_stage1_enemies.tscn": BASE_STAGE},
            {"scenes/combat/stages/act1_stage1_enemies.tscn": BASE_STAGE},
            BASE_SAVE,
            BASE_SAVE,
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("주사위 면 수 축소", problems[0])

        bumped_save = BASE_SAVE.replace("16", "17")
        self.assertEqual(
            check_texts(
                BASE_DEFS,
                shrunk_defs,
                {"scenes/combat/stages/act1_stage1_enemies.tscn": BASE_STAGE},
                {"scenes/combat/stages/act1_stage1_enemies.tscn": BASE_STAGE},
                BASE_SAVE,
                bumped_save,
            ),
            [],
        )

    def test_expanded_die_without_bump_passes(self):
        expanded_defs = BASE_DEFS.replace("[4, 8, 8, 4, 4, 4]", "[4, 10, 8, 4, 4, 4]")
        self.assertEqual(
            check_texts(BASE_DEFS, expanded_defs, {}, {}, BASE_SAVE, BASE_SAVE),
            [],
        )

    def test_stage_position_only_change_passes_without_bump(self):
        moved_stage = BASE_STAGE.replace("Vector2i(10, 3)", "Vector2i(11, 5)")
        self.assertEqual(
            check_texts(
                BASE_DEFS,
                BASE_DEFS,
                {"scenes/combat/stages/act1_stage1_enemies.tscn": BASE_STAGE},
                {"scenes/combat/stages/act1_stage1_enemies.tscn": moved_stage},
                BASE_SAVE,
                BASE_SAVE,
            ),
            [],
        )

    def test_stage_enemy_count_or_kind_change_requires_bump(self):
        added_stage = BASE_STAGE + '''
[node name="Spiderling2" parent="." instance=ExtResource("1_unit")]
kind = 2
is_ally = false
start_cell = Vector2i(11, 5)
'''
        problems = check_texts(
            BASE_DEFS,
            BASE_DEFS,
            {"scenes/combat/stages/act1_stage1_enemies.tscn": BASE_STAGE},
            {"scenes/combat/stages/act1_stage1_enemies.tscn": added_stage},
            BASE_SAVE,
            BASE_SAVE,
        )
        self.assertEqual(len(problems), 1)
        self.assertIn("적 배치 수 또는 종류 순서 변경", problems[0])

    def test_git_repo_merge_base_comparison(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            subprocess.run(["git", "init", "-q", "-b", "main"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Tester"], cwd=root, check=True)
            (root / "scenes/combat/stages").mkdir(parents=True)
            (root / "scenes/save").mkdir(parents=True)
            (root / "scenes/combat/enemy_definitions.gd").write_text(BASE_DEFS, encoding="utf-8")
            (root / "scenes/combat/stages/act1_stage1_enemies.tscn").write_text(BASE_STAGE, encoding="utf-8")
            (root / "scenes/save/game_save.gd").write_text(BASE_SAVE, encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "base"], cwd=root, check=True)
            subprocess.run(["git", "checkout", "-q", "-b", "feat/test"], cwd=root, check=True)

            (root / "scenes/combat/enemy_definitions.gd").write_text(
                BASE_DEFS.replace("[4, 8, 8, 4, 4, 4]", "[4, 4, 8, 4, 4, 4]"),
                encoding="utf-8",
            )
            self.assertEqual(len(check_repo(root, base_ref="main")), 1)
            (root / "scenes/save/game_save.gd").write_text(
                BASE_SAVE.replace("16", "17"),
                encoding="utf-8",
            )
            self.assertEqual(check_repo(root, base_ref="main"), [])

    def test_git_repo_stage_change_only_requires_bump(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            subprocess.run(["git", "init", "-q", "-b", "main"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Tester"], cwd=root, check=True)
            (root / "scenes/combat/stages").mkdir(parents=True)
            (root / "scenes/save").mkdir(parents=True)
            (root / "scenes/combat/enemy_definitions.gd").write_text(BASE_DEFS, encoding="utf-8")
            (root / "scenes/combat/stages/act1_stage1_enemies.tscn").write_text(BASE_STAGE, encoding="utf-8")
            (root / "scenes/save/game_save.gd").write_text(BASE_SAVE, encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "base"], cwd=root, check=True)
            subprocess.run(["git", "checkout", "-q", "-b", "feat/stage"], cwd=root, check=True)

            (root / "scenes/combat/stages/act1_stage1_enemies.tscn").write_text(
                BASE_STAGE + '\n[node name="Spiderling2" parent="." instance=ExtResource("1_unit")]\nkind = 2\n',
                encoding="utf-8",
            )
            problems = check_repo(root, base_ref="main")
            self.assertEqual(len(problems), 1)
            self.assertIn("적 배치 수 또는 종류 순서 변경", problems[0])
            (root / "scenes/save/game_save.gd").write_text(
                BASE_SAVE.replace("16", "17"),
                encoding="utf-8",
            )
            self.assertEqual(check_repo(root, base_ref="main"), [])

    def test_repository_save_version_is_consistent(self):
        self.assertEqual(check_repo(ROOT), [])


if __name__ == "__main__":
    unittest.main()
