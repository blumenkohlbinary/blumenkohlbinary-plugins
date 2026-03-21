---
name: optimize
description: |
  Optimize context budget and resolve contradictions. Shortens verbose entries, modularizes
  CLAUDE.md into rules, deduplicates across files, suggests @imports, resolves conflicts
  between CLAUDE.md/MEMORY.md/rules, migrates CLAUDE.local.md. Uses SFEIR compliance data.
  Also reads .claude-mind/suggestions.md for pending CLAUDE.md update suggestions.

  Use when the user says "optimize context", "reduce tokens", "mind optimize",
  "CLAUDE.md too long", "budget optimization", "token budget", "fix contradictions",
  "resolve conflicts", "sync context", or "/mind:optimize".
argument-hint: "[--dry-run]"
context: inherit
allowed-tools: Read Glob Grep Edit Write Bash Agent
---

# Context Budget Optimizer

Optimize token usage and compliance rate through restructuring.

## Objective

Analyze context files, generate optimization plan with token savings estimates, apply changes with user confirmation. Use `--dry-run` to preview without changes.

## Workflow

### Step 1: Parse Arguments

Check `$ARGUMENTS` for `--dry-run` flag. Dry-run shows plan without applying changes.

### Step 2: Dispatch Optimizer Agent

Launch **context-optimizer** agent:
"Analyze all context files and generate optimization suggestions: shortening, modularization into rules, progressive disclosure via @imports, deduplication, MEMORY.md offloading, missing .claudeignore. Estimate token savings for each suggestion. Order by impact."

### Step 3: Load Reference Data

Read [references/quality-criteria.md](references/quality-criteria.md) for optimization patterns and anti-patterns.

### Step 4: Detect Contradictions

Launch **claude-md-analyzer** agent with focus on cross-file contradictions:
"Read all CLAUDE.md files (global, project, local), MEMORY.md, and rule files. Find contradictions: instructions that conflict, version mismatches, and redundant entries expressed differently. Report each with exact file:line references."

Categorize findings:
- **Direct Contradictions:** Opposite instructions (e.g., "Use jest" vs "Prefer vitest")
- **Version Mismatches:** Different versions (e.g., "Node 18" vs "Node 20")
- **Redundant Instructions:** Same meaning, different wording
- **Scope Conflicts:** Lower scope overrides higher (may be intentional)

### Step 5: Check Pending Suggestions

Read `.claude-mind/suggestions.md` if it exists — these are CLAUDE.md update suggestions
collected automatically by the Stop hook. Include them in the optimization plan.

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
