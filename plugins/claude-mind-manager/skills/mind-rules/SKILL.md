---
name: mind-rules
description: |
  [Mind Manager] Manage project rules (.claude/rules/*.md). List, validate syntax, create new rules,
  migrate from paths: to globs: (fixing the known bug where paths: silently fails).
  Supports alwaysApply workaround (rule without globs: = always loaded). Offers
  InstructionsLoaded debug mode to verify which files load.

  Use when the user says "manage rules", "check rules", "mind rules", "create a rule",
  "fix my rules", "rules not working", "paths to globs", "rules syntax check",
  or "/mind-rules [list|check|create|migrate]".
argument-hint: "[list|check|create|migrate]"
context: inherit
allowed-tools: Read Glob Grep Edit Write Bash
---

# Rules Management

Manage, validate, create, and fix Claude Code rule files.

## Objective

Provide complete management of `.claude/rules/*.md` files including syntax validation, creation, and migration from the buggy `paths:` field to the working `globs:` field.

## Step 0: Modus + Snapshot (PFLICHT, NEU v5.0.0)

**Autonom ist der Standard.** `check`/`migrate` wenden Fixes selbstaendig an (Syntax,
`paths:`→`globs:`); `create` fragt weiterhin nach Inhalt, weil es ohne Vorgabe nichts
zu erzeugen gibt.

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
  SNAPSHOT=$(mind_snapshot "${CLAUDE_PROJECT_DIR:-$(pwd)}" "pre-rules") || {
    echo "ABBRUCH: Snapshot fehlgeschlagen — es wird NICHTS editiert." >&2; exit 1; }
  echo "Snapshot: $SNAPSHOT"
fi
```

`--ask` = Diff zeigen + Freigabe (Verhalten vor v5.0.0) · `--dry-run` = nichts aendern.

**DESIGN-Befunde werden NIE automatisch angewendet** — markiert eine Rule sich selbst oder
eine andere als "niemals anfassen"/"by design", nur listen. Gilt auch fuer `migrate` auf
**globalen** User-Rules (`~/.claude/rules/`): die sind im Snapshot, aber besonders wertvoll.
**Bei Snapshot-Fehlschlag wird NICHT editiert.**

## Workflow

### Step 1: Parse Subcommand

From `$ARGUMENTS`:
- **list** — show all rules with frontmatter and line counts
- **check** — validate syntax, detect issues
- **create** — guided creation of a new rule
- **migrate** — auto-convert paths: to globs:
- No argument — default to `list`

Optional flag: `--debug` (only with `check`) — enable InstructionsLoaded hook

---

### Subcommand: list

1. Glob for `.claude/rules/*.md` and `~/.claude/rules/*.md`
2. Read each file's YAML frontmatter
3. Display table:

```
=== Rules Overview ===

| File | Scope | Glob Pattern | Lines | Status |
|------|-------|-------------|-------|--------|
| .claude/rules/typescript.md | Project | **/*.ts, **/*.tsx | 30 | OK (globs:) |
| .claude/rules/api.md | Project | src/api/**/* | 25 | OK (globs:) |
| .claude/rules/general.md | Project | (none — always loaded) | 15 | OK |
| ~/.claude/rules/style.md | User | — | 20 | WARNING (paths: — won't work) |

Total: 4 rules, 90 lines
```

---

### Subcommand: check

1. Read all rule files
2. Parse YAML frontmatter
3. Check for issues:

| Issue | Severity | Detection |
|-------|----------|-----------|
| Uses `paths:` instead of `globs:` | WARNING | Grep `^paths:` |
| User-level rule uses `paths:` | ERROR | paths: in ~/.claude/rules/ never works |
| YAML quoting issue | WARNING | `*` or `{` at line start without quotes |
| Empty frontmatter | INFO | No globs: = always loaded (may be intentional) |
| Rule >50 lines | INFO | Large rule may impact compliance |
| Dead `globs:` pattern | WARNING | `ls <pattern>` returns 0 matches — rule never loads |

Output:
```
=== Rules Syntax Check ===

.claude/rules/typescript.md — OK (globs: **/*.ts, **/*.tsx)
.claude/rules/testing.md   — WARNING: uses paths: instead of globs:
~/.claude/rules/global.md  — ERROR: paths: in user-level rules (never works)

Fixable: 2 issues (run /mind-rules migrate)
```

**With `--debug` flag:** Explain InstructionsLoaded hook:
```
To debug which files Claude loads and when, add this to .claude/settings.json:

"hooks": {
  "InstructionsLoaded": [{
    "hooks": [{ "type": "command",
      "command": "echo '[Debug] Files loaded:' && cat | jq -r '.files // empty'" }]
  }]
}

View output with Ctrl+O (verbose mode). Remove after debugging.
```

---

### Subcommand: create

Guided rule creation:

1. Ask: "What should this rule enforce?"
2. Ask: "Which files should it apply to? (glob pattern, e.g., **/*.ts)"
   - Option: "Always load (no file filter)" → creates rule without globs: frontmatter
3. Generate rule file:

```yaml
---
globs: src/api/**/*.ts
---
# API Development Rules

- All endpoints MUST validate input with Zod
- Error handling per src/lib/errors.ts
- NEVER use direct DB queries in route handlers — use repository pattern
```

4. Show preview, confirm file path (`.claude/rules/<name>.md`)
5. Write on confirmation

#### Companion-Rules fuer installierte Tools ("No Dead Tools" — NEU v4.0)

Wenn eine Rule ein **installiertes Tool erreichbar machen** soll (z.B. `tools/backup_tools.py`,
`tools/version.py`, `tools/update_changelog.py`, `tools/coverage_gate.py`), gelten zwei
Zusatz-Regeln:

- **`globs:` muss auf die Trigger-Dateien zeigen**, an denen das Tool relevant wird — nicht
  irgendein Muster. Beispiele:
  - Backup-Tool (immer relevant vor Datei-Ops) -> `globs: ["**/*"]` (always-on).
  - Versions-Tool -> `globs: ["build.py", "*.spec", "**/*.py", "pyproject.toml", "VERSION"]`.
  - Doku-Gate (relevant sobald Wissen uebertragen wird) -> `globs: ["**/*"]` (always-on).
- **Inhalt = WANN + WIE**, nicht nur WAS: konkreter Trigger ("vor Mass-Delete", "nach
  Feature-Fertigstellung"), der genaue CLI-Aufruf, und die 2-3 load-bearing Fallen.
- **Grund (ehrlich):** Eine glob-Rule laedt auto, sobald Claude eine passende Datei anfasst,
  und macht das Tool *erreichbar* — sie garantiert NICHT dass es genutzt wird (Prosa =
  schwaechste Enforcement-Stufe). Aber ein totes `.py` im Ordner -> eine geladene Anweisung
  ist eine echte Verbesserung. `docs/*.md` (Menschen-Doku) wird NICHT auto-geladen und zaehlt nicht.

mind-files nutzt fertige Companion-Rule-Templates aus `references/rule-templates/`
(`backup-usage.md`, `release-hygiene.md`, `release-build.md`, `wissenstransfer-pruefen.md`) —
diese hier sind die Vorlage/Muster fuer handgeschriebene Companion-Rules.

⚠ **Diese Liste zieht nicht automatisch mit.** Es gibt im Plugin **keine maschinenlesbare
Registry** installierbarer Tools; sie steht als Prosa an genau zwei Stellen — hier und in der
Step-5-Struktur von `mind-files/SKILL.md`. Wer ein Bundle ergaenzt, traegt es in **beide** ein,
sonst ist es an einer Stelle unsichtbar.

---

### Subcommand: migrate

Auto-convert `paths:` to `globs:` in all rule files:

1. Find all rule files with `paths:` frontmatter
2. For each file, show diff:

```
=== Migrating .claude/rules/testing.md ===

Before:
  paths:
    - "tests/**/*.test.ts"
    - "tests/**/*.spec.ts"

After:
  globs: tests/**/*.test.ts, tests/**/*.spec.ts

[Apply / Skip]
```

3. **Read each rule file BEFORE Edit** — Edit-Tool benoetigt vorherigen Read im
   selben Tool-Call-Kontext, sonst Crash mit `<tool_use_error>File has not been
   read yet`. Apply changes with Edit on confirmation.
4. Summary: "Migrated N files from paths: to globs:"

## Hard Constraints

- ALWAYS use `globs:` in generated rules, NEVER `paths:`
- ALWAYS show preview before writing new rule files
- ALWAYS warn about user-level rules with paths: (known to not work)
- **NEVER modify rules without a successful `mind_snapshot` (Step 0)** — Fehlschlag = Abbruch. (v5.0.0: im Autonom-Modus wird der Diff NACH dem Anwenden im Bericht gezeigt, statt vorher zur Freigabe; bei `--ask` weiter vorher.)
- **ALWAYS report every applied change** mit `file:line` + before→after + Snapshot-Pfad.
- Rules without globs: are valid — they always load (document this, don't warn)
- **"No Dead Tools" (NEU v4.0):** Wird ein Tool ins Projekt installiert, MUSS eine Companion-Rule mit passendem `globs:`-Trigger dazu — sonst liegt das Tool tot im Ordner. Companion-Rule = WANN + WIE + load-bearing Fallen, nicht nur WAS. Ehrlich: Rule = erreichbar, nicht garantiert-genutzt.

## ⛔ `paths:` gegen `globs:` — Stand der Belege (NEU v5.7.0)

Die Migrations-Empfehlung dieses Skills stuetzte sich bis v5.6.0 **ausschliesslich** auf
Community-Recherche (`Wissen/block-4-community.md`), nicht auf die offizielle Doku. Am
21.08.2026 in der CLI-Binaerdatei nachgesehen (dieselbe Technik, die die
Auto-Kompaktierungs-Formel geliefert hat):

| Befund | Zahl |
|---|---|
| `globs:` in Frontmatter-Beispielen | **11** |
| `alwaysApply:` | 1 (im selben Beispiel) |
| `paths:` in einem Frontmatter-Beispiel | **0** |

Wortlaut des mitgelieferten Beispiels:

```yaml
description: Use Bun instead of Node.js, npm, pnpm, or vite.
globs: "*.ts, *.tsx, *.html, *.css, *.js, *.jsx, package.json"
alwaysApply: false
```

⚠ **Das beweist NICHT, dass `paths:` scheitert.** Gefunden sind Beispiel- und Dokumenttexte,
nicht der Parser. Belegt ist nur: Claude Code liefert selbst Regeln mit `globs:` aus und
keine mit `paths:`.

⛔ **Die zweite offene Haelfte bleibt offen:** ein `globs:`-Muster **ohne einen einzigen
Treffer** verhindert das Laden NICHT (gemessen an CC 2.1.237). Die Tabelle oben stuft das
weiterhin als „rule never loads" ein — das ist **falsch** und wird bis zur Klaerung nur als
Hinweis ausgegeben, nie als Grund fuer eine Aenderung.

**Das Experiment, das beides entscheiden wuerde:** je eine Testregel mit `paths:` und mit
`globs:` anlegen, den `InstructionsLoaded`-Hook registrieren und nachsehen, welche geladen
wird. Bis dahin: **`migrate` nicht blind laufen lassen.**
