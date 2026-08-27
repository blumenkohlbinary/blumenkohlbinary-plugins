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

**Sektionen:** gegen die **gemeinsame Sektionsliste** in Step 4c pruefen (5 Pflicht + Workflow
optional) — **nicht** gegen eine eigene, kuerzere Aufzaehlung.

- [ ] Alle 5 Pflichtsektionen da (Übersicht · Commands · Architektur · Konventionen · Gotchas)?
- [ ] Keine Emojis? *(= Check 3 — Piktogramme, nicht `→`/`—`)*
- [ ] Kein Versions-Tag in einer Überschrift? *(= Check 15)*
- [ ] No generic advice ("write clean code")?
- [ ] No linter tasks (belongs in linter config)?
- [ ] Under 100 lines?
- [ ] Uses H2/H3 headings + bullets?
- [ ] No secrets or credentials? *(= Check 17)*

### Step 3e: Preview + Write

Show generated CLAUDE.md to user. Ask for confirmation before writing.

## Step 4: Audit-Modus (CLAUDE.md vorhanden)

### Step 4a: Referenzen laden

Read these reference files:
- [references/quality-scoring-guide.md](../../references/quality-scoring-guide.md) — 0-100 scoring rubric, A-F grading
- [references/claudemd-audit-criteria.md](../../references/claudemd-audit-criteria.md) — **NEU v5.4.0: ZWEITE Rubrik** (Anthropic, andere Gewichtung, **ohne** Notenskala) + Red Flags + `update-guidelines.md`-Kategorien
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

**NEU v5.4.0 — vier Anforderungen, die nachweislich NICHT messbar sind** und deshalb
ausdruecklich in den Agent-Prompt gehoeren, statt still zu fehlen:

- **Keine Ausfuehrungsplaene** — sie veralten zu schnell, gehoeren in MEMORY.md/Task-Dateien
- **Zeiger statt Inline-Kopien** — *„Prefer pointers to copies"*
- **Kein Hotfix-Sammelbecken** — jede ueberfluessige Zeile senkt die Befolgung aller anderen
- **Keine vorsorglichen Regeln** — reaktiv ergaenzen, wenn Claude einen Fehler macht

Dazu die zwei Leitfragen: *„Wuerde das Entfernen dieser Zeile dazu fuehren, dass Claude einen
Fehler macht?"* und *„Would a new Claude session find this helpful?"*

⛔ **Der Agent zaehlt NICHT selbst.** Zeilenzahl und Tokens/Zeile kommen kanonisch aus
Step 4c Schritt 2 und werden ihm uebergeben — sonst stehen zwei verschiedene Zahlen fuer
dieselbe Groesse im selben Bericht.

### Step 4c: Deterministische Prüf-Pipeline (NEU v5.4.0 — ergaenzend, NICHT statt Agent)

⛔ **AUSGEFUEHRT WIRD DAS SKRIPT, NICHT DIESE TABELLE (NEU v5.7.0).**

```bash
PIPE="$CLAUDE_PLUGIN_ROOT/references/claudemd_pipeline.py"
python "$PIPE" "<ziel.md>" --projekt "${CLAUDE_PROJECT_DIR:-$(pwd)}"
# Rueckgabe: 0 = keine Befunde · 1 = Befunde · 2 = Aufruffehler
#            3 = MESSUNG UNGUELTIG (Instrumentenkontrolle durchgefallen) -> Zahlen verwerfen
python "$PIPE" --selbsttest      # 22 Pruefungen, vor jedem Zweifelsfall
```

⛔ **Diese Pipeline NIE nachbauen.** Sie stand von v5.4.0 bis v5.6.0 nur als Prosa hier — und
wurde deshalb bei jedem Lauf neu geschrieben, samt der schon behobenen Fehler. Erhebung ueber
16 Laufabschnitte in zwei `listeverbesserungen.md`: **„instrument-nachgebaut" ist mit ~25
Vorkommen die haeufigste Ursachenklasse ueberhaupt**, dreimal in Folge derselbe Fall:

| Wann | Was der Nachbau meldete | Was wirklich war |
|---|---|---|
| 20.08.2026 | 11 tote Pfade | 11 Slash-Commands (`/mind-all`, …) |
| 20.08.2026 | `hooks/hooks.json` tot | liegt im Nachbar-Repo, das die Datei selbst nennt |
| 21.08.2026 | 9 tote Pfade | 8 Slash-Commands + 1 Nachbar-Repo — **echte tote Pfade: 0** |

Alle drei Klassen waren seit v5.3.1 in `classify_path()` behoben. Der Nachbau kannte sie nie.
Das Skript **portiert** die Funktion und haelt die Faelle mit `--selbsttest` fest — darunter
ein Fixture fuer die Nachbar-Repo-Wurzel, an dem der zweite Anlauf vom 20.08. gescheitert waere.

**Die Tabellen unten bleiben die SPEZIFIKATION** — sie sagen, was das Skript tut, und sind bei
einer Aenderung die Quelle. Sie sind keine Arbeitsanweisung mehr.

⛔ **Das ist eine PIPELINE, keine Liste. Die Reihenfolge ist Teil der Spezifikation** — mehrere
Fehlerklassen entstehen ausschliesslich dadurch, dass man sie missachtet.

#### Schritt 0 — Vorverarbeitung (PFLICHT, vor jedem Check)

1. **Fenced Codebloecke herausschneiden und merken.** Sie sind von Check 3, 6 und 13
   ausgenommen. Ohne das reisst die Backtick-Extraktion an den Fences auf, und Code-Inhalt
   landet ungefiltert in der Pfadliste.
2. **Mehrzeilige Bullets zusammenfassen** — Bullet + eingerueckte Folgezeilen zu EINER Einheit.
   Ohne das meldet Check 7 falsch: das `NEVER` steht auf Zeile 1, die Alternative auf Zeile 2.
3. **Alle Textvergleiche case-insensitiv.** `**stattdessen**` klein geschrieben zaehlt.

> Alle drei sind real passiert, am 2026-08-18 beim Bau genau dieser Pruefungen.

#### Schritt 1 — Instrumentenkontrolle (EINZIGER Abbruchgrund)

Die Pruefung zusaetzlich gegen eine **bekannt schlechte** Kontrolldatei fahren (Prosa-Wand,
keine Struktur, generische Ratschlaege). Schneidet sie **nicht deutlich schlechter** ab, misst
das Instrument nichts → **Lauf abbrechen**, alle Zahlen ungueltig.

**Warum das keine Zierde ist:** In einer einzigen Sitzung traten **neun** Messfehler auf, deren
Ausgabe jedes Mal wie ein plausibler Befund aussah — u.a. `grep -c $'\r'`, das jede Zeile
zaehlte und „CRLF in allen Hooks" meldete (byte-genau: **0**), und ein Emoji-Zaehler, der nur
die Unicode-Kategorien `So`/`Sk` prueft und deshalb `→` (Kategorie `Sm`) uebersah.
**Eine Bewertung ohne Gegenprobe ist eine Behauptung.**

#### Schritt 2 — Harte Checks → Berichtsblock „Befunde"

| # | Check | Regel |
|---|---|---|
| 2 | H1 **oder** direkter H2-Start | beides zulaessig |
| 3 | Keine Emojis | **Piktogramm-Ranges** U+1F300–1FAFF, ausgewaehlte U+2600–27BF. **NIE nach Unicode-Kategorie** — `→` und `—` sind erlaubt |
| 4 | Bullets ≤ 3 Ebenen | tiefere melden |
| 5 | Keine Leerzeile **zwischen** Bullets | **beide** Nachbarn pruefen — vor `## Gotchas` ist sie erlaubt |
| 6 | Zeilenlaenge — **zwei Schwellen** | **Prosa 100 · strukturierte Zeile (Bullet, Tabelle, nummeriert) 250.** Codebloecke ganz ausgenommen. Eine Regelzeile mit Alternative/Grund ist lang, **weil Check 7 es verlangt** — bis 250 kein Befund |
| 7 | Jedes `NEVER` nennt eine Alternative | nach Schritt 0.2, jedes einzeln melden |
| 11 | Zeilenzahl — **zwei Skalen, beide melden** | *diese Datei:* `<60` optimal · `<150` akzeptabel · 150–200 Warnung · `>200` kritisch. *Summe ueber alle Scopes:* `<100` · `<200` · 200–400 · `>400` (71 % Befolgung). Zielwert Wurzeldatei 40–80 |
| 12 | Tokens/Zeile | **drei** Schaetzer: Zeichen/4 · Bytes/4 · Woerter×1,4. **Alle drei ausweisen**, Schwelle 15 — sie laufen bei deutschem Text um ein Drittel auseinander |
| 13 | Pfade existieren | **ERSETZT den alten Punkt 2.** Kette: Fences raus → Backtick+Slash extrahieren → Spans mit Interpreter-Praefix an Check 14 abgeben → `classify_path()` (mind-update 3b) → `test -e`. **Drei Klassen:** `DEAD` (nirgends) = Befund · **`EXTERN`** (existiert unter Elternverzeichnis oder unter einer Wurzel, die die Datei selbst nennt) = **nur Hinweis** · `SKIP` |
| 14 | Befehle lauffaehig | **nur** Spans mit Interpreter-Praefix (`python `, `node `, `bash `, `./`). Fragmente wie `restore <name>` ignorieren |
| 15 | Versionen | Manifest-Abgleich **plus** `grep -E '^#+ .*\(v[0-9]'` → **muss 0 sein** |
| 17 | Keine Secrets | `sk-ant-` · `AKIA` · `BEGIN … PRIVATE KEY` · `password=` |
| 18 | Modularity messbar | `.claude/rules/*.md` zaehlen · `@import`-Vorkommen · Memory-Topic-Files. **15 Rubrik-Punkte, bis v5.3.1 von keinem Check beruehrt** |
| 19 | Ueberschriften-Hierarchie | `##` Haupt-, `###` Unterabschnitt, keine Spruenge |
| 20 | Architektur: 3–7 Eintraege | mehr = „vollstaendige Verzeichnisliste" (Anti-Pattern) |
| 21 | Commands-Inhalt | Stichwortsuche nach `build`, `test`, `lint`, `dev` — Sektions-Praesenz allein genuegt nicht. ⛔ **NUR bei Code-Projekten** (`package.json`/`pyproject.toml`/`Cargo.toml`/`go.mod`/`Makefile`/…). Ein Doku- oder Workspace-Projekt hat kein build/test/lint — dort waere der Check ein garantierter Fehltreffer, also gar keine Messung |

**Unveraendert uebernommen:** Git-Check (`git log --oneline -10`, nur wenn `.git/` existiert)
und die `CLAUDE.local.md`-Deprecation-Warnung.

#### Schritt 3 — Heuristiken → Berichtsblock „Hinweise" (NIE Punktabzug)

| # | Check | Warum nur Hinweis |
|---|---|---|
| 1 | Pflichtsektionen | **DE/EN-Synonymtabelle**, nicht englische Literale (`Übersicht` == `Overview`). **Workflow ist laut Notiz-Tabelle „(optional, empfohlen)"**, obwohl die Einleitung „MUSS" sagt — Widerspruch nicht aufloesen, Workflow als optional zaehlen. Kein Treffer → *„ungeprueft, Agent bestaetigen"*, nicht „fehlt" |
| 8 | Drei Constraint-Arten, **beide Richtungen** | nur `MUST`/`NEVER` ist bei guten Dateien normal. Auch der Spiegelfall (0 harte Regeln, nur `PREFER`) ist ein Hinweis |
| 9 | Betonung ueber Fett statt Marker | nur Extremfaelle (> 10:1) |
| 10 | Generische Ratschlaege | Phrasenlisten finden keine Paraphrasen — Agent-Aufgabe |
| 16 | Dopplung | identische Zeilen gegen README **und** `package.json` **und** `tsconfig.json` |
| 22 | Prosa-Wand | Anteil Nicht-Bullet-Zeilen |
| 23 | Linter-Aufgaben | eigene Kategorie, nicht dasselbe wie „generisch" |
| 24 | Backtick-Pflicht | fehleranfaellig, deshalb **nie** Befund |

⛔ **Heuristiken warnen, sie strafen nicht.** Ein Punktabzug auf Verdacht waere derselbe Fehler
wie ein autonom geloeschter „toter" Pfad.

#### ⛔ Drei Checks wurden erst durch das AUSFUEHREN richtig (2026-08-19)

Die Pipeline wurde auf zwei echten Dateien gefahren, bevor sie hier stand. Ergebnis im ersten
Lauf: die **gute** Datei loeste **8 Befunde** aus. Kein einziger war ein Mangel der Datei:

| Check | Fehlverhalten | Ursache |
|---|---|---|
| 6 | 3 Fehltreffer | Schwelle 100 traf **Regelzeilen mit Grund** — genau das Format, das der Leitfaden verlangt. Die echten Prosa-Waende der schlechten Datei lagen bei **518** und **643** Zeichen. Zwei Schwellen trennen beides sauber |
| 13 | 4 Fehltreffer | Ein Befehl (`python tools/rollback.py list`) landete in der Pfadliste statt bei Check 14 · und Pfade in ein **Nachbar-Repo** galten als tot. Eine CLAUDE.md, die anderswo liegenden Code dokumentiert, haette so reihenweise `DEAD` erzeugt — bei ≤5 Treffern **autonom geloescht** |
| 21 | 1 Fehltreffer | Ein Workspace ohne Build hat kein `build`/`test`/`lint`. Ein Check, der auf einer ganzen Projektklasse **immer** anschlaegt, misst dort nichts |

**Danach: gute Datei 0 Befunde · schlechte 17 · Kontrolldatei 11.** Zusaetzlich 27 benannte
Regressionsfaelle, davon **13 Gegenproben** (soll NICHT anschlagen) — alle bestanden.

> **Die Lehre:** Eine Pruefliste, die nie gelaufen ist, sieht genauso gut aus wie eine, die
> laeuft. Drei von 16 harten Checks waren falsch, und alle drei sahen auf dem Papier richtig aus.

#### Gemeinsame Sektionsliste (Check 1 **und** Step 3d — EINE Quelle)

| Sektion | Pflicht? | Erkannt an (case-insensitiv, DE **oder** EN) |
|---|---|---|
| Übersicht | ja | `übersicht`, `overview`, `projekt`, `project`, `zweck`, `purpose`, `about` |
| Commands | ja | `command`, `befehl`, `build`, `test`, `script`, `entwicklung`, `development` |
| Architektur | ja | `architekt`, `architecture`, `struktur`, `structure`, `aufbau`, `layout` |
| Konventionen | ja | `konvention`, `convention`, `stil`, `style`, `regel`, `rule`, `pattern` |
| Gotchas | ja | `gotcha`, `falle`, `pitfall`, `warnung`, `warning`, `bekannte fehler`, `known issue` |
| Workflow | **optional** | `workflow`, `ablauf`, `prozess`, `process`, `beitrag`, `contributing` |

⛔ **Workflow ist optional.** Die Notiz sagt in der Einleitung „MUSS", die Tabelle darunter
„(optional, empfohlen)". Der Widerspruch wird **nicht aufgeloest**, sondern zugunsten der
spezifischeren Angabe entschieden — und hier sichtbar gemacht statt stillschweigend.

⛔ **Diese Liste steht genau EINMAL.** Bis v5.3.1 nannte Step 3d eine andere, kuerzere Auswahl
(Übersicht, Gotchas und Workflow fehlten) — zwei Wahrheiten in derselben Datei, beide gleich
glaubwuerdig. Wer sie aendert, aendert sie hier.

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
[Step 4c Pipeline v5.4.0] Instrumentenkontrolle: <bestanden/ABBRUCH> (Kontrolle <K> vs. Ziel <N>)
  Schritt 2: <B> Befunde aus 16 harten Checks  ·  Schritt 3: <H> Hinweise aus 8 Heuristiken
  Pfade: <D> DEAD, <E> EXTERN (Hinweis), <S> SKIP  ·  Versionen: <ok/mismatch>, <T> Tags in Ueberschriften
  Git-Check: <Z> unreflektierte Commits
  Beleg: Bash-Tool-Call #<N>
[Step 5c Bestands-Pass v5.22.0] PFLICHT, auch bei leerem Befund
  Dauerkontext: <A> -> <B> Zeilen (<+/-D>) · Anweisungen <A> -> <B> (<+/-D>)
  Bestand: <g>/<s> geprueft · <d> Duplikat · <c> Code-Kandidat · <b> ohne Beleg · <u> UNGEPRUEFT
  ⛔ `(nichts)` ist erlaubt, FEHLEN nicht — ein fehlender Block macht den Lauf zum Teilsync
  Beleg: Bash-Tool-Call #<N>
```

Fehlt der Self-Check-Block oder enthaelt `(SKIPPED)`: User darf zurueckweisen.

**NEU v5.4.0 — ZWEIMAL bewerten, mit beiden Rubriken:**

1. `references/quality-scoring-guide.md` — Structure 20 · Completeness 25 · Efficiency 20 ·
   Modularity 15 · Currency 10 · Format Quality 10. **Hat eine A–F-Skala.**
2. `references/claudemd-audit-criteria.md` — Commands 20 · Architecture 20 · Non-Obvious 15 ·
   Conciseness 15 · Currency 15 · Actionability 15. ⛔ **Hat KEINE Skala — keine Note erfinden.**

**Warum beide:** dieselbe Datei ergab **54** (Rubrik 2) und **67** (Rubrik 1), nach dem Umbau
**95** und **91**. Gleiche Defekte, andere Gewichte — eine Rubrik allein findet die Haelfte nicht.

Der Bericht nennt beide getrennt und trennt Befunde von Hinweisen:

```
=== CLAUDE.md Audit Report v5.4.0 ===
Instrumentenkontrolle: bestanden (Kontrolldatei 284 Tok/Z gegen 12,3) — Messung gueltig

RUBRIK 1 (quality-scoring-guide.md, mit Notenskala)   67/100  Grade C
  Structure 16/20 · Completeness 13/25 · Efficiency 15/20
  Modularity 10/15 · Currency 3/10 · Format Quality 10/10

RUBRIK 2 (claudemd-audit-criteria.md, OHNE Notenskala)   54/100
  Commands 10/20 · Architecture 18/20 · Non-Obvious 5/15
  Conciseness 5/15 · Currency 8/15 · Actionability 8/15
  ⚠ keine Note — das Quelldokument definiert keine Skala

--- BEFUNDE (harte Checks) ---
[1] CRITICAL  CLAUDE.md:52   Versions-Tag in Ueberschrift: (v5.2.2), Ist-Stand 5.3.1
[2] WARNING   CLAUDE.md:—    Gotchas-Sektion fehlt
[3] WARNING   CLAUDE.md:—    Tokens/Zeile 26,0 / 26,3 / 17,0 (Schwelle 15)

--- HINWEISE (Heuristiken, KEIN Punktabzug) ---
[H1] Sektion „Architecture" nicht gefunden — ungeprueft, Agent bestaetigen
[H2] nur MUST/NEVER, keine PREFER/AVOID — bei diesem Projekttyp ggf. richtig
```

⛔ **Befunde und Hinweise nie in einer Liste mischen** — sonst stehen harte Messungen neben
Verdachtsmomenten und der Leser kann beides nicht trennen.

```
=== CLAUDE.md Audit Report (Altformat, weiterhin gueltig fuer die Findings-Tabelle) ===

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

Apply (diese Auswahl gilt NUR bei `--ask`):
  [safe]    — Nur sichere Currency-Fixes (Drift, Versions, Pfade)
              Default bei vager Antwort ("ja"/"ok"/"update")
  [all]     — Inklusive struktureller Aenderungen (Modularize, Section-Adds)
  [select]  — Einzeln auswaehlen
  [skip]    — Nichts aendern
```

**Nur bei `AUTO_MODE=no` (`--ask`): STOP HERE, warte auf User-Bestätigung.**
**Bei `AUTO_MODE=yes` (Default): NICHT stoppen** — Findings anwenden (außer DESIGN),
danach Step 6 mit Angewendet-Block. Bei `DRY_RUN=yes`: Liste zeigen, nichts ändern.

⛔ **`AUTO_MODE=yes` entspricht `[all]` — EINSCHLIESSLICH Modularize**, nicht `[safe]`
(Nutzer-Entscheidung 21.08.2026). Die `safe`/`all`-Trennung gilt **ausschliesslich fuer
`--ask`**; im autonomen Lauf gibt es sie nicht.

**Der Grund ist gemessen, nicht gewaehlt.** Bis v5.9.3 lag Modularize hinter `[all]` und
war damit im autonomen Ablauf unerreichbar — waehrend Check 11 den Befund bei jedem Lauf
neu meldete:

| Projekt | gemeldet als | damals | nach 3 Laeufen |
|---|---|---|---|
| Creator | `[OFFEN] CLAUDE.md hat 406 Zeilen (Schwelle 200 = kritisch)` | 406 | **426** |
| Palvedo | `[11] "278 Zeilen kritisch"` | 278 | **284** |

**Die Dateien sind gewachsen, nachdem sie als kritisch gemeldet wurden.** Ein Befund,
dessen einziger Fix hinter einer Handfreigabe liegt, wird in einem autonomen Ablauf nie
erledigt. Er ist dann kein Schutz, sondern Laerm — und stumpft die Aufmerksamkeit fuer
die echten Befunde ab.

**Disambiguation-Regel (nur `--ask`):** Bei vagen Antworten ("ja", "ok", "update", "los")
IMMER die `safe` Variante wählen (keine Modularization, keine Datei-Restruktur). Dem
User transparent mitteilen: "Wähle `safe` (Currency only) — sage `all` wenn du
auch strukturelle Änderungen willst."

### Step 4e: Modularize autonom — die vier Gates (NEU v5.10.0)

Modularize ist der einzige Fix, der Check 11 aufloest, und zugleich der eingreifendste im
ganzen Skill: er zerschneidet die Wissensdatei des Nutzers. Autonom ist er deshalb **nur
mit allen vier Gates** erlaubt. Bricht eines, wird die Sektion **nicht** ausgelagert und
bleibt als Befund stehen.

| Gate | Pruefung | Warum |
|---|---|---|
| **1 · Erhaltung** | Inhaltszeilen(CLAUDE.md neu) + Inhaltszeilen(neue Rule-Dateien, ohne Frontmatter) **>=** Inhaltszeilen(CLAUDE.md alt) | Modularize **verschiebt**, es kuerzt nicht. Verschwindet auch nur eine Zeile, ist es kein Modularize mehr, sondern ein Loeschen — und das hat einen eigenen Fix-Typ mit eigenem Bericht |
| **2 · Erreichbarkeit** | die neue Rule bekommt **kein `globs:`**, ausser der Inhalt ist echt dateibezogen | ⛔ CLAUDE.md laedt **immer**. Eine glob-gesteuerte Rule ist im schlechtesten Fall situativ — dann waere Auslagern ein stilles Unsichtbarmachen genau des Wissens, das oben stand |
| **3 · Zeiger** | in CLAUDE.md bleibt eine Zeile `Details: .claude/rules/<name>.md` zurueck | Ohne Zeiger weiss niemand, dass es die Datei gibt. Dieselbe Kern-Invariante wie "kein Tool ohne Companion-Rule" |
| **4 · Menge** | hoechstens **3 Sektionen je Lauf** | Ein Lauf, der eine 426-Zeilen-Datei auf einmal in acht Teile zerlegt, ist im Bericht nicht mehr nachpruefbar. Drei sind es, und der naechste Lauf macht weiter |

⚠ **Ehrlich zur Wirkung: Modularize spart KEINEN Kontext.** Gemessen an CC 2.1.237
(`memory/globs-laden-trotz-null-treffer.md`): eine Rule laedt auch dann, wenn ihr `globs:`
**null** Dateien trifft. Die ausgelagerten Zeilen stehen also weiter im Fenster. Was
Modularize verbessert, ist die **Befolgung** (Check 11: ~71 % ab 400 Zeilen Summe), nicht
das Budget. ⛔ **Der Bericht darf keine Token-Ersparnis behaupten** — er nennt die
Zeilenzahl der Wurzeldatei vorher/nachher und sagt dazu, dass die Summe gleich bleibt.

Gate 2 haengt bewusst **nicht** an dieser Messung: sie ist EINE Beobachtung an EINER
Version in EINEM Projekt. Ohne `globs:` laedt die Rule so oder so — auch dann, wenn sich
die Messung spaeter als versionsabhaengig erweist.

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

### Step 4f: ⛔ Das Urteilsbuch — PFLICHT vor jedem `Deduplicate` (NEU v5.16.0)

**Nutzer-Entscheidung 24.08.2026: `/mind-claudemd` UND `/mind-cleaner` dürfen beide
aufräumen.** Damit ist ein gemeinsamer Zustand keine Kür, sondern die Bedingung dafür,
dass die Entscheidung trägt.

⭐ **Der Fall, der ohne das Buch zwangsläufig eintritt:**

1. `/mind-cleaner` sieht: die CLAUDE.md **fasst** eine Regel zusammen **und nennt ihren
   Pfad**. Das ist die **Zielform** — kürzere Fassung plus Zeiger. Urteil: nichts tun.
2. Dieser Skill sieht beim nächsten `/mind-all` zwei Stellen mit demselben Inhalt, hält es
   für ein Duplikat und entfernt eine — **autonom, ohne Rückfrage**.
3. Beim übernächsten Lauf fehlt der Kurz-Regel ihr Inhalt, und niemand weiß, warum.

**Vor jedem `Deduplicate` also:**

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_urteile.py" "$PROJ" \
       --orte "<stelle-a>" "<stelle-b>"
```

| Rückgabe | Bedeutung | was du tust |
|---|---|---|
| `unbekannt` | noch nie beurteilt | anwenden **und Urteil eintragen** |
| `gueltig` + `duplikat` | schon als Duplikat erkannt | anwenden |
| `gueltig` + `zielform`/`zeiger` | ⛔ **bewusst so gelassen** | **NICHT anfassen** |
| `veraltet` | Inhalt hat sich geändert | neu beurteilen |

⛔ **`zielform` und `zeiger` darf dieser Skill NIE aufheben.** Er läuft autonom; das wäre
die Umkehrung einer menschlichen Entscheidung ohne Rückfrage. `duplikat` darf er anwenden —
das ist Aufräumen, keine Umkehrung.

**Nach jedem Urteil eintragen — auch bei „nichts tun":**

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_urteile.py" "$PROJ" --schreiben \
       --orte "<a>" "<b>" --urteil duplikat --werkzeug mind-claudemd --von autonom \
       --grund "<ein Satz>"
```

⚠ **Widerspricht dein Befund dem Buch, überstimme es nicht — melde es:**
*„Buch sagt `zielform` (mensch, 24.08.), ich sehe ein Duplikat."*

**Im Self-Check-Block ausweisen:** `Urteilsbuch: <n> gefragt · <n> gesperrt · <n> eingetragen`.

Für jeden bestätigten Fix:
| Fix-Typ | Tool | Aktion |
|---|---|---|
| Version updaten | Edit | `old_string: "2.3.0"` → `new_string: "2.6.0"` |
| Modularize | Write + Edit | Write neue Rule-Datei (**ohne `globs:`**), Edit CLAUDE.md: Sektion durch **Zeiger** ersetzen. ⛔ **Die vier Gates aus Step 4e sind Pflicht** — ohne sie nicht anwenden, sondern listen |
| Shorten | Edit | `old_string: verbose Zeile` → `new_string: kompakte Zeile` |
| Deduplicate | Edit | Duplikat-Zeile aus CLAUDE.md entfernen. ⛔ **Erst das Urteilsbuch fragen** — Step 4f |
| Dead path (`DEAD`) | Edit | Pfad-Zeile entfernen oder aktualisieren. ⛔ **>5 auf einmal bleibt gesperrt** (Massenlösch-Sicherung) |
| **`EXTERN`-Pfad** | **nichts** | ⛔ **NIE anfassen.** Der Pfad existiert — nur nicht unter diesem Projekt. Nur als Hinweis listen |
| Add info | Edit | Neue Zeile in passende Sektion einfügen |
| Remove generic | Edit | Zeile entfernen |

## Step 5c: ⛔ Der Bestands-Pass — PFLICHT, auch bei leerem Befund (NEU v5.22.0)

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
| **Bereich** | `$PROJ/CLAUDE.md` · `~/.claude/CLAUDE.md` · `$PROJ/.claude/CLAUDE.md` |
| **`--skill`** | `mind-claudemd` |
| **schon verdrahtet** | `cleaner_duplikate` (Step 4) · `cleaner_urteile` (Step 4f) |
| **neu in diesem Schritt** | `cleaner_belege` · `cleaner_aussagen --code` |

```bash
[ -n "$CLAUDE_PLUGIN_ROOT" ] || { echo "ERROR: $CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 1; }
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"

# 1) PFLICHTZEILE — sie MUSS woertlich in den Self-Check-Block des Berichts.
#    ⛔ Nicht nur erwaehnen: die Zeile selbst, mit beiden Zahlenpaaren.
mind_kontext_bilanz "$PROJ" --vergleichen

# 2) Stichprobe: 3 Einträge, die am längsten ungeprüft sind (max. 15 je Kettenlauf)
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_stichprobe.py" "$PROJ" \
       --skill mind-claudemd "$PROJ/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

# 3) je Eintrag die drei Fragen — siehe Referenz, EINE Berichtszeile je Eintrag

# 4) Quittung — ohne sie gilt der Lauf als Teilsync
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_stichprobe.py" "$PROJ" \
       --quittung --skill mind-claudemd --geprueft <n> --stichprobe <n>
```

⛔ **Ein FEHLENDER Block macht den Lauf zum Teilsync.** `(nichts)` ist eine gültige
Antwort — leerer Bestand, neues Projekt, Laufbudget erschöpft. **Schweigen ist es nicht.**
Ein Skill, der schweigt weil sein Bestand sauber ist, und einer, der schweigt weil der Pass
ausfiel, sehen von außen identisch aus. Dieselbe Lehre wie v5.3.1 und die Agent-Quittung.

⚠ **Fail-open:** fehlt ein Werkzeug oder stürzt es ab, wird `UNGEPRUEFT: <werkzeug>`
gemeldet und der Skill **läuft weiter**. Ein Bestands-Pass darf nie einen Sync töten.

## Step 6: Summary

```
=== CLAUDE.md Updated ===
Applied: 5 fixes | Skipped: 2
Score: 72 → 88 (Grade: C → B+)
Lines: 145 → 118 (-27)
Token savings: ~270
```

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

- **NEVER apply without a successful `mind_snapshot` (Step 0)** — Snapshot fehlgeschlagen = keine Edits, Abbruch. (Ersetzt v5.0.0 die alte Regel "NEVER apply without User-Bestätigung": Sicherheit kommt jetzt vom Netz, nicht von der Rückfrage.)
- **NEVER auto-apply DESIGN findings** — das sind Stellen, die eine Regel als "niemals anfassen" markiert; sie zu überschreiben bricht die Sperre des Users. Nur listen.
- **ALWAYS report every applied change** mit `file:line` + before→after + Snapshot-Pfad + Restore-Einzeiler.
- Bei `--ask`: Step 4d stoppt und wartet (altes Verhalten). Bei `--dry-run`: nichts ändern.
- **NEVER Modularize ohne die vier Gates aus Step 4e** — Erhaltung, Erreichbarkeit
  (kein `globs:`), Zeiger, hoechstens 3 je Lauf. Autonom seit v5.10.0; bricht ein Gate,
  wird die Sektion **gelistet statt ausgelagert**.
- **NEVER eine Token-Ersparnis fuer Modularize behaupten** — die ausgelagerte Rule laedt
  weiter mit (gemessen). Modularize verbessert Befolgung, nicht Budget.
- NEVER delete information without showing what will be lost
- ALWAYS show before/after for every edit
- ALWAYS backup CLAUDE.md before first edit (cp to .claude-mind/backups/)
- ALWAYS use Edit tool (not Write) for modifications — preserves surrounding content
- Generate-Modus: ALWAYS show preview, NEVER write without confirmation
- If CLAUDE.local.md found: warn but NEVER auto-delete (deprecated is not deleted)

**NEU v5.4.0 — Pipeline-Invarianten (Step 4c):**

- **Step 4c ERSETZT den Agent nicht.** Der context-analyzer-Dispatch (Step 4b) bleibt Pflicht;
  vier Anforderungen sind nachweislich nicht messbar und existieren nur dort.
- ⛔ **Die Instrumentenkontrolle (Schritt 1) ist der EINZIGE Abbruchgrund.** Kein Check darunter
  bricht ab — sie sind Befunde, keine Fehler.
- ⛔ **Heuristiken (Schritt 3) fuehren NIE zu Punktabzug** und stehen NIE im Block „Befunde".
- ⛔ **Ein Pfad-Check und ein Versions-Check, nicht je zwei.** Check 13 *ersetzt* den alten
  Punkt 2, Check 15 *erweitert* Punkt 1. Bleibt der alte Pfad-Check daneben stehen, laeuft der
  v5.3.1-Bug parallel weiter — Markdown-Links als `DEAD`, bei ≤5 **autonom geloescht**.
- ⛔ **Check 6 meldet keine Zeile, die Check 7 verlangt.** `NEVER`+Alternative ist lang, weil
  die Regel es fordert. Zwei Kriterien, die einander ausschliessen, machen das Werkzeug kaputt.
- **Beide Rubriken im Bericht, mit Namen.** `quality-scoring-guide.md` hat eine Notenskala,
  `claudemd-audit-criteria.md` hat **keine** — dort keine Note erfinden.
- **Zahlen kommen kanonisch aus Schritt 2** und werden dem Agent uebergeben, statt dass er
  selbst zaehlt.
