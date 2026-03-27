---
name: mind-import
description: |
  [Mind Manager] Import knowledge from other Claude Code projects. Discovers all projects via
  ~/.claude/projects/, shows their MEMORY.md content, and allows selective import
  into the current project. Uses the same classification logic as /mind-remember.

  Use when the user says "import from project", "cross-project", "mind import",
  "knowledge from other project", "bring over settings", or "/mind-import [project]".
argument-hint: "[project-name or path]"
context: inherit
allowed-tools: Read Glob Grep Edit Write Bash
---

# Cross-Project Import

Import knowledge from other Claude Code projects into the current one.

## Objective

Discover available projects, let user select entries to import, classify and insert them into the correct target file.

## Workflow

### Step 1: Discover Projects

List all directories in `~/.claude/projects/`:
```bash
ls -d ~/.claude/projects/*/
```

For each directory:
- Extract project hash (directory name)
- Best-effort decode to original path (replace `-` with path separators — note ambiguity)
- Check if `memory/MEMORY.md` exists
- Count lines

### Step 2: Present Project List

If no project specified in `$ARGUMENTS`, show all:

```
=== Available Projects ===

| # | Project (best-effort decode) | Memory Lines | Topic Files |
|---|----------------------------|-------------|-------------|
| 1 | Z:\APPBASE\CD\KOHLEKTIV\APP - Zustellplan | 45 lines | 2 files |
| 2 | Z:\APPBASE\CD\KOHLEKTIV\Compress - Dokumente | 120 lines | 0 files |
| 3 | C:\Users\HackJ\Neuer Ordner (2) | 30 lines | 1 file |

Note: Project paths are decoded from hashes. Paths with hyphens
may decode incorrectly (ambiguity between space/hyphen/slash).

Select project [1-3]:
```

### Step 3: Show Source Content

Read and display the selected project's MEMORY.md and topic files:

```
=== Project: APP — MEMORY.md (45 lines) ===

1: # Auto Memory
2:
3: ## TDO v11.2
4: - Plugin path: ...
5: - User commands: /tdo:compress, /tdo:fuse-docs
...

Select entries to import (line numbers, ranges, or 'all'):
Example: 3-5, 12, 20-25
```

### Step 4: Classify Imported Entries

For each selected entry, use the same classification logic as `/mind-remember`:
- Project convention → CLAUDE.md
- Learned pattern → MEMORY.md
- File-scoped rule → .claude/rules/
- Cross-project preference → ~/.claude/CLAUDE.md

### Step 5: Budget Check

Before inserting:
- Check MEMORY.md line count if target is MEMORY.md
- Warn if import would exceed 200 lines
- Suggest topic file or CLAUDE.md as alternative

### Step 6: Confirm and Insert

```
=== Import Plan ===

From: APP
To: Plugin - Entwicklung (current project)

| Entry | Target | Lines |
|-------|--------|-------|
| "TDO plugin commands" | MEMORY.md | 3 |
| "Build: npm run build" | CLAUDE.md | 1 |

Current MEMORY.md: 185 lines → After import: 188 lines (OK)

Confirm? [Y/n]
```

Apply with Edit on confirmation.

## Hard Constraints

- NEVER import automatically — ALWAYS show source content first
- NEVER exceed 200 lines in MEMORY.md through import
- ALWAYS warn about hash-to-path ambiguity
- ALWAYS classify entries using the remember classification logic
- ALWAYS show import plan with targets before applying
