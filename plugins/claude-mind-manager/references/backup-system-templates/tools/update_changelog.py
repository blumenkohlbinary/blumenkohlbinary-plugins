#!/usr/bin/env python3
"""update_changelog.py - Generiert CHANGELOG.md aus Conventional-Commits.

Installiert von claude-mind-manager v3.3.0 (mind-files Skill).
Adaptiert aus Zustellplan-App (update_changelog.py), generisch fuer beliebige Projekte.

Conventional-Commits-Pattern:
    <type>(<scope>)!: <subject>

    feat, fix, refactor, perf, test, docs, build, chore, style, revert, release

CLI:
    python tools/update_changelog.py                    # Schreibt CHANGELOG.md
    python tools/update_changelog.py --print            # Druckt nach stdout
    python tools/update_changelog.py --since v1.0.0     # Nur seit Tag X
    python tools/update_changelog.py --output FILE      # Custom output

__version__ = 1.0.0
"""
from __future__ import annotations
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path


__version__ = "1.0.0"

ROOT = Path.cwd()
CHANGELOG_PATH = ROOT / "CHANGELOG.md"

CONVENTIONAL_RE = re.compile(
    r'^(?P<type>feat|fix|refactor|perf|test|docs|build|chore|style|revert|release)'
    r'(?:\((?P<scope>[\w/.-]+)\))?'
    r'(?P<breaking>!)?'
    r':\s*(?P<subject>.+)$'
)

# (Section-Title, Sort-Order) pro Type
TYPE_SECTIONS = {
    "feat":     ("Features", 1),
    "fix":      ("Bug Fixes", 2),
    "perf":     ("Performance", 3),
    "refactor": ("Refactoring", 4),
    "docs":     ("Documentation", 5),
    "test":     ("Tests", 6),
    "build":    ("Build System", 7),
    "chore":    ("Chores", 8),
    "style":    ("Style", 9),
    "revert":   ("Reverts", 10),
    "release":  ("Releases", 11),
}


def run_git(args: list[str]) -> str:
    """Fuehrt git aus. Leerer String bei Fehler."""
    try:
        result = subprocess.run(
            ["git"] + args, cwd=str(ROOT),
            capture_output=True, text=True, encoding='utf-8', timeout=30,
        )
        return result.stdout.strip() if result.returncode == 0 else ""
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def get_tags() -> list[tuple[str, str]]:
    """Liste von (tag, date), aelteste zuerst."""
    out = run_git(["for-each-ref", "--sort=creatordate",
                   "--format=%(refname:short)|%(creatordate:short)",
                   "refs/tags/v*"])
    if not out:
        return []
    tags = []
    for line in out.splitlines():
        if "|" in line:
            tag, date = line.split("|", 1)
            tags.append((tag.strip(), date.strip()))
    return tags


def get_commits_between(from_ref: str | None, to_ref: str = "HEAD") -> list[dict]:
    """Liest Commits zwischen Refs."""
    rev_range = f"{from_ref}..{to_ref}" if from_ref else to_ref
    SEP = "\x1e"   # record separator
    FSEP = "\x1f"  # field separator
    out = run_git([
        "log", rev_range,
        f"--pretty=format:%H{FSEP}%s{FSEP}%b{SEP}",
    ])
    if not out:
        return []
    commits = []
    for record in out.split(SEP):
        record = record.strip()
        if not record:
            continue
        parts = record.split(FSEP)
        if len(parts) < 2:
            continue
        commits.append({
            "hash": parts[0].strip(),
            "subject": parts[1].strip(),
            "body": parts[2].strip() if len(parts) > 2 else "",
        })
    return commits


def parse_conventional(commit: dict) -> dict | None:
    """Parse Subject zu (type, scope, subject, breaking). None bei non-conventional."""
    m = CONVENTIONAL_RE.match(commit["subject"])
    if not m:
        return None
    breaking = bool(m.group("breaking"))
    if "BREAKING CHANGE:" in commit["body"] or "BREAKING-CHANGE:" in commit["body"]:
        breaking = True
    return {
        "hash": commit["hash"],
        "type": m.group("type"),
        "scope": m.group("scope"),
        "subject": m.group("subject"),
        "breaking": breaking,
        "body": commit["body"],
    }


def render_section(version: str, date: str, parsed_commits: list[dict]) -> str:
    """Rendert einen Versions-Block in Markdown."""
    lines = [f"## [{version}] - {date}", ""]
    if not parsed_commits:
        lines.append("_Keine Conventional-Commits in diesem Bereich._")
        lines.append("")
        return "\n".join(lines)

    # Breaking-Changes oben
    breakings = [c for c in parsed_commits if c["breaking"]]
    if breakings:
        lines.append("### BREAKING CHANGES")
        lines.append("")
        for c in breakings:
            scope = f"**{c['scope']}**: " if c["scope"] else ""
            lines.append(f"- {scope}{c['subject']} ({c['hash'][:7]})")
        lines.append("")

    # Gruppiere nach type
    grouped = defaultdict(list)
    for c in parsed_commits:
        grouped[c["type"]].append(c)

    for typ, (sec_title, _order) in sorted(TYPE_SECTIONS.items(), key=lambda x: x[1][1]):
        if typ not in grouped:
            continue
        lines.append(f"### {sec_title}")
        lines.append("")
        for c in grouped[typ]:
            scope = f"**{c['scope']}**: " if c["scope"] else ""
            lines.append(f"- {scope}{c['subject']} ({c['hash'][:7]})")
        lines.append("")

    return "\n".join(lines)


def generate_changelog(since: str | None = None) -> str:
    """Generiert komplette CHANGELOG.md."""
    out = ["# Changelog", "",
           "Alle nennenswerten Aenderungen werden hier dokumentiert.",
           "",
           "Format: [Keep a Changelog](https://keepachangelog.com/de/1.1.0/) | "
           "Versionierung: [SemVer](https://semver.org/lang/de/)",
           ""]

    tags = get_tags()
    if not tags:
        commits = [parse_conventional(c) for c in get_commits_between(None)]
        commits = [c for c in commits if c is not None]
        out.append(render_section("Unreleased",
                                  datetime.now().strftime("%Y-%m-%d"), commits))
        return "\n".join(out)

    # Unreleased = Commits nach letztem Tag
    last_tag, _ = tags[-1]
    unreleased = get_commits_between(last_tag, "HEAD")
    unreleased_parsed = [parse_conventional(c) for c in unreleased]
    unreleased_parsed = [c for c in unreleased_parsed if c is not None]
    if unreleased_parsed:
        out.append(render_section("Unreleased",
                                  datetime.now().strftime("%Y-%m-%d"),
                                  unreleased_parsed))

    # Pro Tag-Bereich (neueste zuerst)
    for i, (tag, date) in enumerate(reversed(tags)):
        prev_idx = len(tags) - 2 - i
        prev_tag = tags[prev_idx][0] if prev_idx >= 0 else None

        if since and tag != since and prev_tag and prev_tag < since:
            break

        commits = get_commits_between(prev_tag, tag)
        parsed = [parse_conventional(c) for c in commits]
        parsed = [c for c in parsed if c is not None]
        version = tag.lstrip("v")
        out.append(render_section(version, date, parsed))

    return "\n".join(out)


def main(argv: list[str]) -> int:
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0

    print_only = "--print" in argv
    since = None
    if "--since" in argv:
        idx = argv.index("--since")
        if idx + 1 < len(argv):
            since = argv[idx + 1]

    output_path = CHANGELOG_PATH
    if "--output" in argv:
        idx = argv.index("--output")
        if idx + 1 < len(argv):
            output_path = Path(argv[idx + 1])
            # Security-Fix CWE-22: --output muss unter Projekt-Root liegen
            try:
                resolved = output_path.resolve()
                resolved.relative_to(ROOT.resolve())
            except ValueError:
                print(f"FEHLER: --output '{argv[idx + 1]}' ausserhalb Projekt-Root", file=sys.stderr)
                print(f"        Erlaubt sind nur Pfade unter: {ROOT.resolve()}", file=sys.stderr)
                print(f"        Workaround fuer externe Pfade: --print > <pfad>", file=sys.stderr)
                return 2
            output_path = resolved

    if not (ROOT / ".git").exists():
        print("FEHLER: Kein .git/ Verzeichnis. update_changelog.py braucht Git.", file=sys.stderr)
        return 1

    content = generate_changelog(since=since)

    if print_only:
        print(content)
    else:
        output_path.write_text(content, encoding='utf-8')
        print(f"OK: CHANGELOG geschrieben -> {output_path}")
        # Line-Count fuer Feedback
        line_count = len(content.splitlines())
        print(f"     {line_count} Zeilen ({len(content)} chars)")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
