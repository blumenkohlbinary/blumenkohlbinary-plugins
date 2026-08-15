---
name: mind-claudemd
description: |
  [Mind Manager] CLAUDE.md Vollverwaltung — erkennt, erstellt, auditiert, optimiert.
  Wenn keine CLAUDE.md existiert: Projekt scannen und nach Best Practices erstellen.
  Wenn vorhanden: Qualitäts-Score (0-100, A-F), veraltete/fehlende Infos erkennen,
  Duplikate mit MEMORY.md/Rules finden, Widersprüche aufdecken, dann AUTONOM fixen (v5.0.0;
  Snapshot vorher, '--ask' fragt wie frueher, '--dry-run' aendert nichts).

  Use when the user says "check claude.md", "create claude.md", "optimize claude.md",
  "improve claude.md", "mind claudemd", "audit claude.md", "fix claude.md",
  or "/mind-claudemd".
argument-hint: "[global]"
context: inherit
allowed-tools: Read Glob Grep Edit Write Bash Agent
---

# CLAUDE.md Vollverwaltung

Erkennen → Erstellen oder Auditieren → **autonom anwenden** (bzw. Freigabe bei `--ask`) → Bericht.

## Step 0: Modus + Snapshot (PFLICHT, NEU v5.0.0)

**Autonom ist der Standard.** Dieser Skill wendet gefundene Befunde selbstaendig an.

```bash
ARGS="${ARGUMENTS:-}"; AUTO_MODE="yes"; DRY_RUN="no"
echo "$ARGS" | grep -qE '(^|[[:space:]])--(ask|interactive)([[:space:]]|$)' && AUTO_MODE="no"
echo "$ARGS" | grep -qE '(^|[[:space:]])--dry-run([[:space:]]|$)' && { DRY_RUN="yes"; AUTO_MODE="no"; }

# Snapshot VOR dem ersten Edit — ausgefuehrter Aufruf, kein Prosa-Versprechen.
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
  SNAPSHOT=$(mind_snapshot "${CLAUDE_PROJECT_DIR:-$(pwd)}" "pre-claudemd") || {
    echo "ABBRUCH: Snapshot fehlgeschlagen — es wird NICHTS editiert." >&2; exit 1; }
  echo "Snapshot: $SNAPSHOT"
fi
```

| Modus | Aufruf | Verhalten |
|---|---|---|
| **autonom (Default)** | `/mind-claudemd` | Befunde werden angewendet, danach Bericht |
| **interaktiv** | `/mind-claudemd --ask` | Report → Freigabe → anwenden (Verhalten vor v5.0.0) |
| **Probelauf** | `/mind-claudemd --dry-run` | zeigt alles, aendert nichts |

**Bei Snapshot-Fehlschlag wird NICHT editiert** — lieber kein Lauf als ein Lauf ohne Netz.
**DESIGN-Befunde werden NIE automatisch angewendet** (Stellen, die eine Regel als
"niemals anfassen" markiert) — nur gelistet.

## Step 1: Scope bestimmen

Check `$ARGUMENTS`:
- `global` → Bearbeite `~/.claude/CLAUDE.md` (globale Datei)
- Kein Argument → Bearbeite Projekt-CLAUDE.md (`./CLAUDE.md` oder `./.claude/CLAUDE.md`)

## Step 2: CLAUDE.md suchen

Glob für die Ziel-Datei:
- Projekt: `./CLAUDE.md`, `./.claude/CLAUDE.md`
- Global: `~/.claude/CLAUDE.md`

Auch prüfen: `./CLAUDE.local.md` (deprecated — Warnung ausgeben wenn vorhanden).

**Wenn KEINE gefunden → weiter zu Step 3 (Generate-Modus)**
**Wenn gefunden → weiter zu Step 4 (Audit-Modus)**

## Step 3: Generate-Modus (keine CLAUDE.md vorhanden)

### Step 3a: Projekt scannen

Dispatch **project-scanner** Agent:
"Scan this project for tech stack, project type, build/test/lint commands, key directories, and frameworks. Report structured findings."

### Step 3b: Referenzen laden

Read these reference files:
- [references/claudemd-best-practices.md](../../references/claudemd-best-practices.md) — Required sections, anti-patterns, size guidelines
- [references/templates.md](../../references/templates.md) — 13 project type templates

### Step 3c: Template wählen + generieren

Basierend auf project-scanner Ergebnis:
1. Passenden Template-Typ wählen (web_app, api, cli, library, fullstack, mobile, default, workspace, scripts, data, config, desktop_app, game_mod)
2. Template mit Scan-Daten füllen (tech stack, build commands, conventions)
3. Ziel: 40-80 Zeilen, max 100

### Step 3d: Generation Checklist (MUST pass)
- [ ] Has build/test commands section?
- [ ] Has architecture/structure section?
- [ ] Has conventions section?
- [ ] No generic advice ("write clean code")?
- [ ] No linter tasks (belongs in linter config)?
- [ ] Under 100 lines?
- [ ] Uses H2/H3 headings + bullets?
- [ ] No secrets or credentials?

### Step 3e: Preview + Write

Show generated CLAUDE.md to user. Ask for confirmation before writing.

## Step 4: Audit-Modus (CLAUDE.md vorhanden)

### Step 4a: Referenzen laden

Read these reference files:
- [references/quality-scoring-guide.md](../../references/quality-scoring-guide.md) — 0-100 scoring rubric, A-F grading
- [references/quality-criteria.md](../../references/quality-criteria.md) — Optimization patterns + anti-patterns
- [references/prompt-quality-guide.md](../../references/prompt-quality-guide.md) — CLAUDE.md writing best practices
- [references/budget-thresholds.md](../../references/budget-thresholds.md) — SFEIR compliance data

### Step 4b: Dispatch context-analyzer Agent (directive, v3.3.2)

**Identitaet:** Im Audit-Modus dispatcht dieser Skill IMMER context-analyzer fuer den
semantischen Teil (Quality-Score, Widersprueche, semantische Duplikate). Dafuer gibt
es **keinen Inline-Ersatz** — die deterministischen Inline-Checks (Step 4c) decken nur
Version/Pfad/Budget ab, NICHT die semantische Bewertung. Der Agent ist der einzige Weg dorthin.

Launch **context-analyzer** with scope=claude-md:
"Analyze all CLAUDE.md files in this project. Scope: claude-md. Report quality score, contradictions, staleness, and optimization suggestions."

### Step 4c: Deterministische Inline-Checks (ergaenzend, NICHT statt Agent)

Während der Agent läuft, selbst prüfen:

1. **Versions-Check**: Read plugin.json/package.json → extract version. Grep CLAUDE.md für Versionsnummern. Mismatch → Finding.
2. **Pfad-Check**: Extract alle Pfade aus CLAUDE.md (backtick-wrapped, Zeilen mit `/` oder `\`). Bash: `test -e "$path"` für jeden. Tot → Finding.
3. **Git-Check** (nur wenn `.git/` existiert): `git log --oneline -10` → Gibt es Commits (feat, fix, refactor) die nicht in CLAUDE.md reflektiert sind?
4. **CLAUDE.local.md**: Wenn vorhanden → Deprecation-Warnung

### Step 4d: Ergebnisse konsolidieren + präsentieren

**Reduktion (v3.2.2):** Wenn context-analyzer-Agent eine vollstaendige
Findings-Tabelle geliefert hat, Tabelle **1:1 uebernehmen** statt eigenes Format
neu zu generieren. Nur Apply-Optionen (safe/all/select) hinzufuegen.

Agent-Ergebnisse + eigene Inline-Checks zusammenführen. Anzeigen als:

**PFLICHT-Self-Check-Block am Anfang (NEU v3.3.1):**

```
=== CLAUDE.md Audit Report v3.3.2 — Self-Check ===
[Step 4b context-analyzer] Agent dispatched: <N> Findings (Severity: <C> CRITICAL, <W> WARNING, <I> INFO), Health-Score <X>/100
  Beleg: context-analyzer Tool-Call #<N>
[Step 4c Inline-Checks] Version-Match: <ok/mismatch>, Pfad-Check: <Y> tote Pfade, Git-Check: <Z> unreflektierte Commits
  Beleg: Bash-Tool-Call #<N>
```

Fehlt der Self-Check-Block oder enthaelt `(SKIPPED)`: User darf zurueckweisen.

```
=== CLAUDE.md Audit Report ===

Score: 72/100 (Grade: C)
File: ./CLAUDE.md (145 lines, ~1450 tokens)
Compliance prognosis: ~85% (200-400 line range)

Findings (8):
[1] CRITICAL  CLAUDE.md:3    Version says "2.3.0" but plugin.json says "2.6.0"
[2] WARNING   CLAUDE.md:30-55 25-line section "TypeScript" → modularize to rules/ (~250 tokens)
[3] WARNING   CLAUDE.md:12   Verbose: "When you are writing..." → "TypeScript: MUST use strict"
[4] WARNING   CLAUDE.md:67   Duplicate of MEMORY.md:15 (same build command)
[5] INFO      CLAUDE.md:89   Dead path: `src/old-module/` does not exist
[6] INFO      —              Missing: Git commit "feat: add dark mode" not documented
[7] INFO      CLAUDE.md:45   Generic advice: "Write meaningful variable names" → remove
[8] INFO      —              CLAUDE.local.md exists → deprecated, migrate to @imports

Suggested actions:
[A] Fix version (auto)
[B] Modularize TypeScript section → .claude/rules/typescript.md
[C] Shorten 3 verbose lines (auto)
[D] Remove duplicate with MEMORY.md
[E] Remove dead path
[F] Add dark mode feature to Architecture section
[G] Remove generic advice line

Apply:
  [safe]    — Nur sichere Currency-Fixes (Drift, Versions, Pfade)
              Default bei vager Antwort ("ja"/"ok"/"update")
  [all]     — Inklusive struktureller Aenderungen (Modularize, Section-Adds)
  [select]  — Einzeln auswaehlen
  [skip]    — Nichts aendern
```

**Nur bei `AUTO_MODE=no` (`--ask`): STOP HERE, warte auf User-Bestätigung.**
**Bei `AUTO_MODE=yes` (Default): NICHT stoppen** — Findings anwenden (außer DESIGN),
danach Step 6 mit Angewendet-Block. Bei `DRY_RUN=yes`: Liste zeigen, nichts ändern.

**Disambiguation-Regel:** Bei vagen Antworten ("ja", "ok", "update", "los") IMMER
die `safe` Variante wählen (keine Modularization, keine Datei-Restruktur). Dem
User transparent mitteilen: "Wähle `safe` (Currency only) — sage `all` wenn du
auch strukturelle Änderungen willst."

## Step 5: Fixes anwenden (nach User-OK)

### Step 5a: Backup + Pre-Edit Read (MUST)

**Backup-Block (KONKRETER Bash-Snippet — NEU v3.2.2, präzisiert):**

```bash
# WICHTIG: Backup MIT cd ins Projekt-Verzeichnis VOR cp.
# Sonst landet relativer Pfad im aktuellen CWD (z.B. Mind-Manager-Workspace
# statt Ziel-Projekt — Bug aus Session 2026-05-29 Log 1 Tool 15).
# N2-Fix: $CLAUDE_PROJECT_DIR (Claude Code env var) bevorzugt, Fallback $(pwd)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" && \
  mkdir -p .claude-mind/backups && \
  cp CLAUDE.md ".claude-mind/backups/CLAUDE.md.$(date +%Y%m%d_%H%M%S).bak" && \
  echo "Backup OK: $(ls -t .claude-mind/backups/CLAUDE.md.*.bak | head -1)"
```

**Pre-Edit Read (praezisiert v3.2.2):**
- **1× Read der Ziel-Datei VOR dem ersten Edit** — reicht fuer N sequentielle
  Edits (Edit-Tool garantiert "file state is current — no need to Read it back")
- **Re-Read nur** wenn anderes Tool (z.B. Bash) die Datei zwischendurch modifiziert
- Crash-Vermeidung: `<tool_use_error>File has not been read yet` tritt auf wenn
  Edit OHNE vorherigen Read aufgerufen wird

Beispiel-Sequenz:
1. Read CLAUDE.md  (1× am Anfang)
2. Edit CLAUDE.md Z.96 (v10 → v11)
3. Edit CLAUDE.md Z.181 (v10 → v11)
4. Edit CLAUDE.md Z.185 (8 → 11 cols)
   ... (beliebig viele weitere Edits ohne neuen Read)

Bei Modularize-Fix: zusaetzlich Write der neuen Rule-Datei (kein Read noetig — neue Datei).

### Step 5b: Fixes anwenden

Für jeden bestätigten Fix:
| Fix-Typ | Tool | Aktion |
|---|---|---|
| Version updaten | Edit | `old_string: "2.3.0"` → `new_string: "2.6.0"` |
| Modularize | Write + Edit | Write neue Rule-Datei, Edit CLAUDE.md: Sektion entfernen |
| Shorten | Edit | `old_string: verbose Zeile` → `new_string: kompakte Zeile` |
| Deduplicate | Edit | Duplikat-Zeile aus CLAUDE.md entfernen |
| Dead path | Edit | Pfad-Zeile entfernen oder aktualisieren |
| Add info | Edit | Neue Zeile in passende Sektion einfügen |
| Remove generic | Edit | Zeile entfernen |

## Step 6: Summary

```
=== CLAUDE.md Updated ===
Applied: 5 fixes | Skipped: 2
Score: 72 → 88 (Grade: C → B+)
Lines: 145 → 118 (-27)
Token savings: ~270
```

## Hard Constraints

- **NEVER apply without a successful `mind_snapshot` (Step 0)** — Snapshot fehlgeschlagen = keine Edits, Abbruch. (Ersetzt v5.0.0 die alte Regel "NEVER apply without User-Bestätigung": Sicherheit kommt jetzt vom Netz, nicht von der Rückfrage.)
- **NEVER auto-apply DESIGN findings** — das sind Stellen, die eine Regel als "niemals anfassen" markiert; sie zu überschreiben bricht die Sperre des Users. Nur listen.
- **ALWAYS report every applied change** mit `file:line` + before→after + Snapshot-Pfad + Restore-Einzeiler.
- Bei `--ask`: Step 4d stoppt und wartet (altes Verhalten). Bei `--dry-run`: nichts ändern.
- NEVER delete information without showing what will be lost
- ALWAYS show before/after for every edit
- ALWAYS backup CLAUDE.md before first edit (cp to .claude-mind/backups/)
- ALWAYS use Edit tool (not Write) for modifications — preserves surrounding content
- Generate-Modus: ALWAYS show preview, NEVER write without confirmation
- If CLAUDE.local.md found: warn but NEVER auto-delete (deprecated is not deleted)
