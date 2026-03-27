---
name: mind-audit
description: |
  [Mind Manager] Deep analysis of context health: detect duplicates between CLAUDE.md and MEMORY.md,
  find contradictions, check for stale paths and versions, estimate compliance rate
  using SFEIR data, validate rules syntax (paths: vs globs: migration), find orphaned
  @imports, flag CLAUDE.local.md deprecation. Dispatches 4 specialized agents in parallel.

  Use when the user says "audit my context", "check context health", "mind audit",
  "find contradictions", "check for duplicates", "context problems", "compliance check",
  or "/mind-audit".
argument-hint: "[--focus memory|claude-md|rules|paths]"
context: inherit
allowed-tools: Read Glob Grep Bash Agent
---

# Context Audit

Comprehensive analysis of context health by dispatching specialized agents in parallel.

## Objective

Run a deep audit across all context files using 4 parallel agents, then consolidate findings into a unified report with prioritized recommendations.

## Workflow

### Step 1: Parse Arguments

Check `$ARGUMENTS` for `--focus` filter:
- `memory` — dispatch only memory-auditor
- `claude-md` — dispatch only claude-md-analyzer
- `rules` — run rules check inline (no agent needed)
- `paths` — dispatch only path-validator
- No focus (default) — dispatch ALL 4 agents in parallel

### Step 2: Load Reference Data

Read these reference files for scoring and analysis:
- [references/context-file-guide.md](references/context-file-guide.md) — file catalog
- [references/budget-thresholds.md](references/budget-thresholds.md) — SFEIR compliance data
- [references/quality-scoring-guide.md](references/quality-scoring-guide.md) — 0-100 quality scoring + A-F grading

### Step 3: Dispatch Agents (Parallel)

Launch up to 4 agents simultaneously using the Agent tool:

1. **memory-auditor** — "Scan all memory files in this project for duplicates, stale entries, budget issues, and misplaced content. Report findings with line numbers."

2. **claude-md-analyzer** — "Analyze all CLAUDE.md files across scopes for structure quality, line efficiency, compliance prognosis, @import validation, CLAUDE.local.md deprecation, and cross-scope contradictions."

3. **context-optimizer** — "Analyze all context files and suggest optimizations: shortening, modularization into rules, progressive disclosure via @imports, deduplication, MEMORY.md offloading to topic files."

4. **path-validator** — "Extract all path references and @imports from context files and verify they exist on disk. Report broken references with source locations."

### Step 4: Inline Rules Check

While agents run, perform rules syntax check directly:
- Glob for `.claude/rules/*.md` and `~/.claude/rules/*.md`
- Grep for `^paths:` — flag as "known bug, use globs: instead"
- Check if user-level rules use `paths:` — flag as "does NOT work in user-level rules"
- Check YAML quoting issues

### Step 5: Calculate Quality Score

Apply the scoring rubric from `quality-scoring-guide.md` to each CLAUDE.md file:
- Structure (20P): Headings, bullets, logical ordering, consistency
- Completeness (25P): Commands, architecture, conventions, gotchas
- Efficiency (20P): Line count, token/line ratio, no generic advice
- Modularity (15P): Rules, @imports, topic files
- Currency (10P): File paths valid, versions accurate
- Format Quality (10P): Valid markdown, no secrets

Assign letter grade: A=90-100, B=70-89, C=50-69, D=30-49, F=0-29

### Step 6: Run 8 Pain-Point Checks

Check for each of the 8 Community Pain Points:
1. Rules with `paths:` bug? (from inline rules check)
2. MEMORY.md overflow risk? (from memory-auditor)
3. Context overview missing? (no .claudeignore, no modularization)
4. Contradictions between CLAUDE.md and MEMORY.md? (from claude-md-analyzer)
5. Auto-memory quality low? (stale/duplicate entries from memory-auditor)
6. Cross-project knowledge lost? (no topic files, no exports)
7. CLAUDE.md too long? (>200 lines)
8. InstructionsLoaded unknown? (no debug rules set up)

### Step 7: Consolidate Report

Collect all agent results, scoring, and pain-point checks. Present consolidated report:

```
=== Claude Mind Manager — Context Audit ===

Quality Score: XX/100 (Grade: X)
Compliance Prognosis: ~XX% (SFEIR: N total instruction lines)

### Quality Scores per File
| File | Score | Grade | Lines | ~Tokens |
|------|-------|-------|-------|---------|
| ./CLAUDE.md | 78 | B | 145 | ~1450 |
| ~/.claude/CLAUDE.md | 62 | C | 55 | ~550 |

### Critical (action required)
- MEMORY.md: 195/200 lines — overflow imminent → /mind-cleanup
- CLAUDE.md:45 contradicts MEMORY.md:23 (test runner) → /mind-optimize
- @import @docs/api.md MISSING — silently ignored → fix path or remove

### Warnings
- 2 rule files use paths: (known bug) → /mind-rules migrate
- CLAUDE.local.md detected (deprecated) → /mind-optimize
- CLAUDE.md:12-18 verbose (could save ~40 tokens) → /mind-optimize
- MEMORY.md:34 stale path "src/old-module/" → /mind-cleanup

### Pain Points Detected
- [1/8] Rules paths: bug — 2 files affected
- [2/8] MEMORY.md at 195/200 lines — overflow imminent
- [7/8] CLAUDE.md at 180 lines — approaching degradation threshold

### Info
- 3 duplicate entries across files → /mind-cleanup
- .claudeignore missing → /mind-optimize
- 2 optimization opportunities identified → /mind-optimize --dry-run

### Recommended Actions (priority order)
1. /mind-cleanup — resolve overflow and stale entries
2. /mind-rules migrate — fix paths: syntax
3. /mind-optimize — resolve contradictions + compress
```

## Hard Constraints

- NEVER modify any files — this skill is read-only
- ALWAYS dispatch agents in parallel (not sequentially)
- ALWAYS include specific file:line references for every finding
- ALWAYS calculate health score using budget-thresholds.md rubric
- ALWAYS recommend specific /mind-* commands for each finding
