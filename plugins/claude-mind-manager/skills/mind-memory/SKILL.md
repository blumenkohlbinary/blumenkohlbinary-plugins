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

---

### 4.0 SICHTBARKEIT — der wichtigste Check (NEU v6)

⛔ **Der Abruf waehlt pro Anfrage hoechstens FUENF Topic-Dateien aus** — ueber eine
Sonnet-Seitenabfrage, anhand von **Dateiname und `description`**, NICHT anhand des Inhalts.
Alles darueber ist pro Turn unerreichbar, egal wie relevant.

```bash
LIMIT="${MIND_MEMORY_VISIBILITY_LIMIT:-5}"
N=$(ls "$MEMORY_DIR"/*.md 2>/dev/null | grep -v '/MEMORY\.md$' | wc -l)
[ "$N" -gt "$LIMIT" ] && echo "SICHTBARKEIT: $N Topic-Dateien, $LIMIT sichtbar, $((N-LIMIT)) pro Anfrage UNSICHTBAR"
```

⚠ **`MEMORY.md` zaehlt NICHT mit** — der Index wird ohnehin immer geladen und steht nicht zur
Auswahl. Wer ihn mitzaehlt, meldet eine Datei zu viel.

✅ **Die Zahl 5 ist am installierten Binaerprogramm VERIFIZIERT** (Claude Code 2.1.237,
21.08.2026). Der Anweisungstext des Auswaehlers steht dort woertlich, direkt daneben sein
Modell (`claude-opus-5`): *„Return a list of filenames for the memories that will clearly be
useful … **(up to 5)**. Only include memories that you are certain will be helpful **based on
their name and description**."* Der Regler `MIND_MEMORY_VISIBILITY_LIMIT` bleibt, falls sich
die Zahl in einer kuenftigen Version aendert. **Nachpruefbar mit `/context`** — dort steht
unter „Memory files", welche Dateien wirklich geladen wurden.

⚠ **Die Grenze gilt PRO ANFRAGE, nicht pro Sitzung.** Derselbe Anweisungstext sagt: *„Do not
re-select memories you already returned for an earlier query in this conversation."* Ueber ein
langes Gespraech sammelt sich die Abdeckung also an. Die Rechnung „40 Dateien, Grenze 5, also
88 % unerreichbar" ist fuer den einzelnen Prompt richtig und fuer den Tag falsch — **der
Bericht muss das dazusagen**, sonst treibt er zu einer Verdichtung, die niemand braucht.

**Schwellen fuer die Dateizahl** (bis v5.9.3 gab es dafuer gar keine — deshalb wuchs der
Bestand ungebremst):

| Anzahl Topic-Dateien | Stufe | Was der Skill tut |
|---|---|---|
| bis `LIMIT` (5) | optimal | nichts |
| bis 3x`LIMIT` (15) | akzeptabel | Hinweis im Bericht |
| bis 6x`LIMIT` (30) | Warnung | Zusammenfuehrungs-Gruppen **vorschlagen** |
| ueber 6x`LIMIT` (30) | kritisch | Zusammenfuehren **anwenden**, Gates aus 4.0c, max 5 je Lauf |

⛔ **Sichtbarkeit ist notwendig, nicht hinreichend.** GitHub-Issue #37586: eine Erinnerung war
geladen und trotzdem wirkungslos — Memory ist *„context, not enforced configuration"*. Fuer
erzwingbares Verhalten braucht es `PreToolUse`-Hooks. **Der Bericht darf keine Garantie
behaupten, die es nicht gibt.**

### 4.0b `description`-Qualitaet — der einzige Hebel auf Sichtbarkeit

⛔ **Zwei Klassen trennen (NEU v5.7.1, gemeldet aus dem Zustellplan-Lauf).** Bis dahin wurde
eine Datei **ganz ohne Frontmatter** einfach als „ohne `description`" gezaehlt. Das ist der
schwerere Fall und gehoert getrennt ausgewiesen:

| Fall | Folge |
|---|---|
| `description` fehlt, Frontmatter vorhanden | schwaches Signal fuer den Auswaehler |
| **gar kein Frontmatter** | die Datei zaehlt **voll gegen das Byte-Budget** — nichts wird abgeschnitten, und der Auswaehler hat ueberhaupt kein Signal |

**Im Bericht beide Zahlen getrennt nennen.** Eine Summe verdeckt, dass der zweite Fall teurer
ist. ⚠ Nicht mit einem **offenen** Frontmatter verwechseln (erste Zeile `---`, keine zweite) —
das ist wieder ein anderer Fall und gehoert zu `mind-rules`.

| Pruefung | Schwelle | Klasse |
|---|---|---|
| `description` fehlt | — | **Befund** — die Datei ist praktisch unsichtbar |
| `description` zu kurz | < `MIND_MEMORY_DESC_MIN` (40) | **Befund** |
| nur generische Woerter (`Notizen`, `Infos`, `Sonstiges`) | Wortliste | Hinweis |
| zwei Beschreibungen zu aehnlich | Ueberlappung > 70 % | Hinweis |

```bash
for f in "$MEMORY_DIR"/*.md; do
  case "$f" in */MEMORY.md) continue;; esac
  D=$(sed -n 's/^description:[[:space:]]*//p' "$f" | head -1)
  [ -z "$D" ] && echo "BEFUND ohne description: $(basename "$f")"
  [ -n "$D" ] && [ ${#D} -lt "${MIND_MEMORY_DESC_MIN:-40}" ] && echo "BEFUND description zu kurz (${#D}): $(basename "$f")"
done
```

**Dateiname ist das zweite Signal.** Generische Namen (`notes-2.md`) verschenken die Haelfte.
**Hinweis, nie automatisch umbenennen** — der Index zeigt auf den Namen.

⛔ **Folge fuer den Fix-Typ „Offload to topic file":** Auslagern **erhoeht** die Dateizahl.
Liegt der Bestand ueber dem Limit, muss der Vorschlag die **neue `description` mitliefern** —
sonst verschiebt er Inhalt in die Unsichtbarkeit. Oberhalb des Limits ist **Zusammenfuehren**
oft besser.

✅ **Seit v5.10.0 fuehrt der Skill autonom zusammen** (Nutzer-Entscheidung 21.08.2026),
gegen die vier Gates in 4.0c. Bis dahin galt „nur Vorschlag" — und das Ergebnis war eine
**Einbahnstrasse**: gemessen im Zustellplan **40 Topic-Dateien bei gruenem Budget**
(MEMORY.md 66/200 Zeilen, 16,9 KB/25 KB). Weil MEMORY.md gesund war, entstand nirgends
Druck; der einzige Hebel, der die Dateizahl bewegte, war `Offload` — **und der erhoeht
sie**. Jeder Lauf konnte hinzufuegen, keiner wegnehmen.

### 4.0c Zusammenfuehren und Aufteilen — die vier Gates (NEU v5.10.0)

Beides ist **inhaltliche** Arbeit, kein Textverschieben. Autonom deshalb nur, wenn **alle
vier** Gates halten; bricht eines, bleibt es beim Vorschlag.

| Gate | Pruefung | Warum |
|---|---|---|
| **1 · Erhaltung** | Inhaltszeilen vorher == nachher (Frontmatter ausgenommen) | Verdichten ja, fallen lassen nein. Was weg soll, ist ein **eigener** Fix-Typ (`Remove stale entry`) mit eigenem Berichtseintrag — sonst verschwindet Wissen unter der Ueberschrift „aufgeraeumt" |
| **2 · Kein Umbenennen** | zusammengefuehrt wird **in eine der beiden bestehenden Dateien**, nie in eine dritte, neue | Der Index zeigt auf den Dateinamen, und `originSessionId` verknuepft ihn mit einer Sitzung |
| **3 · Verweise** | nach dem Lauf zeigt **kein** `[[name]]` mehr auf eine entfernte Datei — weder im Bestand noch in MEMORY.md | Ein toter Wikilink ist genau die Unsichtbarkeit, die der Fix beseitigen sollte |
| **4 · Beschreibung** | die ueberlebende `description` nennt **beide** Themen, 40-200 Zeichen | Der Auswaehler sieht **nur** Name und Beschreibung. Nennt sie nur das eine Thema, ist das andere unauffindbar — dann ist der Merge ein Verlust, kein Aufraeumen |

⛔ **Zusammengefuehrt wird, was thematisch zusammengehoert — nie, um eine Zahl zu druecken.**
Das Urteil darueber traut der autonome Modus dem Skill ausdruecklich zu; die Zahl allein ist
kein Grund. Zwei unverwandte Erinnerungen in einer Datei sind **schlechter** auffindbar als
zwei getrennte: der Auswaehler liest eine Beschreibung, und eine Beschreibung, die zwei
fremde Dinge nennt, passt auf keine Anfrage richtig.

**Mengenbegrenzung: hoechstens 5 Zusammenfuehrungen je Lauf.** Ein Lauf, der 40 Dateien auf
12 zusammenzieht, ist im Bericht nicht mehr pruefbar — und der naechste Lauf macht weiter.

---

1. **Budget-Check**: MEMORY.md gegen **ZWEI** Grenzen (NEU v6).

   | Grenze | Wert | gilt ab |
   |---|---|---|
   | Zeilen | **200** | seit jeher (`DH=200` im Bundle v2.1.81 belegt) |
   | **Bytes** | **25 KB** | **ab v2.1.198** — aeltere Versionen kennen sie nicht |

   Es gilt, **was zuerst kommt**. Schwellen: optimal `<150` (`<19 KB`) · akzeptabel `<180`
   (`<22 KB`) · Warnung `180-195` (`22-24 KB`) · kritisch `>195` (`>24 KB`).

   ```bash
   L=$(wc -l < "$MEMORY_DIR/MEMORY.md"); B=$(wc -c < "$MEMORY_DIR/MEMORY.md")
   CCV=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
   ```

   ⚠ **Der Byte-Check gilt erst ab v2.1.198.** Bei aelterer Version als **Hinweis** ausgeben
   („greift in dieser Version noch nicht"), nicht als Befund — sonst meldet der Skill ein
   Limit, das die laufende Version gar nicht hat.

   ⚠ **Ab v2.1.211** werden YAML-Frontmatter und Block-HTML-Kommentare vor dem Laden entfernt
   und zaehlen nicht mit. Bei Zweifel **beide** Rechnungen ausweisen.

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

   ⚠ **Claude Code kennzeichnet alte Erinnerungen SELBST** (NEU v6). Beim Lesen wird ab
   mehr als einem Tag vorangestellt: *„This memory is N days old. Memories are point-in-time
   observations, not live state — claims about code behavior or file:line citations may be
   outdated."* **Nicht melden, was das System schon kennzeichnet.** Der Check zielt auf das,
   was die Warnung NENNT, aber nicht prueft: **`file:line`-Zitate und Versionsnummern in
   Dateien aelter als `MIND_MEMORY_STALE_DAYS` (Vorgabe 14)** — und ob sie noch stimmen.

### 6. Index-Integritaet — DREI Klassen, nicht zwei (NEU v6)

| Klasse | Bedeutung | Fix |
|---|---|---|
| `TOT` | Datei existiert nirgends | Zeile korrigieren oder entfernen |
| **`PRAEFIX`** | Datei existiert, der Zeiger hat ein Verzeichnis davor (`memory/datei.md` statt `datei.md`) | **Praefix entfernen — NICHT die Zeile loeschen** |
| `VERWAIST` | Datei ohne Zeiger im Index | Zeile ergaenzen |

```bash
grep -o '](\([^)]*\.md\))' "$MEMORY_DIR/MEMORY.md" | sed 's/](//;s/)//' | while read -r z; do
  [ -f "$MEMORY_DIR/$z" ] && continue
  b=$(basename "$z")
  if [ -f "$MEMORY_DIR/$b" ]; then echo "PRAEFIX: $z -> $b"; else echo "TOT: $z"; fi
done
```

⛔ **Eine reine Existenzpruefung meldet `PRAEFIX` als „fehlt"** — und ein autonomer Fix wuerde
die Zeile dann **loeschen** statt sie zu reparieren. Dieselbe Fehlerklasse wie der
v5.3.1-Beinahe-Schaden bei den Pfaden.

**Nach jedem Index-Umbau die Zeiger nachpruefen — ein Arbeitsschritt, nicht zwei.**

### 7. Zeiger von AUSSERHALB (NEU v6)

Globale Regeln koennen auf Erinnerungen zeigen, die nur in EINEM Projekt existieren:
`~/.claude/rules/plan-mode.md` verweist auf `memory/km-dynamic-must-stay.md` — vorhanden nur im
Zustellplan-Projekt. Aus 17 von 18 Projekten zeigt das ins Leere, und der Pfad `memory/…` ist
ohne Projektbezug **prinzipiell nicht aufloesbar**.

```bash
grep -rn 'memory/[a-z0-9-]*\.md' "$HOME/.claude/rules/" "$HOME/.claude/CLAUDE.md" 2>/dev/null
```

⚠ **Hinweis, kein Befund** — die Datei liegt ausserhalb unserer Zustaendigkeit, und sie zu
aendern ist eine Nutzerentscheidung.

### 8. Frontmatter (NEU v6)

| Feld | fehlt oder ungueltig -> |
|---|---|
| `name`, `description`, `type` (aus `user`/`feedback`/`project`/`reference`) | **Befund** |
| `node_type`, `originSessionId`, `modified` | **Hinweis** |

⛔ **`node_type` und `originSessionId` sind NICHT offiziell dokumentiert** — nur durch
Datei-Lektuere belegt (91 von 91 realen Dateien). Auch die vier `type`-Werte sind nicht
offiziell enumeriert. **Kein Punktabzug**, solange ihre Rolle ungeprueft ist.

### ✅ Frontmatter ergaenzen — autonom seit v5.11.0

Bis v5.10.0 wurde das nur **gemeldet**. Die Fix-Tabelle hatte acht Eintraege und keinen
dafuer — **gemessen lagen in `APP - Zustellplan` 7 Dateien ohne jedes Frontmatter**:
dauerhaft unsichtbar, und kein Skill konnte sie sichtbar machen. Das ist die haertere
Haelfte eines ueberfuellten Bestands: Zusammenfuehren hilft den Dateien **mit**
Beschreibung, diesen nicht.

⛔ **Der Rumpf wird NICHT angefasst.** Es wird ausschliesslich ein Kopf vorangestellt;
nach dem Fix muss der Inhalt ab der ersten Nicht-Frontmatter-Zeile **byte-gleich** sein.
Das ist mechanisch pruefbar und die Bedingung dafuer, dass dieser Fix autonom laufen darf.

| Feld | woher |
|---|---|
| `name` | Dateiname ohne `.md`. **Nie umbenennen** — der Index zeigt darauf |
| `description` | aus dem Inhalt, **40-200 Zeichen**, sagt WORUM es geht. Der Auswaehler sieht nur dies |
| `metadata.type` | `user` \| `feedback` \| `project` \| `reference` — nach dem Inhalt, nicht nach dem Ordner |

⚠ **Beim `type` zurueckhaltend sein.** `[user]` und `[project]` werden vom Auswaehler
**extra** zurueckhaltend behandelt (am Binaerprogramm belegt, v5.8.1). Eine Methoden-Lehre,
die in jedem Projekt gilt, ist `feedback`; ein blosser Zeiger auf eine externe Quelle ist
`reference`. Im Zweifel `project` — das ist die Vorgabe fuer Projektwissen.

⛔ **Nur bei GAR KEINEM Frontmatter.** Ein vorhandener Kopf mit schwacher `description`
wird **verbessert** (eigener Fix-Typ), nicht ersetzt — und ein Kopf, der Felder traegt,
die dieser Skill nicht kennt (`originSessionId`, `node_type`, `modified`), bleibt
unangetastet.

**Datei ganz ohne Frontmatter = eigener Befundtyp:** Claude Code fuegt **nie** welches hinzu,
wo keines ist. Solche Dateien zaehlen **voll** gegen das Limit (kein Stripping) **und** sind
fuer den Auswaehler fast unsichtbar (keine `description`). **Fix ist ergaenzen, nicht loeschen.**

### 9. Sammeldateien (NEU v6)

Fuer Topic-Dateien gibt es **kein hartes Limit** — nur die Empfehlung „< 200 Zeilen".

**Befund ab > 200 Zeilen ODER > 20 KB** (beide Zweige pruefen, nicht nur einen), mit
Aufteilungsvorschlag.

✅ **Autonom seit v5.10.0** — ueber dieselben vier Gates wie das Zusammenfuehren (4.0c),
**plus eine fuenfte Bedingung**: aufgeteilt wird nur, wenn die Datei wirklich **zwei
unterscheidbare Themen** traegt, und nur, wenn der Bestand danach unter der kritischen
Schwelle bleibt (4.0). Sonst verschlechtert Aufteilen die Sichtbarkeit, ohne etwas zu
gewinnen — es erhoeht die Dateizahl, und die Grenze von 5 gilt pro Anfrage.

⚠ **Im Zweifel nicht aufteilen.** Eine 220-Zeilen-Datei zu einem Thema ist ein kleineres
Problem als zwei 110-Zeilen-Dateien zu anderthalb Themen.

### 10. Sicherheit — OWASP ASI06 (NEU v6)

Der ungeprueft bei jedem Start geladene Speicher faellt unter **ASI06 „Memory and Context
Poisoning"** (OWASP Top 10 for Agentic Applications 2026). Anders als klassische
Prompt-Injection **ueberdauert die Vergiftung Sitzungen**.

**Umsetzung: `mind_scan_poisoning <datei>` aus `lib.sh`** — nicht hier inline. Dieselbe
Bedrohung betrifft `.claude/rules/*.md` und `CLAUDE.md`; einmal gebaut, dreifach nutzbar.

```bash
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
for f in "$MEMORY_DIR"/*.md; do mind_scan_poisoning "$f"; done
# Ausgabe je Fund: BEFUND|<art>|<zeile>|<detail>  bzw.  HINWEIS|...
```

| Muster | Klasse |
|---|---|
| **unsichtbare Unicode-Zeichen** (Zero-Width, Bidi-Steuerzeichen, Tag U+E0000-E007F) | **Befund** |
| Zugangsdaten (`sk-ant-`, `AKIA`, `BEGIN … PRIVATE KEY`, `password=`) | **Befund** |
| `curl`/`wget` auf fremde Hosts, `data:`-URLs mit base64 | **Befund** |
| Anweisungs-Formulierungen **am Zeilenanfang** („ignoriere", „vergiss", „ab jetzt gilt", „system:") | **Hinweis** |

⛔ **Die Wortliste ist bewusst nur ein HINWEIS und ankert am ZEILENANFANG.** Formulierungen
wie „NIEMALS" mitten im Satz sind in anweisungsreichen deutschen Regeldateien Alltag — ohne
Anker waere eine Fehlalarm-Flut der wahrscheinlichste Fehlschlag des ganzen Checks.
**Gemessen 20.08.2026:** ueber alle 18 Bestaende **und** die globalen `~/.claude/rules/*.md`
zusammen **0 Befunde, 0 Hinweise** — bei nachgewiesener Trefferfaehigkeit (eingefuegtes
`U+200B`, `sk-ant-`, `curl https://…` und eine Anweisungszeile wurden alle gefunden).

⛔ **Nur melden, nie automatisch entfernen.** Ein Fehltreffer, der autonom Inhalt loescht,
waere schlimmer als der Fund.

### 11. Widersprueche CLAUDE.md <-> MEMORY.md (NEU v6)

Es gibt **keine Vorrangregel** — offizielle Doku: *„if two rules contradict each other,
Claude may pick one arbitrarily"*. Beide sind *„context, not enforced configuration"*.

⚠ **Anthropic hat den Auftrag selbst formuliert**, im Auto-Dream-Prompt (Flag
`tengu_onyx_plover`, Vorgabe aus): *„Resolve contradictions — if two files disagree, fix the
wrong one."* Wir bauen also keinen neuen Begriff, sondern aktivieren einen vorhandenen.

**Umsetzung:** Aufgabe des `context-analyzer` (Step 3) — semantisch, nicht mechanisch.
Eigene Befundklasse **`KONFLIKT`**, mit **beiden** Fundstellen.

⛔ **NIE autonom aufloesen.** Ein Widerspruch zwischen einer vom Nutzer geschriebenen Regel
und einer von Claude gelernten Erinnerung ist eine inhaltliche Frage, keine mechanische.
Nur melden.

**Abgrenzung zu Check 3/4 (Duplikate):** Ein Duplikat sagt zweimal dasselbe, ein Konflikt sagt
zweimal Verschiedenes. „nutze vitest" gegen „User bevorzugt jest" ist **kein** Duplikat.

### 12. `AUTO-MANAGED`-Marker respektieren (NEU v6)

```markdown
<!-- AUTO-MANAGED: index -->
- [Titel](datei.md) — Aufhaenger
<!-- /AUTO-MANAGED -->
```

Sind solche Marker vorhanden, fassen autonome Fixes **ausschliesslich** den Bereich dazwischen
an. Alles davor und danach bleibt unberuehrt.

⚠ **Rueckwaertskompatibel:** Ohne Marker verhaelt sich der Skill wie bisher (ganze Datei) —
**meldet das aber im Bericht**, damit der Unterschied sichtbar ist.

⛔ **Der Skill legt die Marker NICHT selbst an.** Das waere eine Formatanderung an einer Datei,
die Claudes internes System schreibt. Er schlaegt sie vor, wenn eine `MEMORY.md` von Hand
gepflegte Abschnitte enthaelt (erkennbar an Fliesstext ausserhalb der Zeiger-Liste).

## Step 5: Ergebnisse konsolidieren + praesentieren

Merge agent results with inline checks. Display as:

**PFLICHT-Self-Check-Block am Anfang (NEU v3.3.1):**

```
=== MEMORY.md Audit Report v5.5.0 — Self-Check ===
[Step 3 context-analyzer] Agent dispatched: <N> Findings (Duplicates: <D>, Stale: <S>, Misplaced: <M>, Konflikte: <K>)
  Beleg: context-analyzer Tool-Call #<N>
[Step 4 Inline-Checks] Sichtbarkeit: <T> Topic-Dateien / <L> sichtbar / <U> unsichtbar
  description: <O> ohne, <K> zu kurz  ·  Index: <P> PRAEFIX, <TT> TOT, <V> VERWAIST
  Budget: <X>/200 Zeilen, <B>/25 KB (Byte-Grenze <aktiv|inaktiv, Version <V>>)
  Sicherheit: <SB> Befunde, <SH> Hinweise  ·  AUTO-MANAGED: <ja|nein>
  Beleg: Bash-Tool-Call #<N>
[Step 6c Bestands-Pass v5.22.0] PFLICHT, auch bei leerem Befund
  Dauerkontext: <A> -> <B> Zeilen (<+/-D>) · Anweisungen <A> -> <B> (<+/-D>)
  Bestand: <g>/<s> geprueft · <d> Duplikat · <c> Code-Kandidat · <b> ohne Beleg · <u> UNGEPRUEFT
  ⛔ `(nichts)` ist erlaubt, FEHLEN nicht — ein fehlender Block macht den Lauf zum Teilsync
  Beleg: Bash-Tool-Call #<N>
```

Fehlt der Self-Check-Block oder enthaelt `(SKIPPED)`: User darf zurueckweisen.

**NEU v5.5.0 — Der Bericht beginnt mit der Sichtbarkeit, nicht mit dem Budget:**

```
=== MEMORY.md Audit Report v5.5.0 ===

SICHTBARKEIT
  40 Topic-Dateien · 5 werden pro Anfrage ausgewaehlt · 35 UNSICHTBAR
  Die Auswahl erfolgt ueber Dateiname + description, nicht ueber den Inhalt.
  -> 7 Dateien ohne description sind praktisch unauffindbar.
  ⚠ Grenze 5 aus Quellcode-Leak v2.1.88, hier NICHT verifiziert.
     Nachpruefen mit /context (Abschnitt "Memory files").
  ⚠ Sichtbarkeit ist notwendig, nicht hinreichend: eine geladene Erinnerung
     kann ignoriert werden (Issue #37586). Fuer Garantien: PreToolUse-Hooks.

BUDGET
  Zeilen  66/200   OK
  Bytes   16747/25600  WARNUNG (65 %) — Byte-Grenze INAKTIV in v2.1.81

--- BEFUNDE (werden angewendet) ---
[1] BEFUND   ohne-description   routen-auftrag-laufend.md    -> unsichtbar fuer die Auswahl
[2] BEFUND   PRAEFIX            MEMORY.md:7                  -> "memory/x.md" -> "x.md"
[3] BEFUND   sammeldatei        lessons.md (59 622 B)        -> Aufteilung VORSCHLAGEN

--- HINWEISE (kein Punktabzug, nichts wird angewendet) ---
[H1] node_type fehlt in 2 Dateien — nicht offiziell dokumentiert, nur beobachtet
[H2] globale Rule zeigt auf memory/km-dynamic-must-stay.md (nur im Zustellplan vorhanden)
[H3] KONFLIKT: CLAUDE.md:12 "nutze vitest" <-> memory/tools.md:4 "User bevorzugt jest"
```

⛔ **Befunde und Hinweise nie in einer Liste mischen** — sonst stehen harte Messungen neben
Verdachtsmomenten, und der Leser kann beides nicht trennen. Dieselbe Regel wie in
`/mind-claudemd` v5.4.0.

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
| Offload to topic file | Write + Edit | Write new topic file, remove section from MEMORY.md. ⛔ **Erhoeht die Dateizahl** — ab der kritischen Schwelle (4.0) stattdessen zusammenfuehren |
| **Topic-Dateien zusammenfuehren** (NEU v5.10.0) | Read + Edit + Bash | Inhalt von B nach A, `description` von A um Bs Thema erweitern, `[[b]]`-Verweise auf `[[a]]` ziehen, B loeschen, MEMORY.md-Zeile entfernen. **Vier Gates aus 4.0c sind Pflicht**, max 5 je Lauf |
| **Topic-Datei aufteilen** (NEU v5.10.0) | Read + Write + Edit | Nur ab 200 Zeilen / 20 KB **und** nur bei zwei unterscheidbaren Themen. Gates aus 4.0c + Abschnitt 9 |
| Compress verbose | Edit | Replace multi-sentence with concise bullet |
| **Frontmatter ergaenzen** (NEU v5.11.0) | Read + Edit | Datei ganz ohne Frontmatter bekommt einen Kopf: `name` aus dem Dateinamen (ohne `.md`), `description` aus dem INHALT, `metadata.type` nach der Tabelle unten. **Der Rumpf bleibt byte-gleich** — es wird nur vorangestellt |

## Step 6c: ⛔ Der Bestands-Pass — PFLICHT, auch bei leerem Befund (NEU v5.22.0)

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
| **Bereich** | `MEMORY.md` **und** die Topic-Dateien im Memory-Verzeichnis |
| **`--skill`** | `mind-memory` |
| **schon verdrahtet** | ⛔ **nichts** — dieser Skill hatte bisher keinen einzigen Cleaner-Aufruf |
| **neu in diesem Schritt** | **alles**: `cleaner_duplikate` · `cleaner_belege` · `cleaner_aussagen --code` |

```bash
[ -n "$CLAUDE_PLUGIN_ROOT" ] || { echo "ERROR: $CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 1; }
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"

# 1) PFLICHTZEILE — sie MUSS woertlich in den Self-Check-Block des Berichts.
#    ⛔ Nicht nur erwaehnen: die Zeile selbst, mit beiden Zahlenpaaren.
mind_kontext_bilanz "$PROJ" --vergleichen

# 2) Stichprobe: 3 Einträge, die am längsten ungeprüft sind (max. 15 je Kettenlauf)
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_stichprobe.py" "$PROJ" \
       --skill mind-memory --verzeichnis "$MEMORY_DIR"

# 3) je Eintrag die drei Fragen — siehe Referenz, EINE Berichtszeile je Eintrag

# 4) Quittung — ohne sie gilt der Lauf als Teilsync
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_stichprobe.py" "$PROJ" \
       --quittung --skill mind-memory --geprueft <n> --stichprobe <n>
```

⛔ **Hier gilt die Inhaltssperre besonders scharf.** Dieser Skill liest fremde
Memory-Bestände; in `APP - Zustellplan` stehen dort **Abonnenten-, Routen- und
Geschäftsdaten**, und `mind_debug_write` schickt Befundtexte in den **gemeinsamen**
Debug-Ordner aller Projekte.

> **Ort und Klasse melden, nie Inhalt.** `thema-x.md:12 doppelt zu thema-y.md:4` —
> **niemals die Zeile selbst.** `cleaner_stichprobe.py` kennt ausschließlich Pfade
> und hat auf Inhalte gar keinen Zugriff; das ist die mechanische Hälfte. Die andere
> Hälfte bist du.

⚠ **Topic-Dateien zählen NICHT in die Dauerkontext-Bilanz** — sie laden höchstens 5
pro Anfrage. Ihr Wuchs kostet **Auffindbarkeit**, nicht Tokens. Für sie ist die
richtige Frage nicht *wie groß*, sondern: **ist die `description` scharf genug, dass
der Auswähler sie findet?** Er sieht **nur** Name und Beschreibung, nie den Inhalt.

⛔ **Ein FEHLENDER Block macht den Lauf zum Teilsync.** `(nichts)` ist eine gültige
Antwort — leerer Bestand, neues Projekt, Laufbudget erschöpft. **Schweigen ist es nicht.**
Ein Skill, der schweigt weil sein Bestand sauber ist, und einer, der schweigt weil der Pass
ausfiel, sehen von außen identisch aus. Dieselbe Lehre wie v5.3.1 und die Agent-Quittung.

⚠ **Fail-open:** fehlt ein Werkzeug oder stürzt es ab, wird `UNGEPRUEFT: <werkzeug>`
gemeldet und der Skill **läuft weiter**. Ein Bestands-Pass darf nie einen Sync töten.

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

### NEU v6

- ⛔ **NIEMALS eine Umgebungsvariable oder einen `settings.json`-Schluessel schreiben** — auch
  nicht „hilfsweise", auch nicht bei `--auto`. **Warum das eine harte Regel ist:** Das Plugin
  `claude-mem` setzte bei der Installation still `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`
  (Issue #2836) — **75 native Memory-Dateien waren ueber Nacht unsichtbar**, nicht geloescht,
  aber nicht mehr geladen, ohne Rueckfrage. Ein Memory-Werkzeug, das die Memory-Umgebung
  still umstellt, ist die schlimmste Form von Nebenwirkung.
- **Zusammenfuehren und Aufteilen sind seit v5.10.0 autonom erlaubt** — aber **nur** gegen
  die vier Gates aus 4.0c (Erhaltung · kein Umbenennen · keine toten `[[Verweise]]` ·
  Beschreibung nennt beide Themen), hoechstens 5 je Lauf. ⛔ **Bricht ein Gate, bleibt es
  beim Vorschlag.** Und ⛔ **nie zusammenfuehren, um eine Zahl zu druecken** — nur, was
  thematisch zusammengehoert.
- ⛔ **NIEMALS eine Datei umbenennen** — der Index zeigt auf den Dateinamen, und
  `originSessionId` verknuepft ihn mit einer Sitzung.
- ⛔ **Keine Inhalte fremder Memory-Bestaende** in Berichte, Logs oder Commits. Nur Struktur,
  Groessen, Feldnamen. In den realen Bestaenden stehen Abonnenten-, Routen- und
  Geschaeftsdaten.
- **`PRAEFIX`-Befunde werden repariert, nicht geloescht** — die Datei existiert ja.
- **Der Bericht behauptet keine Wirkung, nur Sichtbarkeit.** Memory ist „context, not enforced
  configuration"; eine geladene Erinnerung kann ignoriert werden (Issue #37586).
