---
name: mind-update
description: |
  [Mind Manager] Schneller Context-Update — alle Dateien pruefen, Versionen aktualisieren, komprimieren.
  Kein Agent-Dispatch (schnell!). Prueft CLAUDE.md, MEMORY.md, Rules inline:
  Version-Mismatch, tote Pfade, fehlende Git-Commits, Budget-Ueberschreitungen,
  Rules-Syntax. Auto-Fix fuer sichere Aenderungen, Rueckfrage fuer alles andere.

  Use when the user says "update context", "refresh context", "mind update",
  "quick check", "context status", "sync context",
  or "/mind-update".
argument-hint: ""
context: inherit
allowed-tools: Read Glob Grep Edit Bash
---

# Schneller Context-Update

Alle Context-Dateien inline pruefen -> sichere Fixes auto-anwenden -> Report.

Designed to be FAST: no agent dispatch, no deep analysis, pure inline checks.

## Step 1: Alle Context-Dateien lesen

Read all context files inline (no agent dispatch):

1. **CLAUDE.md** (project): `./CLAUDE.md` or `./.claude/CLAUDE.md`
2. **CLAUDE.md** (global): `~/.claude/CLAUDE.md`
3. **MEMORY.md**: Compute hash, read `~/.claude/projects/<hash>/memory/MEMORY.md`
4. **Rules**: Glob `.claude/rules/*.md` + `~/.claude/rules/*.md`

```bash
# Hash for memory path:
PROJECT_DIR=$(pwd)
HASH=$(echo "$PROJECT_DIR" | sed 's|[/\\: ]|-|g' | sed 's|^-*||')
MEMORY_PATH="$HOME/.claude/projects/$HASH/memory/MEMORY.md"
```

Record line counts for each file immediately.

## Step 2: Referenzen laden

Read these reference files for budget thresholds:
- [references/budget-thresholds.md](../../references/budget-thresholds.md) -- SFEIR compliance data, line limits
- [references/token-budget-formulas.md](../../references/token-budget-formulas.md) -- Token calculation formulas

## Step 3: Quick Checks

Run all checks inline (no agents):

### 3a: Version Match
- Read `plugin.json` or `package.json` -> extract `"version":`
- Grep CLAUDE.md for version strings (e.g., "Version: 2.6.0", "Aktuelle Version: 2.6.0")
- Mismatch -> Finding (auto-fixable)

### 3b: Dead Paths
- Extract all file/directory paths from CLAUDE.md (backtick-wrapped, lines with `/` or `\`)
- For each path: `test -e "$path"` via Bash
- Dead path -> Finding (auto-fixable: remove or ask for replacement)

### 3c: Git Log Check
- Only if `.git/` directory exists
- Run `git log --oneline -10`
- Look for `feat:`, `fix:`, `refactor:` commits that are NOT mentioned in CLAUDE.md
- Unreflected commits -> Finding (ask user: add to CLAUDE.md?)

### 3d: MEMORY.md Budget
- Count lines in MEMORY.md
- >200 lines = CRITICAL (truncation imminent)
- >150 lines = WARNING (approaching limit)
- OK otherwise

### 3e: Rules Syntax Check
- Grep all rule files for `^paths:` (known bug -- silently ignored)
- User-level rules with `paths:` = ERROR
- Project rules with `paths:` = WARNING (auto-fixable: migrate to `globs:`)

### 3f: Total Context Budget
- Sum all context file lines: CLAUDE.md (all scopes) + MEMORY.md + all rules
- >500 lines = WARNING: "High context overhead"
- >300 lines = INFO: "Moderate context load"
- <300 lines = OK

## Step 4: Auto-Fix sichere Aenderungen

**Pre-Edit Read (MUST):** Step 1 hat zwar alle Context-Dateien gelesen, aber das
zaehlt NICHT fuer Step 4 — Claude's Edit-Tool benoetigt einen Read im SELBEN
Tool-Call-Kontext wie das Edit. Vor jedem Auto-Fix:
1. Read die Ziel-Datei (CLAUDE.md, Rule-Datei)
2. Edit ausfuehren

Sonst Crash mit `<tool_use_error>File has not been read yet`.

Apply these fixes WITHOUT asking the user, but WITH explicit Read-before-Edit:

| Fix | Condition | Action |
|---|---|---|
| Version update | CLAUDE.md version != package/plugin.json version | Edit: update version string |
| Dead path removal | Path confirmed dead via `test -e` | Edit: remove or comment out line |
| paths: -> globs: | Rule file uses `paths:` | Edit: replace with `globs:` equivalent |

For each auto-fix, log what was changed.

## Step 5: Lossless Compression

Scan CLAUDE.md for verbose lines that can be shortened without losing information:

| Pattern | Replacement |
|---|---|
| "When you are writing TypeScript code, you should always..." | "TypeScript: MUST use strict mode" |
| "It is important to note that we use..." | "Uses: <tool>" |
| "Please make sure to..." | "MUST ..." |
| "You should not..." | "NEVER ..." |
| Multi-sentence entries that could be one bullet | Single MUST/NEVER bullet |

**Only compress lines where meaning is 100% preserved.** If unsure, skip.

Show compressed lines for user approval before applying:
```
Compression candidates (3):
[1] CLAUDE.md:12 "When writing tests, always use..." -> "Tests: MUST use vitest"
[2] CLAUDE.md:45 "Please note that the build..." -> "Build: `npm run build` (required before PR)"
[3] CLAUDE.md:78 "You should never commit..." -> "NEVER commit .env files"

Apply compressions? [Yes / Select / Skip]
```

## Step 6: Report

```
=== Context Update ===
Checked: 4 files | Issues: 3 | Auto-fixed: 2 | Needs input: 1

CLAUDE.md (project): 145 -> 138 lines (-7)
  [AUTO] Version 2.5.0 -> 2.6.0
  [AUTO] Removed dead path: src/old-module/
  [SKIP] 2 unreflected git commits (feat: dark mode, fix: login) -- add to CLAUDE.md?

MEMORY.md: 89 lines (OK, within 200 budget)
Rules: 3 files, all valid syntax
Global CLAUDE.md: 55 lines (OK)

Total context: 287 lines (~2870 tokens) -- Compliance: ~92%
```

If there are pending items (unreflected commits, compression candidates), ask:
"Want me to add the 2 unreflected commits to CLAUDE.md? [Yes / Skip]"

## Hard Constraints

- MUST be fast: NO Agent tool dispatch (all checks inline)
- Auto-fix ONLY safe changes: version numbers, dead paths, paths: -> globs: migration
- ASK for everything else: compression, adding git commits, removing content
- ALWAYS show what was auto-fixed in the report
- ALWAYS show before/after line counts
- ALWAYS backup files before editing (cp to .claude-mind/backups/)
- NEVER remove content without showing what will be lost
- If no issues found: report "All clean" and stop (no unnecessary changes)
