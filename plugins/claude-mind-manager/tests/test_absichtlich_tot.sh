#!/usr/bin/env bash
# ABSICHTLICH TOTE PFADE (v5.21.2) — N1 aus plan.md
#
# ⛔ DER FALL, gemessen 26.08.2026 an `.claude/rules/hooks.md`:
#      Belegt mit 8 Pruefungen (`tests/test_notfall.sh` — **mit v5.9.3 geloescht**)
#    Der Pfad ist tot, die Zeile sagt es, und die Doku ist RICHTIG so: die
#    Pruefsammlung hat existiert und belegt die Aussage historisch. Wer das
#    meldet, verlangt, korrekte Dokumentation zu zerstoeren.
#
# ⛔ VON DEN SIEBEN VERBLIEBENEN FEHLALARMEN IST DAS DER EINZIGE, DER BEHOBEN
#    WIRD. Die anderen drei Klassen (maskierte Tabellen-Pipe, `i/lf w/lf`,
#    Snapshot-Layout-Pfade) bleiben unangetastet: jede Regel, die sie faengt,
#    ist in Gefahr, auch `("APP - Zustellplan/dist", "CHECK")` zu fangen — einen
#    ECHTEN Pfad mit Leerzeichen, den der Selbsttest zusichert.
#    `werkzeuge-zuerst.md`: "Ein Rauschfilter, der nur gegen Rauschen kalibriert
#    wird, optimiert sich auf Stille."
#
# ⚠ DESHALB SIND HIER MEHR NEGATIV- ALS POSITIVKONTROLLEN. Die Gefahr bei
#   diesem Filter ist nicht, dass er zu wenig faengt, sondern zu viel.
#
# ⛔ WINDOWS-PFADE: python bekommt IMMER cygpath -w.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_absichtlich_tot.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
command -v cygpath >/dev/null 2>&1 || { echo "cygpath fehlt" >&2; exit 2; }
PIPE=$(cygpath -w "$CLAUDE_PLUGIN_ROOT/references/claudemd_pipeline.py")
OK=0; ROT=0
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
P="$D/proj"; mkdir -p "$P/.claude/rules"

pruefe() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — ist '$2', soll '$3'"; ROT=$((ROT+1)); fi; }

# $1 = Dateiinhalt -> gibt "<tote>|<hinweise>" zurueck
lauf() {
  printf '%s\n' "$1" > "$P/f.md"
  AUS=$(python "$PIPE" "$(cygpath -w "$P/f.md")" --projekt "$(cygpath -w "$P")" 2>&1 | tr -d '\r')
  T=$(printf '%s\n' "$AUS" | grep -c 'toter Pfad')
  H=$(printf '%s\n' "$AUS" | grep -c 'absichtlich tot')
  echo "$T|$H"
}

echo "=============================================================================="
echo "  N1 — ein Pfad, der absichtlich tot ist und das SELBST sagt"
echo "=============================================================================="

echo
echo "  --- Positivfall: der echte Wortlaut aus hooks.md ---"
pruefe "gekennzeichnet -> Hinweis, kein Befund" \
  "$(lauf '# H

Belegt mit 8 Pruefungen (`tests/test_notfall.sh` — mit v5.9.3 geloescht), zuerst
gegen den unreparierten Stand gefahren.')" "0|1"

pruefe "Variante: entfallen" \
  "$(lauf '# H

Der Regler `hooks/notfall.sh` ist in v5.9.3 entfallen.')" "0|1"

pruefe "Variante: gibt es nicht mehr" \
  "$(lauf '# H

`tools/alt_skript.py` gibt es nicht mehr, der Nachfolger heisst anders.')" "0|1"

echo
echo "  --- ⛔ NEGATIVKONTROLLEN: hier liegt die Gefahr ---"
pruefe "ohne Kennzeichnung -> Befund" \
  "$(lauf '# H

Siehe `tests/test_notfall.sh` fuer die acht Pruefungen.')" "1|0"

# ⛔ "entfernt" steht NICHT in der Wortliste, und das ist Absicht: es kommt in
#    jeder zweiten Zeile vor ("damit der Aufraeumer keine Version entfernt").
pruefe "'entfernt' zaehlt NICHT als Kennzeichnung" \
  "$(lauf '# H

`tools/x.py` wird entfernt, sobald der Aufraeumer laeuft.')" "1|0"

# ⛔ Regel 3: steht der Pfad auf MEHREREN Zeilen, muss JEDE gekennzeichnet sein.
#    Sonst verdeckt eine historische Nennung einen echten toten Pfad woanders.
pruefe "eine von zwei Zeilen gekennzeichnet -> Befund" \
  "$(lauf '# H

`tools/x.py` wurde in v5.9.3 geloescht.

Fahre danach `tools/x.py` gegen den Bestand.')" "1|0"

pruefe "beide Zeilen gekennzeichnet -> Hinweis" \
  "$(lauf '# H

`tools/x.py` wurde in v5.9.3 geloescht.

Auch `tools/x.py` ist damit entfallen.')" "0|1"

echo
echo "  --- ⛔ ein LEBENDER Pfad wird nie zum Hinweis ---"
mkdir -p "$P/tools"; echo "x" > "$P/tools/lebt.py"
pruefe "lebender Pfad mit dem Wort 'geloescht' -> gar nichts" \
  "$(lauf '# H

`tools/lebt.py` hat frueher etwas geloescht, tut es aber nicht mehr.')" "0|0"

echo
echo "=============================================================================="
echo "  $OK ok, $ROT rot"
echo "=============================================================================="
[ "$ROT" -eq 0 ]
