---
name: mind-cleanup
description: |
  [Mind Manager] Interactive cleanup of context files with confirmation before each change. Removes
  stale entries, deduplicates, compacts overflowing MEMORY.md, migrates entries to
  topic files. Semi-automatic: exact duplicates and trailing whitespace auto-fixed,
  everything else requires confirmation.

  Use when the user says "clean up my context", "tidy memory", "mind cleanup",
  "memory is full", "compact memory", "deduplicate", or "/mind-cleanup".
argument-hint: "[memory|claude-md|rules|all]"
context: inherit
allowed-tools: Read Glob Grep Edit Bash
---

# Interactive Cleanup

Clean up context files with confirmation-based workflow.

## Objective

Identify and resolve quality issues in context files. Auto-fix obvious problems (exact duplicates, whitespace). Require confirmation for everything else.

## Workflow

### Step 1: Parse Arguments

Target scope from `$ARGUMENTS`:
- `memory` — MEMORY.md and topic files only
- `claude-md` — CLAUDE.md files only
- `rules` — rule files only
- `all` (default) — everything

### Step 2: Lightweight Audit

Run inline analysis (no agents — speed over depth):

1. Read all files in target scope
2. **Exact duplicates:** Lines appearing identically in same file or across files
3. **Stale entries:** Version numbers (Node 18, React 17), outdated patterns
4. **Budget overflow:** MEMORY.md >180 lines, CLAUDE.md >200 lines
5. **Empty/whitespace lines** at end of files
6. **Misplaced content:** Conventions in MEMORY.md (should be CLAUDE.md), personal prefs in project CLAUDE.md

### Step 3: Auto-Fix (No Confirmation Needed)

Apply automatically and report:
- Exact duplicate lines (100% identical, same file)
- Trailing empty lines at end of file
- Trailing whitespace on lines

```
Auto-fixed:
- MEMORY.md: removed 3 trailing empty lines
- CLAUDE.md: removed 1 exact duplicate (line 45 = line 12)
```

### Step 4: Interactive Fixes (Confirmation Required)

Present each issue individually:

```
[1/N] MEMORY.md:15 — Stale version reference
  Current: "Project uses Node 18 LTS"
  Suggestion: Remove (Node 20 is current) or update?
  [R] Remove  [U] Update to "Node 20 LTS"  [S] Skip

[2/N] MEMORY.md:34 — Misplaced content
  Current: "Always use conventional commits"
  This is a project convention → belongs in CLAUDE.md
  [M] Move to CLAUDE.md  [K] Keep in MEMORY.md  [S] Skip

[3/N] MEMORY.md approaching limit (192/200 lines)
  Suggest offloading to topic files:
  - Lines 45-67: Debugging notes → .claude-mind/debugging.md
  - Lines 80-95: API patterns → .claude-mind/api-conventions.md
  [O] Offload suggested entries  [S] Skip
```

### Step 5: Apply Changes

Use Edit to apply confirmed changes. For topic file offloading, use Write to create new topic files and Edit to remove offloaded lines from MEMORY.md.

### Step 6: Summary

```
=== Cleanup Complete ===

Auto-fixed: 4 items
User-confirmed: 6 items
Skipped: 2 items

| File | Before | After | Saved |
|------|--------|-------|-------|
| MEMORY.md | 195 lines | 142 lines | 53 lines (~398 tokens) |
| CLAUDE.md | 182 lines | 180 lines | 2 lines (~20 tokens) |
| .claude-mind/debugging.md | (new) | 22 lines | — |

Total savings: ~418 tokens
```

## Hard Constraints

- NEVER delete content without confirmation (except exact duplicates and whitespace)
- NEVER exceed 200 lines when adding to MEMORY.md
- ALWAYS show the current content before proposing changes
- ALWAYS show a summary with before/after line counts
- ALWAYS create topic files when offloading from MEMORY.md (never just delete)
