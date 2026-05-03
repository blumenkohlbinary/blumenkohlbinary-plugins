---
name: mind-claudemd
description: |
  [Mind Manager] CLAUDE.md Vollverwaltung — erkennt, erstellt, auditiert, optimiert.
  Wenn keine CLAUDE.md existiert: Projekt scannen und nach Best Practices erstellen.
  Wenn vorhanden: Qualitäts-Score (0-100, A-F), veraltete/fehlende Infos erkennen,
  Duplikate mit MEMORY.md/Rules finden, Widersprüche aufdecken, dann mit User-OK fixen.

  Use when the user says "check claude.md", "create claude.md", "optimize claude.md",
  "improve claude.md", "mind claudemd", "audit claude.md", "fix claude.md",
  or "/mind-claudemd".
argument-hint: "[global]"
context: inherit
allowed-tools: Read Glob Grep Edit Write Bash Agent
---

# CLAUDE.md Vollverwaltung

Erkennen → Erstellen oder Auditieren → User-OK → Fixen.

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

### Step 4b: Dispatch context-analyzer Agent

Launch **context-analyzer** with scope=claude-md:
"Analyze all CLAUDE.md files in this project. Scope: claude-md. Report quality score, contradictions, staleness, optimization suggestions with token savings estimates."

### Step 4c: Eigene Inline-Checks (parallel zum Agent)

Während der Agent läuft, selbst prüfen:

1. **Versions-Check**: Read plugin.json/package.json → extract version. Grep CLAUDE.md für Versionsnummern. Mismatch → Finding.
2. **Pfad-Check**: Extract alle Pfade aus CLAUDE.md (backtick-wrapped, Zeilen mit `/` oder `\`). Bash: `test -e "$path"` für jeden. Tot → Finding.
3. **Git-Check** (nur wenn `.git/` existiert): `git log --oneline -10` → Gibt es Commits (feat, fix, refactor) die nicht in CLAUDE.md reflektiert sind?
4. **CLAUDE.local.md**: Wenn vorhanden → Deprecation-Warnung

### Step 4d: Ergebnisse konsolidieren + präsentieren

Agent-Ergebnisse + eigene Inline-Checks zusammenführen. Anzeigen als:

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

**STOP HERE. Warte auf User-Bestätigung.**

**Disambiguation-Regel:** Bei vagen Antworten ("ja", "ok", "update", "los") IMMER
die `safe` Variante wählen (keine Modularization, keine Datei-Restruktur). Dem
User transparent mitteilen: "Wähle `safe` (Currency only) — sage `all` wenn du
auch strukturelle Änderungen willst."

## Step 5: Fixes anwenden (nach User-OK)

### Step 5a: Pre-Edit Read (MUST)

Vor JEDEM Edit/Write Tool-Call: Read die Ziel-Datei zuerst. Auch wenn Step 4
sie schon analysiert hat — Claude's Edit-Tool benötigt einen Read im selben
Tool-Call-Kontext, sonst Crash mit `<tool_use_error>File has not been read yet`.

Beispiel:
1. Read CLAUDE.md  (für Currency-Fix)
2. Edit CLAUDE.md  (Zeile X)

Bei Modularize-Fix: zusätzlich Write der neuen Rule-Datei (kein Read nötig — neu).

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

- NEVER apply changes without User-Bestätigung (Step 4d MUST stop and wait)
- NEVER delete information without showing what will be lost
- ALWAYS show before/after for every edit
- ALWAYS backup CLAUDE.md before first edit (cp to .claude-mind/backups/)
- ALWAYS use Edit tool (not Write) for modifications — preserves surrounding content
- Generate-Modus: ALWAYS show preview, NEVER write without confirmation
- If CLAUDE.local.md found: warn but NEVER auto-delete (deprecated is not deleted)
