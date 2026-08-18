# Quality Scoring Guide

Scoring system for CLAUDE.md files. Total: 0-100 points.

## Grading Scale

| Grade | Score | Meaning |
|-------|-------|---------|
| A | 90-100 | Exemplary — concise, modular, high compliance expected |
| B | 70-89 | Good — minor improvements possible |
| C | 50-69 | Adequate — structural or efficiency issues |
| D | 30-49 | Poor — significant problems hurting compliance |
| F | 0-29 | Failing — likely ignored or counterproductive |

---

## Scoring Criteria (100 points total)

### 1. Structure (20 points)

| Criterion | Points | Check |
|-----------|--------|-------|
| Uses H2/H3 markdown headings | +5 | No heading = prose blob, hard to parse |
| Uses bullet points (not prose paragraphs) | +5 | Bullets > paragraphs for instruction compliance |
| Logical section ordering | +5 | Commands > Architecture > Conventions > Gotchas |
| Consistent formatting throughout | +5 | No mixed styles (some bullets, some prose) |

### 2. Completeness (25 points)

| Criterion | Points | Check |
|-----------|--------|-------|
| Documents build/test/lint commands | +8 | Exact CLI commands, not "run the tests" |
| Describes architecture (3-7 components) | +7 | Entry points, data flow, key directories |
| Lists coding conventions | +5 | Only what linters cannot enforce |
| Includes gotchas/non-obvious patterns | +5 | Debugging tips, known traps, workarounds |

### 3. Efficiency (20 points)

Based on SFEIR Institute measurements: unoptimized CLAUDE.md uses ~22.5 tokens/line,
optimized ~9 tokens/line. Compliance drops from 92% (<200 lines) to 71% (>400 lines).

| Criterion | Points | Thresholds |
|-----------|--------|------------|
| Line count in healthy range | +10 | <150 lines: +10, 150-200: +5, >200: 0 |
| Token/line ratio < 15 | +5 | Concise bullet format, no prose walls |
| No generic advice | +5 | "Write clean code" = 0 value, wastes instruction budget |

**Why 150 lines?** Boris Cherny recommends <1,000 tokens. At ~9 tokens/line (optimized),
that is ~110 lines. Anthropic recommends <200 lines. The 150-line threshold balances both.

#### ⛔ Tokens/Zeile: DREI Schaetzer, alle drei ausweisen (NEU v5.4.0)

Es gibt keinen einzelnen richtigen Wert. Auf **deutschem** Text laufen die gaengigen
Naeherungen um rund ein Drittel auseinander — wer nur einen nennt, waehlt damit unausgesprochen
sein Ergebnis:

| Schaetzer | Formel | Neigt zu |
|---|---|---|
| Zeichen/4 | `Zeichen ÷ 4 ÷ Zeilen` | unterschaetzt bei Umlauten (ein Zeichen, zwei Bytes) |
| Bytes/4 | `Bytes ÷ 4 ÷ Zeilen` | naeher an UTF-8-Tokenisierern, ueberschaetzt reines ASCII |
| Woerter×1,4 | `Woerter × 1,4 ÷ Zeilen` | robust gegen Kodierung, blind fuer lange Codespans |

**Gemessen an einer realen deutschen CLAUDE.md (95 Zeilen):** 26,0 · 26,3 · 17,0 — dieselbe
Datei, drei Zahlen, Spanne **9,3**. Die Schwelle 15 ist nur dann eine Aussage, wenn dabeisteht,
womit gemessen wurde.

**Regel:** Step 4c Check 12 gibt **alle drei** aus. Ein Befund wird nur gemeldet, wenn
**mindestens zwei** die Schwelle reissen — sonst ist er ein Artefakt der Formelwahl.

⛔ **Der Skill nutzt die Werte aus Step 4c und rechnet sie nicht neu.** Zwei Zahlen fuer
dieselbe Groesse im selben Bericht sind schlimmer als eine ungenaue.

### 4. Modularity (15 points)

SFEIR data: 5 rule files x 30 lines = 96% compliance vs. single 150-line file = 92%.

| Criterion | Points | Check |
|-----------|--------|-------|
| Uses `.claude/rules/` for scoped conventions | +5 | Path-specific rules via `globs:` frontmatter |
| Uses @imports for detailed docs | +5 | Pointers not copies; avoids stale content |
| Topic files for memory offloading | +5 | MEMORY.md stays under 150 lines |

### 5. Currency (10 points)

| Criterion | Points | Check |
|-----------|--------|-------|
| File paths reference existing files | +5 | No dead links to moved/deleted files |
| Version numbers match actual (package.json etc.) | +5 | Stale versions cause wrong code generation |

### 6. Format Quality (10 points)

| Criterion | Points | Check |
|-----------|--------|-------|
| Valid, well-formed markdown | +5 | No broken tables, unclosed code blocks |
| No secrets or API keys | +5 | CLAUDE.md is context-injected and often git-tracked |

---

## Quick Reference

```
A (90-100): Short, modular, complete, current — compliance ~96%
B (70-89):  Solid but room for optimization — compliance ~92%
C (50-69):  Works but bloated or missing key sections
D (30-49):  Major issues — likely hurting more than helping
F  (0-29):  Empty, generic, or dangerously misconfigured
```

## Scoring Formula

```
score = structure(20) + completeness(25) + efficiency(20)
      + modularity(15) + currency(10) + format_quality(10)
grade = A if score >= 90, B if >= 70, C if >= 50, D if >= 30, F otherwise
```
