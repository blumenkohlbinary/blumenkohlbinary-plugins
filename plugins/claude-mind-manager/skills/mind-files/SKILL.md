---
name: mind-files
description: |
  [Mind Manager] Projekt-Setup Vollverwaltung — erkennt Projekttyp, erstellt/prueft/verbessert alle Dateien.
  Scannt Repo fuer Tech-Stack, vergleicht Ist- mit Soll-Zustand basierend auf Projekttyp
  (Python, Node.js, C#, Docs-Only, Plugin, MCP Workspace), zeigt fehlende/verbesserbare Dateien,
  erstellt AUTONOM (v5.0.0; Snapshot vorher, '--ask' fragt wie frueher). Bestehende Dateien
  werden nie ueberschrieben.

  Use when the user says "setup project", "check project files", "mind files",
  "scaffold", "init project", "bootstrap project", "check setup",
  or "/mind-files".
argument-hint: ""
context: inherit
allowed-tools: Read Glob Grep Write Bash Agent
---

# Projekt-Setup Vollverwaltung

Projekttyp erkennen -> Soll-Zustand definieren -> Ist pruefen -> User-OK -> Erstellen/Verbessern.

## Step 0: Modus + Snapshot (PFLICHT, NEU v5.0.0)

**Autonom ist der Standard.** Fehlende Dateien werden erstellt, verbesserbare verbessert.

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

# Hook-Gesundheit (NEU v5.2.1) — laeuft in JEDEM Modus, auch im Probelauf und in der Kette.
# Kein Abbruchgrund; aber ein toter Hook MUSS im Bericht stehen, sonst haelt der naechste
# Befundlauf ein totes Netz fuer ein gespanntes (genau so entstand die Befundliste 2026-08-16).
if [ -n "$CLAUDE_PLUGIN_ROOT" ] && [ -f "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" ]; then
  source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
  mind_hook_health "${CLAUDE_PROJECT_DIR:-$(pwd)}" || HOOK_WARN="ja"
fi

if [ "$DRY_RUN" = "no" ] && [ "$CHAIN" = "no" ]; then
  [ -z "$CLAUDE_PLUGIN_ROOT" ] && { echo "ERROR: \$CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 1; }
  source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
  SNAPSHOT=$(mind_snapshot "${CLAUDE_PROJECT_DIR:-$(pwd)}" "pre-files") || {
    echo "ABBRUCH: Snapshot fehlgeschlagen — es wird NICHTS editiert." >&2; exit 1; }
  echo "Snapshot: $SNAPSHOT"
fi
```

`--ask` = Report + Freigabe (Verhalten vor v5.0.0) · `--dry-run` = nichts aendern.

**DESIGN-Befunde werden NIE automatisch angewendet** — vor einem Edit pruefen, ob eine Rule
die Stelle als "niemals anfassen"/"NIEMALS <datei>"/"by design" markiert; dann nur listen.

**Zwei Dinge bleiben AUCH autonom rueckfragepflichtig** (kein Widerspruch zur Autonomie —
beide betreffen Fremd-/Bestandsdaten, nicht Befunde):
- **Ueberschreiben existierender Dateien** (Overwrite-Guards in Step 5/5b/5c): weiter SKIP + melden.
- **Tool-Bundles** (Backup/Release-Hygiene/Versioning-Pack): installieren veraendert die
  Projekt-Struktur dauerhaft → bleibt ein Angebot, wird im Bericht als offener Punkt gelistet.

## Step 1: Projekttyp erkennen + Setup-Bereiche scannen (project-scanner)

Dispatch **project-scanner** agent (ein Dispatch — er hat Read/Glob/Grep/Bash und
deckt alle Setup-Bereiche in einem Durchgang ab):

```
"Scan this project for tech stack, project type, build/test/lint commands, key
directories, frameworks, and package manager. Report structured findings.

Zusaetzlich (PFLICHT, via `test -e`/Glob konkret pruefen — Exist/Missing pro Punkt):
- BUILD:   Build-System vorhanden (package.json/pyproject.toml/*.csproj/CMakeLists...)?
           Build-Commands dokumentiert? Linter/Formatter konfiguriert (.editorconfig,
           eslint, prettier, ruff...)?
- BACKUP:  Projekt-Backup-System schon da (`tools/backup_tools.py` o.ae.)?
           `.claude-mind/backups/` Dir? `.backuprc`?
- TESTS:   Test-Infra (pytest/jest/xunit/...) + `tests/`-Dir? CI-Config (.github/workflows)?
- SECRETS: `.env`/credential-Files? `.gitignore`-Coverage ok? `.claudeignore`?
           `.claude/settings.json` mit `permissions.deny` fuer `.env*`/secrets?
- RELEASE: Git-Repo (`.git` vorhanden)? Versionierungs-Signal (`build.py` / `*.spec` /
           `pyproject.toml` mit `[project] version` / `VERSION`-Datei / `package.json` version)?
           **Python vorhanden** (`python`/`python3` im PATH ODER `.venv/`)? — noetig fuers
           Gating des Versioning-Packs (Step 5c: NUR Python-Release-App).
- DOCS:    `docs/`-Verzeichnis vorhanden? **Anzahl `.md`-Dateien** ausserhalb von
           vendor-/Beispiel-Ordnern (`node_modules`, `vendor`, `Beispiele`, `.venv`) —
           als ZAHL zurueckgeben, nicht als "viele". Python vorhanden (s. RELEASE)?
           — noetig fuers Gating des Doku-Gates (Step 5d).

Gib die 6 Bereiche als eigene Exist-vs-Missing-Sektion zurueck."
```

> **v3.3.3 (Weg B):** Frueher liefen hier 4 zusaetzliche `context-analyzer`-Agents
> (build/backup/tests/secrets). Sie pruefen nur Datei-Existenz (`test -e`) — der
> project-scanner (hat Bash) erledigt das im selben Durchgang. Die 4 Agents waren
> redundant und wurden **entfernt** (statt einen ueberspringbaren Redundanz-Schritt
> zu erzwingen). Kein Verlust an Abdeckung — die 4 Bereiche stehen jetzt im
> project-scanner-Auftrag oben.

## Step 2: Referenzen laden

Read these reference files for templates and best practices:
- [references/templates.md](../../references/templates.md) -- 13 project type templates
- [references/claudemd-best-practices.md](../../references/claudemd-best-practices.md) -- Required sections, anti-patterns
- [references/context-file-guide.md](../../references/context-file-guide.md) -- Complete file catalog
- [references/backup-system-templates/README.md](../../references/backup-system-templates/README.md) -- Backup-System Templates (NEU v3.3.0)

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

**Nur bei `AUTO_MODE=no` (`--ask`): STOP HERE, warte auf User-Bestaetigung.**
**Bei `AUTO_MODE=yes` (Default): NICHT stoppen** — fehlende Dateien erstellen, verbesserbare
verbessern, danach Step 6 mit Angewendet-Block. **Ausgenommen bleiben** (Step 0): Ueberschreiben
existierender Dateien + Tool-Bundle-Installation → als offene Punkte listen.
Bei `DRY_RUN=yes`: nur zeigen.

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

**Pre-Edit Read (MUST, praezisiert v3.2.2):** **1× Read der Ziel-Datei VOR dem
ersten Edit** — reicht fuer N sequentielle Edits (Edit-Tool garantiert
"file state is current"). **Re-Read nur** wenn anderes Tool die Datei zwischendurch
modifiziert. Step 4 Best-Practice-Checks zaehlen nicht — Read muss im SELBEN
Tool-Call-Kontext wie Edit erfolgen.

Fuer NEUE Files mit Write ist KEIN vorheriger Read noetig.

| Improvement | Tool | Aktion |
|---|---|---|
| Add missing .gitignore entries | Edit | Append missing patterns |
| Add permissions.deny entries | Edit | Add to existing settings.json |
| Add missing CLAUDE.md section | Edit | Insert section at appropriate position |

### Backup-System installieren (NEU v3.3.0)

Wenn der project-scanner BACKUP als `MISSING` meldet (kein `tools/backup_tools.py`)
UND User Backup-Vorschlag bestaetigt: Backup-System ins Projekt installieren.

**Vorgehen:**

```bash
# 1. Tools-Dir anlegen
mkdir -p "$CLAUDE_PROJECT_DIR/tools" "$CLAUDE_PROJECT_DIR/docs" "$CLAUDE_PROJECT_DIR/.claude-mind/backups"

# 2. Templates 1:1 ins Projekt schreiben (Read aus references/, Write ins Projekt)
# 3 Python-Files + 1 Doku-File:
# (update_changelog.py gehoert NICHT hierher — es ist Release-Hygiene, nicht Backup;
#  wird im Release-Hygiene-Bundle installiert, siehe Step 5b.)
# Overwrite-Guard PFLICHT (Hard Constraint "NEVER overwrite without confirmation"):
# existiert eine Datei schon -> SKIP + User fragen, NIE blind ueberschreiben.
for FILE in tools/backup_tools.py tools/rollback.py tools/mutation_guard.py docs/BACKUP_USAGE.md; do
  if [ -f "$CLAUDE_PROJECT_DIR/$FILE" ]; then
    echo "SKIP: $FILE existiert bereits (User fragen ob ueberschreiben)"
  else
    cp "$CLAUDE_PLUGIN_ROOT/references/backup-system-templates/$FILE" "$CLAUDE_PROJECT_DIR/$FILE"
  fi
done

# 3. .backupignore generieren (Standard-Defaults)
cat > "$CLAUDE_PROJECT_DIR/.backupignore" << 'EOF'
# .backupignore - Files die NICHT in Backups landen
# Format aehnlich .gitignore
node_modules/
__pycache__/
.venv/
.git/
dist/
build/
*.pyc
.DS_Store
.pytest_cache/
.coverage
EOF

# 4. .backuprc generieren — projekt-spezifisch basierend auf project-scanner
# (siehe Detection-Tabelle unten)
```

**Test-Cmd-Detection fuer `.backuprc`** (project-scanner-Output nutzen):

| project-scanner-Detection | `BACKUP_TEST_CMD` in `.backuprc` |
|---|---|
| `pyproject.toml` + `tests/` + pytest in deps | `pytest -q` |
| `package.json` mit `"test": "jest"` im scripts | `npm test` |
| `package.json` mit `"test": "vitest"` im scripts | `npx vitest run` |
| `package.json` mit anderem `"test"` script | `npm test` |
| `Cargo.toml` | `cargo test` |
| `go.mod` | `go test ./...` |
| `*.csproj` / `*.sln` (C# / .NET) | `dotnet test` |
| `pom.xml` (Maven) | `mvn test` |
| `build.gradle` / `build.gradle.kts` | `gradle test` |
| Sonst (kein erkanntes Build-System) | `""` (leer = skip Test-Gate, sicher) |

`.backuprc` Template:
```bash
# .backuprc - Backup-System-Konfiguration
# Auto-generiert von claude-mind-manager v3.3.0

# Test-Cmd das vor riskanten Operationen laeuft (leer = skip)
export BACKUP_TEST_CMD="<aus Detection oben>"

# Backup-Target (default OK, hier expliziert)
export BACKUP_TARGET=".claude-mind/backups"

# Test-Timeout in Sekunden (default 300 = 5 min)
export BACKUP_TEST_TIMEOUT=300
```

**5. Companion-Rule schreiben (PFLICHT — "No Dead Tools"):**

Ohne diese Rule liegen die `tools/*.py` tot im Ordner — Claude weiss nicht WANN er sie
aufrufen soll (`BACKUP_USAGE.md` ist Menschen-Doku, wird nicht auto-geladen). Die Rule
mit `globs:`-Frontmatter laedt automatisch, sobald Claude eine passende Datei anfasst,
und macht das Backup-Tool **erreichbar**.

```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.claude/rules"
# Overwrite-Guard: existiert die Rule schon -> NICHT ueberschreiben (ASK, default Skip)
if [ -f "$CLAUDE_PROJECT_DIR/.claude/rules/backup-usage.md" ]; then
  echo "SKIP: .claude/rules/backup-usage.md existiert bereits (User fragen ob ueberschreiben)"
else
  cp "$CLAUDE_PLUGIN_ROOT/references/rule-templates/backup-usage.md" \
     "$CLAUDE_PROJECT_DIR/.claude/rules/backup-usage.md"
fi
```

Dann **1 Pointer-Zeile** in `CLAUDE.md` (via Edit, unter einem `## Tooling`/`## Backup`-Abschnitt
oder anlegen): `- Backup-System: \`tools/backup_tools.py\` + \`rollback.py\` — Nutzung siehe \`.claude/rules/backup-usage.md\``

**Edge-Cases:**
- **Existierende `tools/`-Files:** Skill checkt `test -f tools/backup_tools.py` — bei Treffer ASK "Existierende Files ueberschreiben? [Yes/Select/Skip]". Default Skip.
- **Projekt ohne Python:** Installation laeuft, aber WARN: *"Python nicht gefunden. Backup-System installiert aber NICHT lauffaehig bis Python installiert ist."*
- **Bestehende `backup_tools.py` mit anderem `__version__`:** ASK "Auf v.X updaten?". Default Skip.

**User-Output nach Installation:**
```
[OK] Backup-System installiert in $CLAUDE_PROJECT_DIR/tools/
  3 Python-Files + 1 Doku + .backupignore + .backuprc
  + .claude/rules/backup-usage.md  (Companion-Rule — macht die Tools erreichbar)
  + CLAUDE.md Pointer-Zeile

Naechste Schritte:
  source .backuprc                                       # Env-Vars laden
  python tools/backup_tools.py --help                    # CLI-Hilfe
  python tools/rollback.py list                          # Snapshots listen
  python tools/backup_tools.py gfs .claude-mind/backups  # GFS-Retention-Plan (dry-run)

Doku: docs/BACKUP_USAGE.md
```

### Step 5b: Release-Hygiene-Bundle installieren (NEU v4.0 — jedes Git-Projekt)

**Wann:** Projekt ist ein Git-Repo (`test -d .git`) UND User bestaetigt den Vorschlag.
Rule-only-Baseline fuer Commit-/Changelog-Disziplin — kein Sprach-Gate, funktioniert fuer
Node/C#/Python/etc. (Bump laeuft ueber die native Toolchain bzw. das Versioning-Pack unten).

**No-Dead-Tools:** `update_changelog.py` ist ein *Tool* -> es wird NUR mit seiner Companion-Rule
installiert, nie allein.

```bash
if [ -d "$CLAUDE_PROJECT_DIR/.git" ]; then
  mkdir -p "$CLAUDE_PROJECT_DIR/tools" "$CLAUDE_PROJECT_DIR/.claude/rules"

  # update_changelog.py ist ein PYTHON-Tool -> ohne Interpreter waere es ein totes Tool.
  # Python-Detection; fehlt Python -> WARN (analog Backup-Bundle), Install laeuft trotzdem.
  if ! (python --version >/dev/null 2>&1 || python3 --version >/dev/null 2>&1); then
    echo "WARN: Python nicht gefunden. update_changelog.py installiert aber NICHT lauffaehig"
    echo "      bis Python installiert ist (die Conventional-Commit-Regeln gelten trotzdem)."
  fi

  # 1. Changelog-Engine (git-basiert) — gehoert hierher, NICHT zum Backup-Bundle. Overwrite-Guard.
  if [ -f "$CLAUDE_PROJECT_DIR/tools/update_changelog.py" ]; then
    echo "SKIP: tools/update_changelog.py existiert bereits (User fragen ob ueberschreiben)"
  else
    cp "$CLAUDE_PLUGIN_ROOT/references/backup-system-templates/tools/update_changelog.py" \
       "$CLAUDE_PROJECT_DIR/tools/update_changelog.py"
  fi

  # 2. Companion-Rule (Overwrite-Guard: nie ueberschreiben, ASK default Skip)
  if [ -f "$CLAUDE_PROJECT_DIR/.claude/rules/release-hygiene.md" ]; then
    echo "SKIP: .claude/rules/release-hygiene.md existiert bereits (User fragen)"
  else
    cp "$CLAUDE_PLUGIN_ROOT/references/rule-templates/release-hygiene.md" \
       "$CLAUDE_PROJECT_DIR/.claude/rules/release-hygiene.md"
  fi
fi
```

Dann **1 Pointer-Zeile** in `CLAUDE.md`: `- Release-Hygiene: Conventional Commits + \`python tools/update_changelog.py\` — siehe \`.claude/rules/release-hygiene.md\``

### Step 5c: Versioning-Pack installieren (NEU v4.0 — NUR Python-Release-App)

**Gating (alle drei Bedingungen aus dem project-scanner-Report, sonst NICHT anbieten):**
1. **Python vorhanden** (project-scanner meldet `python`/`python3`/`.venv`), UND
2. **Release-produzierende App** — Primary `code_app` (NICHT `library`/`workspace`/
   `scripts`/`data`/`config`/`plugin`/`mcp`). Eine PyInstaller-GUI-App faellt unter
   `code_app` (Build-System + ausfuehrbarer Code) — die project-scanner-Taxonomie kennt
   kein separates `desktop_app`. UND
3. **Build/Version-Signal** — `build.py` ODER `*.spec` ODER `pyproject.toml` (mit oder
   ohne `[project] version`) ODER eine `VERSION`-Datei. (version.py bedient VERSION,
   pyproject, package.json und *.csproj — daher hier breit.)

**Immer detect-and-OFFER, nie erzwungen.** Fehlt Python -> Pack GAR NICHT anbieten (sonst
totes Tool — genau der Bug den v4.0 killt). User bestaetigt ("notwendig").

**Companion-Rule schreiben ist PFLICHT** (No-Dead-Tools, wie Step 5) — version.py wird NIE
ohne `release-build.md` installiert:

```bash
# nur ausfuehren wenn Gating erfuellt UND User bestaetigt
mkdir -p "$CLAUDE_PROJECT_DIR/tools" "$CLAUDE_PROJECT_DIR/.claude/rules"

# 1. version.py (stdlib-only, kein PyInstaller-Teil)
if [ -f "$CLAUDE_PROJECT_DIR/tools/version.py" ]; then
  echo "SKIP: tools/version.py existiert bereits (User fragen ob ueberschreiben)"
else
  cp "$CLAUDE_PLUGIN_ROOT/references/release-templates/version.py" \
     "$CLAUDE_PROJECT_DIR/tools/version.py"
fi

# 2. Companion-Rule release-build.md (PFLICHT, Overwrite-Guard)
if [ -f "$CLAUDE_PROJECT_DIR/.claude/rules/release-build.md" ]; then
  echo "SKIP: .claude/rules/release-build.md existiert bereits (User fragen)"
else
  cp "$CLAUDE_PLUGIN_ROOT/references/rule-templates/release-build.md" \
     "$CLAUDE_PROJECT_DIR/.claude/rules/release-build.md"
fi
```

Dann **1 Pointer-Zeile** in `CLAUDE.md`: `- Versionierung: \`python tools/version.py show|bump|release\` — siehe \`.claude/rules/release-build.md\``

**Changelog-Kopplung (ehrlich):** `version.py release --changelog` ruft `tools/update_changelog.py`
auf — das liefert das Release-Hygiene-Bundle (Step 5b), das aber ein **Git-Repo** braucht
(der Changelog wird aus Git-Tags generiert). Daher **NICHT** in 5c mit-installieren (in einem
Nicht-Git-Repo waere update_changelog.py selbst ein totes Tool). Zwei Faelle:
- **Git-Repo:** Step 5b lief bereits (gleiche Setup-Runde) -> `--changelog` funktioniert.
- **Kein Git-Repo:** `version.py release` ohne `--changelog` nutzen. Wird `--changelog` doch
  gesetzt und das Tool fehlt, **degradiert version.py sauber**: WARN "update_changelog.py nicht
  gefunden - Changelog uebersprungen", der Bump/Tag laeuft normal durch (kein Abbruch).

### Step 5d: Doku-Gate installieren (NEU v5.3.0 — Projekte mit nennenswerter Doku)

**Wozu:** `coverage_gate.py` beantwortet die Frage „ist beim Uebertragen wirklich alles
angekommen?" **messend statt schaetzend** — Quelldateien rein, Zieldokument rein, belegte
Pruefpunkte raus. Relevant, sobald Wissen aus mehreren Dateien in ein Dokument wandert
(Referenzen -> Leitfaden, Recherche -> Notiz, Rohmaterial -> Doku).

**Gating (alle Bedingungen aus dem project-scanner-Report, sonst NICHT anbieten):**
1. **Python vorhanden** (`python`/`python3`/`.venv` — Bereich RELEASE/DOCS), UND
2. **nennenswerte Doku-Flaeche**: `docs/`-Verzeichnis existiert **ODER** ≥ 10 `.md`-Dateien
   ausserhalb vendor-/Beispiel-Ordnern (Bereich DOCS).

Fehlt Python -> **gar nicht anbieten** (totes Tool, genau der Fall den v4.0 abgeschafft hat).
Unter 10 Markdown-Dateien und ohne `docs/` gibt es schlicht nichts zu messen — dann **INFO**
statt Angebot: *"zu wenig Doku-Flaeche, das Gate haette hier keinen Gegenstand"*.

**Immer detect-and-OFFER, nie erzwungen.** User bestaetigt.

```bash
# nur ausfuehren wenn Gating erfuellt UND User bestaetigt
mkdir -p "$CLAUDE_PROJECT_DIR/tools" "$CLAUDE_PROJECT_DIR/.claude/rules"

# 1. coverage_gate.py (stdlib-only, keine Fremd-Abhaengigkeit, kein Netzzugriff)
if [ -f "$CLAUDE_PROJECT_DIR/tools/coverage_gate.py" ]; then
  echo "SKIP: tools/coverage_gate.py existiert bereits (User fragen ob ueberschreiben)"
else
  cp "$CLAUDE_PLUGIN_ROOT/references/doc-templates/coverage_gate.py" \
     "$CLAUDE_PROJECT_DIR/tools/coverage_gate.py"
fi

# 2. Companion-Rule wissenstransfer-pruefen.md (PFLICHT, Overwrite-Guard)
if [ -f "$CLAUDE_PROJECT_DIR/.claude/rules/wissenstransfer-pruefen.md" ]; then
  echo "SKIP: .claude/rules/wissenstransfer-pruefen.md existiert bereits (User fragen)"
else
  cp "$CLAUDE_PLUGIN_ROOT/references/rule-templates/wissenstransfer-pruefen.md" \
     "$CLAUDE_PROJECT_DIR/.claude/rules/wissenstransfer-pruefen.md"
fi
```

Dann **1 Pointer-Zeile** in `CLAUDE.md`: `- Wissenstransfer messen: \`python tools/coverage_gate.py <ziel.md> <quelle...>\` — siehe \`.claude/rules/wissenstransfer-pruefen.md\``

⚠ **Was im Angebot dazugesagt werden MUSS** (sonst wird das Gate ueberschaetzt): es misst
**Erwaehnung, nicht inhaltliche Treue**, und die **absolute Prozentzahl ist wertlos** — nur der
Zuwachs zwischen Vorher- und Nachher-Stand traegt eine Aussage. Beides steht in der Rule; wer
das Bundle anbietet, nennt es auch im Report.

## Step 6: Report — PFLICHT-Self-Check-Block am Anfang (v4.0)

**WICHTIG:** Report MUSS mit Self-Check-Block BEGINNEN. Jeder Marker mit konkreten Belegen.

**Wenn der Marker fehlt oder `(SKIPPED)` enthaelt ohne explizite Begruendung:**
User darf zurueckweisen mit "Self-Check-Block fehlt — bitte Step 1 ausfuehren".

```
=== Project Setup Report v4.0 — Self-Check ===
[Step 1 project-scanner] Profile: <z.B. code_app +docs +tests>
  Tech-Stack: <z.B. Python 3.11, pyproject.toml, pytest>
  Setup-Bereiche (vom project-scanner via test -e/Glob gescannt):
  - BUILD   → <Exist/Missing + Kurzbefund>
  - BACKUP  → <Exist/Missing>
  - TESTS   → <Exist/Missing>
  - SECRETS → <Exist/Missing>
  - RELEASE → <Git? Versions-Signal? Python? — entscheidet Pack-Angebot>
  - DOCS    → <`docs/`? Anzahl .md ausserhalb vendor? Python? — entscheidet Doku-Gate (5d)>
  No-Dead-Tools-Nachweis — GEMESSEN, nicht behauptet (v5.2.1):
  <woertliche Ausgabe von mind_check_tools_have_rules, eine Zeile je Tool>
  Beleg: project-scanner Agent Tool-Call #<N>
```

**Der Nachweis wird AUSGEFUEHRT, nicht aufgeschrieben (NEU v5.2.1):**
```bash
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
mind_check_tools_have_rules "${CLAUDE_PROJECT_DIR:-$(pwd)}"; TOOLCHECK_RC=$?
```
Die **woertliche Ausgabe** kommt in den Block — nicht paraphrasiert, nicht gekuerzt. Bei
`TOOLCHECK_RC=1` MUSS der Report das als **verletzte Invariante** ausweisen und die fehlende
Rule nachtragen.

**Warum das den alten Prosa-Block ersetzt:** Bis v5.2.0 stand hier eine Tabelle, die der Skill
selbst ausfuellte — also eine Behauptung ueber die eigene Arbeit. Gemeldet 2026-08-16 als
„Self-Check-Block nicht durchsetzbar", und das war berechtigt. `mind_check_tools_have_rules`
prueft stattdessen am Dateisystem: Nennt eine `.claude/rules/*.md` das Tool **namentlich**, und
hat sie **`globs:`** im Frontmatter (ohne die triggert sie nie)? Die Pruefung kann scheitern —
ein Tool ohne Rule ergibt nachweislich `FAIL`.

> ⚠ **Was sie NICHT belegt:** dass die Rule je gelesen oder befolgt wird. Gemessen wird die
> **Erreichbarkeit**, nicht die Wirkung. Dieser Rest bleibt Prosa und wird nicht als mehr
> ausgegeben, als er ist.

**Pflicht-Format:** Profile + alle 6 Setup-Bereiche mit Exist/Missing + die **ausgefuehrte**
Nachweis-Ausgabe + `(Beleg: project-scanner Tool-Call #<N>)`.

---

## Step 6.1: Summary (nach Self-Check-Block)

```
=== Project Setup Complete ===
Created: 3 files (settings.json, .claudeignore, testing.md)
Improved: 1 file (.gitignore: +2 patterns)
Already OK: 2 files
Project readiness: Good (all critical files present)
```

## Hard Constraints

- **NEVER overwrite existing files without user confirmation** — gilt WEITER auch im Autonom-Modus (v5.0.0). Autonomie heißt: fehlende Dateien anlegen + eigene Befunde anwenden — NICHT fremden Bestand überschreiben. Overwrite-Guards (Step 5/5b/5c) bleiben aktiv: SKIP + melden.
- **NEVER apply without a successful `mind_snapshot` (Step 0)** — Snapshot fehlgeschlagen = keine Edits, Abbruch.
- **ALWAYS report every created/changed file** + Snapshot-Pfad + Restore-Einzeiler; Tool-Bundles bleiben Angebot (Step 0).
- NEVER create files without showing preview content first
- ALWAYS show what would be created/changed before doing it
- ALWAYS use Write for new files, Edit for modifications
- ALWAYS check if directories exist before creating files in them (mkdir -p if needed)
- For CLAUDE.md generation: ALWAYS use project-scanner results, NEVER guess
- For settings.json: ALWAYS include .env* in deny patterns (security baseline)
- NEVER include secrets, API keys, or credentials in any generated file
- **Ein Agent-Dispatch (v3.3.3):** NUR project-scanner (Step 1) deckt Typ-Erkennung + alle 4 Setup-Bereiche (build/backup/tests/secrets) in EINEM Durchgang ab. Die frueheren 4 separaten context-analyzer-Agents (Step 1.5) waren reine Datei-Existenz-Redundanz und sind entfernt — kein zweiter Dispatch, nichts zum Ueberspringen.
- **Backup-System Direktive H (v5.0.0 typ-gated, Befund 8):** Vorschlag nur bei Primary
  `code_app`/`library`/`plugin`/`mcp`/`scripts`. Bei **`workspace`/`docs`/`data`/`config`**
  NICHT anbieten, sondern **INFO**: "reiner Doku-/Datenordner — PreCompact-Hook + globale
  Backups decken das ab; Python-Tools waeren hier totes Gewicht". Zusaetzlich: enthaelt die
  Projekt-CLAUDE.md eine Abhaengigkeits-/Tool-Sperre (z.B. "zero dependencies", "keine
  Fremd-Tools"), **melden statt vorschlagen**. Grund: "backups schaden nie" stimmt, aber ein
  nie genutztes Tool im Ordner ist genau der Dead-Tool-Fall, den v4.0 abgeschafft hat.
- **Templates plugin-unabhaengig:** Nach Installation kein Plugin-Bezug — Tools laufen autonom im Projekt. Keine Hardcodes von Plugin-Pfaden in den installierten Files (Direktive C)
- **Python-Detection vor Backup-Installation:** Wenn `python --version` UND `python3 --version` fehlschlagen: Installation laeuft trotzdem (User-OK gegeben) ABER mit WARN "nicht lauffaehig bis Python da ist"
- **"No Dead Tools"-Invariante (NEU v4.0, KERN):** JEDES Tool das dieser Skill ins Projekt installiert (`tools/backup_tools.py`, `tools/rollback.py`, `tools/mutation_guard.py`, `tools/update_changelog.py`, `tools/version.py`, `tools/coverage_gate.py`) MUSS zusammen mit einer glob-getriggerten Companion-`.claude/rules/*.md` installiert werden, die Claude sagt WANN + WIE er's nutzt + 1 Pointer-Zeile in CLAUDE.md. **Kein Tool-Install ohne Rule** — sonst liegt das Tool tot im Ordner (`docs/*.md` ist Menschen-Doku, wird nicht auto-geladen). Ehrlich: die Rule macht das Tool *erreichbar*, nicht garantiert-genutzt (Prosa-Enforcement) — aber totes `.py` -> geladene Anweisung ist eine echte Verbesserung.
- **Versioning-Pack-Gating (NEU v4.0):** `version.py` + `release-build.md` NUR bei Python + Release-App (Primary `code_app`) + Build/Version-Signal anbieten. **Nie wo Python fehlt** — sonst waere version.py selbst ein totes Tool. Immer OFFER, nie erzwungen.
- **update_changelog.py-Ownership (NEU v4.0):** gehoert ins Release-Hygiene-Bundle (Step 5b, `test -d .git`), NICHT ins Backup-Bundle. Nie ohne `release-hygiene.md`.
- **Doku-Gate-Gating (NEU v5.3.0):** `coverage_gate.py` + `wissenstransfer-pruefen.md` NUR bei **Python vorhanden** UND (`docs/` existiert ODER ≥10 `.md` ausserhalb vendor-Ordnern). **Nie wo Python fehlt** — sonst waere das Gate selbst ein totes Tool. Zu wenig Doku-Flaeche → INFO statt Angebot, nicht stillschweigend installieren. Immer OFFER, nie erzwungen. **Und im Angebot dazusagen, was es NICHT kann:** es misst Erwaehnung statt inhaltlicher Treue, und die absolute Prozentzahl ist wertlos (gemessen: 43 % gegen einen Stand, in dem das Material nachweislich fehlte) — nur der Zuwachs traegt eine Aussage.
