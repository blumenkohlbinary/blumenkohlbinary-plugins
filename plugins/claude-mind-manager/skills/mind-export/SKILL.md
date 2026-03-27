---
name: mind-export
description: |
  [Mind Manager] Export all project context as a portable markdown bundle. Creates a single file
  containing CLAUDE.md content, MEMORY.md, rules, topic files, and metadata.
  Useful for sharing context between machines, archiving before major changes,
  or preparing for cross-project import.

  Use when the user says "export context", "backup context", "mind export",
  "save my context", "archive context", or "/mind-export [output-path]".
argument-hint: "[output-path]"
context: inherit
allowed-tools: Read Glob Grep Write Bash
---

# Context Export

Export all project context as a single portable markdown file.

## Objective

Collect all context files, generate a comprehensive export bundle with metadata, health score, and statistics.

## Workflow

### Step 1: Determine Output Path

From `$ARGUMENTS` or default: `./mind-export-YYYY-MM-DD.md` (use Bash `date` for timestamp).

### Step 2: Collect All Context Files

Same discovery logic as /mind-status:
- Global CLAUDE.md, Project CLAUDE.md, CLAUDE.local.md
- MEMORY.md and all topic files
- All rule files (.claude/rules/ and ~/.claude/rules/)
- .claudeignore content

### Step 3: Security Check

Grep all collected content for sensitive patterns:
- API keys (`[A-Za-z0-9_]{20,}`)
- Bearer tokens
- Passwords in plaintext
- .env file references with values

If found, warn user before proceeding:
```
WARNING: Potential secrets detected in context files:
- CLAUDE.md:34 contains what may be an API key
Include anyway? [Y/n — recommended: No]
```

### Step 4: Generate Export File

```markdown
# Claude Mind Manager — Context Export

**Export date:** YYYY-MM-DD HH:MM
**Project:** <project path>
**Health score:** XX/100
**Total lines:** N | **Estimated tokens:** ~N

---

## Global CLAUDE.md
> Source: ~/.claude/CLAUDE.md

[full content]

---

## Project CLAUDE.md
> Source: ./CLAUDE.md

[full content]

---

## MEMORY.md
> Source: ~/.claude/projects/<hash>/memory/MEMORY.md
> Lines: N/200

[full content]

---

## Topic Files

### debugging.md
> Source: <cwd>/.claude-mind/debugging.md

[full content]

---

## Rules

### typescript.md
> Source: .claude/rules/typescript.md
> Globs: **/*.ts, **/*.tsx

[full content]

---

## .claudeignore
> Source: ./.claudeignore

[full content]

---

## Statistics

| Component | Files | Lines | ~Tokens |
|-----------|-------|-------|---------|
| CLAUDE.md (all scopes) | N | N | ~N |
| Memory | N | N | ~N |
| Rules | N | N | ~N |
| Total | N | N | ~N |
```

### Step 5: Write Export File

Write to the determined output path. Report:
```
Export saved to: ./mind-export-2026-03-18.md
Total: N files, N lines, ~N tokens
```

## Hard Constraints

- NEVER include secrets or credentials without explicit user confirmation
- ALWAYS warn if potential secrets are detected
- ALWAYS include metadata (date, project path, health score)
- ALWAYS include line counts and token estimates per section
- Include global CLAUDE.md only if `export_include_global` setting is true (default: true)
