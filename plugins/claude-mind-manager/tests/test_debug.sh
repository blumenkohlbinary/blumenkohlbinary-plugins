#!/bin/bash
# Pruefstand fuer den zentralen Debug-Ordner (Teil 2, v5.7.0).
#
# Die entscheidende Frage ist NICHT "wird geschrieben?", sondern:
#   Erkennt die Auswertung eine WIEDERHOLUNG ueber Projektgrenzen hinweg?
# Dazu gehoert zwingend die Gegenprobe: zwei VERSCHIEDENE Klassen duerfen es NICHT melden.

# Respektiert eine bereits gesetzte Wurzel. Bis v5.7.5 stand hier eine harte Zuweisung
# auf den QUELLBAUM — damit lief diese Sammlung nie am gebauten Paket, entgegen ihrer
# eigenen README und entgegen fertig-heisst-fertig.md 1.
export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-C:/CD/KOHLEKTIV/Plugin - Entwicklung/hackj-plugins/plugins/claude-mind-manager}"
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"

ok=0; rot=0
pruef() {
  if [ "$2" = "$3" ]; then echo "  [ok ] $1"; ok=$((ok+1))
  else echo "  [ROT] $1 — erwartet '$3', bekommen '$2'"; rot=$((rot+1)); fi
}

T=$(mktemp -d)

# --- 0 · Vorgabe ist AUS -----------------------------------------------------
unset MIND_DEBUG_DIR
printf '# Bericht\n' > "$T/bericht.md"
: > "$T/befunde.jsonl"
mind_debug_write "/pfad/projekt-a" "test" "$T/bericht.md" "$T/befunde.jsonl"
pruef "ohne MIND_DEBUG_DIR wird NICHTS angelegt" "$(ls "$T" | grep -c laeufe)" "0"

# --- 1 · zwei Projekte, DIESELBE Klasse -> WIEDERHOLT ------------------------
export MIND_DEBUG_DIR="$T/debug"
printf '{"ts":"2026-08-20 10:00","projekt":"/x/projekt-a","klasse":"instrument-nachgebaut","kurz":"classify_path nachgebaut","lauf":"L1"}\n' > "$T/b1.jsonl"
printf '{"ts":"2026-08-21 11:00","projekt":"/y/projekt-b","klasse":"instrument-nachgebaut","kurz":"Pipeline erneut nachgebaut","lauf":"L2"}\n' > "$T/b2.jsonl"
mind_debug_write "/x/projekt-a" "Kompaktierung" "$T/bericht.md" "$T/b1.jsonl"
mind_debug_write "/y/projekt-b" "Handaufruf"    "$T/bericht.md" "$T/b2.jsonl"

pruef "Berichte je Lauf abgelegt" "$(ls -1 "$MIND_DEBUG_DIR/laeufe" 2>/dev/null | wc -l | tr -d ' ')" "2"
pruef "index.jsonl hat 2 Zeilen"  "$(wc -l < "$MIND_DEBUG_DIR/index.jsonl" | tr -d ' ')" "2"
pruef "BEFUNDE.md erzeugt"        "$([ -f "$MIND_DEBUG_DIR/BEFUNDE.md" ] && echo ja || echo nein)" "ja"
# Der Marker steht EINMAL, in der Klassen-Ueberschrift. Die Tabelle darueber nutzt
# Fettschrift statt des Wortes — meine erste Erwartung (2) war falsch kalibriert, nicht der Code.
pruef "WIEDERHOLT-Marker an der Klasse"  "$(grep -c 'WIEDERHOLT' "$MIND_DEBUG_DIR/BEFUNDE.md" 2>/dev/null)" "1"
pruef "Wiederholungs-Tabelle nennt 2x"   "$(grep -c '| \*\*instrument-nachgebaut\*\* | \*\*2' "$MIND_DEBUG_DIR/BEFUNDE.md" 2>/dev/null)" "1"
pruef "Warnung ab 3 Vorkommen steht da"  "$(grep -c 'Konstruktionsfehler' "$MIND_DEBUG_DIR/BEFUNDE.md" 2>/dev/null)" "1"
pruef "beide Projekte genannt"    "$(grep -c 'projekt-a.*projekt-b\|projekt-b.*projekt-a' "$MIND_DEBUG_DIR/BEFUNDE.md" 2>/dev/null)" "1"

# --- 2 · GEGENPROBE: zwei VERSCHIEDENE Klassen -> KEIN WIEDERHOLT ------------
export MIND_DEBUG_DIR="$T/debug2"
printf '{"ts":"2026-08-20 10:00","projekt":"/x/a","klasse":"windows-pfad","kurz":"MSYS-Pfad","lauf":"L1"}\n' > "$T/c1.jsonl"
printf '{"ts":"2026-08-21 11:00","projekt":"/y/b","klasse":"zeilenenden","kurz":"CRLF","lauf":"L2"}\n' > "$T/c2.jsonl"
mind_debug_write "/x/a" "test" "$T/bericht.md" "$T/c1.jsonl"
mind_debug_write "/y/b" "test" "$T/bericht.md" "$T/c2.jsonl"
pruef "GEGENPROBE: kein WIEDERHOLT bei verschiedenen Klassen" \
      "$(grep -c 'WIEDERHOLT' "$MIND_DEBUG_DIR/BEFUNDE.md" 2>/dev/null)" "0"
pruef "GEGENPROBE: Text sagt es ausdruecklich" \
      "$(grep -c 'jede Ursachenklasse bisher genau einmal' "$MIND_DEBUG_DIR/BEFUNDE.md" 2>/dev/null)" "1"

# --- 3 · unbekannte Klasse wird als solche gemeldet --------------------------
export MIND_DEBUG_DIR="$T/debug3"
printf '{"ts":"2026-08-21 12:00","projekt":"/x/a","klasse":"phantasieklasse","kurz":"xy","lauf":"L1"}\n' > "$T/d1.jsonl"
mind_debug_write "/x/a" "test" "$T/bericht.md" "$T/d1.jsonl"
pruef "unbekannte Klasse wird markiert" \
      "$(grep -c 'unbekannte Klasse' "$MIND_DEBUG_DIR/BEFUNDE.md" 2>/dev/null)" "1"

# --- 4 · Zeilenenden der index.jsonl bleiben erhalten ------------------------
export MIND_DEBUG_DIR="$T/debug4"; mkdir -p "$MIND_DEBUG_DIR"
printf '{"ts":"a","projekt":"p","klasse":"sonstiges","kurz":"alt","lauf":"L0"}\r\n' > "$MIND_DEBUG_DIR/index.jsonl"
mind_debug_write "/x/a" "test" "$T/bericht.md" "$T/d1.jsonl"
CR=$(tr -cd "$(printf '\r')" < "$MIND_DEBUG_DIR/index.jsonl" | wc -c | tr -d ' ')
pruef "CRLF-index.jsonl bleibt CRLF (2 CR)" "$CR" "2"

# --- 4 · known-issues #10: EIN Projekt, DREI Schreibweisen -------------------
# ⛔ DER ECHTE FEHLSTAND, nicht konstruiert: `BEFUNDE.md` meldete am 02.09.2026
#    "Projekte | 16", gemessen waren es SECHS. Vier Projekte zerfielen in
#    mehrere Schreibweisen, weil jeder Lauf eintraegt, welche Form er gerade
#    hatte. Der Befund stand seit dem 27.08. dokumentiert und war nie behoben.
# ⚠ Die drei Formen unten kommen so im echten Index vor (43 / 47 / 2 Zeilen).
rm -rf "$T/d2"; export MIND_DEBUG_DIR="$T/d2"; mkdir -p "$MIND_DEBUG_DIR"
{
  printf '{"ts":"2026-09-01 10:00","projekt":"Claude Mind Manager","klasse":"doku-veraltet","kurz":"a"}\n'
  printf '{"ts":"2026-09-01 11:00","projekt":"C:/CD/K/Plugin - Entwicklung/Claude Mind Manager","klasse":"doku-veraltet","kurz":"b"}\n'
  printf '{"ts":"2026-09-01 12:00","projekt":"/c/CD/K/Plugin - Entwicklung/Claude Mind Manager","klasse":"doku-veraltet","kurz":"c"}\n'
} > "$MIND_DEBUG_DIR/index.jsonl"
python "$CLAUDE_PLUGIN_ROOT/references/debug_auswertung.py" "$MIND_DEBUG_DIR" >/dev/null 2>&1

pruef "⭐ drei Schreibweisen zaehlen als EIN Projekt" \
      "$(grep -oE '\| Projekte \| [0-9]+ \|' "$MIND_DEBUG_DIR/BEFUNDE.md" | grep -oE '[0-9]+')" "1"
# ⛔ GEGENPROBE: das Gate muss NEIN sagen koennen. Zwei WIRKLICH verschiedene
#    Projekte duerfen NICHT zusammenfallen — sonst waere die Normalisierung
#    ein Filter, der alles auf 1 drueckt und jeden Positivfall besteht.
{
  printf '{"ts":"2026-09-01 10:00","projekt":"C:/CD/K/Creator","klasse":"doku-veraltet","kurz":"a"}\n'
  printf '{"ts":"2026-09-01 11:00","projekt":"C:/CD/K/Pc Forschung","klasse":"doku-veraltet","kurz":"b"}\n'
} > "$MIND_DEBUG_DIR/index.jsonl"
python "$CLAUDE_PLUGIN_ROOT/references/debug_auswertung.py" "$MIND_DEBUG_DIR" >/dev/null 2>&1
pruef "⛔ zwei ECHTE Projekte bleiben zwei" \
      "$(grep -oE '\| Projekte \| [0-9]+ \|' "$MIND_DEBUG_DIR/BEFUNDE.md" | grep -oE '[0-9]+')" "2"

# ⚠ Und die Projektliste JE KLASSE darf denselben Namen nicht mehrfach fuehren —
#   das war die zweite Haelfte von #10 (Zeile 126 normalisierte, 98 nicht).
{
  printf '{"ts":"2026-09-01 10:00","projekt":"Creator","klasse":"windows-pfad","kurz":"a"}\n'
  printf '{"ts":"2026-09-01 11:00","projekt":"C:/CD/K/Creator","klasse":"windows-pfad","kurz":"b"}\n'
} > "$MIND_DEBUG_DIR/index.jsonl"
python "$CLAUDE_PLUGIN_ROOT/references/debug_auswertung.py" "$MIND_DEBUG_DIR" >/dev/null 2>&1
pruef "Projektliste nennt Creator genau einmal" \
      "$(grep -c 'Creator, Creator' "$MIND_DEBUG_DIR/BEFUNDE.md")" "0"


rm -rf "$T"
echo
echo "=================================="
echo "  $ok bestanden, $rot rot"
[ "$rot" -eq 0 ]
