#!/usr/bin/env python3
"""Ratchet check preventing new occurrences of removed terms in active docs and game files."""

from pathlib import Path
import subprocess
import sys

SCAN_TARGETS = ("docs", "GLOSSARY.md", "README.md", "scenes", "tests", "locale")
SKIP_SUFFIXES = (".png", ".ogg", ".ttf", ".bin", ".import", ".uid")

# Ratchet ceiling per removed term. Lower these numbers as stale references are cleaned up.
BASELINE = {
    "독 장판": 5,
    "시험값": 16,
    "시험 아이템": 0,
    "기름병 추가 전": 0,
    "위임 초기 권장안": 0,
}


def scan_files(root):
    listed = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *SCAN_TARGETS],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split("\0")
    return sorted(
        name for name in listed
        if name
        and not name.startswith("docs/planning/")
        and not name.endswith(SKIP_SUFFIXES)
        and (Path(root) / name).is_file()
    )


def find_occurrences(root, terms=BASELINE):
    root = Path(root)
    hits = {term: [] for term in terms}
    for rel in scan_files(root):
        text = (root / rel).read_text(encoding="utf-8", errors="replace")
        for number, line in enumerate(text.splitlines(), 1):
            if rel == "GLOSSARY.md" and line.startswith("_Avoid_:"):
                continue
            for term in terms:
                if term not in line:
                    continue
                if term == "독 장판" and rel.startswith("tests/") and "삭제된 독 장판" in line:
                    continue
                for _ in range(line.count(term)):
                    hits[term].append(f"{rel}:{number}: {line.strip()}")
    return hits


def check(root, baseline=BASELINE):
    hits = find_occurrences(root, baseline)
    problems = []
    for term, limit in baseline.items():
        found = hits[term]
        if len(found) > limit:
            sample = "; ".join(found[:5])
            problems.append(
                f"폐기 용어 '{term}' 건수 증가 ({len(found)} > 기준선 {limit}): {sample}"
            )
    return problems


def main():
    problems = check(Path(__file__).resolve().parents[1])
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
