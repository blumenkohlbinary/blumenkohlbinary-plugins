---
name: mind-update
description: |
  [Mind Manager] Context-Sweep mit ZWEI Pflicht-Teilen: (1) deterministische
  Drift-Erkennung (Versionen, Pfade, Counts, Syntax, Commit-Coverage) inline,
  (2) Knowledge-Sync — dispatcht IMMER 4 Per-Bereich-Agents parallel (claude-md/
  memory/rules/custom-context) die Session-Inhalte mit den Context-Files abgleichen
  und in 5 Klassen klassifizieren (UPDATE/ENRICH/ADD/NEW_FILE/INFO). Auto-Fix fuer
  sichere Aenderungen, Rueckfrage fuer alles andere.

  Der Knowledge-Sync ist KEINE optionale Beschleunigungs-Stufe — er ist Teil der
  Identitaet dieses Skills. Nur `--quick` schaltet ihn explizit ab.

  Use when the user says "update context", "refresh context", "mind update",
  "quick check", "context status", "sync context",
  or "/mind-update [--quick]".
argument-hint: "[--quick]"
context: inherit
allowed-tools: Read Glob Grep Edit Bash Agent
---

# Context-Sweep + Knowledge-Sync

Deterministische Drift-Checks inline -> Knowledge-Sync via Per-Bereich-Agents
-> sichere Fixes auto-anwenden -> Report.

**Identitaet (directive):** Dieser Skill macht BEIDES — Drift-Checks UND Knowledge-Sync.
Der Knowledge-Sync (Step 3.5) wird IMMER ausgefuehrt (ausser `--quick`). Es gibt
KEINEN Inline-Ersatz dafuer: der semantische Abgleich Session<->Context laeuft NUR
ueber die dispatchten Agents. "Ich kenne den Stand schon" ist kein gueltiger Grund
ihn zu ueberspringen — siehe Step 3c Commit-Coverage, die Gaps objektiv belegt.

## Step 1: Alle Context-Dateien lesen (project + global + topic-files)

Read all context files directly via Read/Bash (dies ist der Datei-Lese-Schritt;
der Knowledge-Sync via Agents folgt in Step 3.5). **6 Targets — alle PFLICHT,
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
GET_MEM_RC=$?  # H1-Fix Skill-Review v3.3.1: $? in Variable capturen vor naechstem Cmd
# H2-aware: $? = 1 wenn Fallback verwendet wurde
if [ "$GET_MEM_RC" = "1" ]; then
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

## Step 2.5: Args parsen (NEU v3.3.0)

```bash
ARGS="${ARGUMENTS:-}"
QUICK_MODE="no"
echo "$ARGS" | grep -qE '(^|[[:space:]])--quick([[:space:]]|$)' && QUICK_MODE="yes"

if [ "$QUICK_MODE" = "yes" ]; then
  echo "INFO: --quick Mode -> nur Drift-Checks (Step 3), kein Knowledge-Sync (Step 3.5)"
fi
```

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

### 3c: Commit-Coverage-Gate (deterministisch — objektiver Knowledge-Gap)

**Zweck (v3.3.2):** Dies ist der DETERMINISTISCHE Kern der Knowledge-Gap-Erkennung.
Er entwertet die "ich kenne den Stand schon"-Ausrede: wenn Commit X nachweislich
in keiner Context-Datei steht, IST das ein Gap — unabhaengig davon was Claude
zu wissen glaubt. Diese Findings speisen Step 3.5 mit konkreten Pruef-Punkten.

- Nur wenn `.git/` existiert.
- `git log --oneline -30` (oder seit letztem doc-beruehrenden Commit).
- Pro `feat:`/`fix:`/`refactor:`/`perf:` Commit: Scope + Subject-Stichworte gegen
  **CLAUDE.md UND MEMORY.md** greppen.

```bash
# Commit-Coverage: welche Feature-Commits sind NICHT in den Context-Dateien?
# Stichwort-Wahl (N1-Fix): zuerst dev.NN, dann der conventional-commit-SCOPE
# (feat(SCOPE):), erst zuletzt ein Subject-Token — Stopwords ausgeschlossen.
STOP='the|and|for|that|with|from|into|als|der|die|das|und|fix|feat|add|new|update'
git log --oneline -30 | grep -iE '^[0-9a-f]+ (feat|fix|refactor|perf)(\(|:)' | while read -r line; do
  hash=$(echo "$line" | cut -d' ' -f1)
  subj=$(echo "$line" | cut -d' ' -f2-)
  # 1) dev.NN  2) scope aus feat(scope):  3) erstes Subject-Token >=4 chars, kein Stopword
  key=$(echo "$subj" | grep -oiE 'dev\.[0-9]+' | head -1)
  [ -z "$key" ] && key=$(echo "$subj" | sed -nE 's/^[a-z]+\(([a-z0-9_-]{3,})\).*/\1/p' | head -1)
  [ -z "$key" ] && key=$(echo "$subj" | tr ' ' '\n' | grep -iE '^[a-z_]{4,}$' | grep -ivE "^($STOP)$" | head -1)
  if [ -n "$key" ] && ! grep -qiF "$key" CLAUDE.md "$MEMORY_MAIN" 2>/dev/null; then
    echo "GAP: $hash '$subj' — Stichwort '$key' fehlt in CLAUDE.md+MEMORY.md"
  fi
done
```

**N1-Hinweis:** Die Stichwort-Heuristik kann im Zweifel einen Gap *übersehen* (false-negative),
aber nie einen *erfinden* (kein false-GAP) — die Gate-Evidenz bleibt verlässlich. Bei
Unsicherheit lieber Step 3.5 trotzdem laufen lassen (Agents finden den semantischen Rest).

- Jeder `GAP:` = **objektives Knowledge-Gap-Finding** (Commit-Hash + Subject + fehlendes Stichwort).
- Diese Liste geht als konkreter Input an Step 3.5 ("verifiziere/ergaenze diese unreflektierten Commits").
- **WICHTIG:** Wenn die Commit-Coverage Gaps zeigt, MUSS Step 3.5 laufen — ein nicht-leeres Gap-Set widerlegt jede "alles synchron / ich kenne den Stand"-Annahme.

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
# Project rules — Syntax-Check (paths: vs globs:)
grep -rn '^paths:' .claude/rules/*.md 2>/dev/null

# Global rules (NEU v3.2.1)
grep -rn '^paths:' "$HOME"/.claude/rules/*.md 2>/dev/null
```

### 3e.2: Rules-Inhalts-Drift (NEU v3.3.1, zusaetzlich zu 3e Syntax) — PFLICHT

**WICHTIG (Real-World-Bug aus Session 2026-05-31):** Step 3e prueft nur `paths:` Syntax,
aber NICHT den INHALT der Rule-Files. Drift (veraltete Versionen, Test-Counts) bleibt
unbemerkt. **Skip nur bei `QUICK_MODE=yes`.**

**Restriktive Patterns** (vermeiden Plauder-False-Positives wie "we discussed dev.13"):

```bash
if [ "$QUICK_MODE" != "yes" ]; then
  RULES_HITS=0
  for f in .claude/rules/*.md "$HOME"/.claude/rules/*.md; do
    [ -f "$f" ] || continue
    # Versions-Patterns nur mit Kontext-Keyword (Stable/Unstable/Last sync/Tabelle/Bullet/Code)
    hits=$(grep -nE "v?[0-9]+\.[0-9]+\.[0-9]+(-dev\.[0-9]+)?" "$f" 2>/dev/null | \
           grep -iE "(stable|unstable|tag|commit|last sync|^[[:space:]]*[-*|\`])" )
    # Test-Counts nur mit Test-Keyword in derselben Zeile
    hits2=$(grep -nE "\b[0-9]{2,4}\s+(pytest-)?[Tt]ests?\b" "$f" 2>/dev/null | \
            grep -iE "(gruen|gruene|passed|collected|pytest|coverage)")
    if [ -n "$hits$hits2" ]; then
      echo "=== $f ($(wc -l < "$f") Zeilen) ==="
      [ -n "$hits" ] && echo "$hits"
      [ -n "$hits2" ] && echo "$hits2"
      RULES_HITS=$((RULES_HITS + 1))
    fi
  done
  echo "Rules-Files mit potentieller Drift: $RULES_HITS"
fi
```

**False-Positive-Mitigation:**
- Versions-Pattern valid nur wenn Zeile mit Kontext-Keyword (`Stable`/`Unstable`/`Tag`/`Commit`/`Last sync`) ODER mit `-`/`*`/`|`/backtick beginnt (Tabelle/Bullet/Code)
- Test-Counts valid nur wenn `gruen`/`passed`/`collected`/`pytest`/`coverage` in derselben Zeile
- Bei >10 Hits in EINEM Rule-File: Warnung "vermutlich noch False-Positives" + User-Frage statt Auto-Action

**Jeder Hit → Finding mit Klasse aus Step 4:**
- AUTO bei eindeutiger Drift (z.B. `434 Tests gruen` und Source-of-Truth ist 464)
- ASK bei Build/Release-relevanten Files (z.B. `build-process.md` `Last sync` updaten?)
- INFO bei Genesis-Refs ("Pool-Reform seit v1.0.6-dev.6" — Doku der Historie, keine Drift)

**Beispiel-Hits (Real-World Zustellplan):**
- `build-process.md:17` `Last sync: v1.0.3 / 2026-05-07` (Stable jetzt v1.0.5) → ASK
- `git-conventional-commits.md:94` `283 Tests gruen` (jetzt 464) → AUTO
- `tab1-berechnung.md:44` `Pool-Reform seit v1.0.6-dev.6` → INFO (Genesis)

### 3f: Total Context Budget
- Sum all context file lines: CLAUDE.md (all scopes) + MEMORY.md + all rules
- >500 lines = WARNING: "High context overhead"
- >300 lines = INFO: "Moderate context load"
- <300 lines = OK

## Step 3.5: Per-Bereich Knowledge-Sync (4 parallel Agents)

**Directive:** Dieser Schritt laeuft IMMER (ausser `QUICK_MODE=yes`). Es gibt keinen
Inline-Ersatz — der semantische Abgleich Session<->Context laeuft NUR ueber die
Agents. Wenn Step 3c Commit-Coverage-Gaps gefunden hat, ist "alles synchron / ich
kenne den Stand" objektiv widerlegt → dispatchen ist Pflicht, nicht Ermessen.

Dispatch 4 `context-analyzer` Agents PARALLEL (alle in 1 Tool-Call-Message). Jeder bekommt:
- Scope: `claude-md` / `memory` / `rules` / `custom-context`
- Mode: `knowledge-sync`
- Bereich-Files (Read-only)
- **Die Commit-Coverage-Gaps aus Step 3c** als konkrete Pruef-Punkte ("verifiziere/ergaenze diese unreflektierten Commits in deinem Bereich")
- Session-Auszug (USER + ASSISTANT_TEXT der letzten 200 Events) — siehe Sampling unten

### Session-Auszug-Sampling (Plan-EC2: 3-stufiger Algorithmus)

Bei langen Sessions (>500 Events) verliert naives "letzte 200" Architektur-Entscheidungen
aus der Mitte. 3-Stufen-Algorithmus:

```bash
# Python-Helper extrahiert relevante Events aus aktueller JSONL
# (gleicher Code wie mind-compact Step 3, hier zur Wiederverwendung)
SAMPLE_BASH="/tmp/mind_update_sample.py"

if ! command -v cygpath &>/dev/null; then
  echo "ERROR: cygpath nicht verfuegbar — mind-update Step 3.5 benoetigt cygpath" >&2
  exit 1
fi
SAMPLE_WIN=$(cygpath -w "$SAMPLE_BASH")

# JSONL der aktuellen Session finden (gleicher Code wie mind-session-log Step 2)
# H3-Fix Skill-Review: Guard wiederholen, falls Step 3.5 in fresh bash invocation laeuft
if [ -z "$CLAUDE_PLUGIN_ROOT" ] || [ ! -f "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" ]; then
  echo "ERROR: \$CLAUDE_PLUGIN_ROOT nicht gesetzt oder lib.sh nicht gefunden" >&2
  exit 1
fi
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
SLUG=$(hash_project_dir)
PROJECTS_DIR="$HOME/.claude/projects/$SLUG"
[ ! -d "$PROJECTS_DIR" ] && PROJECTS_DIR=$(ls -td "$HOME"/.claude/projects/*/ 2>/dev/null | head -1 | sed 's|/$||')
JSONL=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | grep -v '/subagents/' | head -1)
JSONL_WIN=$(cygpath -w "$JSONL")

# Sample-Script (Heredoc)
cat > "$SAMPLE_BASH" << 'PYEOF'
#!/usr/bin/env python3
"""Session-Auszug fuer mind-update Step 3.5 — 3-stufiges Sampling.

Stage 1 Pre-Filter: Events mit Decision/Bug/Architecture/Constraint-Markern
Stage 2 Stratified: bei >300 Pre-Filtered -> 5 Buckets, Top-60 nach Score
Stage 3 Hint: bei >1000 Total -> User-Hinweis (im Skill-Output)
"""
import json, re, sys
from pathlib import Path

JSONL_PATH = sys.argv[1]
OUT_PATH = sys.argv[2]

# Pre-Filter Patterns (gleicher Geist wie mind-compact)
RELEVANT_PATTERNS = [
    re.compile(r'\b(decision|architekt|pattern|wir entscheiden|wir nutzen|wir machen)\b', re.IGNORECASE),
    re.compile(r'\b(bug|error|fail|crash|fix|tool_use_error|cancelled)\b', re.IGNORECASE),
    re.compile(r'\b(MUST|NEVER|niemals|immer|wichtig|kein push)\b', re.IGNORECASE),
    re.compile(r'\bversion\s+(?:v?\d+\.\d+|\d+\.\d+\.\d+)', re.IGNORECASE),
    re.compile(r'\b(install|deploy|release|commit|push|merge)\b', re.IGNORECASE),
]

# Self-Exclusion: aktueller mind-update Run
SELF = re.compile(r'<command-name>/(?:[^/<]+:)?mind-update</command-name>')

EXCLUDE_FROM = None
for lineno, line in enumerate(open(JSONL_PATH, encoding='utf-8'), 1):
    if SELF.search(line):
        EXCLUDE_FROM = lineno

events = []  # (lineno, role, text, score)
total = 0

with open(JSONL_PATH, encoding='utf-8') as f:
    for lineno, line in enumerate(f, 1):
        if EXCLUDE_FROM and lineno >= EXCLUDE_FROM:
            continue
        try:
            obj = json.loads(line.strip())
        except json.JSONDecodeError:
            continue
        if obj.get('isSidechain') or obj.get('type') == 'queue-operation':
            continue
        msg = obj.get('message', {}) or {}
        content = msg.get('content')
        text = ""
        role = ""
        if obj.get('type') == 'user' and isinstance(content, str):
            text, role = content, "USER"
        elif obj.get('type') == 'assistant' and isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get('type') == 'text':
                    text += block.get('text', '') + "\n"
            role = "ASSISTANT"
        if not text:
            continue
        total += 1
        # Stage 1: Pre-Filter Score = Anzahl gematchter Patterns
        score = sum(1 for p in RELEVANT_PATTERNS if p.search(text))
        if score > 0:
            events.append((lineno, role, text[:500], score))  # text auf 500 chars limit

# Stage 2: Stratified bei >300 Pre-Filtered
if len(events) > 300:
    events.sort(key=lambda x: x[0])  # by line_no
    bucket_size = len(events) // 5
    buckets = [events[i*bucket_size:(i+1)*bucket_size] for i in range(5)]
    buckets[-1] = events[4*bucket_size:]  # rest in letzten Bucket
    # Top-60 pro Bucket nach Score
    selected = []
    for b in buckets:
        b.sort(key=lambda x: -x[3])  # score desc
        selected.extend(b[:60])
    events = selected

# Stage 3 wird im Skill-Output gehandhabt (Hinweis bei total > 1000)

# Output JSON
out = {
    "total_events": total,
    "filtered_events": len(events),
    "long_session_hint": total > 1000,
    "self_exclusion_line": EXCLUDE_FROM,
    "sample": [{"line": l, "role": r, "text": t} for (l, r, t, _) in events]
}
Path(OUT_PATH).write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
print(f"OK: {total} total -> {len(events)} sampled")
PYEOF

# Python-Path
if [ -x ".venv/Scripts/python.exe" ]; then PYTHON=".venv/Scripts/python.exe"
elif command -v python3 &>/dev/null; then PYTHON="python3"
else PYTHON="python"; fi

SESSION_SAMPLE_BASH="/tmp/mind_update_session.json"
SESSION_SAMPLE_WIN=$(cygpath -w "$SESSION_SAMPLE_BASH")
"$PYTHON" "$SAMPLE_WIN" "$JSONL_WIN" "$SESSION_SAMPLE_WIN"

# Hinweis bei sehr langer Session
TOTAL=$(grep -oE '"total_events":\s*[0-9]+' "$SESSION_SAMPLE_BASH" | grep -oE '[0-9]+')
LONG=$(grep -oE '"long_session_hint":\s*(true|false)' "$SESSION_SAMPLE_BASH" | grep -oE '(true|false)')
if [ "$LONG" = "true" ]; then
  echo "WARN: Session sehr lang ($TOTAL Events). Empfehlung: erst /mind-compact + /compact, dann /mind-update erneut."
fi
```

### 4 parallel Agent-Dispatches

Dispatcht in EINER Tool-Call-Message (echtes Parallel — siehe Plan D1: max 4 Agents pro Skill):

| Agent | scope | mode | Input |
|---|---|---|---|
| 1 | `claude-md` | `knowledge-sync` | CLAUDE.md project + global + Session-Auszug aus `$SESSION_SAMPLE_BASH` |
| 2 | `memory` | `knowledge-sync` | MEMORY.md + Topic-Files aus Step 1 + Session-Auszug |
| 3 | `rules` | `knowledge-sync` | Project-Rules + Global-Rules aus Step 1 + Session-Auszug |
| 4 | `custom-context` | `knowledge-sync` | `CUSTOM_CONTEXT_FILES` aus Step 1.5 + Session-Auszug |

**Skip-Logik pro Agent:**
- Agent 4 (`custom-context`) skippen wenn `${#CUSTOM_CONTEXT_FILES[@]} == 0` (Plan EC4)

**Prompt-Format pro Agent** (Skill-Review M5 — Serialisierung explizit):

Skill konstruiert pro Agent einen Markdown-Prompt mit Sections:
```markdown
mode: knowledge-sync
scope: <claude-md|memory|rules|custom-context>

## Memory Dir
<MEMORY_DIR-Pfad aus get_memory_dir()>

## Custom Context Files       (NUR scope: custom-context)
./plan.md
./research.md
./docs/architecture.md

## Session Auszug (letzte N Events)
[Inhalt aus $SESSION_SAMPLE_BASH JSON, formatiert als USER/ASSISTANT-Blocks]
```

Die `CUSTOM_CONTEXT_FILES`-Array wird **als 1 Pfad pro Zeile** in die `## Custom Context Files`-Section serialisiert:
```bash
printf '%s\n' "${CUSTOM_CONTEXT_FILES[@]}"
```

Findings aller (3-4) Agents aggregieren → an Step 4.

## Step 4: Findings-Klassifikation + Fixes (Skill-Review M6 — Header ergaenzt)

**Pre-Edit Read (MUST, praezisiert v3.2.2):** Step 1 hat zwar alle Context-Dateien
gelesen, aber das zaehlt NICHT fuer Step 4 — Read muss im SELBEN Tool-Call-Kontext
wie Edit erfolgen.

**1× Read der Ziel-Datei** reicht fuer N sequentielle Auto-Fixes (Edit-Tool
garantiert "file state is current — no need to Read it back"). Re-Read nur wenn
anderes Tool die Datei zwischendurch modifiziert.

### 4a: Klassifikation pro Finding

Jedes Finding bekommt eine Klasse aus 9 Optionen (4 Drift + 5 Knowledge-Sync):

**Drift-Klassen (aus Step 3, bestehend):**

| Klasse | Bedeutung | Aktion |
|---|---|---|
| **AUTO** | Mismatch, sicher fix-bar (Versions-Drift CLAUDE.md ↔ package.json, paths→globs) | Read + Edit OHNE Frage |
| **ASK** | Echter Mismatch ABER mit Build/Release-Konsequenzen (z.B. `pyproject.toml` Version, Hatchling/PyPI-Metadata, semver-relevant) | User fragen — NIE silent auto-fixen |
| **DESIGN** | "By design" markiert in Rule/CLAUDE.md (explizite Regel sagt "NICHT anfassen") | NICHT als "Issue" zaehlen, aber als Hinweis am Ende erwaehnen — ggf. Regel praezisieren |
| **DEAD** | Pfad existiert nicht UND Pfad enthaelt `/` oder `\` (siehe Step 3b) | AUTO falls eindeutig (max 5 Findings), sonst ASK |

**Knowledge-Sync-Klassen (aus Step 3.5, NEU v3.3.0):**

| Klasse | Bedeutung | Aktion |
|---|---|---|
| **UPDATE** | Custom-Context-Wert veraltet (Session-Stand widerspricht) | ASK Default — User entscheidet weil "veraltet" subjektiv |
| **ENRICH** | Wert vorhanden aber vage — Session hat Details | ASK Default — User entscheidet ob Details rein sollen |
| **ADD** | Wissen aus Session fehlt komplett in Custom-Context | ASK Default — User waehlt Ziel-Datei + Section |
| **NEW_FILE** | Komplett neues Thema, kein passender Container | ASK Default — User bestaetigt Filename + Inhalt |
| **INFO** (uebergreifend, Drift+Sync) | Hinweis ohne Action (Archive-Vorschlag, Limit-Warnung) | Listen only, kein Action |

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

## Step 6: Report — PFLICHT-Self-Check-Block am Anfang (NEU v3.3.1)

**WICHTIG:** Der Report MUSS mit dem Self-Check-Block BEGINNEN. Jeder Marker MUSS
konkrete Beleg-Daten enthalten (Tool-Call-Refs, file:line, Agent-Findings).

**Wenn ein Marker fehlt oder `(SKIPPED)` ohne `--quick` enthaelt:** Der Skill-Run
ist BUGGY — User darf zurueckweisen mit "Self-Check-Block fehlt — bitte Steps
1.5 + 3.5 + 3e.2 ausfuehren".

### Bei QUICK_MODE=yes: Banner + SKIPPED-Markers

```
##############################################################
##  QUICK MODE ACTIVE — Knowledge-Sync wurde SKIPPED         ##
##  Du siehst nur Drift-Checks (Version, Pfade, Test-Counts) ##
##  Fuer vollen Sweep: /mind-update OHNE --quick aufrufen    ##
##############################################################

=== Context Update v3.3.2 — Self-Check ===
[Step 1.5 Custom-Context-Discovery] SKIPPED — --quick mode (User-Wahl)
[Step 3.5 Per-Bereich Knowledge-Sync] SKIPPED — --quick mode (User-Wahl)
[Step 3e.2 Rules-Inhalts-Check] SKIPPED — --quick mode (User-Wahl)
```

### Bei NORMAL MODE: PFLICHT-Format mit Belegen (anti-faking EC1)

```
=== Context Update v3.3.2 — Self-Check ===
[Step 1.5 Custom-Context-Discovery] <N> Files discovered:
  - <pfad1> (mtime: YYYY-MM-DD HH:MM, size: <X>KB)
  - <pfad2> (mtime: YYYY-MM-DD HH:MM, size: <X>KB)
  ... (oder "0 Files — Bash-find Output in Tool-Call #<N>")

[Step 3c Commit-Coverage] <K> unreflektierte feat/fix/refactor-Commits:
  - <hash> "<subject>" — Stichwort "<key>" fehlt in CLAUDE.md+MEMORY.md
  ... (oder "0 — alle Feature-Commits in Context-Files reflektiert")
  Beleg: git-log + grep Output in Tool-Call #<N>

[Step 3.5 Per-Bereich Knowledge-Sync] 4 Agents dispatched:
  - scope=claude-md      → <A> Findings (U:<x> E:<y> A:<z> NF:<w> I:<v>)
      Beispiel-Belege: [UPDATE] CLAUDE.md:15 "v3.2.2" -> Session v3.3.0
  - scope=memory         → <B> Findings (oder "0 — MEMORY aktuell")
  - scope=rules          → <C> Findings (Beleg: file:line)
  - scope=custom-context → <D> Findings (oder "SKIPPED: 0 Custom-Context-Files aus Step 1.5")
  Beleg: Agent-Tool-Calls #X, #Y, #Z, #W

**Regel (v3.3.2):** Wenn Step 3c K>0 Gaps zeigt, DARF [Step 3.5] nicht "0 dispatched /
gegenstandslos" sein — die Gaps sind objektiver Gegenbeweis. "Ich kenne den Stand"
ist kein zulaessiger Eintrag hier.

[Step 3e.2 Rules-Inhalts-Check] <R> Drift-Hits in <F> Rule-Files:
  - build-process.md:17 "Last sync: v1.0.3" (Stable jetzt v1.0.5)
  - git-conventional-commits.md:94 "283 Tests gruen" (jetzt 464)
  ... (oder "0 Hits — Rules sind inhaltlich aktuell")
  Beleg: Bash-grep Output in Tool-Call #<N>
```

**Pflicht-Format jeder Marker-Zeile:** `<scope/check>` → `<count> <kind>` → `(Beleg-Quelle: <Tool-Call-Ref oder file:line>)`. Ohne Beleg ist Marker UNGUELTIG.

---

## Step 6.1: Drift-Report + Knowledge-Sync-Report (nach Self-Check-Block)

```
=== Context Update ===
Checked: N files | Drift: A auto-fixed, B need input, C by design, D dead
Knowledge-Sync: E findings (U:N E:N A:N NF:N I:N) — skipped if --quick

CLAUDE.md (project):     145 -> 138 lines (-7)
  [AUTO] Version 2.5.0 -> 2.6.0
  [AUTO] Removed dead path: src/old-module/
  [ASK]  Unreflected commit "feat: dark mode" — add to CLAUDE.md?

CLAUDE.md (global):       55 lines (OK)

MEMORY.md (project):      89 lines (OK, within 200 budget)
MEMORY topic files:       2 (lessons.md: 12, tab7-bugfixes.md: 18)

Rules (project):          3 files, all valid syntax
Rules (global):           4 files, all valid syntax

Total context: 287 lines (~2870 tokens) -- Compliance: ~92%

=== Knowledge-Sync (NEU v3.3.0, Session ↔ Custom Context) ===
Scope claude-md       (Agent 1): 2 UPDATE, 1 ENRICH
Scope memory          (Agent 2): 0 Findings
Scope rules           (Agent 3): 1 ADD ("Plan-Mode-Regel" fehlt in ~/.claude/rules/)
Scope custom-context  (Agent 4): 1 NEW_FILE-Vorschlag (backup-strategie.md)

[UPDATE]   CLAUDE.md:15 "Version 3.2.2" -> Session diskutiert v3.3.0
[ENRICH]   knowledge/best-practices.md:120 Heredoc-Section knapp -> Session hat 4 Code-Beispiele
[ADD]      Session erklaert "Self-Exclusion Pattern" — keine Custom-Context-Datei
           Vorschlag: knowledge/best-practices.md "Self-Reference Patterns" anhaengen
[NEW_FILE] backup-strategie.md (~40 Zeilen, deckt 8 Zustellplan-Patterns ab)
[INFO]     MEMORY.md 180 Zeilen — nahe 200-Limit

Want me to apply [1]? [Yes / Select / Skip]
```

**WICHTIG:** Wenn pending Findings (ASK/UPDATE/ENRICH/ADD/NEW_FILE), IMMER explizit listen
— kein "0 issues". Step 4 Klassifikation entscheidet Klasse, Step 6 zaehlt korrekt.

**Knowledge-Sync-Findings sind alle ASK-Default** (User entscheidet pro Finding):
"Want me to apply [N]? [Yes / Select / Skip]"

If `QUICK_MODE=yes`: Knowledge-Sync-Sektion komplett ueberspringen, Report endet bei
Total-Context-Zeile.

## Hard Constraints

### Identitaet: dieser Skill dispatcht IMMER (directive, v3.3.2)

**Step 1.5 (Custom-Context-Discovery) + Step 3.5 (4 parallel Agents) + Step 3e.2 (Rules-Inhalts-Check) gehoeren zur Identitaet des Skills** (ausser `QUICK_MODE=yes`).

- Der semantische Abgleich (Step 3.5) hat **keinen Inline-Ersatz** — er laeuft NUR ueber die Agents. Inline-Reasoning ist kein Substitut.
- **"Ich kenne den Stand schon / habe es selbst geschrieben" ist KEIN gueltiger Skip-Grund.** Step 3c Commit-Coverage belegt Gaps OBJEKTIV (Commit X steht nachweislich nicht in den Context-Files). Subjektives Wissen schlaegt diese Evidenz nicht.
- Wenn Step 3c ein nicht-leeres Gap-Set liefert, MUSS Step 3.5 laufen — der Schritt ist dann nicht "gegenstandslos".
- Step 1.5 entdeckt projekt-weite Custom-Context-Files (plan.md, research.md, docs/*) via Bash-Discovery — die Files sind ohne find/grep gar nicht bekannt.
- Step 6 Self-Check-Block weist jeden Step mit Belegen aus; fehlt er, darf der User den Report zurueckweisen.

### Bei QUICK_MODE=yes (--quick Arg)

- Step 1.5 + Step 3.5 + Step 3e.2 explizit skippen
- Prominenter Banner im Report-Header (siehe Step 6)
- Self-Check-Block markiert jeden Step als `SKIPPED — --quick (User-Wahl)`

### Parallel-Agent-Limit

- **MAX 4 context-analyzer parallel** (Plan D1). Skills duerfen NICHT andere Skills dispatchen die ihrerseits Agents starten.
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
