#!/usr/bin/env python3
"""Require GameSave.FORMAT_VERSION bump when enemy dice shrink or stage rosters change."""

from pathlib import Path
import re
import subprocess
import sys

ENEMY_DEFS_PATH = "scenes/combat/enemy_definitions.gd"
GAME_SAVE_PATH = "scenes/save/game_save.gd"
STAGES_GLOB = "scenes/combat/stages/*_enemies.tscn"

ENEMY_BLOCK = re.compile(
    r'^static\s+var\s+([A-Z0-9_]+)\s*:\s*Dictionary\s*=\s*\{(.*?)^\}',
    re.M | re.S,
)
ABILITIES = re.compile(r'"abilities"\s*:\s*\[([^\]]+)\]')
FORMAT_VERSION = re.compile(r'^\s*const\s+FORMAT_VERSION\s*:\s*int\s*=\s*(\d+)', re.M)
NODE_HEADER = re.compile(r'^\[node\s+name="([^"]+)"\s+parent="\."(?:\s+[^\]]*)?\]')
KIND_LINE = re.compile(r'^kind\s*=\s*(\d+)\b')


def parse_enemy_abilities(text):
    """Return {ENEMY_NAME: [die_size, ...]} from enemy_definitions.gd text."""
    result = {}
    for match in ENEMY_BLOCK.finditer(text):
        abilities = ABILITIES.search(match.group(2))
        if abilities:
            result[match.group(1)] = [int(part.strip()) for part in abilities.group(1).split(",") if part.strip()]
    return result


def parse_stage_enemies(text):
    """Return ordered list of enemy kind ints for top-level enemy nodes in *_enemies.tscn."""
    enemies = []
    in_enemy = False
    current_kind = None
    for line in text.splitlines():
        if line.startswith("["):
            if in_enemy:
                enemies.append(0 if current_kind is None else current_kind)
            in_enemy = bool(NODE_HEADER.match(line))
            current_kind = None
        elif in_enemy:
            kind = KIND_LINE.match(line.strip())
            if kind:
                current_kind = int(kind.group(1))
    if in_enemy:
        enemies.append(0 if current_kind is None else current_kind)
    return enemies


def parse_format_version(text):
    """Return GameSave.FORMAT_VERSION integer, or None if missing."""
    match = FORMAT_VERSION.search(text)
    return int(match.group(1)) if match else None


def find_save_incompatibilities(old_defs_text, new_defs_text, old_stages, new_stages):
    """Return reasons requiring a GameSave.FORMAT_VERSION bump."""
    reasons = []
    old_defs = parse_enemy_abilities(old_defs_text)
    new_defs = parse_enemy_abilities(new_defs_text)
    for name, old_abilities in sorted(old_defs.items()):
        if name not in new_defs:
            reasons.append(f"{ENEMY_DEFS_PATH}: {name} 정의가 삭제됨")
            continue
        new_abilities = new_defs[name]
        if len(new_abilities) != len(old_abilities):
            reasons.append(f"{ENEMY_DEFS_PATH}: {name} 능력치 주사위 수 변경")
        elif any(new < old for old, new in zip(old_abilities, new_abilities)):
            reasons.append(f"{ENEMY_DEFS_PATH}: {name} 능력치 주사위 면 수 축소 ({old_abilities} -> {new_abilities})")

    for path in sorted(set(old_stages) | set(new_stages)):
        if path not in new_stages:
            reasons.append(f"{path}: 적 배치 장면이 삭제됨")
            continue
        if path not in old_stages:
            continue
        old_roster = parse_stage_enemies(old_stages[path])
        new_roster = parse_stage_enemies(new_stages[path])
        if old_roster != new_roster:
            reasons.append(f"{path}: 적 배치 수 또는 종류 순서 변경 ({len(old_roster)} -> {len(new_roster)})")
    return reasons


def check_texts(old_defs_text, new_defs_text, old_stages, new_stages, old_save_text, new_save_text):
    """Verify FORMAT_VERSION increases when incompatible monster or stage changes occur."""
    reasons = find_save_incompatibilities(old_defs_text, new_defs_text, old_stages, new_stages)
    if not reasons:
        return []
    old_version = parse_format_version(old_save_text)
    new_version = parse_format_version(new_save_text)
    if old_version is None or new_version is None or new_version <= old_version:
        joined = "; ".join(reasons)
        return [
            f"{GAME_SAVE_PATH}: FORMAT_VERSION을 올리지 않음 ({old_version} -> {new_version}): {joined}"
        ]
    return []


def _git_output(root, *args):
    return subprocess.check_output(["git", *args], cwd=root, text=True, stderr=subprocess.DEVNULL)


def _git_show(root, commit, rel_path):
    proc = subprocess.run(
        ["git", "show", f"{commit}:{rel_path}"],
        cwd=root,
        capture_output=True,
        text=True,
    )
    return proc.stdout if proc.returncode == 0 else None


def check_repo(root, base_ref="origin/main"):
    """Compare working tree against merge-base with base_ref; skip cleanly if base_ref is absent."""
    root = Path(root)
    try:
        commit = _git_output(root, "rev-parse", "--verify", "--end-of-options", f"{base_ref}^{{commit}}").strip()
        base = _git_output(root, "merge-base", "HEAD", commit).strip()
    except (OSError, subprocess.CalledProcessError):
        return []

    old_defs = _git_show(root, base, ENEMY_DEFS_PATH) or ""
    new_defs_path = root / ENEMY_DEFS_PATH
    new_defs = new_defs_path.read_text(encoding="utf-8") if new_defs_path.is_file() else ""

    old_save = _git_show(root, base, GAME_SAVE_PATH) or ""
    new_save_path = root / GAME_SAVE_PATH
    new_save = new_save_path.read_text(encoding="utf-8") if new_save_path.is_file() else ""

    base_stage_names = [
        line for line in _git_output(root, "ls-tree", "-r", "--name-only", base, "--", STAGES_GLOB).splitlines()
        if line
    ]
    old_stages = {name: (_git_show(root, base, name) or "") for name in base_stage_names}
    new_stages = {
        path.relative_to(root).as_posix(): path.read_text(encoding="utf-8")
        for path in sorted(root.glob(STAGES_GLOB))
    }
    return check_texts(old_defs, new_defs, old_stages, new_stages, old_save, new_save)


def main():
    problems = check_repo(Path(__file__).resolve().parents[1])
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print("적 주사위 면 수 축소나 스테이지 배치 수 변경 시 GameSave.FORMAT_VERSION을 올리고 docs/adr/0003-save-files.md를 갱신합니다.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
