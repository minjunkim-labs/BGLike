#!/usr/bin/env python3
"""Fail when a GDScript file lacks its Godot .gd.uid sidecar file."""

from pathlib import Path
import subprocess
import sys


def _git_files(root, *args):
    listed = subprocess.run(
        ["git", "ls-files", "-z", *args],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split("\0")
    return [name for name in listed if name]


def check(root):
    root = Path(root)
    tracked_gd = _git_files(root, "--cached", "--", "*.gd")
    tracked_uid = set(_git_files(root, "--cached", "--", "*.gd.uid"))
    untracked_gd = _git_files(root, "--others", "--exclude-standard", "--", "*.gd")

    problems = []
    for name in sorted(set(tracked_gd)):
        if not (root / name).is_file():
            continue
        uid_name = f"{name}.uid"
        if uid_name not in tracked_uid:
            problems.append(f"{name}: 대응하는 {uid_name} 파일이 git에 추적되지 않음")
    for name in sorted(set(untracked_gd)):
        uid_name = f"{name}.uid"
        if not (root / uid_name).is_file():
            problems.append(f"{name}: 대응하는 {uid_name} 파일이 없음")
    return problems


def main():
    problems = check(Path(__file__).resolve().parents[1])
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(
            "새 GDScript 파일은 Godot --import로 생성된 .gd.uid 파일과 함께 커밋합니다.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
