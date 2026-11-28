"""Exercise the merge queue reviewed-head check."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from reviewed_head import DEPENDABOT, git_changed, reviewed_head, verdict

HEAD = "a" * 40
OTHER = "b" * 40
BASE = "c" * 40
# The SHA in a queue branch name is the queue base, not the PR head (BGLike pr-711 run, 2026-11-20).
REF = f"refs/heads/gh-readonly-queue/main/pr-12-{BASE}"
MANIFEST = json.dumps({"files": {".github/pull_request_template.md": {}},
                       "blocks": {"ops": {"target": "AGENTS.md"}}})


def body(*heads, author="Claude Code / opus"):
    lines = [f"Author: {author}", "## Review"]
    lines += [f"리뷰한 head와 되돌리기: {head}, 쉬움" for head in heads]
    return "\n".join(lines)


class ReviewedHeadTests(unittest.TestCase):
    def test_matching_head_passes(self):
        self.assertIsNone(verdict(REF, HEAD, "me@example.invalid", body(HEAD), ["src/a.py"], ""))

    def test_moved_head_fails(self):
        self.assertIn("다릅니다", verdict(REF, HEAD, "me@example.invalid", body(OTHER), ["src/a.py"], ""))

    def test_last_review_round_wins(self):
        self.assertIsNone(verdict(REF, HEAD, "x", body(OTHER, HEAD), ["a"], ""))
        self.assertIsNotNone(verdict(REF, HEAD, "x", body(HEAD, OTHER), ["a"], ""))

    def test_missing_or_placeholder_review_fails(self):
        for text in ["", body(), "리뷰한 head와 되돌리기: <커밋 SHA>, <쉬움 | 어려움>"]:
            with self.subTest(text=text):
                self.assertIn("없습니다", verdict(REF, HEAD, "x", text, ["a"], ""))

    def test_queue_ref_with_or_without_refs_heads_prefix(self):
        bare = REF.removeprefix("refs/heads/")
        self.assertIsNone(verdict(bare, HEAD, "x", body(HEAD), ["a"], ""))
        self.assertIn("다릅니다", verdict(REF, HEAD, "x", body(BASE), ["a"], ""))

    def test_last_review_line_without_full_sha_fails(self):
        text = body(HEAD) + "\n리뷰한 head와 되돌리기: aaaaaaa, 쉬움"
        self.assertIn("없습니다", verdict(REF, HEAD, "x", text, ["a"], ""))

    def test_unreadable_queue_ref_fails(self):
        self.assertIn("읽지 못했습니다", verdict("main", HEAD, "x", body(HEAD), ["a"], ""))

    def test_dependabot_passes_by_email_only(self):
        self.assertIsNone(verdict(REF, HEAD, DEPENDABOT, "", ["a"], ""))
        self.assertIsNotNone(verdict(REF, HEAD, "dependabot[bot]", "", ["a"], ""))

    def test_sync_pr_passes_only_on_managed_paths(self):
        sync = body(author="스크립트 / 없음 (repo-baseline tools/sync_consumers.py)")
        self.assertIsNone(verdict(REF, HEAD, "x", sync, [".github/repo-baseline.json", "AGENTS.md"], MANIFEST))
        self.assertIsNotNone(verdict(REF, HEAD, "x", sync, [".github/repo-baseline.json", "src/a.py"], MANIFEST))
        # A migration PR: the base has no manifest, so it needs a review.
        self.assertIsNotNone(verdict(REF, HEAD, "x", sync, [".github/repo-baseline.json"], ""))
        self.assertIsNotNone(verdict(REF, HEAD, "x", body(), [".github/repo-baseline.json"], MANIFEST))

    def test_reviewed_head_accepts_backticks_and_crlf(self):
        self.assertEqual(reviewed_head(f"x\r\n리뷰한 head와 되돌리기: `{HEAD}`, 어려움 (이유)\r\n"), HEAD)

    def test_reviewed_head_reads_the_v2_field_and_the_last_line_of_either_form(self):
        other = "b" * 40
        self.assertEqual(reviewed_head(f"리뷰한 head: {HEAD}\n등급: 쉬움\n"), HEAD)
        self.assertEqual(reviewed_head(f"리뷰한 head와 되돌리기: {other}, 어려움\n리뷰한 head: {HEAD}\n"), HEAD)
        self.assertIsNone(reviewed_head("리뷰한 head:\n"))

    def test_v2_field_wins_over_a_stale_v1_paragraph_after_it(self):
        old = "b" * 40
        self.assertEqual(reviewed_head(f"리뷰한 head: {HEAD}\n등급: 어려움\n\n리뷰한 head와 되돌리기: {old}, 어려움\n"), HEAD)

    def test_doc_only_pr_passes_without_reviewed_head(self):
        v1_unreviewed = "## Review\n리뷰어(구현과 다른 컨텍스트, 도구/모델): 아직 없음.\n"
        v2_empty = "## Review\n리뷰어(구현과 다른 컨텍스트):\n리뷰한 head:\n등급: 문서\n"
        for text in ["", v1_unreviewed, v2_empty]:
            with self.subTest(text=text):
                self.assertIsNone(verdict(REF, HEAD, "x", text, ["docs/design/combat/environment.md", "README.md"], ""))

    def test_doc_only_pr_still_checks_recorded_sha_and_escalated_grade(self):
        self.assertIsNone(verdict(REF, HEAD, "x", f"리뷰한 head: {HEAD}\n등급: 문서\n", ["docs/a.md"], ""))
        self.assertIn("다릅니다", verdict(REF, HEAD, "x", f"리뷰한 head: {OTHER}\n등급: 문서\n", ["docs/a.md"], ""))
        for invalid in [
            "리뷰한 head: bbbbbbb\n등급: 문서\n",
            f"리뷰한 head: {HEAD.upper()}\n등급: 문서\n",
            "리뷰한 head: <커밋 SHA>\n등급: 문서\n",
            f"리뷰한 head: {OTHER}\n리뷰한 head:\n등급: 문서\n",
            "리뷰한 head:\n리뷰한 head와 되돌리기: bbbbbbb, 문서\n",
        ]:
            with self.subTest(invalid=invalid):
                self.assertIn("없습니다", verdict(REF, HEAD, "x", invalid, ["docs/a.md"], ""))
        for grade in ("쉬움", "어려움", "알수없음"):
            with self.subTest(grade=grade):
                self.assertIn("없습니다", verdict(REF, HEAD, "x", f"## Review\n리뷰한 head:\n등급: {grade}\n", ["docs/a.md"], ""))
        outside_override = "## Review\n리뷰한 head:\n등급: 쉬움\n## Notes\n등급: 문서\n"
        self.assertIn("없습니다", verdict(REF, HEAD, "x", outside_override, ["docs/a.md"], ""))
        duplicate_grade = "## Review\n리뷰한 head:\n등급: 쉬움\n등급: 문서\n"
        self.assertIn("없습니다", verdict(REF, HEAD, "x", duplicate_grade, ["docs/a.md"], ""))
        duplicate_heading = "## Review\n등급: 쉬움\n## Review\n등급: 문서\n"
        self.assertIn("없습니다", verdict(REF, HEAD, "x", duplicate_heading, ["docs/a.md"], ""))

    def test_instruction_agent_config_manifest_and_linked_paths_require_reviewed_head(self):
        non_doc_sets = [
            [],
            ["docs/a.md", "scenes/a.gd"],
            ["docs/a.md", "docs/img.png"],
            ["AGENTS.md"],
            ["CLAUDE.md"],
            ["REVIEW.md"],
            ["docs/agents/review.md"],
            [".github/pull_request_template.md"],
            [".claude/skills/pr/SKILL.md"],
            [".agents/a.md"],
            [".codex/a.md"],
            [".cursor/a.md"],
            [".baseline/a.md"],
            [".mise/tasks/README.md"],
            ["mise/README.md"],
            ["prompts/review.md"],
            ["docs/skills/a.md"],
            [".env.example.md"],
            ["requirements.txt"],
            ["docs/requirements-dev.txt"],
            ["docs/\x1b.md"],
        ]
        for paths in non_doc_sets:
            with self.subTest(paths=paths):
                self.assertIn("없습니다", verdict(REF, HEAD, "x", body(), paths, ""))
        self.assertIn("없습니다", verdict(REF, HEAD, "x", "", ["docs/a.md"], "", has_linked=True))

    def test_git_changed_detects_renames_deletes_and_symlinks(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@e",
                   "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@e"}
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            (root / "scenes").mkdir()
            (root / "scenes" / "a.gd").write_text("extends Node\n", encoding="utf-8")
            (root / "docs").mkdir()
            (root / "docs" / "old.md").write_text("hi\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=root, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "base"], cwd=root, env=env, check=True)
            base = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()

            (root / "docs" / "moved.md").write_text("extends Node\n", encoding="utf-8")
            (root / "scenes" / "a.gd").unlink()
            (root / "docs" / "old.md").unlink()
            (root / "docs" / "link.md").symlink_to("../README.md")
            subprocess.run(["git", "add", "-A"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "head"], cwd=root, env=env, check=True)

            old_cwd = os.getcwd()
            try:
                os.chdir(root)
                changed, has_linked = git_changed(base, "HEAD")
            finally:
                os.chdir(old_cwd)
            self.assertEqual(set(changed), {"scenes/a.gd", "docs/moved.md", "docs/old.md", "docs/link.md"})
            self.assertTrue(has_linked)


if __name__ == "__main__":
    unittest.main()
