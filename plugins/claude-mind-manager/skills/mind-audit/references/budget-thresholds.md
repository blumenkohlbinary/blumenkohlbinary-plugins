# Budget Thresholds — Token & Compliance Data

## SFEIR Institute Compliance Measurements

| Configuration | Lines | Compliance Rate | Source |
|--------------|-------|-----------------|--------|
| 5 rule files x 30 lines | 150 total | **96%** | SFEIR Institute |
| Single CLAUDE.md | <200 | **92%** | SFEIR Institute |
| Single CLAUDE.md | >400 | **71%** | SFEIR Institute |

**Key insight:** Modularizing into 5 separate rule files gains +4% compliance over a single file with the same content.

## Recommended Line Limits

| File | Optimal | Acceptable | Warning | Critical |
|------|---------|------------|---------|----------|
| CLAUDE.md (project) | <60 (HumanLayer) | <150 | 150-200 | >200 |
| CLAUDE.md (total across scopes) | <100 | <200 | 200-400 | >400 (71% compliance) |
| MEMORY.md | <150 | <180 | 180-195 | >195 (near hard 200 limit) |
| Single rule file | <30 | <50 | >50 | >100 |
| Topic files | <200 | <500 | >500 | — |

## Token Estimation Formulas

| Content Type | Tokens/Line | Source |
|-------------|-------------|--------|
| MEMORY.md (mixed) | ~7.5 | SFEIR (200 lines = 1,500 tokens) |
| CLAUDE.md (optimized) | ~9 | SFEIR (60% reduction after optimization) |
| CLAUDE.md (unoptimized) | ~22.5 | SFEIR |
| **Conservative estimate** | **~10** | Safe default for all files |

**Practical formula:** `estimated_tokens = line_count * 10`

## Authority Recommendations

| Authority | Recommendation | Weight |
|-----------|---------------|--------|
| Boris Cherny (Claude Code creator) | <1,000 tokens | Highest |
| Anthropic (official docs) | <200 lines | High |
| HumanLayer (power user) | <60 lines | Aggressive but proven |

## System Context Budget

| Component | Token Cost | Notes |
|-----------|-----------|-------|
| Claude Code system prompt | ~50 instructions | Already consumes part of the 150-200 instruction budget |
| Each MCP server | ~14,000 tokens | Tool definitions only |
| All skill descriptions | ~2% of context | Frontmatter always loaded |
| Auto-compaction threshold | ~167K/200K tokens | 75-83.5% capacity |

**Effective instruction budget:** LLMs reliably follow ~150-200 instructions. System prompt uses ~50. Remaining: **~100-150 user instructions** across all CLAUDE.md files, rules, and memory combined.

## Health Score Calculation

### Structure Quality (0-30 points)
- Uses markdown headings: +10
- Uses bullet points (not prose): +10
- Logical section ordering: +5
- Uses @imports or rules for modularity: +5

### Budget Efficiency (0-30 points)
- CLAUDE.md < 150 lines: +15 (150-200: +10, 200-300: +5, >300: 0)
- MEMORY.md < 150 lines: +15 (150-180: +10, 180-195: +5, >195: 0)

### Hygiene (0-25 points)
- No stale/non-existent paths: +10
- No contradictions between files: +10
- No duplicate entries across files: +5

### Best Practices (0-15 points)
- Has .claudeignore: +5
- Rules use `globs:` not `paths:`: +5
- Progressive disclosure (rules or @imports used): +5
