"""Merge queue check: the queued PR head must be the head its review recorded (POLICY §5).

Run it in a `merge_group` job. GitHub names the queue branch `gh-readonly-queue/<base>/pr-<N>-<SHA>`; that
SHA is the queue base, not the PR head, so only N is read from it. The script reads the PR head and body with
`gh api` and compares the head with the last 「리뷰한 head:」 line in the body (v2 review-report), or the v1
「리뷰한 head와 되돌리기:」 line.
A push to a queued PR removes it from the queue, so the head read here is the head that was queued.

This catches a head that moved after review. It is not a security boundary: anyone who can edit the PR body
can write any SHA there. Three kinds of PR pass without a review:
- Dependabot, by the queue commit's author email (no other account can claim that noreply address).
- repo-baseline sync PRs: the Author line names tools/sync_consumers.py, the base already has the manifest
  (migration PRs need review), and every changed path is the manifest or a path the base manifest records
  (POLICY §5 lets those go to the queue without review).
- Documentation-only PRs (POLICY §3): every changed path is a regular doc file (not instruction, agent,
  config, dependency manifest, symlink/submodule, or non-printable paths), the ## Review section does not
  report a non-doc grade (쉬움/어려움), and no 「리뷰한 head:」 value was recorded (if any value was
  recorded, it must be a valid 40-char SHA matching the queued head).

Usage (environment): QUEUE_REF, QUEUE_AUTHOR, BASE_SHA, GITHUB_REPOSITORY, GH_TOKEN.
"""

import fnmatch
import json
import os
import re
import subprocess
import sys

DEPENDABOT = "49699333+dependabot[bot]@users.noreply.github.com"
MANIFEST = ".github/repo-baseline.json"
SYNC_AUTHOR = "tools/sync_consumers.py"
DOC_SUFFIXES = (".md", ".mdx", ".rst", ".txt", ".adoc")
INSTRUCTIONS = {"AGENTS.MD", "CLAUDE.MD", "REVIEW.MD"}
NON_DOC_DIRS = {".claude", ".agents", ".codex", ".cursor", ".github", ".baseline", ".mise", "mise", "prompts", "skills"}
SPECIAL_MODES = {"120000", "160000"}


def queued(ref):
    """The PR number from a merge queue ref (`refs/heads/` optional), or None."""
    match = re.fullmatch(r"(?:refs/heads/)?gh-readonly-queue/.+/pr-([0-9]+)-[0-9a-f]{40}", ref or "")
    return match.group(1) if match else None


def review_lines(body):
    """Matching review-head lines: v2 「리뷰한 head:」 if present, else v1 「리뷰한 head와 되돌리기:」."""
    body = (body or "").replace("\r\n", "\n")
    return re.findall(r"^리뷰한 head:(.*)$", body, re.M) or re.findall(r"^리뷰한 head와 되돌리기:(.*)$", body, re.M)


def reviewed_head(body):
    """The SHA on the last 「리뷰한 head:」 line, else the last v1 「리뷰한 head와 되돌리기:」 line, or None.

    v2 review-report keeps a trailing v1-only paragraph, so a stale v1 SHA can come after the new v2 field.
    """
    lines = review_lines(body)
    match = re.match(r"\s*`?([0-9a-f]{40})\b", lines[-1]) if lines else None
    return match.group(1) if match else None


def has_recorded_review(body):
    """True if any v2 or v1 review-head line contains non-whitespace text."""
    body = (body or "").replace("\r\n", "\n")
    lines = re.findall(r"^리뷰한 head:(.*)$", body, re.M) + re.findall(r"^리뷰한 head와 되돌리기:(.*)$", body, re.M)
    return any(line.strip() for line in lines)


def managed_paths(manifest_text):
    """Paths a sync PR may change: the manifest, its copied files, and its block targets."""
    if not manifest_text:
        return set()
    manifest = json.loads(manifest_text)
    paths = {MANIFEST, *manifest.get("files", {})}
    paths.update(block["target"] for block in manifest.get("blocks", {}).values() if "target" in block)
    return paths


def is_sync(body, changed, manifest_text):
    author = next((line for line in (body or "").splitlines() if line.startswith("Author:")), "")
    allowed = managed_paths(manifest_text)
    return SYNC_AUTHOR in author and bool(changed) and set(changed) <= allowed


def is_doc_path(path):
    """True only for regular documentation files outside instruction, agent, manifest, and config paths."""
    if not path or not path.isprintable():
        return False
    parts = path.split("/")
    name = parts[-1]
    if not name.endswith(DOC_SUFFIXES):
        return False
    if name.upper() in INSTRUCTIONS or name == "SKILL.md" or fnmatch.fnmatchcase(name, "requirements*.txt"):
        return False
    if any(part in NON_DOC_DIRS or part.startswith(".env") for part in parts):
        return False
    return not path.startswith("docs/agents/")


def is_doc_only(changed):
    return bool(changed) and all(is_doc_path(path) for path in changed)


def review_section(body):
    """The single `## Review` section body, whole body if absent, or None if duplicated."""
    normalized = (body or "").replace("\r\n", "\n")
    headings = list(re.finditer(r"^## Review[ \t]*$", normalized, re.M))
    if not headings:
        return normalized
    if len(headings) > 1:
        return None
    rest = normalized[headings[0].end():]
    next_heading = re.search(r"^## ", rest, re.M)
    return rest[:next_heading.start()] if next_heading else rest


def reported_grade(body):
    """The single 「등급:」 value in `## Review`, or '어려움' if ambiguous."""
    section = review_section(body)
    if section is None:
        return "어려움"
    grades = re.findall(r"^등급:(.*)$", section, re.M)
    if len(grades) > 1:
        return "어려움"
    return grades[0].strip().strip("`") if grades else ""


def verdict(ref, head, author_email, body, changed, manifest_text, has_linked=False):
    """None when the queued head may merge, else the reason it may not.

    manifest_text is the base commit's manifest, so a migration PR (no manifest in base) is not a sync PR.
    """
    number = queued(ref)
    if not number:
        return f"머지 큐 브랜치 이름을 읽지 못했습니다: {ref!r}"
    if author_email == DEPENDABOT:
        return None
    if is_sync(body, changed, manifest_text):
        return None
    review = reviewed_head(body)
    grade = reported_grade(body)
    if not has_linked and not has_recorded_review(body) and is_doc_only(changed) and grade in ("", "문서"):
        return None
    if not review:
        return f"PR #{number} 본문 Review 칸에 「리뷰한 head:」 SHA가 없습니다."
    if review != head:
        return (f"PR #{number}을 큐에 넣은 head {head[:12]}가 리뷰한 head {review[:12]}와 다릅니다. "
                "새 head를 다른 컨텍스트가 다시 리뷰하고 그 SHA로 큐에 넣습니다.")
    return None


def git_changed(base, target="HEAD"):
    """Return (changed_paths, has_linked) between base and target without C-quoting or rename folding."""
    raw = subprocess.check_output(["git", "diff", "--no-renames", "--raw", "-z", base, target], text=True)
    fields = raw.split("\0")[:-1]
    changed = []
    has_linked = False
    for index in range(0, len(fields), 2):
        modes = fields[index].lstrip(":").split()
        path = fields[index + 1]
        changed.append(path)
        if len(modes) >= 2 and (modes[0] in SPECIAL_MODES or modes[1] in SPECIAL_MODES):
            has_linked = True
    if not has_linked and changed:
        linked = set()
        for ref in (base, target):
            tree = subprocess.check_output(["git", "ls-tree", "-r", "-z", ref], text=True).split("\0")[:-1]
            for entry in tree:
                meta, _, tree_path = entry.partition("\t")
                mode = meta.split()[0] if meta else ""
                if mode in SPECIAL_MODES:
                    linked.add(tree_path)
        if any("/".join(p.split("/")[:i + 1]) in linked for p in changed for i in range(p.count("/") + 1)):
            has_linked = True
    return changed, has_linked


def main():
    ref = os.environ.get("QUEUE_REF", "")
    number = queued(ref)
    head = body = manifest = ""
    changed = []
    has_linked = False
    if number:
        pr = json.loads(subprocess.check_output(
            ["gh", "api", f"repos/{os.environ['GITHUB_REPOSITORY']}/pulls/{number}",
             "--jq", "{head: .head.sha, body: (.body // \"\")}"], text=True))
        head, body = pr["head"], pr["body"]
        base = os.environ["BASE_SHA"]
        changed, has_linked = git_changed(base, "HEAD")
        shown = subprocess.run(["git", "show", f"{base}:{MANIFEST}"], capture_output=True, text=True)
        manifest = shown.stdout if shown.returncode == 0 else ""
    reason = verdict(ref, head, os.environ.get("QUEUE_AUTHOR", ""), body, changed, manifest, has_linked=has_linked)
    if reason:
        print(f"::error::{reason}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
