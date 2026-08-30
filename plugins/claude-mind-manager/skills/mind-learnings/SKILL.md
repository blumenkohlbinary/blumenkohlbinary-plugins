---
name: mind-learnings
description: |
  [Mind Manager] Prueft ALLE Projekte unter KOHLEKTIV auf strukturelle Probleme —
  Memory ohne `description`, offenes Frontmatter, `globs:` ohne Treffer, ueberlange
  CLAUDE.md, tote Werkzeuge, Arbeitsmaterial im Memory — und meldet die Befunde in
  den zentralen Debug-Ordner, der die Wiederholungserkennung traegt.

  Laeuft UNABHAENGIG von /mind-all und AENDERT NICHTS. Nur lesen und melden.

  Use when the user says "mind learnings", "learnings sammeln", "alle projekte
  pruefen", "was ist ueberall kaputt", or "/mind-learnings".
allowed-tools: Bash, Read, Glob, Grep
---

# Projektuebergreifende Strukturpruefung

## ⛔ PFLICHTSCHRITTE — dieser Skill fuehrt aus, was hier steht (NEU v5.25.0)

```
PFLICHTSCHRITTE
learnings_quellen
learnings_scan
mind_debug_write
```

**Vor dem ersten Schritt, ohne Ausnahme:**

```bash
mind_schritt_start "$PROJ" mind-learnings learnings_quellen learnings_scan mind_debug_write
```

**Nach JEDEM Schritt** — auch nach einem, der entfaellt:

```bash
mind_schritt <name> gelaufen              "$(wc -c < "$AUSGABE")" "$PROJ"
mind_schritt <name> "gelaufen:5/11"       "$BYTES" "$PROJ"   # TEILABDECKUNG
mind_schritt <name> "uebersprungen:<grund>" 0      "$PROJ"
mind_schritt <name> "fehler:<grund>"      -1       "$PROJ"
```

⛔ **`uebersprungen` ist ein gueltiger Status und braucht einen GRUND.** Ein Schritt,
der legitim entfaellt (`--dry-run`, kein Git, kein Quellbaum), ist kein Fehler — aber
sein Entfallen gehoert in den Bericht statt zu verschwinden.

⭐ **`gelaufen:5/11` ist die TEILABDECKUNG und der Anlass dieses Baus.** Am 30.08.2026
lief `cleaner_leitplanke.py` ueber 5 von 11 Dateien und wurde als **Bereichspruefung**
berichtet. Der Fehler war nicht ein fehlender Aufruf, sondern ein gelaufener, der
weniger abdeckte als der Bericht behauptete. `5/11` ist eine gueltige Antwort;
sie als `11/11` zu berichten ist es nicht.

⛔ **Die Bytezahl ist Pflicht, wo ein Schritt etwas ausgeben MUSS.** Am selben Tag
lief `cleaner_belege.py` und seine Ausgabe wurde weggegreppt — aus Sicht einer
naiven Quittung waere das „gelaufen". `0` meldet die Bilanz als **LEER**; `-1`
heisst „nicht gemessen" und zaehlt nicht.

**Im Bericht, als erste Zeile des Self-Checks:**

```bash
mind_schritt_bilanz "$PROJ"
```

⛔ **Fehlt diese Zeile oder nennt sie `FEHLT`, ist der Bericht unvollstaendig** und
darf zurueckgewiesen werden. Rueckgabe **2 heisst: gar keine Quittung** — der Lauf
hat nie begonnen zu quittieren, und das ist NICHT „nichts zu melden".

⚠ **Was die Quittung nicht kann:** sie erzwingt keinen Schritt, sie macht sein Fehlen
sichtbar — wie `decision:block` und die Agent-Quittung. Und sie misst nicht die GUETE:
ein Werkzeug, das laeuft und Unsinn liefert, quittiert als `gelaufen`.

## Warum es diesen Skill gibt — und warum er NICHT das tut, was der Name vermuten laesst

Der urspruengliche Plan war ein Uebertrag von **Lehren** zwischen Projekten. Die
Phase-0-Messung am 21.08.2026 hat ihn widerlegt:

```
207 Bulletpoints aus Lehr-Abschnitten (6 Projekte)
104 Uebertrags-Kandidaten
 26 mit Evidenz aus >= 2 Projekten UND >= 2 Laeufen
 21 nicht schon global gedeckt
~ 3 beim EINZELNEN Nachlesen echte uebertragbare Lehren
```

Die staerksten drei standen **bereits woertlich** in der globalen `CLAUDE.md`. Das
bestehende Verfahren funktioniert also — was uebertragbar war, ist laengst von Hand
dort gelandet. Ein Sammler daneben haette den Bodensatz eingesammelt.

⛔ **Was NICHT gefuellt ist: strukturelle Befunde ueber Projekte hinweg.** Die entstehen
heute nur, wenn in einem Projekt zufaellig `/mind-all` laeuft. Ein Projekt ohne Lauf
meldet nichts — und niemand sieht, dass dort Memory-Dateien ohne `description` liegen.

Am 21.08.2026 hat der Debug-Kanal **vier echte Plugin-Fehler aus fremden Projekten**
geliefert. Er funktioniert; er war nur zu schmal gespeist. Dieser Skill speist ihn breiter.

## Step 1: Vorbedingungen

```bash
[ -z "$CLAUDE_PLUGIN_ROOT" ] && { echo "ERROR: \$CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 1; }
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"

WURZEL="${MIND_LEARNINGS_ROOT:-C:/CD/KOHLEKTIV}"
[ -d "$WURZEL" ] || { echo "ERROR: Wurzel nicht gefunden: $WURZEL" >&2; exit 1; }

if [ -z "${MIND_DEBUG_DIR:-}" ]; then
  echo "HINWEIS: MIND_DEBUG_DIR ist nicht gesetzt — der Bericht entsteht, wird aber"
  echo "         NICHT zentral gemeldet. Die Variable setzt der MENSCH von Hand in"
  echo "         ~/.claude/settings.json; das Plugin setzt sie nie selbst."
fi
```

⛔ **Das Plugin setzt `MIND_DEBUG_DIR` NIE selbst.** `claude-mem` (#2836) hat auf diesem
Weg 75 Erinnerungen unsichtbar gemacht. Ein Werkzeug, das seine eigenen Regler stellt,
nimmt dem Menschen die Kontrolle ueber etwas, das er nicht mehr sieht.

## Step 2: Pruefen (nur lesen)

```bash
TS=$(date '+%Y-%m-%dT%H:%M:%S')
TMP=$(mktemp -d)
PY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)

BESTAND="${MIND_LEARNINGS_BESTAND:-$WURZEL/Plugin - Entwicklung/Claude Mind Manager/Learnings/bestand.md}"
mkdir -p "$(dirname "$BESTAND")" 2>/dev/null

"$PY" "$CLAUDE_PLUGIN_ROOT/references/learnings_scan.py" "$WURZEL" \
      --jsonl   "$TMP/befunde.jsonl" \
      --bericht "$TMP/bericht.md" \
      --bestand "$BESTAND" \
      --ts      "$TS"
```

⛔ **Der Pruefer AENDERT NICHTS.** Er liest, er meldet. Wer einen Befund behebt,
entscheidet der Mensch — und zwar in dem Projekt, dem er gehoert.

### Was er durchsucht — und was er ausdruecklich NICHT betritt

| gesucht wird in | |
|---|---|
| `CLAUDE.md`, `.claude/CLAUDE.md`, `AGENTS.md` | je Projekt |
| `.claude/rules/**` | **rekursiv**, auch Unterordner |
| `.claude/skills/**`, `agents/**`, `commands/**` | |
| `.claude/hooks/*` | `.sh`, `.py`, `.json`, `.md` |
| Memory-Verzeichnis | ueber die Slug-Regel aufgeloest |

⛔ **Die Projektsuche ist voll rekursiv — mit einer sorgfaeltigen Ausschlussliste.**
Gemessen 21.08.2026: blosse Rekursion fand **57** Projekte statt 23. Die 34
Ueberzaehligen kamen aus `.claude-mind/backups/` und `snapshots/` — den Sicherungen
des Plugins selbst. Jede Lehre haette dort ein halbes Dutzend Mal gestanden, und ein
Schnappschuss haette als eigenes Projekt gegolten.

> **Wer rekursiv sucht, muss ebenso sorgfaeltig ausschliessen.** Die Liste steht in
> `references/learnings_quellen.py` (`AUS`); jeder Eintrag hat einen Grund.

Ausgeschlossen: `.claude-mind` · `_claude_backups` · `Beispiele` · `cache` ·
`bundled-skills` · `worktrees` · `archive` · `node_modules` · `.git` · `dist` ·
`build` · `.venv` · `target` · `vendor` · alles mit `_` am Anfang.

## Step 3: Nach Debug melden (PFLICHT, wenn `MIND_DEBUG_DIR` gesetzt ist)

```bash
if [ -n "${MIND_DEBUG_DIR:-}" ] && [ -s "$TMP/befunde.jsonl" ]; then
  mind_debug_write "$WURZEL" "mind-learnings" "$TMP/bericht.md" "$TMP/befunde.jsonl"
  echo "Zentral gemeldet: $MIND_DEBUG_DIR/laeufe/ + index.jsonl"
  echo "Auswertung neu erzeugt: $MIND_DEBUG_DIR/BEFUNDE.md"
fi
rm -rf "$TMP"
```

**Die Wiederholungserkennung ist der eigentliche Zweck.** `BEFUNDE.md` markiert ab dem
**zweiten** Vorkommen einer Ursachenklasse `WIEDERHOLT` — und trennt nach Zustaendigkeit
(Plugin gegen Projekt). Ein Befund, der in drei Projekten auftaucht, ist ein
Konstruktionsfehler, kein Einzelfall.

## Step 4: Bericht

```
=== /mind-learnings — Strukturpruefung ===
Wurzel   : <pfad>
Projekte : <N> geprueft, <M> mit Befunden
Befunde  : <K>

<je Projekt: Klasse + Kurztext>

Ohne Befund: <Liste>

Zentral gemeldet: <MIND_DEBUG_DIR>/index.jsonl (<K> Zeilen)
Wiederholungen  : siehe <MIND_DEBUG_DIR>/BEFUNDE.md
```

⚠ **Ein Projekt ohne Befund ist nicht dasselbe wie ein Projekt, das nicht geprueft
wurde.** Deshalb nennt der Bericht beide Listen. Der erste Stand des Pruefers stieg
nicht unter Projekte ab, die selbst schon ein `.claude/` hatten — sieben Projekte
fehlten dadurch **vollstaendig**, ohne dass es der Ausgabe anzusehen war.

## Hard Constraints

- **Nur lesen.** Der Skill schreibt ausschliesslich nach `MIND_DEBUG_DIR` und in
  temporaere Dateien. Kein Projekt wird veraendert.
- **`MIND_DEBUG_DIR` niemals selbst setzen** — siehe Step 1.
- **Keine Agents.** Die Pruefung ist deterministisch; ein Agent brauchte hier nur
  Tokens und koennte falsch berichten.
- **Fremde Projekte nur lesen, nie schreiben** — auch dann nicht, wenn ein Befund
  trivial zu beheben waere. In einem fremden Projekt kann eine laufende Sitzung
  arbeiten; ein Eingriff von aussen ist dort nicht sichtbar.
- **Beide Listen im Bericht** (mit und ohne Befund), damit ein uebersprungenes Projekt
  auffaellt.

## Was dieser Skill ausdruecklich NICHT tut

| Nicht | Warum |
|---|---|
| Lehren zwischen Projekten uebertragen | gemessen widerlegt: ~3 echte Kandidaten, alle schon global vorhanden |
| Memory-Dateien zusammenfuehren | inhaltliche Arbeit an Nutzerdaten — das entscheidet der Mensch |
| Befunde beheben | in einem fremden Projekt kann eine Sitzung laufen |
| Automatisch laufen | getaktetes Sammeln ohne Leser ist genau der Weg, auf dem der Vorgaenger starb |
