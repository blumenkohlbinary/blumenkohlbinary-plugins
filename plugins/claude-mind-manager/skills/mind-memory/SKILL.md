---
name: mind-memory
description: |
  [Mind Manager] MEMORY.md Vollverwaltung — lokalisiert, auditiert, optimiert, bereinigt.
  Findet MEMORY.md + Topic-Files, prueft auf Duplikate, veraltete Eintraege, Budget-Ueberschreitungen,
  fehlplatzierte Inhalte (Instructions die in CLAUDE.md gehoeren), semantische Duplikate.
  v5.0.0: wendet Fixes AUTONOM an (deduplizieren, kompaktieren, in Topic-Files auslagern,
  stale Eintraege entfernen) — Snapshot vorher, Bericht danach. '--ask' fragt wie frueher,
  '--dry-run' aendert nichts.

  Use when the user says "check memory", "optimize memory", "mind memory",
  "clean memory", "audit memory", "fix memory", "memory too long",
  or "/mind-memory".
argument-hint: ""
context: inherit
allowed-tools: Read Glob Grep Edit Write Bash Agent
---

# MEMORY.md Vollverwaltung

Lokalisieren -> Auditieren -> **autonom anwenden** (bzw. Freigabe bei `--ask`) -> Bericht.

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
  SNAPSHOT=$(mind_snapshot "${CLAUDE_PROJECT_DIR:-$(pwd)}" "pre-memory") || {
    echo "ABBRUCH: Snapshot fehlgeschlagen — es wird NICHTS editiert." >&2; exit 1; }
  echo "Snapshot: $SNAPSHOT"
fi
```

| Modus | Aufruf | Verhalten |
|---|---|---|
| **autonom (Default)** | `/mind-memory` | Befunde werden angewendet, danach Bericht |
| **interaktiv** | `/mind-memory --ask` | Report → Freigabe → anwenden (Verhalten vor v5.0.0) |
| **Probelauf** | `/mind-memory --dry-run` | zeigt alles, aendert nichts |

**Bei Snapshot-Fehlschlag wird NICHT editiert.** **DESIGN-Befunde nie automatisch.**
**Geloeschter Inhalt** wird im Bericht woertlich ausgewiesen (`Entfernt: <zeile>`).

## Step 1: MEMORY.md lokalisieren

Compute the project hash for the memory path:
1. Get the absolute project path (CWD)
2. Convert to the hash format: replace `/`, `\`, `:`, and spaces with hyphens, strip leading hyphens
3. Read `~/.claude/projects/<hash>/memory/MEMORY.md`
4. Also glob topic files: `~/.claude/projects/<hash>/memory/*.md`

```bash
# Hash + Memory-Verzeichnis (v3.2.2: zentralisiert in lib.sh)
# Korrektes Windows-Slug-Mapping via cygpath (siehe lib.sh hash_project_dir)
# Beispiel: C:\CD\KOHLEKTIV\Plugin - Entwicklung -> C--CD-KOHLEKTIV-Plugin---Entwicklung
# M3-Fix: $CLAUDE_PLUGIN_ROOT Guard
if [ -z "$CLAUDE_PLUGIN_ROOT" ] || [ ! -f "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" ]; then
  echo "ERROR: \$CLAUDE_PLUGIN_ROOT nicht gesetzt oder lib.sh nicht gefunden" >&2
  exit 1
fi
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
MEMORY_DIR=$(get_memory_dir)
```

**Wenn KEINE MEMORY.md gefunden:**
- Inform user: "No MEMORY.md found. Claude creates this file automatically when you use /memory or the remember command. The plugin cannot create it — only Claude's internal system can."
- STOP here.

**Wenn gefunden -> weiter zu Step 2.**

## Step 2: Referenzen laden

Read these reference files for quality criteria and budget data:
- [references/quality-criteria.md](../../references/quality-criteria.md) -- Optimization patterns + anti-patterns
- [references/budget-thresholds.md](../../references/budget-thresholds.md) -- SFEIR compliance data, line thresholds

## Step 3: Dispatch context-analyzer Agent (directive, v3.3.2)

**Identitaet:** Dieser Skill dispatcht IMMER context-analyzer fuer den semantischen Teil
(exakte + semantische Duplikate, fehlplatzierte Inhalte). Dafuer gibt es **keinen
Inline-Ersatz** — die deterministischen Inline-Checks (Step 4) decken nur Budget/
Cross-File-Exakt-Duplikate/Stale-Pfade ab, NICHT die semantische Deduplizierung.
Der Agent ist der einzige Weg dorthin.

Launch **context-analyzer** with scope=memory:
"Analyze all memory files in this project. Scope: memory. Report duplicates (exact and semantic), stale entries, budget issues, misplaced content, and optimization suggestions."

## Step 4: Deterministische Inline-Checks (ergaenzend, NICHT statt Agent)

While the agent runs, perform these checks directly:

1. **Budget-Check**: Count lines in MEMORY.md.
   - >200 lines = CRITICAL: "Truncation imminent — Claude truncates MEMORY.md at ~200 lines"
   - >150 lines = WARNING: "Approaching truncation limit"
   - Also count topic files and their line counts

2. **Misplaced Content**: Grep MEMORY.md for patterns that belong in CLAUDE.md:
   - Lines starting with "ALWAYS", "NEVER", "MUST" -> instructions, not memory
   - Lines containing "when writing", "when coding", "convention" -> conventions
   - Lines with build/test commands -> belong in CLAUDE.md Commands section

3. **Semantic Duplicates**: Look for entries conveying the same info differently:
   - Same tool/version mentioned multiple times (e.g., "Node 20" vs "Node.js version is 20.18.3")
   - Same path referenced in different formats
   - Same decision/learning recorded with different wording

4. **Cross-File Duplicates**: Grep for key terms from MEMORY.md across CLAUDE.md and rules:
   - Exact line matches
   - Version numbers appearing in both MEMORY.md and CLAUDE.md
   - Build commands duplicated across files

5. **Stale Entries**: Check for entries referencing:
   - File paths that no longer exist (Bash `test -e`)
   - Version numbers that don't match current package.json/plugin.json
   - Features/tools that are no longer in the project

## Step 5: Ergebnisse konsolidieren + praesentieren

Merge agent results with inline checks. Display as:

**PFLICHT-Self-Check-Block am Anfang (NEU v3.3.1):**

```
=== MEMORY.md Audit Report v3.3.2 — Self-Check ===
[Step 3 context-analyzer] Agent dispatched: <N> Findings (Duplicates: <D>, Stale: <S>, Misplaced: <M>)
  Beleg: context-analyzer Tool-Call #<N>
[Step 4 Inline-Checks] Budget: <X>/200 lines, Cross-File-Duplikate: <Y>, Stale-Pfade: <Z>
  Beleg: Bash-Tool-Call #<N>
```

Fehlt der Self-Check-Block oder enthaelt `(SKIPPED)`: User darf zurueckweisen.

```
=== MEMORY.md Audit Report ===

File: ~/.claude/projects/<hash>/memory/MEMORY.md
Lines: 178/200 (WARNING: approaching truncation)
Topic Files: 2 (api-notes.md: 45 lines, debug-tips.md: 23 lines)

Findings (7):
[1] CRITICAL  MEMORY.md:178  Budget 178/200 — truncation at ~200 lines
[2] WARNING   MEMORY.md:12   Misplaced: "ALWAYS use strict mode" -> belongs in CLAUDE.md
[3] WARNING   MEMORY.md:45   Duplicate of CLAUDE.md:23 (same build command)
[4] WARNING   MEMORY.md:67   Semantic duplicate: lines 67+89 both describe Node version
[5] INFO      MEMORY.md:34   Stale: path "src/old-module/" does not exist
[6] INFO      MEMORY.md:90   Could be topic file: 15-line section about API patterns
[7] INFO      MEMORY.md:5    Verbose: multi-sentence entry could be 1 line

Suggested actions:
[A] Move 2 instruction lines to CLAUDE.md
[B] Remove duplicate with CLAUDE.md (keep in CLAUDE.md)
[C] Merge semantic duplicates (lines 67+89 -> 1 line)
[D] Remove stale path entry
[E] Offload API section to topic file api-patterns.md
[F] Compress verbose entry

Projected: 178 -> 145 lines (-33), well within budget

Apply all? [Yes / Select / Skip]
```

**Nur bei `AUTO_MODE=no` (`--ask`): STOP HERE, warte auf User-Bestaetigung.**
**Bei `AUTO_MODE=yes` (Default): NICHT stoppen** — Fixes anwenden (außer DESIGN), danach
Step 7 mit Angewendet-Block. Bei `DRY_RUN=yes`: nur zeigen. Geloeschte Zeilen woertlich melden.

## Step 6: Fixes anwenden (nach User-OK)

### Step 6a: Pre-Edit Read (MUST, praezisiert v3.2.2)

**1× Read der Ziel-Datei VOR dem ersten Edit** — reicht fuer N sequentielle
Edits (Edit-Tool garantiert "file state is current — no need to Read it back").
**Re-Read nur** wenn anderes Tool die Datei zwischendurch modifiziert.

Auch wenn der context-analyzer-Agent in Step 3 die Datei gelesen hat: **das
zaehlt nicht** — Read muss im SELBEN Tool-Call-Kontext wie Edit erfolgen.

Reihenfolge pro Datei: 1× Read → beliebig viele Edits → (ggf. Re-Read nach
externer Modifikation).

Write fuer NEUE Topic-Files: kein Read noetig (neue Datei).

### Step 6b: Fixes anwenden

For each confirmed fix:
| Fix-Typ | Tool | Aktion |
|---|---|---|
| Move to CLAUDE.md | Edit (both files) | Remove from MEMORY.md, add to CLAUDE.md appropriate section |
| Remove cross-file duplicate | Edit | Remove from MEMORY.md (keep in CLAUDE.md) |
| Merge semantic duplicates | Edit | Replace both lines with single concise line |
| Remove stale entry | Edit | Remove line(s) referencing dead paths/versions |
| Offload to topic file | Write + Edit | Write new topic file, remove section from MEMORY.md |
| Compress verbose | Edit | Replace multi-sentence with concise bullet |

## Step 7: Summary

```
=== MEMORY.md Updated ===
Applied: 5 fixes | Skipped: 2
Lines: 178 -> 145 (-33)
Budget status: OK (145/200)
Topic files: 3 (was 2, created api-patterns.md)
```

## Hard Constraints

- NEVER delete entries without showing what will be lost
- **NEVER apply without a successful `mind_snapshot` (Step 0)** — Snapshot fehlgeschlagen = keine Edits, Abbruch. (Ersetzt v5.0.0 die alte Regel "NEVER apply without User-Bestaetigung".)
- **NEVER auto-apply DESIGN findings** — nur listen.
- **ALWAYS report every applied change** mit `file:line` + before→after; **geloeschte Zeilen woertlich** (`Entfernt: <zeile>`) + Snapshot-Pfad + Restore-Einzeiler.
- Bei `--ask`: Step 5 stoppt und wartet (altes Verhalten). Bei `--dry-run`: nichts aendern.
- ALWAYS backup MEMORY.md before first edit (cp to .claude-mind/backups/)
- ALWAYS use Edit tool (not Write) for modifications — preserves surrounding content
- ALWAYS show before/after line counts
- If MEMORY.md does not exist: inform user and STOP — do NOT attempt to create it
- Misplaced content: MOVE (not just delete) — show destination file
