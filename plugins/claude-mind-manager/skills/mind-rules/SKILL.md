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
- **migrate** — auto-convert paths: to globs: ⚠ **siehe Widerspruch unten**
- **budget** (NEU v5.12.0) — was laedt wirklich, wie ist der Bestand aufgebaut
- No argument — default to `list`

Optional flag: `--debug` (nur mit `check`) — Ladeprotokoll auswerten

### ⛔ UNGEKLAERTER WIDERSPRUCH: `paths:` gegen `globs:`

Dieser Skill migriert `paths:` → `globs:` und stuft `paths:` als *„won't work"* ein.
**Die offizielle Doku sagt das Gegenteil** (Recherche 21.08.2026):

| Quelle | Aussage |
|---|---|
| `[DOKU]` code.claude.com/docs/en/memory | **nur `paths:` ist dokumentiert**; *„Rules without a `paths` field are loaded unconditionally"*; *„Path-scoped rules trigger when Claude reads files matching the pattern"* |
| `[ISSUE]` #17204 (*closed, not planned*) | `globs:` ist **undokumentiert** und funktioniert laut Nutzern, waehrend `paths:` in mehreren Konfigurationen versagt |
| `[ISSUE]` #13905 · #16853 · #24112 · #63142 | konkrete `paths:`-Ausfaelle (Invalid-YAML bei `{`/`*`; feuert beim ANLEGEN einer Datei nicht) |
| `[ISSUE]` #21858 · #22170 (**offen**) | fuer `~/.claude/rules/` (global) laedt `paths:` **gar nicht**; im Projekt funktioniert dieselbe Regel |

⛔ **Der Widerspruch wird hier NICHT aufgeloest.** Beide Seiten haben Belege, keine
hat eine Messung an dieser Maschine. **`migrate` bleibt wie es ist** — es folgt den
Nutzerberichten, und die sind naeher am Verhalten als die Doku.

**Was ihn aufloesen wuerde:** eine Sonde, die beide Feldnamen auf eine wirklich
gelesene Datei setzt, plus das Ladeprotokoll (`budget`). Taucht `path_glob_match`
auf, traegt `paths:` hier. Bis dahin gilt: **im Bericht beide Seiten nennen.**

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
| **Frontmatter nicht mit `---` geschlossen** | **CRITICAL** | erste Zeile ist `---`, aber es gibt keine zweite `---`-Zeile |
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

**Mit `--debug`:** ⛔ **Nichts mehr von Hand eintragen.** Seit v5.12.0 liefert das
Plugin den Hook mit (`hooks/instructions-loaded.sh`, per Auto-Discovery registriert).
Er laeuft in **jedem** Projekt und schreibt ein Ladeprotokoll:

```bash
python "$CLAUDE_PLUGIN_ROOT/references/ladeprotokoll_auswertung.py"
```

*(Die frueher hier vorgeschlagene Handregistrierung riet den Feldnamen `.files` —
die Feldnamen des Ereignisses sind **undokumentiert**. Der mitgelieferte Hook
probiert mehrere Kandidaten und haengt bei Misserfolg die ROHE Zeile an, statt
still leere zu schreiben.)*

⚠ Der Hook feuert beim **Sitzungsstart**. Die laufende Sitzung zeigt nichts —
es braucht eine neue.

---

### Subcommand: budget (NEU v5.12.0)

**Beantwortet zwei Fragen, die bis v5.11.0 nur zu raten waren:** was laedt hier
wirklich, und wie ist der Bestand aufgebaut?

```bash
# 1. Was wurde tatsaechlich geladen, wann, und mit welchem Grund?
python "$CLAUDE_PLUGIN_ROOT/references/ladeprotokoll_auswertung.py"

# 2. Wie ist der Bestand aufgebaut? (Beleg / Vorfall / Code / reine Anweisung)
python "$CLAUDE_PLUGIN_ROOT/references/bestandsaufnahme.py" \
       --ordner "$CLAUDE_PROJECT_DIR/.claude/rules"
```

**Danach je Regel einordnen** — nach dem Vier-Wege-Kriterium:

| Woran ist der Moment erkennbar? | Mechanismus | Kosten |
|---|---|---|
| **am Werkzeugaufruf** (Pfad, Endung, Befehlswort) | **Hook** | 0 Tokens, erzwingt |
| **an der Aufgabe** (der Nutzer sagt, was er will) | **Skill** | ~1 Zeile |
| **der Nutzer ruft es beim Namen** | **Slash-Command** | ~1 Zeile, deterministisch |
| **gar nicht** — gilt vor jedem Eingriff | **bleibt Rule** | volle Groesse |

⛔ **Bei jedem Umzug bleibt die Leitplanke als Kurz-Rule zurueck und zeigt auf Hook
oder Skill.** Ein Skill feuert nur, wenn er erkannt wird — *„nie auf dem Desktop des
Nutzers starten"* muss man wissen, **bevor** man etwas startet. Ohne diesen Rest ist
der Umzug ein Rueckschritt.

### ⛔ Was der Bericht NICHT behaupten darf

- **„nicht im Protokoll" heisst NICHT „laedt nicht".** Es kann auch heissen, dass
  keine protokollierte Sitzung die Datei erreicht hat.
- **Gezaehlt werden Ladevorgaenge, keine Tokens.** Ein Budget laesst sich daraus
  nicht ableiten.
- **Fehlt `path_glob_match`, ist das kein Befund gegen Scoping** — erst eine Sonde
  mit `paths:` auf eine wirklich gelesene Datei macht es zu einem.

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

## ⛔ SUCHEN, BEVOR DU ERGAENZT (PFLICHT, NEU v5.20.0)

**Eine Ergaenzung ohne Ruecknahme der alten Aussage ist ein WIDERSPRUCH, kein Update.**

Bevor eine Aussage hinzugefuegt oder korrigiert wird, wird die Datei nach dem
**KERNBEGRIFF** durchsucht — nicht nach der Ueberschrift, unter der die Ergaenzung
landen soll:

```bash
grep -n "<kernbegriff>" <datei>        # z.B. den Bezeichner, den Dateinamen, die Zahl
```

Findet sich eine aeltere Stelle, die etwas anderes sagt, gibt es **genau zwei**
zulaessige Ausgaenge:

| | |
|---|---|
| **Ruecknahme** | die alte Stelle wird durchgestrichen und datiert: `✅ ~~alte Aussage~~ — BEHOBEN in vX.Y.Z` |
| **Aufloesung** | ein Satz sagt ausdruecklich, welche Fassung ab wann gilt: `Bis v5.6.0 stand hier ...` |

⛔ **Beides stehenlassen ist KEINE Option.** Zwei Stellen, die sich widersprechen,
sind gleich glaubwuerdig — und der naechste Leser waehlt die falsche.

**Der Anlass ist gemessen.** Der `/mind-all`-Lauf im Projekt `Creator` fand am
24.08.2026 **sieben Halb-Korrekturen** an einem Tag:

```
stimme.md:93     "⛔ NOCH NICHT IM CODE"  (der Echo-Vorabschnitt)
stimme.md:1193   "`VORAB_MS = 150` ... ist fuer Qwen richtig"  — setzt ihn voraus
                 1100 Zeilen auseinander, beide gleich glaubwuerdig
```

Der Lauf nannte auch die Bilanz: **sechs von sieben** waeren mit einem `grep` auf
den Kernbegriff vor dem Anhaengen aufgefallen. `doku-veraltet` ist mit **25
Vorkommen** die haeufigste Projekt-Klasse im Debug-Ordner ueberhaupt.

⚠ **Der Detektor ersetzt die Suche NICHT.**
`references/cleaner_duplikate.py` findet solche Widersprueche nachtraeglich
(`--widersprueche`), aber nur, wenn beide Stellen eine **gemeinsame Marke**
tragen — einen Bezeichner, Pfad oder Zahlenwert. Ein Widerspruch, bei dem die eine
Seite den Bezeichner nennt und die andere ihn nur umschreibt, ist fuer ihn
unsichtbar. **Die Suche vor dem Schreiben ist die tragende Massnahme, das Werkzeug
das Netz darunter.**

## Hard Constraints

- ALWAYS use `globs:` in generated rules, NEVER `paths:`
- ALWAYS show preview before writing new rule files
- ALWAYS warn about user-level rules with paths: (known to not work)
- **NEVER modify rules without a successful `mind_snapshot` (Step 0)** — Fehlschlag = Abbruch. (v5.0.0: im Autonom-Modus wird der Diff NACH dem Anwenden im Bericht gezeigt, statt vorher zur Freigabe; bei `--ask` weiter vorher.)
- **ALWAYS report every applied change** mit `file:line` + before→after + Snapshot-Pfad.
- Rules without globs: are valid — they always load (document this, don't warn)
- **"No Dead Tools" (NEU v4.0):** Wird ein Tool ins Projekt installiert, MUSS eine Companion-Rule mit passendem `globs:`-Trigger dazu — sonst liegt das Tool tot im Ordner. Companion-Rule = WANN + WIE + load-bearing Fallen, nicht nur WAS. Ehrlich: Rule = erreichbar, nicht garantiert-genutzt.

## ⛔ Der schwerste Befund, den bis v5.7.0 KEIN Check sah

**Ein Frontmatter, das mit `---` beginnt und nie geschlossen wird.** Der Parser liest dann
entweder die ganze Datei als Frontmatter oder gar keines — beides macht die Regel unwirksam,
und **keine** der bisherigen Pruefungen bemerkte es.

Gemeldet am 21.08.2026 aus dem Projekt **APP - Zustellplan**, nicht von hier. Der Befund
kam ueber den zentralen Debug-Ordner (`MIND_DEBUG_DIR`) zurueck — der erste Fall, in dem ein
anderes Projekt einen Fehler in diesem Skill gefunden hat.

⚠ **Die dort genannte Zahl „6 von 12 Regeldateien" ist hier NICHT mehr nachpruefbar.**
Nachgemessen am 21.08.2026 um 08:00: alle 12 Dateien haben vollstaendiges Frontmatter —
derselbe Lauf, der den Befund meldete, hat ihn offenbar auch repariert. **Die Zahl steht
deshalb als Meldung da, nicht als Tatsache.** Der Check bleibt trotzdem richtig: er faengt
einen realen Fehlermodus, den kein anderer sieht.

```bash
# Die Pruefung, die gefehlt hat:
for f in "$RULES_DIR"/*.md; do
  head -1 "$f" | grep -q '^---$' || continue          # kein Frontmatter -> anderer Fall
  [ "$(grep -c '^---$' "$f")" -ge 2 ] || echo "CRITICAL: $f — Frontmatter nie geschlossen"
done
```

⚠ **Nicht verwechseln mit „ganz ohne Frontmatter".** Eine Datei ohne jedes `---` nutzt den
alwaysApply-Weg und laedt korrekt. Eine Datei mit **einem** `---` ist kaputt.

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

---

## Step 9: ⛔ Der Bestands-Pass — PFLICHT, auch bei leerem Befund (NEU v5.22.0)

**Nutzer-Auftrag 27.08.2026:** *„die anderen skills sollen von vorne rein sauber arbeiten,
ähnlich wie der mind cleaner — nicht immer mehr und mehr. Auch gucken: braucht man das,
kann das weg, steht das schon woanders."*

Gemessen: der **immer geladene** Kontext wuchs an EINEM Tag um **+21 %** auf 2 601 Zeilen
und 138 Anweisungen — bei einer Schwelle von ~400 Zeilen und ~100–150 Anweisungen.
`/mind-all` trägt nach, **niemand sieht zurück**. Dieser Schritt sieht zurück.

⛔ **Er MELDET. Er schneidet nicht, verschiebt nicht, löscht nicht.** Handeln bleibt
`/mind-cleaner`, dessen Nicht-Autonomie (Nutzer-Entscheidung 24.08.2026) unberührt bleibt.

**Die vollständige Vorschrift steht in
[references/bestands-pass.md](../../references/bestands-pass.md)** — Bilanz, Stichprobe, die
drei Fragen, Urteilsbuch, Quittung, Fehlerszenarien, Risiko. **Lies sie**, bevor du diesen
Schritt ausführst. Hier steht nur, was für **diesen** Skill gilt:

| | |
|---|---|
| **Bereich** | `$PROJ/.claude/rules/` **und** `~/.claude/rules/` |
| **`--skill`** | `mind-rules` |
| **schon verdrahtet** | `cleaner_duplikate` |
| **neu in diesem Schritt** | `cleaner_belege` · `cleaner_aussagen --code` · `cleaner_einordnung` |

```bash
[ -n "$CLAUDE_PLUGIN_ROOT" ] || { echo "ERROR: $CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 1; }
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"

# 1) PFLICHTZEILE — sie MUSS woertlich in den Self-Check-Block des Berichts.
#    ⛔ Nicht nur erwaehnen: die Zeile selbst, mit beiden Zahlenpaaren.
mind_kontext_bilanz "$PROJ" --vergleichen

# 2) Stichprobe: 3 Einträge, die am längsten ungeprüft sind (max. 15 je Kettenlauf)
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_stichprobe.py" "$PROJ" \
       --skill mind-rules --verzeichnis "$PROJ/.claude/rules"

# 3) je Eintrag die drei Fragen — siehe Referenz, EINE Berichtszeile je Eintrag

# 4) Quittung — ohne sie gilt der Lauf als Teilsync
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_stichprobe.py" "$PROJ" \
       --quittung --skill mind-rules --geprueft <n> --stichprobe <n>
```

⭐ **Hier ist der Hebel am größten.** Regeldateien mit `globs: ["**/*"]` laden
**vollständig, bei jeder Anfrage, ohne Obergrenze** — anders als Memory-Topics, die
ein Auswähler auf 5 begrenzt. Gemessen trugen drei Dateien dieses Projekts zusammen
**79 KB**, davon 79–88 % Versions-Historie statt Anweisung.

⚠ `cleaner_einordnung` beantwortet dazu die Frage, die nur hier auftritt:
**gehört das überhaupt in eine Regel** — oder ist es ein Hook, ein Skill, oder
Wissen, das nach `knowledge/` gehört?

**PFLICHT im Bericht — dieser Skill hat als einziger keinen Self-Check-Block, also steht die Vorlage hier:**

```
[Step 9 Bestands-Pass v5.22.0] PFLICHT, auch bei leerem Befund
  Dauerkontext: <A> -> <B> Zeilen (<+/-D>) · Anweisungen <A> -> <B> (<+/-D>)
  Bestand: <g>/<s> geprueft · <d> Duplikat · <c> Code-Kandidat · <b> ohne Beleg · <u> UNGEPRUEFT
  ⛔ `(nichts)` ist erlaubt, FEHLEN nicht — ein fehlender Block macht den Lauf zum Teilsync
  Beleg: Bash-Tool-Call #<N>
```

⛔ **Ein FEHLENDER Block macht den Lauf zum Teilsync.** `(nichts)` ist eine gültige
Antwort — leerer Bestand, neues Projekt, Laufbudget erschöpft. **Schweigen ist es nicht.**
Ein Skill, der schweigt weil sein Bestand sauber ist, und einer, der schweigt weil der Pass
ausfiel, sehen von außen identisch aus. Dieselbe Lehre wie v5.3.1 und die Agent-Quittung.

⚠ **Fail-open:** fehlt ein Werkzeug oder stürzt es ab, wird `UNGEPRUEFT: <werkzeug>`
gemeldet und der Skill **läuft weiter**. Ein Bestands-Pass darf nie einen Sync töten.

