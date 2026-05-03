---
name: mind-files
description: |
  [Mind Manager] Projekt-Setup Vollverwaltung — erkennt Projekttyp, erstellt/prueft/verbessert alle Dateien.
  Scannt Repo fuer Tech-Stack, vergleicht Ist- mit Soll-Zustand basierend auf Projekttyp
  (Python, Node.js, C#, Docs-Only, Plugin, MCP Workspace), zeigt fehlende/verbesserbare Dateien,
  erstellt mit User-Bestaetigung.

  Use when the user says "setup project", "check project files", "mind files",
  "scaffold", "init project", "bootstrap project", "check setup",
  or "/mind-files".
argument-hint: ""
context: inherit
allowed-tools: Read Glob Grep Write Bash Agent
---

# Projekt-Setup Vollverwaltung

Projekttyp erkennen -> Soll-Zustand definieren -> Ist pruefen -> User-OK -> Erstellen/Verbessern.

## Step 1: Projekttyp erkennen

Dispatch **project-scanner** agent:
"Scan this project for tech stack, project type, build/test/lint commands, key directories, frameworks, and package manager. Report structured findings."

## Step 2: Referenzen laden

Read these reference files for templates and best practices:
- [references/templates.md](../../references/templates.md) -- 13 project type templates
- [references/claudemd-best-practices.md](../../references/claudemd-best-practices.md) -- Required sections, anti-patterns
- [references/context-file-guide.md](../../references/context-file-guide.md) -- Complete file catalog

## Step 3: Soll-Zustand dynamisch ableiten

Basierend auf dem Profil vom project-scanner, den Soll-Zustand ABLEITEN statt nachschlagen:

#### Claude-Dateien (fuer ALLE Projekttypen):
| Datei | Wann noetig | Inhalt |
|---|---|---|
| CLAUDE.md | IMMER | Projektuebersicht, Commands (wenn vorhanden), Konventionen |
| .claude/settings.json | Wenn sensible Dateien existieren (.env, credentials) | permissions.deny fuer Secrets |
| .claude/rules/*.md | Wenn Projekt gross genug (>10 Dateien in einer Sprache) | Sprach-/Domain-spezifische Rules |

#### Projekt-Dateien (abhaengig vom Profil):

Wenn Primary=code_app oder library:
-> Pruefe ob Build-System existiert (package.json, pyproject.toml, CMakeLists.txt, etc.)
-> Pruefe ob Tests existieren
-> Pruefe ob .gitignore existiert und vollstaendig ist
-> Pruefe ob Linter/Formatter konfiguriert ist

Wenn Primary=workspace oder +docs:
-> CLAUDE.md soll Ordner-Struktur beschreiben (was liegt wo, was ist der Zweck jedes Ordners)
-> Keine Build-Commands noetig
-> Stattdessen: Navigations-Hilfe (welcher Ordner fuer was)

Wenn Primary=scripts:
-> CLAUDE.md mit Script-Uebersicht (was macht welches Script)
-> Keine package.json/pyproject.toml noetig
-> Pruefe ob Scripts ausfuehrbar sind (chmod +x) und Shebangs haben

Wenn Primary=data:
-> CLAUDE.md mit Datenformat-Beschreibung (welche Felder, welche Formate)
-> Pruefe ob .gitignore grosse Datenfiles ausschliesst

Wenn Primary=config:
-> CLAUDE.md mit Konfigurations-Uebersicht
-> Pruefe ob Secrets in Dateien sind

Wenn Primary=plugin:
-> Pruefe plugin.json Vollstaendigkeit
-> Pruefe ob agents/, skills/, hooks/ existieren
-> CLAUDE.md soll Plugin-Architektur beschreiben

Wenn Primary=mcp:
-> Pruefe .mcp.json Validitaet
-> CLAUDE.md mit MCP-Server-Uebersicht

Wenn +hybrid:
-> Fuer jedes erkannte Sub-Profil die obigen Regeln anwenden
-> CLAUDE.md soll die verschiedenen Teile klar trennen

### Claude-Specific Files (check for all types):

| File | Purpose | Check |
|---|---|---|
| `CLAUDE.md` | Project instructions | Exists? Has build commands? Has architecture? |
| `.claude/settings.json` | Permissions | Exists? Has `permissions.deny` for sensitive patterns? |
| `.claude/rules/*.md` | Conditional rules | Any rules exist? Are they well-structured? |
| `.claudeignore` | Token savings | Exists? Covers node_modules, dist, build, etc.? |
| `.mcp.json` | MCP server config | Only for MCP-enabled projects |

### Security Best-Practice Checks:

| Check | What | Where |
|---|---|---|
| Deny .env access | `permissions.deny` includes `.env*` patterns | .claude/settings.json |
| Deny credentials | `permissions.deny` includes credential file patterns | .claude/settings.json |
| Ignore large dirs | node_modules, dist, .git, __pycache__ etc. | .claudeignore |

## Step 4: Ist-Zustand pruefen (Gap-Analyse)

For each file in the Soll-Zustand:

**If MISSING:** Add to "Create" list with:
- What would be created (preview content)
- Why it's needed
- Priority (CRITICAL / RECOMMENDED / NICE-TO-HAVE)

**If EXISTS:** Run quick best-practice check:
- CLAUDE.md: Has build commands? Architecture section? Under 200 lines?
- settings.json: Has `permissions.deny`? Denies `.env*`?
- .gitignore: Covers build artifacts for this project type?
- .claudeignore: Covers large directories?

Present findings:

```
=== Project Setup Report ===

Profile: code_app +docs +tests
Tech Stack: TypeScript, React, Vitest
Language: TypeScript (34 .ts files)

### Missing Files (3)
[1] CRITICAL    .claude/settings.json — No permission restrictions configured
    -> Will create with deny patterns for .env, credentials, secrets
[2] RECOMMENDED .claudeignore — No token savings configured
    -> Will create ignoring node_modules/, dist/, coverage/, .next/
[3] NICE-TO-HAVE .claude/rules/testing.md — No testing conventions documented
    -> Will create with globs: **/*.test.ts, **/*.spec.ts

### Existing Files (3)
[4] OK          CLAUDE.md — 85 lines, has build commands, architecture section
[5] IMPROVE     .gitignore — Missing: coverage/, .env.local
[6] OK          package.json — Valid, has scripts

### Not Needed for this Project Type
- (none — code_app benefits from all file types)

### Summary
Create: 3 files | Improve: 1 file | OK: 2 files

Proceed? [Yes / Select / Skip]
```

Example for non-code project:

```
=== Project Setup Report ===

Profile: workspace +docs
Content: 23 .md files, 5 .txt files, 3 folders (Wissen/, Beispiele/, recherche/)
Language: Markdown (primary), keine Code-Sprache

### Missing Files (1)
[1] RECOMMENDED  CLAUDE.md — Projekt hat keine Uebersicht
    -> Will create with:
       - Ordner-Beschreibung (Wissen/ = Recherche-Dateien, Beispiele/ = Referenz-Plugins)
       - Zweck des Projekts
       - Navigation: Welcher Ordner fuer was

### Existing Files (0)

### Not Needed for this Project Type
- .gitignore (kein Build-Output)
- .claude/settings.json (keine sensiblen Dateien)
- Test-Infrastruktur (kein Code zum Testen)

### Summary
Create: 1 file | Improve: 0 files | OK: 0 files

Proceed? [Yes / Select / Skip]
```

**STOP HERE. Warte auf User-Bestaetigung.**

## Step 5: Dateien erstellen/verbessern (nach User-OK)

For each confirmed action:

### Creating new files:

**CLAUDE.md** (if missing):
- Use template from references/templates.md matching the detected project type
- Fill with scan data (tech stack, build commands, directory structure)
- Target: 40-80 lines, max 100
- MUST pass generation checklist:
  - [ ] Has build/test commands section?
  - [ ] Has architecture/structure section?
  - [ ] Has conventions section?
  - [ ] No generic advice?
  - [ ] Under 100 lines?

**.claude/settings.json** (if missing):
```json
{
  "permissions": {
    "deny": [
      "Edit .env*",
      "Edit *credentials*",
      "Edit *secret*",
      "Edit *.pem",
      "Edit *.key"
    ]
  }
}
```

**.claudeignore** (if missing):
- Auto-detect which directories exist using `test -d`:
  node_modules/, dist/, build/, .next/, __pycache__/, target/,
  coverage/, .claude-mind/backups/, .claude-mind/sessions/
- Only include directories that actually exist

**Rule files** (if missing):
- Create with appropriate `globs:` pattern
- Use MUST/NEVER/ALWAYS format
- Keep under 30 lines

### Improving existing files:

**Pre-Edit Read (MUST):** Vor JEDEM Edit existierender Datei: Read tool zuerst
aufrufen. Auch wenn Step 4 Best-Practice-Checks gemacht hat — Claude's Edit-Tool
benoetigt einen Read im selben Tool-Call-Kontext, sonst Crash mit
`<tool_use_error>File has not been read yet`. (Fuer neue Files mit Write ist
KEIN vorheriger Read noetig.)

| Improvement | Tool | Aktion |
|---|---|---|
| Add missing .gitignore entries | Edit | Append missing patterns |
| Add permissions.deny entries | Edit | Add to existing settings.json |
| Add missing CLAUDE.md section | Edit | Insert section at appropriate position |

## Step 6: Summary

```
=== Project Setup Complete ===
Created: 3 files (settings.json, .claudeignore, testing.md)
Improved: 1 file (.gitignore: +2 patterns)
Already OK: 2 files
Project readiness: Good (all critical files present)
```

## Hard Constraints

- NEVER overwrite existing files without user confirmation
- NEVER create files without showing preview content first
- ALWAYS show what would be created/changed before doing it
- ALWAYS use Write for new files, Edit for modifications
- ALWAYS check if directories exist before creating files in them (mkdir -p if needed)
- For CLAUDE.md generation: ALWAYS use project-scanner results, NEVER guess
- For settings.json: ALWAYS include .env* in deny patterns (security baseline)
- NEVER include secrets, API keys, or credentials in any generated file
