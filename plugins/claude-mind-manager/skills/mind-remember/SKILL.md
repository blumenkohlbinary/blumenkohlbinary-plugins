---
name: mind-remember
description: |
  [Mind Manager] Guided "remember this" — automatically classifies and sorts new knowledge into the
  correct context file: CLAUDE.md for project conventions, MEMORY.md for learned
  patterns, .claude/rules/ for file-scoped rules, or ~/.claude/CLAUDE.md for global
  preferences. Supports --error mode for Korrektur-Flywheel (auto-formats as MUST/NEVER
  rule). Optionally offers Cline-style Memory Bank templates.

  Use when the user says "remember this", "save this", "mind remember", "add to memory",
  "note this down", "store this", "keep this in mind", "don't forget",
  or "/mind-remember [fact]". Use with --error when Claude made a mistake that
  should become a rule.
argument-hint: "[--error] <what to remember>"
context: inherit
allowed-tools: Read Glob Grep Edit Write
---

# Guided Remember

Classify and store new knowledge in the optimal context file.

## Objective

Take user-provided knowledge, classify it, check for duplicates and budget, then insert into the correct file with user confirmation.

## Workflow

### Step 1: Parse Arguments

- Check for `--error` flag (Korrektur-Flywheel mode)
- Remaining `$ARGUMENTS` is the content to remember
- If no arguments provided, ask: "What should I remember? Provide the fact, preference, or convention."

### Step 2: Classify Content

Determine the best target based on content type:

| Content Type | Target | Examples |
|-------------|--------|---------|
| Project convention | `./CLAUDE.md` | Code style, build commands, architecture decisions |
| Learned pattern | `MEMORY.md` | Debugging insight, tool behavior, workflow observation |
| File-scoped rule | `.claude/rules/<name>.md` | Applies only to specific file patterns (*.ts, src/api/*) |
| Cross-project preference | `~/.claude/CLAUDE.md` | Language preference, communication style, global tools |

**--error mode classification:**
Always targets `./CLAUDE.md` (conventions section) or `.claude/rules/` (if file-scoped).
Auto-formats as: `- NEVER <bad pattern> — <alternative instead>`

### Step 3: Check for Duplicates

Grep all context files for similar content (case-insensitive). If found:
```
Similar entry found in MEMORY.md:23 — "Prefer vitest for tests"
Your new entry: "Always use vitest instead of jest"

[A] Update existing entry
[B] Add as new entry (both will exist)
[C] Cancel
```

### Step 4: Check Budget

- If target is MEMORY.md: check if adding will exceed 200-line limit
  - If yes: "MEMORY.md is at 195/200 lines. Run /mind-cleanup first, or I'll add to a topic file instead."
- If target is CLAUDE.md: warn if total will exceed 200 lines
  - Suggest modularization: "Consider using /mind-optimize to extract sections into rules"

### Step 5: Format Entry

**Normal mode:** Format as concise bullet point
- Input: "The project uses PostgreSQL 16 with Prisma ORM"
- Output: `- Database: PostgreSQL 16, Prisma ORM`

**--error mode (Korrektur-Flywheel):**
- Input: "Claude used console.log instead of logger"
- Output: `- NEVER use console.log — use libs/core/logger instead`
- Input: "Claude created a new utility file instead of checking existing ones"
- Output: `- MUST check for existing implementations before creating new files`

### Step 6: Present and Confirm

```
Classification: Project Convention
Target: ./CLAUDE.md (section: ## Code-Konventionen)
Current file: 120 lines (budget: OK)

Will add:
- NEVER use console.log — use libs/core/logger instead

Confirm? [Y/n]
```

### Step 7: Insert Entry

Use Edit to insert at the appropriate section. If section does not exist, create it.

### Step 8: Optional — Cline Memory Bank Templates

If the user wants structured memory organization, offer Cline-inspired templates:

```
Would you like to set up structured Memory Bank files?
Available templates:
- projectbrief.md — Project overview and goals
- productContext.md — Domain and business context
- activeContext.md — Current work focus
- systemPatterns.md — Architecture patterns
- techContext.md — Tech stack details
- progress.md — Status and milestones

These will be created as topic files in .claude-mind/ or rules in .claude/rules/.
```

Create selected template files with starter content on confirmation.

## Hard Constraints

- NEVER add content without showing classification and target first
- NEVER exceed 200 lines in MEMORY.md — suggest cleanup or topic file instead
- NEVER add generic advice ("write clean code") — ask user to be more specific
- ALWAYS show the formatted entry before inserting
- ALWAYS check for duplicates before adding
- In --error mode, ALWAYS format as MUST/NEVER with alternative
