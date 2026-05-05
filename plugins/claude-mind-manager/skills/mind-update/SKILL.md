---
name: mind-update
description: |
  [Mind Manager] Schneller Context-Update — alle Dateien pruefen, Versionen aktualisieren, komprimieren.
  Kein Agent-Dispatch (schnell!). Prueft CLAUDE.md, MEMORY.md, Rules inline:
  Version-Mismatch, tote Pfade, fehlende Git-Commits, Budget-Ueberschreitungen,
  Rules-Syntax. Auto-Fix fuer sichere Aenderungen, Rueckfrage fuer alles andere.

  Use when the user says "update context", "refresh context", "mind update",
  "quick check", "context status", "sync context",
  or "/mind-update".
argument-hint: ""
context: inherit
allowed-tools: Read Glob Grep Edit Bash
---

# Schneller Context-Update

Alle Context-Dateien inline pruefen -> sichere Fixes auto-anwenden -> Report.

Designed to be FAST: no agent dispatch, no deep analysis, pure inline checks.

## Step 1: Alle Context-Dateien lesen (project + global + topic-files)

Read all context files inline (no agent dispatch). **6 Targets — alle PFLICHT,
keine Auslassung. Wenn ein Target fehlt: explizit "(none)" loggen, NICHT silent
skippen.**

1. **CLAUDE.md** (project): `./CLAUDE.md` or `./.claude/CLAUDE.md`
2. **CLAUDE.md** (global): `~/.claude/CLAUDE.md`
3. **MEMORY.md** (project): Compute hash, read `$MEMORY_DIR/MEMORY.md`
4. **MEMORY-Topic-Files** (NEU v3.2.1): Glob `$MEMORY_DIR/*.md` MINUS `MEMORY.md`
   selbst (z.B. `lessons.md`, `topic-bugfixes.md` — Topic-Files sind Markdown
   ohne YAML-Frontmatter, werden via Reference-Links aus MEMORY.md geladen)
5. **Rules** (project): Glob `.claude/rules/*.md`
6. **Rules** (global): Glob `~/.claude/rules/*.md`

```bash
# Hash + Memory-Verzeichnis:
PROJECT_DIR=$(pwd)
HASH=$(echo "$PROJECT_DIR" | sed 's|[/\\: ]|-|g' | sed 's|^-*||')
MEMORY_DIR="$HOME/.claude/projects/$HASH/memory"

# MEMORY.md (Hauptdatei)
MEMORY_MAIN="$MEMORY_DIR/MEMORY.md"

# Topic-Files-Glob (NEU v3.2.1) — alle .md im memory-Verzeichnis AUSSER MEMORY.md
TOPIC_FILES=$(ls "$MEMORY_DIR"/*.md 2>/dev/null | grep -v "/MEMORY.md$")

# Project Rules
PROJECT_RULES=$(ls .claude/rules/*.md 2>/dev/null)

# Global Rules
GLOBAL_RULES=$(ls "$HOME"/.claude/rules/*.md 2>/dev/null)
```

Record line counts for each file immediately. Output-Pattern (siehe Step 6):
- "(none)" wenn ein Target leer ist
- Datei-Liste + Zeilen pro Topic-File / Rule-File explizit zeigen

## Step 2: Referenzen laden

Read these reference files for budget thresholds:
- [references/budget-thresholds.md](../../references/budget-thresholds.md) -- SFEIR compliance data, line limits
- [references/token-budget-formulas.md](../../references/token-budget-formulas.md) -- Token calculation formulas

## Step 3: Quick Checks

Run all checks inline (no agents):

### 3a: Version Match
- Read `plugin.json` or `package.json` -> extract `"version":`
- Grep CLAUDE.md for version strings (e.g., "Version: 2.6.0", "Aktuelle Version: 2.6.0")
- Mismatch -> Finding (auto-fixable)

### 3b: Dead Paths (kontextuell, KEINE False-Positives)

**Pfad-Pattern STRIKT** — nur backtick-wrapped Strings die mindestens einen
Slash oder Backslash enthalten. Bare-Filenames wie `model.py`, `ui.py` werden
NICHT als Pfade behandelt (sind referentielle Code-Erwaehnungen).

**Extraktion (Python-Pattern):**
```python
import re
# Backtick-wrapped Strings, die mindestens ein / oder \ enthalten:
pattern = r'`([^`]*[/\\][^`]+)`'
paths = set(re.findall(pattern, claude_md_content))
```

✅ **Inkludieren** (echte Pfade mit Separator):
- `src/zustellplan/model.py`
- `dist/stable/`
- `.claude/rules/build-process.md`
- `C:/CD/KOHLEKTIV/...`

❌ **Ausschließen** (Bare-Filenames als Code-Referenz):
- `model.py`, `ui.py`, `weather.py` — nur Filename, kein Pfad
- `__init__.py` — Convention-Name ohne Pfad
- `pyproject.toml` — Top-Level-Datei ohne Pfad-Prefix (separate Version-Check
  in Step 3a behandelt das ohnehin)

**Verifikation pro Pfad:**
- `test -e "$path"` via Bash
- Bei DEAD-Status: Finding mit Klasse DEAD (siehe Step 4)

**Sanity-Check:**
- Bei >5 Findings: User-Frage "Sehen False-Positives aus?" — vermutlich noch
  Algorithmus-Probleme
- Bei 1-5 Findings: Auto-Fix erlaubt (mit Read-vor-Edit pro Step 4)

### 3c: Git Log Check
- Only if `.git/` directory exists
- Run `git log --oneline -10`
- Look for `feat:`, `fix:`, `refactor:` commits that are NOT mentioned in CLAUDE.md
- Unreflected commits -> Finding (ask user: add to CLAUDE.md?)

### 3d: MEMORY.md Budget
- Count lines in MEMORY.md
- >200 lines = CRITICAL (truncation imminent)
- >150 lines = WARNING (approaching limit)
- OK otherwise

### 3e: Rules Syntax Check (project + global, beide PFLICHT)

- Grep BEIDE rule sets fuer `^paths:` (known bug — silently ignored by Claude Code):
  - **Project rules** (`.claude/rules/*.md`)
  - **Global rules** (`~/.claude/rules/*.md`) — NEU v3.2.1: explizit pruefen
- User-level rules (global) mit `paths:` = ERROR (never works in `~/.claude/rules/`)
- Project rules mit `paths:` = WARNING (auto-fixable via mind-rules migrate)
- **MEMORY-Topic-Files NICHT auf `paths:`/`globs:` pruefen** — sind Markdown ohne
  YAML-Frontmatter, sollen das auch nicht haben. Wenn doch eines welche hat:
  WARNING "Topic-File hat unerwartete Frontmatter".

```bash
# Project rules
grep -rn '^paths:' .claude/rules/*.md 2>/dev/null

# Global rules (NEU v3.2.1)
grep -rn '^paths:' "$HOME"/.claude/rules/*.md 2>/dev/null
```

### 3f: Total Context Budget
- Sum all context file lines: CLAUDE.md (all scopes) + MEMORY.md + all rules
- >500 lines = WARNING: "High context overhead"
- >300 lines = INFO: "Moderate context load"
- <300 lines = OK

## Step 4: Findings-Klassifikation + Fixes

**Pre-Edit Read (MUST):** Step 1 hat zwar alle Context-Dateien gelesen, aber das
zaehlt NICHT fuer Step 4 — Claude's Edit-Tool benoetigt einen Read im SELBEN
Tool-Call-Kontext wie das Edit. Vor jedem Fix:
1. Read die Ziel-Datei (CLAUDE.md, Rule-Datei)
2. Edit ausfuehren

Sonst Crash mit `<tool_use_error>File has not been read yet`.

### 4a: Klassifikation pro Finding

Jedes Finding bekommt eine Klasse aus 4 Optionen:

| Klasse | Bedeutung | Aktion |
|---|---|---|
| **AUTO** | Mismatch, sicher fix-bar (Versions-Drift CLAUDE.md ↔ package.json, paths→globs) | Read + Edit OHNE Frage |
| **ASK** | Echter Mismatch ABER mit Build/Release-Konsequenzen (z.B. `pyproject.toml` Version, Hatchling/PyPI-Metadata, semver-relevant) | User fragen — NIE silent auto-fixen |
| **DESIGN** | "By design" markiert in Rule/CLAUDE.md (explizite Regel sagt "NICHT anfassen") | NICHT als "Issue" zaehlen, aber als Hinweis am Ende erwaehnen — ggf. Regel praezisieren |
| **DEAD** | Pfad existiert nicht UND Pfad enthaelt `/` oder `\` (siehe Step 3b) | AUTO falls eindeutig (max 5 Findings), sonst ASK |

**KRITISCHE REGEL:** Wenn ein Finding "ASK" ist und User sagt "behebe alle" /
"fix all" / "ja mach", gilt das als explizite Erlaubnis — Fix darf erfolgen.

### 4b: DESIGN-Detection-Heuristik (deterministisch, keine silent dropouts)

**Vor** der Klassifikation eines Mismatch-Findings als DESIGN: explizite
Marker-Suche durchfuehren. Nur wenn ein Marker matched, ist DESIGN gerechtfertigt.

**Marker-Patterns (Regex, alle case-insensitive):**

**WICHTIG:** `target_basename` MUSS via `re.escape(basename)` substituiert werden,
sonst matcht `pyproject.toml` auch `pyproject_toml` (Punkt = Regex-Metacharakter).

```python
import re
escaped = re.escape(target_basename)  # z.B. "pyproject\\.toml"

DESIGN_MARKERS = [
    # "NIEMALS [target]" oder "NEVER edit/change/modify [target]"
    rf'NIEMALS\s+`?{escaped}',
    rf'NEVER\s+(edit|change|modify|touch)\s+`?{escaped}',

    # Explizite Marker (target-unabhaengig, in Naehe des targets greppen)
    r'by\s+design',
    r'intentional(ly)?',
    r'absichtlich',
    r'manuell\s+synchronisieren',
    r'manually\s+sync',

    # Sync-Hinweise — broad pattern statt eng
    r'(einmal\s+pro|once\s+per)\s+(Stable-?Release|release)',
    r'(last|letzter?)[-_\s]+sync',
]
```

**Detection-Workflow:**

1. Mismatch gefunden (z.B. `pyproject.toml` 1.0.0 vs Stable 1.0.2)
2. Extract `target_basename` aus Finding (z.B. `pyproject.toml`)
3. Grep ALLE rule files (project + global) + CLAUDE.md (project + global) fuer
   DESIGN_MARKERS mit substituiertem `target_basename`
4. **Wenn Match in einer Rule:**
   - Klassifizieren als DESIGN
   - Show file:line des Matches
   - Hinweis: "Regel '$rule_path:$line' sagt '$matched_text' → Fix nicht auto"
   - **ABER:** Trotzdem als Finding mit Klasse DESIGN listen — NICHT silent dropout
5. **Wenn KEIN Match:** → Klasse AUTO oder ASK je nach Severity (siehe 4c)

**Beispiel** (echt aus Session 2026-05-05):
- Mismatch: `pyproject.toml` Version `1.0.0` vs Stable `1.0.2`
- Grep: `build-process.md:14` sagt `NIEMALS \`pyproject.toml\` Version anfassen`
- Match auf Pattern `NIEMALS\s+\`?pyproject\.toml` → DESIGN
- **Aber:** Step 6 Report listet trotzdem als `[DESIGN]`, NICHT "0 issues"

### 4c: Fix-Tabelle mit Coupled-Files

| Klasse | Tool | Aktion | Coupled-Files (auch pruefen/updaten) |
|---|---|---|---|
| AUTO Version-Drift | Edit | Read → update version string in CLAUDE.md | (none — single source) |
| AUTO paths→globs | Edit | Read → replace `paths:` with `globs:` | (none — per Datei isoliert) |
| ASK `pyproject.toml` Version | Edit (after user OK) | Read → update version + Sync-Datum-Kommentar | **Generisch ableiten** via Coupled-Files-Detection (siehe unten) — NICHT hardcoden. Beispiel Zustellplan: `__init__.py` Fallback + `dist/stable/_build_info.py` Verifikation |
| ASK CLAUDE.md major | Edit (after user OK) | Read → update + show diff | (project-spezifisch, je nach Inhalt) |
| DESIGN Marker | (no edit) | List finding mit Verweis auf Marker-Rule, ggf. Vorschlag Regel-Praezisierung | Marker-Datei + Ziel-Datei |
| DEAD path | Edit | Read → entfernen oder Pfad korrigieren | (none) |

**Coupled-Files-Detection (generisch, NICHT hardcoded):**

- Skill grept das Mismatch-Target (z.B. `pyproject.toml`) in `.claude/rules/*.md` +
  globale Rules + CLAUDE.md (project + global)
- **Pattern fuer gekoppelte Files** (Regex, in Marker-Match-Zeile + Folgezeilen):
  ```python
  COUPLE_PATTERNS = [
      r'auch\s+`?([^\s`]+\.\w+)`?',          # "auch `__init__.py`"
      r'Coupled\s+with\s+`?([^\s`]+)`?',     # "Coupled with `dist/stable/_build_info.py`"
      r'Sync(?:hron(?:isieren)?)?\s+mit\s+`?([^\s`]+)`?',  # "Synchron mit ..."
      r'(?:Fallback|fallback)[\s:]+`?([^\s`]+\.\w+)`?',  # "Fallback: `__init__.py`"
  ]
  ```
- Extrahiere alle gekoppelten Filenames → Read sie alle vor dem Fix
- Bei Auto-Edit: alle gekoppelten Files in EINER konsistenten Operation
- Bei User-Frage: gekoppelte Files explizit erwaehnen
  - z.B. *"Fix `pyproject.toml` 1.0.0 → 1.0.2? Coupled-Files aus Rule `build-process.md:14`:
    `__init__.py` Fallback (mit-updaten), `dist/stable/_build_info.py` (verifizieren)."*

**Wenn KEINE Coupled-Files gefunden:** Nur das Target-File anpacken, kein Hint im
User-Prompt.

### 4d: Apply-Reihenfolge

1. AUTO-Findings: Read jede Ziel-Datei → Edit → log
2. DEAD-Findings: bei <=5 → AUTO, sonst ASK
3. DESIGN-Findings: NICHT auto, listen als Hinweis
4. ASK-Findings: User fragen, dann (ggf.) Read + Edit + Coupled-Files

For each fix, log what was changed (file, line, before/after).

## Step 5: Lossless Compression

Scan CLAUDE.md for verbose lines that can be shortened without losing information:

| Pattern | Replacement |
|---|---|
| "When you are writing TypeScript code, you should always..." | "TypeScript: MUST use strict mode" |
| "It is important to note that we use..." | "Uses: <tool>" |
| "Please make sure to..." | "MUST ..." |
| "You should not..." | "NEVER ..." |
| Multi-sentence entries that could be one bullet | Single MUST/NEVER bullet |

**Only compress lines where meaning is 100% preserved.** If unsure, skip.

Show compressed lines for user approval before applying:
```
Compression candidates (3):
[1] CLAUDE.md:12 "When writing tests, always use..." -> "Tests: MUST use vitest"
[2] CLAUDE.md:45 "Please note that the build..." -> "Build: `npm run build` (required before PR)"
[3] CLAUDE.md:78 "You should never commit..." -> "NEVER commit .env files"

Apply compressions? [Yes / Select / Skip]
```

## Step 6: Report (alle 6 Targets explizit)

```
=== Context Update ===
Checked: N files (project + global + topic-files) | Auto-fixed: X | Needs input: Y | By design: Z | Dead: W

CLAUDE.md (project):     145 -> 138 lines (-7)
  [AUTO] Version 2.5.0 -> 2.6.0
  [AUTO] Removed dead path: src/old-module/
  [ASK]  Unreflected commit "feat: dark mode" — add to CLAUDE.md?

CLAUDE.md (global):       55 lines (OK)

MEMORY.md (project):      89 lines (OK, within 200 budget)
MEMORY topic files:       2 (lessons.md: 12, tab7-bugfixes.md: 18)

Rules (project):          3 files, all valid syntax
  build-process.md         126 lines
  portal.md                 36 lines
  ...

Rules (global):           4 files, all valid syntax (NEU v3.2.1: explizit geprueft)
  backup-before-delete.md  34 lines
  deep-review.md           18 lines
  keine-annahmen.md         9 lines
  plan-mode.md              8 lines

Total context: 287 lines (~2870 tokens) -- Compliance: ~92%
```

**WICHTIG:** Wenn Y > 0, IMMER explizit listen — kein "0 issues" wenn ASK-Findings
existieren. Step 4 Klassifikation entscheidet Klasse, Step 6 zaehlt korrekt.

If there are pending items (ASK-Findings, compression candidates), ask:
"Want me to fix item [1]? [Yes / Skip]"

## Hard Constraints

- MUST be fast: NO Agent tool dispatch (all checks inline)
- Auto-fix ONLY safe changes: version numbers, dead paths, paths: -> globs: migration
- ASK for everything else: compression, adding git commits, removing content
- ALWAYS show what was auto-fixed in the report
- ALWAYS show before/after line counts
- ALWAYS backup files before editing (cp to .claude-mind/backups/)
- NEVER remove content without showing what will be lost
- If no issues found: report "All clean" and stop (no unnecessary changes)
