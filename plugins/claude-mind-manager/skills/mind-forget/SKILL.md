---
name: mind-forget
description: |
  [Mind Manager] Search for and remove specific entries from context files. Searches across CLAUDE.md
  (all scopes), MEMORY.md, rules, and topic files with case-insensitive matching.
  Shows surrounding context before removal to prevent accidental deletions.

  Use when the user says "forget this", "remove from memory", "mind forget",
  "delete that rule", "remove the preference about...", or "/mind-forget [search term]".
argument-hint: "<search term>"
context: inherit
allowed-tools: Read Glob Grep Edit
---

# Guided Forget

Search and remove specific entries from context files with safety checks.

## Objective

Find entries matching a search term across all context files, show them with context, and remove selected entries after user confirmation.

## Workflow

### Step 1: Parse Arguments

- `$ARGUMENTS` is the search term
- If no arguments, ask: "What should I forget? Provide a keyword or phrase."

### Step 2: Search All Context Files

Use Grep with case-insensitive matching (`-i`) across:
- `~/.claude/CLAUDE.md`
- `./CLAUDE.md`, `./.claude/CLAUDE.md`
- `./CLAUDE.local.md`
- `.claude/rules/*.md`
- `~/.claude/rules/*.md`
- MEMORY.md (at `~/.claude/projects/<hash>/memory/MEMORY.md`)
- All topic files in `<cwd>/.claude-mind/`

### Step 3: Present Matches with Context

Show 2 lines before and after each match for safety:

```
Found 3 matches for "vitest":

[1] MEMORY.md:23
    21: - Build: npm run build
    22: - Test: npm test
  > 23: - User prefers vitest over jest for testing
    24: - Coverage: npm run coverage
    25:

[2] CLAUDE.md:45
    43: ## Testing
    44: - Run single test: npx vitest run path/to/test
  > 45: - Test runner: vitest
    46: - Coverage threshold: 80%
    47:

[3] .claude/rules/testing.md:8
    6: # Testing Rules
    7: - Use describe/it pattern
  > 8: - Use vitest for all *.test.ts files
    9: - Mock external APIs with msw
    10:

Remove which? [1,2,3 / all / none]
```

### Step 4: Remove Selected Entries

On selection, use Edit to remove the selected line(s). For multi-line entries (recognized by indentation), remove the entire block.

### Step 5: Confirm Result

```
Removed 1 entry:
- MEMORY.md:23 "User prefers vitest over jest for testing"

MEMORY.md: 195 → 194 lines
```

## Hard Constraints

- NEVER remove without showing matches with surrounding context
- NEVER remove entries without explicit user selection
- ALWAYS show 2 lines before and after each match
- ALWAYS show updated line count after removal
- If no matches found, report: "No matches found for '[term]' in any context file."
