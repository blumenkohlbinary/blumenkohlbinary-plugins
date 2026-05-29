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
# Hash + Memory-Verzeichnis (v3.2.2: zentralisiert in lib.sh)
# Nutzt cygpath fuer korrektes Windows-Slug-Mapping (siehe lib.sh hash_project_dir)
# M3-Fix: $CLAUDE_PLUGIN_ROOT Guard vor source
if [ -z "$CLAUDE_PLUGIN_ROOT" ] || [ ! -f "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" ]; then
  echo "ERROR: \$CLAUDE_PLUGIN_ROOT nicht gesetzt oder lib.sh nicht gefunden" >&2
  exit 1
fi
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
MEMORY_DIR=$(get_memory_dir)
# H2-aware: $? = 1 wenn Fallback verwendet wurde
if [ "$?" = "1" ]; then
  echo "WARN: MEMORY-Dir-Fallback aktiv — Slug-Mismatch erkannt" >&2
fi

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

## Step 1.5: Custom-Context-Discovery (NEU v3.2.2, 2-Phasen)

Vor Step 3: finde projekt-weite Custom-Context-Files (alles im Projekt-Ordner
das fachlichen/technischen Code-Context enthaelt, nicht nur Auto-Loading-Rules).

**User-Direktive:** Custom Context kann ueberall im Projekt liegen. Discovery-Logik:
1. **Referenz-basiert** (deterministisch): Files die in CLAUDE.md/Rules per
   Backtick erwaehnt werden zaehlen automatisch
2. **Heuristik-basiert** (Fallback): score >= 2 ueber Code-Pattern-Indikatoren

### SKIP_SET: Files die in Step 1 bereits behandelt sind

```bash
# Step 1.5 darf KEINE Files erneut als Custom Context aufnehmen die
# Step 1 schon hat (CLAUDE.md, MEMORY, Topic-Files, Rules) — sonst
# Double-Counting in Step 3a Version-Match (Bug B1 v3.2.2 Skill-Review).
SKIP_SET=("./CLAUDE.md" "./.claude/CLAUDE.md" "$MEMORY_MAIN")

# Add MEMORY-Topic-Files + Project-Rules + Global-Rules (von Step 1)
while IFS= read -r f; do SKIP_SET+=("$f"); done <<< "$TOPIC_FILES"
while IFS= read -r f; do SKIP_SET+=("$f"); done <<< "$PROJECT_RULES"
while IFS= read -r f; do SKIP_SET+=("$f"); done <<< "$GLOBAL_RULES"

is_in_skip_set() {
  local target="$1"
  for skip in "${SKIP_SET[@]}"; do
    [ "$skip" = "$target" ] && return 0
    # Normalize ./path vs path
    [ "$skip" = "./$target" ] && return 0
    [ "./$skip" = "$target" ] && return 0
  done
  return 1
}
```

### Phase 1: Referenz-Discovery (deterministisch)

```bash
# Whitelist nur Doku-Formate (.md/.txt/.rst) — KEINE .json/.yaml/.py
# (das sind Build-Configs/Source-Files, nicht Custom Context)
REFERENCED=$(
  grep -hoE '`[^`]*\.(md|txt|rst)`' \
    CLAUDE.md .claude/rules/*.md ~/.claude/rules/*.md 2>/dev/null |
  sed 's|^`||; s|`$||' |
  sort -u
)
```

### Phase 2: Heuristik-Discovery (Fallback)

```bash
# Optional: User-Override via .mindcontext (EC1)
if [ -f .mindcontext ]; then
  # Explizite Liste — Heuristik skippen
  CUSTOM_CONTEXT_FILES=()
  while IFS= read -r line; do
    # Skip Kommentare + leere Zeilen
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    # Glob-Expansion
    for f in $line; do
      [ -f "$f" ] && CUSTOM_CONTEXT_FILES+=("$f")
    done
  done < .mindcontext
else
  # Glob alle .md ausser ignorierte
  ALL_MD=$(find . -name "*.md" \
    -not -path "./.venv/*" \
    -not -path "./.git/*" \
    -not -path "./dist/*" \
    -not -path "./build/*" \
    -not -path "./node_modules/*" \
    -not -path "./.pytest_cache/*" \
    -not -path "./.claude-mind/*" \
    -not -path "./CLAUDE.md" \
    -not -path "./.claude/rules/*" \
    2>/dev/null)

  TOTAL_MD=$(echo "$ALL_MD" | wc -l)

  # Tiered Schwelle (EC1: gross-Projekte)
  if [ "$TOTAL_MD" -gt 100 ]; then
    SCORE_THRESHOLD=3
    echo "INFO: $TOTAL_MD .md Files gefunden — Heuristik-Schwelle erhoeht auf score >= 3"
    echo "      Tipp: .mindcontext anlegen fuer explizite User-Konfiguration"
  else
    SCORE_THRESHOLD=2  # User-Direktive Default
  fi

  CUSTOM_CONTEXT_FILES=()

  # 2a: Alle referenzierten Files (deterministisch, Phase 1)
  for ref in $REFERENCED; do
    for candidate in "./$ref" "$ref"; do
      if [ -f "$candidate" ] && ! is_in_skip_set "$candidate"; then
        CUSTOM_CONTEXT_FILES+=("$candidate")
        break
      fi
    done
  done

  # 2b: Heuristik fuer nicht-referenzierte .md
  for f in $ALL_MD; do
    # Skip wenn bereits in Step 1 Liste (B1-Fix)
    is_in_skip_set "$f" && continue
    # Skip wenn bereits via Referenz aufgenommen
    [[ " ${CUSTOM_CONTEXT_FILES[@]} " =~ " $f " ]] && continue

    # Heuristik-Counter (defensiv: || true + tr -d Newlines fuer Arithmetik, M1-Fix)
    has_code_blocks=$(grep -c '```' "$f" 2>/dev/null | tr -d '\n' || true)
    has_paths=$(grep -cE '`[^`]*[/\\][^`]*`' "$f" 2>/dev/null | tr -d '\n' || true)
    has_versions=$(grep -cE 'v[0-9]+\.[0-9]+' "$f" 2>/dev/null | tr -d '\n' || true)
    has_test_counts=$(grep -cE '\b[0-9]{2,4}\s+[Tt]ests?\b' "$f" 2>/dev/null | tr -d '\n' || true)
    has_function_refs=$(grep -cE '`[a-z_][a-zA-Z0-9_]*\(\)`|`[A-Z][a-zA-Z0-9]+\.[a-zA-Z_]+`' "$f" 2>/dev/null | tr -d '\n' || true)

    # Default 0 falls Variable leer (defensive)
    score=$(( ${has_code_blocks:-0} + ${has_paths:-0} + ${has_versions:-0} + ${has_test_counts:-0} + ${has_function_refs:-0} ))
    if [ "$score" -ge "$SCORE_THRESHOLD" ]; then
      CUSTOM_CONTEXT_FILES+=("$f")
    fi
  done
fi

echo "Custom Context discovered: ${#CUSTOM_CONTEXT_FILES[@]} files"
```

**Edge-Cases-Handling:**
- **EC1 Performance:** bei >100 .md Files → score-Schwelle erhoeht auf 3, User-Hinweis fuer `.mindcontext`
- **EC2 False-Positives:** Whitelist nur `.md/.txt/.rst` als Custom Context (kein `.json/.yaml/.py`)
- **EC3 .mindcontext Override:** User kann projekt-spezifisch konfigurieren

## Step 2: Referenzen laden

Read these reference files for budget thresholds:
- [references/budget-thresholds.md](../../references/budget-thresholds.md) -- SFEIR compliance data, line limits
- [references/token-budget-formulas.md](../../references/token-budget-formulas.md) -- Token calculation formulas

## Step 3: Quick Checks

Run all checks inline (no agents):

### 3a: Version Match (ueber ALLE Custom Context — NEU v3.2.2)

**Source of Truth bestimmen** (Reihenfolge):
1. `dist/stable/_build_info.py` (wenn Build-System), sonst
2. `pyproject.toml` / `package.json` / `plugin.json` Version

**Grep alle Custom-Context-Files** (aus Step 1 + Step 1.5):
- CLAUDE.md (project + global)
- `.claude/rules/*.md` (project) + `~/.claude/rules/*.md` (global)
- MEMORY.md + Topic-Files
- Custom-Context-Files aus Step 1.5 Discovery

**Pattern (Regex, case-insensitive):**
```python
VERSION_PATTERNS = [
    r'v\d+\.\d+\.\d+(?:-\w+(?:\.\d+)?)?',  # v1.0.5, v1.0.6-dev.13
    r'Version:\s*v?\d+\.\d+',
    r'Aktuelle\s+Version:\s*v?\d+',
    r'Stable\s+v\d+\.\d+',
]
```

Pro Match: `file:line + extrahierte Version + Source-Truth → Mismatch?`
Mismatch → Finding mit Klasse AUTO/ASK/DESIGN (siehe Step 4 v3.2.1).

**Sonder-Behandlung "abgeschlossen markierte" Files (User-Direktive):**
- Wenn Custom-Context-File alle Bugs/Tasks als "geschlossen"/"erledigt" markiert
  UND mtime > 30 Tage alt → Klasse **INFO** mit Vorschlag "koennte archiviert
  werden". **NIEMALS Auto-Action.**

### 3a.1: Stale Test-Counts (NEU v3.2.2, conditional)

**Conditional (M2-Fix):** Test-Count-Check nur wenn Python+pytest+tests/ existieren.
Skill ist projekt-agnostisch — bei Nicht-Python-Projekten skippen.

```bash
# Pytest verfuegbar UND tests/ existiert?
if [ -d "tests/" ] && (command -v pytest &>/dev/null || [ -x ".venv/Scripts/python.exe" ]); then
  # Source of Truth: pytest --collect-only
  if [ -x ".venv/Scripts/python.exe" ]; then
    REAL_COUNT=$(.venv/Scripts/python -m pytest tests/ --collect-only -q 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1)
  else
    REAL_COUNT=$(pytest tests/ --collect-only -q 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1)
  fi

  if [ -n "$REAL_COUNT" ] && [ "$REAL_COUNT" -gt 0 ]; then
    # Grep alle Custom-Context-Files fuer hardcoded Test-Counts
    # Pattern: '\b\d{2,4}\s+[Tt]ests?\b' (z.B. "434 Tests", "283 tests")
    # Mismatch → Finding (AUTO bei Drift <10%, ASK bei groesserer)
    :  # Logik in Step 4 implementiert
  fi
else
  # Skip — nicht-Python oder kein tests/-Dir
  REAL_COUNT=""
fi
```

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

**Pre-Edit Read (MUST, praezisiert v3.2.2):** Step 1 hat zwar alle Context-Dateien
gelesen, aber das zaehlt NICHT fuer Step 4 — Read muss im SELBEN Tool-Call-Kontext
wie Edit erfolgen.

**1× Read der Ziel-Datei** reicht fuer N sequentielle Auto-Fixes (Edit-Tool
garantiert "file state is current — no need to Read it back"). Re-Read nur wenn
anderes Tool die Datei zwischendurch modifiziert.

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
- **Parallel-Bash-Limit (NEU v3.2.2):** Skill startet MAX 2 Bash-Tools parallel,
  niemals 3+. Bei 3+ Calls: zu seriellem Aufruf wechseln ODER kombinieren via `&&`.
  Claude Code's Tool-System cancelled uebermaessige Parallelitaet (siehe Session
  2026-05-29 Log 4 Tool 5+7 `Cancelled: parallel tool call ... errored`).
- Auto-fix ONLY safe changes: version numbers, dead paths, paths: -> globs: migration
- ASK for everything else: compression, adding git commits, removing content
- ALWAYS show what was auto-fixed in the report
- ALWAYS show before/after line counts
- ALWAYS backup files before editing (cp to .claude-mind/backups/)
- NEVER remove content without showing what will be lost
- If no issues found: report "All clean" and stop (no unnecessary changes)
