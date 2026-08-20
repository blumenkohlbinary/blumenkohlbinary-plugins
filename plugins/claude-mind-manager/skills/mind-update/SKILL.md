---
name: mind-update
description: |
  [Mind Manager] Context-Sweep mit ZWEI Pflicht-Teilen: (1) deterministische
  Drift-Erkennung (Versionen, Pfade, Counts, Syntax, Commit-Coverage) inline,
  (2) Knowledge-Sync — dispatcht IMMER die 4 Per-Bereich-Agents (claude-md/memory/
  rules/custom-context), aber SEQUENZIELL bzw. max 2 gleichzeitig, NIE >=3 im selben
  Tool-Call (Anthropic Server-Rate-Limit). Alle 4 gleichen Session-Inhalte mit den
  Context-Files ab und klassifizieren in 5 Klassen (UPDATE/ENRICH/ADD/NEW_FILE/INFO).
  v5.0.0: Befunde werden AUTONOM angewendet (ausser DESIGN); '--ask' fragt wie
  frueher, '--dry-run' aendert nichts.

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

## Step 0: Modus + Snapshot (PFLICHT, NEU v5.0.0)

**Autonom ist der Standard.** Drift-Fixes UND Knowledge-Sync-Befunde werden selbstaendig
angewendet (frueher: alles ASK-Default).

```bash
ARGS="${ARGUMENTS:-}"; AUTO_MODE="yes"; DRY_RUN="no"
echo "$ARGS" | grep -qE '(^|[[:space:]])--(ask|interactive)([[:space:]]|$)' && AUTO_MODE="no"
echo "$ARGS" | grep -qE '(^|[[:space:]])--dry-run([[:space:]]|$)' && { DRY_RUN="yes"; AUTO_MODE="no"; }

# Laeuft dieser Skill innerhalb eines AKTIVEN /mind-all? (C1-Fix: drei Bedingungen, nicht nur
# "Datei existiert" — sonst gilt nach dem ersten /mind-all JEDER spaetere Einzellauf als Kette
# und editiert ohne Snapshot.)
CHAIN="no"; _SC="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude-mind/analyzed-scopes"
if [ -f "$_SC" ]; then
  _SNAP=$(grep -m1 '^snapshot=' "$_SC" 2>/dev/null | cut -d= -f2-)
  _START=$(grep -m1 '^run_started=' "$_SC" 2>/dev/null | cut -d= -f2)
  _AGE=$(( $(date +%s) - ${_START:-0} ))
  # 1) Snapshot-Pfad eingetragen  2) Verzeichnis existiert wirklich  3) Lauf juenger als 2 h
  [ -n "$_SNAP" ] && [ -d "$_SNAP" ] && [ "$_AGE" -lt 7200 ] && CHAIN="yes"
fi

if [ "$DRY_RUN" = "no" ] && [ "$CHAIN" = "no" ]; then
  [ -z "$CLAUDE_PLUGIN_ROOT" ] && { echo "ERROR: \$CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 1; }
  source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
  SNAPSHOT=$(mind_snapshot "${CLAUDE_PROJECT_DIR:-$(pwd)}" "pre-update") || {
    echo "ABBRUCH: Snapshot fehlgeschlagen — es wird NICHTS editiert." >&2; exit 1; }
  echo "Snapshot: $SNAPSHOT"
fi
```

| Modus | Aufruf | Verhalten |
|---|---|---|
| **autonom (Default)** | `/mind-update` | AUTO/DEAD/UPDATE/ENRICH/ADD/NEW_FILE werden angewendet |
| **interaktiv** | `/mind-update --ask` | Report → Freigabe (Verhalten vor v5.0.0) |
| **Probelauf** | `/mind-update --dry-run` | zeigt alles, aendert nichts |
| **nur Drift** | `/mind-update --quick` | ohne Knowledge-Sync (unveraendert) |

**Nie automatisch:** DESIGN-Befunde · **>5 DEAD-Pfade** (Massenloesch-Sicherung, Step 3b).
**Bei Snapshot-Fehlschlag wird NICHT editiert.**

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
   **MIT** YAML-Frontmatter (`name`, `description`, `metadata.type`); das ist das
   aktuelle Harness-Format. **v5.0.0-Korrektur:** frueher stand hier "ohne
   Frontmatter", woraus Step 3e eine Falschwarnung fuer JEDE korrekt formatierte
   Datei ableitete)
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

**VOR-FILTER (PFLICHT, NEU v5.0.0) — vor jedem `test -e` anwenden.**

Ein `test -e` kann nur beantworten "existiert als Datei" — NICHT "ist ueberhaupt ein
Dateipfad". Web-Adressen ohne Protokoll, abgekuerzte Beispiele und Platzhalter fallen
sonst als DEAD durch und werden **autonom geloescht**. Real gemessen: 5 echte Treffer,
**5 Fehltreffer** (`asus.com/…/helpdesk_qvl_memory`, `testufo.com/frameskipping`,
`/releases/44/`, `/releases/test/`, ein relativ geschriebener existierender Pfad).

```bash
# Klassifikation pro extrahiertem String -> SKIP | UNSURE | CHECK
classify_path() {
  local p="$1"
  # 1) SKIP: Web-Adresse ohne Protokoll (Domain + TLD am Anfang oder nach /)
  echo "$p" | grep -qiE '(^|/)([a-z0-9-]+\.)+(com|de|org|net|io|dev|ai|co|eu|info)(/|$)' && { echo SKIP; return; }
  # 2) SKIP: Protokoll explizit
  echo "$p" | grep -qiE '^(https?|ftp|mailto|file)://' && { echo SKIP; return; }
  # 3) SKIP: abgekuerztes Beispiel oder Platzhalter
  #    v5.3.1: *'['*']('* ergaenzt — Markdown-Link-Syntax. `[name](../../references/file.md)`
  #    enthielt KEINES der anderen Zeichen, wurde also CHECK -> nicht gefunden -> DEAD ->
  #    und bei <=5 Findings AUTONOM GELOESCHT. Genau diese Zeile steht in der CLAUDE.md
  #    dieses Projekts (Referenz-Loading-Konvention). Gemessen 2026-08-17.
  case "$p" in
    *'…'*|*'...'*|*'<'*'>'*|*'{'*'}'*|*'$'*|*'*'*|*'['*']('*) echo SKIP; return;;
  esac
  # 3b) SKIP: Slash-Command (NEU v5.3.1) — fuehrender /, GENAU ein Segment, mit Bindestrich.
  #     `/mind-all`, `/deep-review` sind Befehlsnamen, keine Pfade. Sie landeten bisher auf
  #     UNSURE und erzeugten 8 INFO-Findings Rauschen in genau dem Projekt, das sie baut.
  #     ⛔ Kriterium bewusst ENG: NICHT "ein Segment ohne Punkt" — das verschluckte /etc,
  #     /tmp, /usr, /var, /opt. Ein Bindestrich trennt Befehlsnamen sauber von
  #     Unix-Wurzelverzeichnissen; Mehrsegmentiges wie /tmp/mind-manager.log faellt vorher raus.
  #     EHRLICHER PREIS: ein wirklich toter Pfad der Form /foo-bar wird nicht mehr gelistet.
  #     Vertretbar, weil fuehrende-/-Pfade ohnehin nie angewendet, sondern nur gemeldet werden.
  case "$p" in
    */*/*) : ;;                            # mehr als ein Segment -> kein Befehlsname
    /*-*)  echo SKIP; return;;
  esac
  # 4) UNSURE: fuehrender / ohne Laufwerk/MSYS-Wurzel -> auf Windows meist URL-Fragment
  case "$p" in
    /[a-z]/*|/) : ;;                       # /c/... = MSYS-Laufwerk -> pruefbar
    /*) echo UNSURE; return;;
  esac
  echo CHECK
}
```

**Verifikation pro Pfad:**
- Nur `CHECK`-Strings gehen in `test -e`. **Relative Pfade gegen `$CLAUDE_PROJECT_DIR`
  aufloesen**, nicht gegen das aktuelle CWD — ein Fehltreffer der Messung war ein real
  existierender, relativ geschriebener Pfad, der nur vom falschen Verzeichnis aus fehlte:
  `[ -e "$CLAUDE_PROJECT_DIR/$p" ] || [ -e "$p" ]`.
- `SKIP` → gar kein Finding (keine Dateipfade).
- `UNSURE` → Finding Klasse **INFO**, wird **nie** angewendet (nur gelistet).
- `CHECK` + nicht auffindbar → Finding Klasse DEAD.

**Massenloesch-Sicherung (gilt AUCH im Autonom-Modus):**
- **≤5 DEAD-Findings:** werden angewendet. **Jede geloeschte Zeile wandert WOERTLICH in den
  Report** (`Entfernt: <zeile>`) — zusammen mit dem Snapshot aus Step 0 ist jede Loeschung
  nachlesbar und rueckholbar.
- **>5 DEAD-Findings:** **NICHT** anwenden, auch nicht autonom. Als Block listen mit
  Begruendung *"ungewoehnlich viele tote Pfade — Verdacht auf Filter-Fehler, bitte pruefen"*.
  Grund: Autonomie multipliziert einen Algorithmus-Fehler; ein einzelner Fehlgriff ist
  reparabel, ein Massenschnitt durch alle Context-Dateien nicht zumutbar.

### 3c: Commit-Coverage-Gate (deterministisch — objektiver Knowledge-Gap)

**Zweck (v3.3.2):** Dies ist der DETERMINISTISCHE Kern der Knowledge-Gap-Erkennung.
Er entwertet die "ich kenne den Stand schon"-Ausrede: wenn Commit X nachweislich
in keiner Context-Datei steht, IST das ein Gap — unabhaengig davon was Claude
zu wissen glaubt. Diese Findings speisen Step 3.5 mit konkreten Pruef-Punkten.

- Nur wenn `.git/` existiert.
- **KEIN Git (v5.0.0, Befund 7): NICHT stillschweigend ueberspringen.** Der Self-Check MUSS
  dann diese Zeile enthalten:
  `[Step 3c] KEIN GIT — kein objektives Gate verfuegbar; alle Befunde beruhen allein auf
  semantischem Abgleich`. Gleiches gilt fuer Step 3c.1 (Datei-Targeting faellt aus → es
  greift der Groessen-Guard). Grund: 3c ist laut diesem Skill "der DETERMINISTISCHE Kern",
  der die "ich kenne den Stand"-Ausrede entwertet. Faellt er weg, ist die Beweislage eine
  andere — der Bericht darf das nicht verschweigen.
- `git log --oneline -30` (oder seit letztem doc-beruehrenden Commit).
- Pro `feat:`/`fix:`/`refactor:`/`perf:` Commit: Scope + Subject-Stichworte gegen
  **CLAUDE.md UND MEMORY.md** greppen.

```bash
# Commit-Coverage: welche Feature-Commits sind NICHT in den Context-Dateien?
# Stichwort-Wahl (N1-Fix): zuerst dev.NN, dann der conventional-commit-SCOPE
# (feat(SCOPE):), erst zuletzt ein Subject-Token — Stopwords ausgeschlossen.
# Grep-Ziele als ARRAY, nie als Zeichenkette: ein Pfad mit Leerzeichen zerfaellt sonst in
# Stuecke — derselbe Fehler, der in v5.2.1 die Rotation lahmlegte (xargs +
# "Plugin - Entwicklung"). Die Zusatzziele kommen aus der CLAUDE.md SELBST; es wird nicht
# geraten, welche Datei "kanonisch" ist. Gemessen: 2 -> 17 Ziele im Zustellplan-Projekt.
ZIELE=("CLAUDE.md" "$MEMORY_MAIN")
while IFS= read -r z; do
  [ -n "$z" ] && [ -f "$z" ] && ZIELE+=("$z")
done < <(grep -oE '`[A-Za-z0-9_./-]+\.md`' CLAUDE.md 2>/dev/null | tr -d '`' | sort -u)

git log --oneline -30 | grep -iE '^[0-9a-f]+ (feat|fix|refactor|perf|docs)(\(|:)' | while read -r line; do
  hash=$(echo "$line" | cut -d' ' -f1)
  subj=$(echo "$line" | cut -d' ' -f2-)
  # 1) VERSION (fuehrendes v abgestreift)  2) dev.NN  3) Scope, Punkt erlaubt: docs(claude.md)
  key=$(echo "$subj" | grep -oiE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^[vV]//')
  [ -z "$key" ] && key=$(echo "$subj" | grep -oiE 'dev\.[0-9]+' | head -1)
  [ -z "$key" ] && key=$(echo "$subj" | sed -nE 's/^[a-z]+\(([a-z0-9_.-]{3,})\).*/\1/p' | head -1)
  # KEIN -F: grep -iF auf UTF-8 (deutsche Umlaute in MEMORY.md) wirft auf Git-Bash/MSYS
  # "Aborted (core dumped)" -> non-zero -> falsche GAPs (real 2026-07-15: 24 Fake-GAPs aus
  # dem Crash). grep -qi (ohne -F) ist verifiziert crash-frei; Keys sind regex-safe. v4.1.0-Fix.
  if [ -z "$key" ]; then
    # Sichtbar machen statt verschweigen: ohne belastbares Stichwort ist der Commit
    # UNGEPRUEFT, nicht unauffaellig. Genau diese Stille war der Defekt bis v5.5.1.
    echo "KEIN-STICHWORT: $hash '$subj' — ungeprueft, kein belastbares Stichwort"
  elif ! grep -qi "$key" "${ZIELE[@]}" 2>/dev/null; then
    echo "GAP: $hash '$subj' — Stichwort '$key' fehlt in ${#ZIELE[@]} Context-Dateien"
  fi
done
```

**N1-Hinweis (neu gefasst v5.5.2 — die alte Zusicherung war teuer erkauft):** Der enge Weg
bis v5.5.1 konnte einen Gap *übersehen*, aber nie einen *erfinden*. Der Preis dafür war, in
einem Doku-Workspace **gar nichts** zu sehen: `docs:` fiel durch den Filter, und damit blieben
dort **0 von 17** Commits ungeprüft — gemeldet wurde trotzdem „keine Lücken".

Der neue Weg hält die Zusicherung anders: Ein Stichwort wird nur genommen, wenn es **belastbar**
ist (Version · `dev.NN` · Scope). Gibt es keines, wird geraten — nein: wird der Commit als
`KEIN-STICHWORT` **ausgewiesen**. Der Rückfall auf ein beliebiges Subject-Token ist entfallen;
deutsche Subjects lieferten dort Verben („vereinheitlichen", „protokollieren"), die per
Konstruktion nie in der Doku stehen und damit garantierte Fehlalarme waren.

⛔ **`KEIN-STICHWORT` ist ein Ergebnis, kein Rauschen.** Es heißt „dieser Commit wurde nicht
geprüft" — nicht „dieser Commit ist in Ordnung". Wer die Zeilen wegblendet, stellt genau die
Stille wieder her, die der Defekt war.

**Belege (2026-08-20, alle gegen echte Git-Historie, nicht gegen Kunstbeispiele):**
Reproduktion am eigenen Repo — altes Gate **0** betrachtete Commits und **0** GAPs, während
`v5.5.1` nachweislich in *keiner* Context-Datei stand; das neue Gate findet genau diesen Commit.
**Negativkontrolle:** am Stand nach dem Nachtrag meldet es ihn nicht mehr — die Messung schlägt
in beide Richtungen aus. Stichwort-Erkennung gegen **14 synthetische Subjects inkl. 3
Gegenproben** (`95 -> 79`, `12.30 Uhr`, `3.2x` dürfen NICHT als Version durchgehen).
**Flut-Kontrolle** in zwei realen Projekten: Zustellplan 23 → 28 betrachtete Commits bei
weiterhin **0** GAPs, Grep-Ziele 2 → 17.

⚠ **Was weiterhin blind bleibt:** Repos ohne Conventional-Commit-Präfixe. In `APP - Palvedo`
trifft der Filter **0 von 30** Commits — vorher wie nachher. Das ist keine Regression, aber auch
keine Lösung; es steht hier, damit niemand das Gate für vollständig hält.

- Jeder `GAP:` = **objektives Knowledge-Gap-Finding** (Commit-Hash + Subject + fehlendes Stichwort).
- Jedes `KEIN-STICHWORT:` = **ungeprueft** (v5.5.2). Zaehlt NICHT als Gap, darf aber auch nicht
  als "sauber" gelten — beide Zahlen gehoeren getrennt in den Self-Check-Block.
- Diese Liste geht als konkreter Input an Step 3.5 ("verifiziere/ergaenze diese unreflektierten Commits").
- **WICHTIG:** Wenn die Commit-Coverage Gaps zeigt, MUSS Step 3.5 laufen — ein nicht-leeres Gap-Set widerlegt jede "alles synchron / ich kenne den Stand"-Annahme.

### 3c.1: Datei-Targeting — welche Rules hat die Session berührt? (v4.1.0 — Skalierung)

**Zweck:** Bei Projekten mit vielen/großen Rules (Zustellplan: ~118k Tokens in 11 Files, 2 davon
>1200 Zeilen) kann ein einzelner semantischer Agent NICHT alle Rules lesen — er läuft über (0 Output).
Lösung: der semantische Pass (Step 3.5) prüft nur die **session-berührten** Rules. Diese hier
deterministisch bestimmen — aus den Commit-Scopes (die mappen auf Datei-Inhalte).

```bash
# Existenz-Guards (H3/Skill-Review G): ohne .git kein Scope-Signal, ohne rules-Dir nichts zu targeten.
if [ ! -d .claude/rules ]; then
  echo "kein .claude/rules/ -> 3c.1 gegenstandslos"; SEM_RULES=""; TARGET_MODE="none"
else
  # 1) Größe des gesamten Rules-Satzes — entscheidet, ob Targeting überhaupt nötig ist.
  RULES_KB=$(( $(cat .claude/rules/*.md 2>/dev/null | wc -c) / 1024 ))

  # 2) Commit-Scopes als Targeting-Signal (nur wenn .git). SCOPE bevorzugen (mappt auf Datei-Inhalt).
  KEYS=""
  if [ -d .git ]; then
    STOP='the|and|for|that|with|from|into|als|der|die|das|und|fix|feat|add|new|update'
    KEYS=$(git log --oneline -30 | grep -iE '^[0-9a-f]+ (feat|fix|refactor|perf)(\(|:)' | while read -r line; do
      subj=$(echo "$line" | cut -d' ' -f2-)
      scope=$(echo "$subj" | sed -nE 's/^[a-z]+\(([a-z0-9_-]{3,})\).*/\1/p' | head -1)
      key="${scope:-$(echo "$subj" | tr ' ' '\n' | grep -iE '^[a-z_]{4,}$' | grep -ivE "^($STOP)$" | head -1)}"
      [ -n "$key" ] && echo "$key"
    done | sort -u)
  fi

  # 3) Touched-Map: robuster per-Datei-grep OHNE -r und OHNE -F (crashen zusammen auf Git-Bash/MSYS
  #    bei UTF-8-Rules, verifiziert 2026-07-15). Keys sind regex-safe ([a-z0-9_-]).
  TOUCHED_RULES=$(for key in $KEYS; do for f in .claude/rules/*.md; do grep -li "$key" "$f" 2>/dev/null; done; done | sort -u)

  # 4) Entscheidungsbaum — KEIN stilles 0 (Skill-Review B):
  if [ "$RULES_KB" -lt 160 ]; then
    TARGET_MODE="all"; SEM_RULES=$(ls .claude/rules/*.md)   # klein genug -> alle passen, Targeting unnötig
    echo "Rules-Satz klein (${RULES_KB}KB) -> semantischer Pass: ALLE Rules"
  elif [ -n "$TOUCHED_RULES" ]; then
    TARGET_MODE="targeted"; SEM_RULES="$TOUCHED_RULES"
    echo "Rules groß (${RULES_KB}KB) -> semantischer Pass NUR session-berührte:"; echo "$SEM_RULES"
  else
    TARGET_MODE="unscopable"; SEM_RULES=""
    echo "WARN: Rules groß (${RULES_KB}KB) ABER kein Commit-Scope-Signal (kein .git / keine passenden Scopes)."
    echo "      -> semantischer Rules-Pass NICHT scopebar. Report MUSS das als 'deterministisch-only,"
    echo "         nicht semantisch geprüft' ausweisen + /mind-rules einzeln empfehlen. KEIN stilles 0."
  fi
  echo "=== NICHT im semantischen Pass (nur deterministisch: 3e+3e.2) ==="
  for f in .claude/rules/*.md; do echo "$SEM_RULES" | grep -qxF "$f" || printf "  %s (%s Z.)\n" "$f" "$(wc -l < "$f")"; done
fi
```

- **Erring broad = sicher:** ein zu breiter Treffer prüft nur ein paar Files extra; ein *verpasster*
  wäre schlimm — die `{3,}`/`{4,}`-Guards halten Keys ≥3-4 Zeichen (kein 2-Zeichen-Scope-Explosion).
- **Targeting ≠ Skip (ehrlich, Skill-Review C):** Der DETERMINISTISCHE Rules-Sicherungsnetz ist
  **Step 3e (Syntax) + 3e.2 (Content-Drift)** — die laufen über ALLE Project+Global-Rules, PFLICHT,
  unabhängig vom Targeting. (Das Commit-Coverage-Gate 3c prüft CLAUDE.md+MEMORY, NICHT die Rules.)
  Das Targeting fokussiert NUR den *semantischen* Re-Read.
- **Ehrlicher Rest:** „untouched" heißt „diese Session hat die Datei nicht per Commit berührt" —
  NICHT „da ist garantiert nichts zu ergänzen". Eine ADD-würdige Session-Erkenntnis, die in eine
  *unberührte* große Rule gehört, fällt aus dem gezielten semantischen Pass → sie wird über 3e.2
  (falls Versions-/Muster-Drift) ODER über die Report-Offenlegung (`TARGET_MODE`/deterministisch-only
  + `/mind-rules`-Pointer) sichtbar, nicht stillschweigend geschluckt.

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
  **Frontmatter ist der SOLLZUSTAND (v5.0.0-Korrektur).** Pruefen statt warnen:
  `name` + `description` + `metadata.type` vorhanden UND
  `type` aus {user, feedback, project, reference}. **WARNING nur bei Verstoss**
  (fehlendes Feld / unbekannter type) — NICHT dafuer, dass Frontmatter da ist.

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

## Step 3.5: Per-Bereich Knowledge-Sync (4 Agents, sequenziell/gestaffelt)

**Directive:** Dieser Schritt laeuft IMMER (ausser `QUICK_MODE=yes`). Es gibt keinen
Inline-Ersatz — der semantische Abgleich Session<->Context laeuft NUR ueber die
Agents. Wenn Step 3c Commit-Coverage-Gaps gefunden hat, ist "alles synchron / ich
kenne den Stand" objektiv widerlegt → dispatchen ist Pflicht, nicht Ermessen.

**WICHTIG — Methode ≠ Mandat (Anti-Burst, v4.0.1):** Alle 4 Bereiche sind PFLICHT und
werden IMMER abgedeckt. Aber sie werden **SEQUENZIELL** (einer nach dem anderen) bzw.
**maximal 2 gleichzeitig** dispatcht — **NIE 3-4 im selben Tool-Call**. Grund: ein Burst
aus ≥3 gleichzeitigen Agents trippt reproduzierbar Anthropics **server-seitiges
Rate-Limit** ("Server is temporarily limiting requests — not your usage limit", 429/529)
→ ALLE Agents scheitern, 0 Ergebnisse (3× gemessen: 2026-06-15/29 + 2026-07-04, schon 3
gleichzeitig reichten). Das gilt **auch unter Ultracode**. **`sequenziell` heißt NICHT
`optional`** — alle 4 laufen, nur nicht im selben Tool-Call. Diese Staffelung NIE
"aus Performance-Gründen" zu einem Parallel-Burst zurückdrehen.

Dispatch die 4 `context-analyzer` Agents **nacheinander** (oder in 2 Wellen à 2 —
Welle 1: claude-md + memory, Welle 2: rules + custom-context; jede Welle ihr eigener
Tool-Call). Ergebnisse aller 4 einsammeln, dann konsolidieren. Jeder bekommt:
- Scope: `claude-md` / `memory` / `rules` / `custom-context`
- Mode: `knowledge-sync`
- **Scope-Dedup (NEU v5.0.0, Befund 5):** Vor jedem Dispatch `.claude-mind/analyzed-scopes`
  pruefen. Steht der Scope dort (von `/mind-all` durch einen vorherigen Skill eingetragen),
  **NICHT erneut dispatchen** — im Self-Check ausweisen als
  `scope=<x> → bereits durch <skill> abgedeckt (analyzed-scopes)`.
  ```bash
  SCOPES_FILE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude-mind/analyzed-scopes"
  # nur wenn Scope UND Modus uebereinstimmen:
  scope_done() { [ -f "$SCOPES_FILE" ] && grep -q "^$1=.*:knowledge-sync$" "$SCOPES_FILE"; }
  # z.B.: scope_done claude-md && echo "skip" || dispatch...
  ```
  **NUR bei gleichem Modus ueberspringen (M3-Fix):** Der Eintrag traegt den Modus
  (`claude-md=mind-claudemd:default`). `mode: default` ist eine **andere Analyse** als
  `mode: knowledge-sync` (letztere vergleicht den Session-Auszug). Ein `:default`-Eintrag
  darf einen `knowledge-sync`-Dispatch **nicht** unterdruecken — sonst faellt der
  semantische Session-Abgleich still aus, den dieser Skill selbst als nicht-ueberspringbar
  fuehrt. **Ersparnis ist kein Skip-Grund.** **Gilt NUR fuer die Kette** — bei
  einem einzelnen `/mind-update` ohne vorherige Skills ist die Datei leer/alt und alle
  4 Scopes laufen normal. `custom-context` wird nie uebersprungen (kein anderer Skill deckt ihn ab).
- Bereich-Files (Read-only) — **rules-scope: die `SEM_RULES` aus Step 3c.1** (je nach `TARGET_MODE`:
  `all` = alle Project-Rules wenn Satz klein; `targeted` = nur session-berührte wenn groß; `unscopable`/
  `none` = leer). **Plus die Global-Rules `~/.claude/rules/*.md`** — die werden IMMER mit übergeben
  (wenige, meist klein, immer-aktive Verhaltensregeln), aber **jede EINZELN dem Größen-Guard unterworfen**
  (große global-Rule → auch grep-gezielt, nicht blind). Ist `SEM_RULES` leer bei `TARGET_MODE=unscopable`:
  rules-Agent mit "Project-Rules nicht scopebar → deterministisch-only, /mind-rules einzeln" vermerken —
  **NICHT stillschweigend 0**, und NICHT ersatzweise blind alle großen Rules lesen.
- **Größen-Guard (v4.1.0):** Für JEDE übergebene Datei Zeilenzahl (`wc -l`) UND Bytes (`wc -c`) aus
  Step-1-Inventory mitgeben. **>~600 Zeilen ODER >~60 KB → dem Agenten sagen: NICHT ganz lesen,
  sondern per Stichwort grep-gezielt (±40 Zeilen um Treffer).** (Bytes-Schwelle fängt dichte kurze
  Files: z.B. data-model.md = 428 Z. aber 67 KB / ~17k Tokens.) Sonst Overflow → 0 Output (real
  gesehen). Der Agent hat den Guard auch selbst (context-analyzer), das hier ist der Skill-Hinweis.
- **Die Commit-Coverage-Gaps aus Step 3c** als konkrete Pruef-Punkte ("verifiziere/ergaenze diese unreflektierten Commits in deinem Bereich")
- Session-Auszug — **Quelle je `SESSION_SOURCE`:**
  - `gerettet`: **die Rettungsdatei** `.claude-mind/rescued/<ts>_chat.md` (vollstaendiger Chat
    vor der Kompaktierung, ungekuerzt). Bei >600 Zeilen/60 KB gilt der Groessen-Guard des
    Agenten — er greppt gezielt statt blind zu lesen.
    > ⛔ **KONTEXT-FLUT-SPERRE (NEU v5.2.1):** Dem Agenten wird der **PFAD** uebergeben, nie der
    > Inhalt. Im **Hauptkontext** wird `*_chat.md` **nie** gelesen — kein `Read`, kein `cat`,
    > kein `sed`/`head` auf den Inhalt; erlaubt sind nur zaehlende Aufrufe (`grep -c`, `wc`).
    > **Warum das eine Invariante ist:** Der Lauf wird per Stop-Hook direkt nach einer
    > Kompaktierung erzwungen. Die Datei ist mehrere hundert KB (gemessen 417 KB / 555 Beitraege);
    > wer sie in den frisch geleerten Kontext liest, loest sofort die naechste Kompaktierung aus,
    > die eine neue Rettung erzeugt, die den naechsten Zwangslauf ausloest. Ein `Read` darauf im
    > Hauptfluss ist **Abbruchgrund**.
  - `live`: der Sampler-Auszug wie bisher (USER + ASSISTANT_TEXT, 3-stufiges Sampling).
  - **`gerettet+live` (NEU v5.2.2, der Normalfall nach einer Kompaktierung): BEIDE.** Dem
    Agenten werden **zwei** Quellen genannt — der Rettungspfad (vollstaendig, aber nur bis zur
    Kompaktierung) **und** der Live-Sampler-Auszug (deckt die Zeit danach ab).
    > **Warum das keine Doppelung ist:** Die Rettung endet zwangslaeufig am
    > Kompaktierungs-Zeitpunkt. Der Lauf, den der Stop-Hook danach erzwingt, soll aber gerade
    > die Arbeit einspeisen, die seitdem passiert ist. Mit nur einer der beiden Quellen fehlt
    > entweder die Tiefe (live ist gesampelt) oder die Aktualitaet (Rettung ist alt).
- ⛔ **Der Agent MUSS die uebergebenen kanonischen Zahlen ZURUECKGEBEN (NEU v5.7.0).**
  Zwei Fehlberichte sind belegt: „14 Topic-Dateien" bei uebergebenen **10**, und
  „`stop.sh` und `session-start.sh` sourcen `lib.sh` nicht (0 von 2)" — gemessen sourct
  `session-start.sh` sie sehr wohl. Beide klangen plausibel und waren falsch.
  Deshalb endet jeder Agent-Prompt mit: *„Gib in der ersten Zeile die dir uebergebenen Zahlen
  woertlich zurueck."* Weicht die Rueckgabe ab, ist der ganze Agentenbericht **ungeprueft** —
  nicht teilweise gueltig. Kostet eine Zeile und macht den Unterschied zwischen Hinweis und Beleg.
- **Im Self-Check MUSS die Quelle stehen** (`Session-Quelle: gerettet+live <pfad>` bzw.
  `gerettet <pfad>` bzw. `live`) — sonst ist nicht erkennbar, ob der Sync auf dem vollen Chat,
  auf Resten oder auf beidem lief. **`gerettet` allein nach einer Kompaktierung ist ab v5.2.2
  ein Befund, kein Normalzustand.**

### Session-Auszug-Sampling (Plan-EC2: 3-stufiger Algorithmus)

Bei langen Sessions (>500 Events) verliert naives "letzte 200" Architektur-Entscheidungen
aus der Mitte. 3-Stufen-Algorithmus:

```bash
# Python-Helper extrahiert relevante Events aus aktueller JSONL
# (gleicher Code wie mind-compact Step 3, hier zur Wiederverwendung)
# --- QUELLEN-WAHL (NEU v5.1.0): geretteter Chat schlaegt Live-Sampling ---
# Nach einer Kompaktierung enthaelt das Live-Transkript nur noch die Zusammenfassung.
# Der PreCompact-Hook hat den VOLLEN Chat vorher nach .claude-mind/rescued/ gerettet —
# DAS ist dann die richtige Quelle. Ohne diese Wahl wuerde der Knowledge-Sync nach jeder
# Kompaktierung auf Resten arbeiten und genau das verpassen, wofuer er da ist.
# v5.2.1: Vorrang hat der Zeiger aus der offenen Schuld (OPEN) — er nennt genau die Rettung,
# fuer die der Sync noch aussteht. Fehlt OPEN (aeltere Version): neueste Datei per Zeitstempel.
_MU_OPEN="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude-mind/rescued/OPEN"
RESCUED=""
# v5.4.1: OPEN kann mehrere Rettungen nennen — alle nehmen, aelteste zuerst.
[ -f "$_MU_OPEN" ] && RESCUED=$(grep '^path=' "$_MU_OPEN" 2>/dev/null | cut -d= -f2-                                 | while IFS= read -r p; do [ -f "$p" ] && echo "$p"; done)
[ -n "$RESCUED" ] && [ ! -f "$RESCUED" ] && RESCUED=""
[ -z "$RESCUED" ] && RESCUED=$(ls -t "${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude-mind/rescued"/*_chat.md 2>/dev/null | head -1)

# ⛔ FIX v5.2.2 — hier stand ein ENTWEDER-ODER, und das war ein Konstruktionsfehler.
# Die Rettung enthaelt per Definition nur, was VOR der Kompaktierung war. Alles, was danach
# gearbeitet wird, steht ausschliesslich im Live-Transkript. Wer nur die Rettung nimmt, ist
# blind fuer die juengste Arbeitsphase — und genau die ist der Grund, warum der Stop-Hook den
# Lauf ueberhaupt erzwingt.
# BELEGT am 2026-08-16 im eigenen Projekt: die Rettung endete 17:40:15, der gesamte
# v5.2.1-Bau lag danach. Der rules-Agent fand NULL Treffer fuer "stop.sh", "OPEN",
# "Flut-Sperre", "listeverbesserungen" — er konnte sie nicht finden, sie waren nicht drin.
# Der Sync haette die Arbeit, wegen der er lief, komplett verpasst.
# Deshalb jetzt: BEIDE Quellen, wenn beide da sind.
if [ -n "$RESCUED" ] && [ -s "$RESCUED" ]; then
  SESSION_SOURCE="gerettet+live"
  # NUR ZAEHLEN, NICHT LESEN (Kontext-Flut-Sperre v5.2.1)
  echo "Session-Quelle: gerettet -> $RESCUED ($(grep -c '^## \[' "$RESCUED") Beitraege)"
  echo "                + live    -> Sampler ueber das laufende Transkript (deckt die Zeit NACH der Rettung ab)"
else
  SESSION_SOURCE="live"
  echo "Session-Quelle: live (kein geretteter Chat vorhanden)"
fi

SAMPLER="$CLAUDE_PLUGIN_ROOT/references/session_sampler.py"   # v5.0.0: ausgeliefert, KEIN Heredoc
# Frueher wurde das Skript zur Laufzeit per Heredoc nach /tmp geschrieben — auf Windows/Git-Bash
# unzuverlaessig (Pfade mit '&', Leerzeichen, Umlauten). Jetzt liegt es im Plugin.
[ -f "$SAMPLER" ] || { echo "ERROR: session_sampler.py fehlt: $SAMPLER" >&2; exit 1; }

# cygpath ist Pflicht (Windows-Pfade fuer den Python-Aufruf)
command -v cygpath >/dev/null 2>&1 || { echo "ERROR: cygpath nicht verfuegbar" >&2; exit 1; }
SAMPLER_WIN=$(cygpath -w "$SAMPLER")

# JSONL der aktuellen Session finden (Slug via lib.sh)
[ -z "$CLAUDE_PLUGIN_ROOT" ] && { echo "ERROR: \$CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 1; }
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
SLUG=$(hash_project_dir)
PROJECTS_DIR="$HOME/.claude/projects/$SLUG"
[ ! -d "$PROJECTS_DIR" ] && PROJECTS_DIR=$(ls -td "$HOME"/.claude/projects/*/ 2>/dev/null | head -1 | sed 's|/$||')
JSONL=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | grep -v '/subagents/' | head -1)
[ -z "$JSONL" ] && { echo "ERROR: kein Session-JSONL in $PROJECTS_DIR" >&2; exit 1; }
JSONL_WIN=$(cygpath -w "$JSONL")

# Python-Path
if [ -x ".venv/Scripts/python.exe" ]; then PYTHON=".venv/Scripts/python.exe"
elif command -v python3 &>/dev/null; then PYTHON="python3"
else PYTHON="python"; fi

SESSION_SAMPLE_BASH="/tmp/mind_update_session.json"
SESSION_SAMPLE_WIN=$(cygpath -w "$SESSION_SAMPLE_BASH")
"$PYTHON" "$SAMPLER_WIN" "$JSONL_WIN" "$SESSION_SAMPLE_WIN"

# Hinweis bei sehr langer Session
TOTAL=$(grep -oE '"total_events":\s*[0-9]+' "$SESSION_SAMPLE_BASH" | grep -oE '[0-9]+')
LONG=$(grep -oE '"long_session_hint":\s*(true|false)' "$SESSION_SAMPLE_BASH" | grep -oE '(true|false)')
if [ "$LONG" = "true" ]; then
  echo "WARN: Session sehr lang ($TOTAL Events). Empfehlung: erst /mind-compact + /compact, dann /mind-update erneut."
fi
```

### 4 Agent-Dispatches — sequenziell bzw. in 2 Wellen à 2 (NIE ≥3 gleichzeitig)

**NICHT alle 4 in EINER Tool-Call-Message** (das wäre der ≥3-Burst, der das Server-Rate-Limit
trippt — v4.0.1). Stattdessen: **einzeln nacheinander**, ODER in 2 Wellen à 2 (Welle 1 =
Agent 1+2 in einem Tool-Call, Welle 2 = Agent 3+4 im nächsten). Alle 4 laufen — nur nie 3-4 auf einmal.

| Agent | scope | mode | Input |
|---|---|---|---|
| 1 | `claude-md` | `knowledge-sync` | CLAUDE.md project + global + Session-Auszug aus `$SESSION_SAMPLE_BASH` |
| 2 | `memory` | `knowledge-sync` | MEMORY.md + Topic-Files aus Step 1 + Session-Auszug |
| 3 | `rules` | `knowledge-sync` | **`SEM_RULES` (Step 3c.1, je `TARGET_MODE`)** + Global-Rules (immer, je einzeln größen-geguardet) + Session-Auszug — bei großem Satz NICHT alle Project-Rules; jede Datei >600 Z. **ODER >60 KB** mit Größen-Guard (grep-gezielt, nicht ganz lesen) |
| 4 | `custom-context` | `knowledge-sync` | `CUSTOM_CONTEXT_FILES` aus Step 1.5 + Session-Auszug |

**Skip-Logik pro Agent:**
- Agent 4 (`custom-context`) skippen wenn `${#CUSTOM_CONTEXT_FILES[@]} == 0` (Plan EC4) — das ist die EINZIGE erlaubte Auslassung; die anderen 3 sind unbedingt Pflicht.

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

**v5.0.0 — Modus entscheidet, nicht die Klasse:**
- `AUTO_MODE=yes` (Default): UPDATE/ENRICH/ADD/NEW_FILE werden **angewendet**, nicht gefragt.
  Die "ASK Default"-Angaben in den Klassen-Tabellen oben gelten NUR fuer `--ask`.
- `AUTO_MODE=no` (`--ask`): Klassen-Tabelle wie beschrieben (ASK Default).
- `DRY_RUN=yes`: nichts anwenden, nur listen.
- **DESIGN bleibt in JEDEM Modus ausgenommen.**

**KRITISCHE REGEL (weiterhin):** Sagt der User "behebe alle"/"fix all"/"ja mach", ist das
explizite Erlaubnis — auch fuer ASK-Findings im `--ask`-Modus.

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

[Step 3c Commit-Coverage] <B> betrachtete Commits · <K> Gaps · <U> ohne Stichwort · <Z> Grep-Ziele
  - <hash> "<subject>" — Stichwort "<key>" fehlt in <Z> Context-Dateien
  - KEIN-STICHWORT: <hash> "<subject>" — ungeprueft
  ... (oder "0 Gaps bei <B> betrachteten Commits")
  ⛔ <B> == 0 ist KEIN gutes Ergebnis, sondern eine Blindstelle — dann ausdruecklich sagen,
     dass das Gate nichts pruefen konnte (Repo ohne Conventional Commits?).
  Beleg: git-log + grep Output in Tool-Call #<N>

[Step 3.5 Per-Bereich Knowledge-Sync] 4 Agents dispatched (sequenziell/≤2 pro Welle, NIE ≥3):
  Session-Quelle: <gerettet <pfad> (N Beitraege) | live>
  - scope=claude-md      → <A> Findings (U:<x> E:<y> A:<z> NF:<w> I:<v>)
      Beispiel-Belege: [UPDATE] CLAUDE.md:15 "v3.2.2" -> Session v3.3.0
  - scope=memory         → <B> Findings (oder "0 — MEMORY aktuell")
  - scope=rules          → TARGET_MODE=<all|targeted|unscopable|none> (aus Step 3c.1). DREI Buckets:
                           (a) voll-semantisch geprüft (klein, ganz gelesen): <liste> → <C> Findings
                           (b) gezielt-semantisch (touched + oversized >600 Z./>60 KB, grep-gezielt N Abschnitte): <liste>
                           (c) deterministisch-only (untouched ODER unscopable, nur 3e+3e.2): <liste mit Zeilenzahl>
                           → Tiefen-Audit einer großen (b/c)-Datei: /mind-rules bzw. /mind-claudemd einzeln darauf
  - scope=custom-context → <D> Findings (oder "SKIPPED: 0 Custom-Context-Files aus Step 1.5")
  Beleg: Agent-Tool-Calls #X, #Y, #Z, #W (nacheinander bzw. 2 Wellen — kein 4er-Burst)

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

**Step 1.5 (Custom-Context-Discovery) + Step 3.5 (4 Agents, sequenziell/≤2 pro Welle) + Step 3e.2 (Rules-Inhalts-Check) gehoeren zur Identitaet des Skills** (ausser `QUICK_MODE=yes`).

- Der semantische Abgleich (Step 3.5) hat **keinen Inline-Ersatz** — er laeuft NUR ueber die Agents. Inline-Reasoning ist kein Substitut.
- **"Ich kenne den Stand schon / habe es selbst geschrieben" ist KEIN gueltiger Skip-Grund.** Step 3c Commit-Coverage belegt Gaps OBJEKTIV (Commit X steht nachweislich nicht in den Context-Files). Subjektives Wissen schlaegt diese Evidenz nicht.
- Wenn Step 3c ein nicht-leeres Gap-Set liefert, MUSS Step 3.5 laufen — der Schritt ist dann nicht "gegenstandslos".
- Step 1.5 entdeckt projekt-weite Custom-Context-Files (plan.md, research.md, docs/*) via Bash-Discovery — die Files sind ohne find/grep gar nicht bekannt.
- Step 6 Self-Check-Block weist jeden Step mit Belegen aus; fehlt er, darf der User den Report zurueckweisen.

### Bei QUICK_MODE=yes (--quick Arg)

- Step 1.5 + Step 3.5 + Step 3e.2 explizit skippen
- Prominenter Banner im Report-Header (siehe Step 6)
- Self-Check-Block markiert jeden Step als `SKIPPED — --quick (User-Wahl)`

### Agent-Parallelitaets-Limit (verschaerft v4.0.1 — Anti-Burst)

- **NIE ≥3 context-analyzer gleichzeitig.** Die 4 Step-3.5-Agents laufen SEQUENZIELL bzw.
  in 2 Wellen à 2 (max 2 pro Tool-Call). Grund: ein Burst aus ≥3 gleichzeitigen Agents trippt
  Anthropics **server-seitiges Rate-Limit** ("Server is temporarily limiting requests — not your
  usage limit", 429/529) → ALLE scheitern, 0 Ergebnisse. 3× real gemessen (2026-06-15/29 +
  2026-07-04, schon 3 gleichzeitig reichten). **Gilt auch unter Ultracode** (stehende User-Regel,
  siehe globale Rule `workflow-agent-rate-limit.md`). **Alle 4 Bereiche bleiben Pflicht** — nur
  gestaffelt, nicht als Burst. (Frueher stand hier faelschlich "MAX 4 parallel" — das war genau
  der brechende Burst.)
- Skills duerfen NICHT andere Skills dispatchen die ihrerseits Agents starten.
- **Parallel-Bash-Limit (NEU v3.2.2):** Skill startet MAX 2 Bash-Tools parallel,
  niemals 3+. Bei 3+ Calls: zu seriellem Aufruf wechseln ODER kombinieren via `&&`.
  Claude Code's Tool-System cancelled uebermaessige Parallelitaet (siehe Session
  2026-05-29 Log 4 Tool 5+7 `Cancelled: parallel tool call ... errored`).
- **Autonom-Modus (v5.0.0, Default):** angewendet werden AUTO · DEAD (≤5) · UPDATE · ENRICH · ADD · NEW_FILE. **NIE automatisch:** DESIGN · **>5 DEAD-Pfade** (Massenloesch-Sicherung Step 3b). Bei `--ask` gilt die alte Aufteilung (nur sichere Fixes auto, Rest fragen).
- **NEVER apply without a successful `mind_snapshot` (Step 0)** — Fehlschlag = Abbruch, keine Edits.
- **ALWAYS report every applied change** mit `file:line` + before→after; **geloeschte Pfad-Zeilen woertlich** (`Entfernt: <zeile>`) + Snapshot-Pfad + Restore-Einzeiler.
- ALWAYS show what was auto-fixed in the report
- ALWAYS show before/after line counts
- ALWAYS backup files before editing (cp to .claude-mind/backups/)
- NEVER remove content without showing what will be lost
- If no issues found: report "All clean" and stop (no unnecessary changes)
