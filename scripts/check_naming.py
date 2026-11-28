#!/usr/bin/env python3
"""Verify scenes/ and tests/ paths use lowercase snake_case names."""

from pathlib import Path
import re
import subprocess
import sys

SNAKE_CASE_PART = re.compile(r"^[a-z0-9_]+(\.[a-z0-9_]+)*$")
EXCLUDED_PREFIXES = (
    "scenes/combat/art/sources/",
    "scenes/combat/audio/sources/",
    "scenes/ui/fonts/",
)


def is_excluded(rel_path):
    if rel_path.endswith("/.gdignore") or rel_path == ".gdignore":
        return True
    return rel_path.startswith(EXCLUDED_PREFIXES)


def check(root):
    root = Path(root)
    listed = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "scenes", "tests"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split("\0")
    problems = []
    for rel in sorted(name for name in listed if name):
        if is_excluded(rel):
            continue
        for part in Path(rel).parts:
            if not SNAKE_CASE_PART.match(part):
                problems.append(f"{rel}: 소문자 snake_case가 아닌 경로 요소 '{part}'")
                break
    return problems


def main():
    problems = check(Path(__file__).resolve().parents[1])
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print("scenes/와 tests/의 리소스 파일과 폴더 이름은 소문자 snake_case를 씁니다 (docs/process/coding-standards.md).",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
