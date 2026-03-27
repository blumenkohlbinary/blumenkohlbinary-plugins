---
name: mind-optimize
description: |
  [Mind Manager] Optimize context budget and resolve contradictions. Shortens verbose entries, modularizes
  CLAUDE.md into rules, deduplicates across files, suggests @imports, resolves conflicts
  between CLAUDE.md/MEMORY.md/rules, migrates CLAUDE.local.md. Uses SFEIR compliance data.
  Also reads .claude-mind/suggestions.md for pending CLAUDE.md update suggestions.

  Use when the user says "optimize context", "reduce tokens", "mind optimize",
  "CLAUDE.md too long", "budget optimization", "token budget", "fix contradictions",
  "resolve conflicts", "sync context", or "/mind-optimize".
argument-hint: "[claude-md|memory|rules|all] [--dry-run]"
context: inherit
allowed-tools: Read Glob Grep Edit Write Bash Agent
---

# Context Budget Optimizer

Optimize token usage and compliance rate through restructuring.

## Objective

Analyze context files, generate optimization plan with token savings estimates, apply changes with user confirmation. Use `--dry-run` to preview without changes.

## Workflow

### Step 1: Parse Arguments

Check `$ARGUMENTS` for flags and scope:
- **Scope filter** (positional argument):
  - `claude-md` — only optimize CLAUDE.md files (all scopes: shortening, modularization, @imports)
  - `memory` — only optimize MEMORY.md and topic files (deduplication, offloading)
  - `rules` — only optimize rule files (consolidation, globs fixes, dead rules)
  - `all` (default if no scope given) — optimize everything
- **--dry-run flag** — show plan without applying changes

Examples: `/mind-optimize claude-md`, `/mind-optimize memory --dry-run`, `/mind-optimize --dry-run`

### Step 2: Dispatch Optimizer Agent

Launch **context-optimizer** agent with scope-aware prompt:
- **claude-md**: "Analyze CLAUDE.md files (global, project, local) and suggest: shortening verbose entries, modularizing sections into rules, progressive disclosure via @imports. Estimate token savings per suggestion."
- **memory**: "Analyze MEMORY.md and .claude-mind/ topic files. Suggest: deduplication, offloading large sections to topic files, removing stale entries. Estimate token savings."
- **rules**: "Analyze .claude/rules/*.md files. Suggest: consolidation of overlapping rules, globs: fixes, removal of dead/unused rules. Estimate token savings."
- **all**: "Analyze all context files and generate optimization suggestions: shortening, modularization into rules, progressive disclosure via @imports, deduplication, MEMORY.md offloading, missing .claudeignore. Estimate token savings for each suggestion. Order by impact."

### Step 3: Load Reference Data

Read [references/quality-criteria.md](references/quality-criteria.md) for optimization patterns and anti-patterns.

### Step 4: Detect Contradictions (only when scope is `all`)

Skip this step if scope is `claude-md`, `memory`, or `rules` — contradictions only make sense across file types.

When scope is `all`, launch **claude-md-analyzer** agent with focus on cross-file contradictions:
"Read all CLAUDE.md files (global, project, local), MEMORY.md, and rule files. Find contradictions: instructions that conflict, version mismatches, and redundant entries expressed differently. Report each with exact file:line references."

Categorize findings:
- **Direct Contradictions:** Opposite instructions (e.g., "Use jest" vs "Prefer vitest")
- **Version Mismatches:** Different versions (e.g., "Node 18" vs "Node 20")
- **Redundant Instructions:** Same meaning, different wording
- **Scope Conflicts:** Lower scope overrides higher (may be intentional)

### Step 5: Check Pending Suggestions

Read `.claude-mind/suggestions.md` if it exists — these are CLAUDE.md update suggestions
collected automatically by the Stop hook. Include them in the optimization plan.

### Step 5b: Selbstdiagnose — Fehlende/Veraltete Informationen erkennen

**CRITICAL:** This step is NOT optional. It is the key differentiator of this plugin. Do NOT skip it. Execute ALL checks below using Read, Grep, Glob, and Bash tools directly (no agent needed).

**Check 1: Learnings → CLAUDE.md/MEMORY.md**
```
Glob: .claude-mind/learnings/session-*.md
For each learning entry (lines starting with "- "):
  → Grep the learning text (first 30 chars) against CLAUDE.md and MEMORY.md
  → If NOT found in either → add to "Missing" list: "Learning not documented: <text>"
```

**Check 2: Debug-Log Recurring Errors**
```
Read: /tmp/mind-manager.log
Grep for "ERROR" and "WARN" lines
Group by message pattern (strip timestamps), count occurrences
Any pattern appearing 3+ times → add to "Missing" list: "Recurring issue: <pattern> (Nx)"
```

**Check 3: Session Decisions**
```
Glob: .claude-mind/sessions/session-*.md (last 3 files)
Read the "## Decisions" section from each
For each decision:
  → Grep against CLAUDE.md
  → If NOT found → add to "Missing" list: "Undocumented decision: <text>"
```

**Check 4: Version Consistency**
```
Read: plugin.json (or package.json) → extract "version" field
Read: CLAUDE.md → grep for version number patterns (e.g., "v2.3.0", "Version: 2.3.0")
If versions differ → add to "Outdated" list: "CLAUDE.md says vX.Y.Z but plugin.json says vA.B.C"
```

**Check 5: Path Validity**
```
Read: CLAUDE.md
Extract all file paths (patterns matching / or \ with extensions, or backtick-wrapped paths)
For each path: check if file/directory exists
Dead paths → add to "Outdated" list: "Dead path in CLAUDE.md: <path>"
```

**Check 6: Default Values**
```
Read: CLAUDE.md → extract all environment variable defaults (MIND_BACKUP_INTERVAL, etc.)
Read: hooks/auto-save-context.sh + hooks/lib.sh → extract actual defaults from code
Compare → mismatches go to "Outdated" list: "CLAUDE.md says default=X but code says Y"
```

**Output:** Present ALL findings as a separate section in the optimization plan:
```
=== Missing/Outdated Information ===

Missing (should be added):
[M1] Learning not documented: "vfs/refresh errors are non-critical warnings"
[M2] Undocumented decision: "switched from exec 2>> to mind_log()"

Outdated (should be updated):
[O1] CLAUDE.md says v2.3.0 but plugin.json says v2.4.0
[O2] Dead path: `hooks/mind-manager-errors.log` (renamed to mind-manager.log)
[O3] Default mismatch: MIND_BACKUP_INTERVAL CLAUDE.md says 15, code says 10

For each: [Apply / Skip]
```

### Step 6: Add Inline Checks

While agents run, perform additional checks:
- **CLAUDE.local.md migration:** If exists, prepare migration plan
- **Missing .claudeignore:** Generate recommended content
- **Token estimate:** Calculate current vs projected totals

### Step 7: Present Optimization Plan

```
=== Context Optimization Plan ===

Current: ~4,500 tokens | Projected: ~2,800 tokens | Savings: ~1,700 (38%)
Compliance: ~89% → ~96% (modularization + compression)

[1] MODULARIZE: "TypeScript Conventions" → .claude/rules/typescript.md
    Source: CLAUDE.md:30-55 (25 lines, ~250 tokens)
    Target: .claude/rules/typescript.md (globs: **/*.ts, **/*.tsx)
    Savings: ~250 tokens (loads only when editing .ts files)
    Compliance: +4% (SFEIR modularization benefit)
    [Apply / Skip]

[2] SHORTEN: Compress verbose instructions
    CLAUDE.md:12 "When you are writing TypeScript code, always use strict mode"
              → "TypeScript: MUST use strict mode"
    CLAUDE.md:67 "Please make sure to run the linter before committing"
              → "Pre-commit: MUST run linter"
    Savings: ~80 tokens
    [Apply / Skip]

[3] PROGRESSIVE DISCLOSURE: Extract "Database" section
    CLAUDE.md:40-58 (18 lines) → @docs/database.md
    Replace with: "Database: PostgreSQL 16, Prisma ORM. Details: @docs/database.md"
    Savings: ~170 tokens from always-loaded context
    [Apply / Skip]

[4] MIGRATE: CLAUDE.local.md → @import
    Move content to ~/.claude/<project>-instructions.md
    Add @import reference in CLAUDE.md
    [Apply / Skip]

[5] CREATE: .claudeignore
    Recommended: node_modules/, dist/, build/, coverage/, *.lock
    Savings: up to 50% of file-scanning token budget
    [Apply / Skip]
```

Add contradiction resolutions to the plan if any were found:

```
[6] RESOLVE CONFLICT: Test Runner
    CLAUDE.md:45 → "Test runner: jest"
    MEMORY.md:23 → "User prefers vitest over jest"
    Options: [A] Keep CLAUDE.md | [B] Keep MEMORY.md | [C] Keep both | [D] Skip
```

Add pending suggestions from `.claude-mind/suggestions.md` if any exist:

```
[7] SUGGESTION (auto-detected): New dependency "prisma" found in package.json
    Recommendation: Add "ORM: Prisma" to CLAUDE.md architecture section
    [Apply / Skip]
```

### Step 8: Apply (If Not Dry-Run)

For each confirmed suggestion:
- **Modularize:** Write new rule file, Edit CLAUDE.md to remove section
- **Shorten:** Edit CLAUDE.md with compressed text
- **Progressive Disclosure:** Write new doc file, Edit CLAUDE.md with @import
- **Migrate:** Write new file, Edit CLAUDE.md with @import, note CLAUDE.local.md for user to delete
- **Claudeignore:** Write .claudeignore file
- **Resolve conflict:** Edit the file to remove/update the deprecated entry
- **Apply suggestion:** Edit CLAUDE.md with suggested content, remove from suggestions.md

### Step 9: Summary

```
=== Optimization Complete ===
Applied: 4 suggestions | Skipped: 1
Token savings: ~1,500 (estimated)
Compliance prognosis: 89% → 96%
Files modified: 2 | Files created: 3
```

## Hard Constraints

- NEVER lose information during optimization — all content must be preserved (relocated, not deleted)
- NEVER apply changes in --dry-run mode
- ALWAYS show before/after comparison for each suggestion
- ALWAYS estimate token savings (lines × 10)
- ALWAYS reference SFEIR compliance data for modularization
- ALWAYS confirm before creating new files
- NEVER auto-resolve contradictions — ALWAYS present options to the user
- Scope conflicts (global vs project) may be intentional — always offer "Keep both" option
- Clear .claude-mind/suggestions.md entries after they are applied or dismissed
