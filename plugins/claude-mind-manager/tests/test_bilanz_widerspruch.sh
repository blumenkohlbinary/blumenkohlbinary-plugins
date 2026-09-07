#!/usr/bin/env bash
# v5.42.0: ERGEBNIS ohne DISPATCH ist ein eigener Zustand, keine Abwesenheit.
#
# ⛔ DER FEHLER. `mind_agent_bilanz` meldete bei DISPATCH=0 "kein einziger Agent
#    dispatcht — der Fan-out hat nicht stattgefunden", OBWOHL im selben Aufruf
#    vier Ergebniszeilen vorlagen. Eine Aussage, die den eigenen Daten
#    widerspricht.
#
# ⭐ ERSTER FUND DER KLASSE `instrument-meldet-falsch` (v5.41.0), gemeldet vom
#    Manager aus einem echten /mind-all-Lauf: DISPATCH=0 ERGEBNIS=4.
#
# ⚠ Der Unterschied ist nicht akademisch:
#     "nie gestartet"                  -> UNGEPRUEFT, Bereiche neu fahren
#     "gestartet, nicht quittiert"     -> GEPRUEFT, nur nachquittieren
#   Wer beides gleich meldet, schickt jemanden vier Bereiche neu fahren, die
#   schon gelaufen sind.
set -u
R="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
GRUEN=0; ROT=0
pruef() { if [ "$2" = "$3" ]; then GRUEN=$((GRUEN+1)); echo "  [ok ] $1"
  else ROT=$((ROT+1)); echo "  [ROT] $1 (erwartet '$2', war '$3')"; fi; }
hat() { case "$3" in *"$2"*) GRUEN=$((GRUEN+1)); echo "  [ok ] $1";;
  *) ROT=$((ROT+1)); echo "  [ROT] $1 — '$2' fehlt";; esac; }
fehlt() { case "$3" in *"$2"*) ROT=$((ROT+1)); echo "  [ROT] $1 — '$2' steht da";;
  *) GRUEN=$((GRUEN+1)); echo "  [ok ] $1";; esac; }

# shellcheck disable=SC1091
. "$R/hooks/lib.sh" 2>/dev/null

mk() { # <verzeichnis> <zeilen…>
  local d="$1"; shift
  mkdir -p "$d/.claude-mind"
  : > "$d/.claude-mind/agent-quittung.jsonl"
  for z in "$@"; do printf '%s\n' "$z" >> "$d/.claude-mind/agent-quittung.jsonl"; done
}

echo "=== 1) ⭐ DER GEMELDETE FALL: 4 Ergebnisse, 0 Dispatch ==="
A="$TMP/a"
mk "$A" \
 '{"ereignis":"ergebnis","bereich":"claude-md","bytes":4200,"ts":"x"}' \
 '{"ereignis":"ergebnis","bereich":"memory","bytes":5100,"ts":"x"}' \
 '{"ereignis":"ergebnis","bereich":"rules","bytes":1800,"ts":"x"}' \
 '{"ereignis":"ergebnis","bereich":"custom-context","bytes":900,"ts":"x"}'
OUT=$(mind_agent_bilanz "$A"); RC=$?
hat "die Zahlen stehen da" "DISPATCH=0 ERGEBNIS=4" "$OUT"
hat "⭐ der Widerspruch wird BENANNT" "QUITTUNG UNVOLLSTAENDIG" "$OUT"
hat "   ... und als logisch unmoeglich bezeichnet" "logisch unmoeglich" "$OUT"
hat "⭐ es sagt, dass der Fan-out STATTGEFUNDEN hat" "STATTGEFUNDEN" "$OUT"
hat "   ... und was zu tun ist" "NICHT neu fahren" "$OUT"
fehlt "⛔ die FALSCHE Aussage steht NICHT mehr da" "hat nicht stattgefunden" "$OUT"
pruef "Rueckgabe 1 (Buchfuehrung lueckenhaft), nicht 2" 1 "$RC"

echo
echo "=== 2) ⛔ NEGATIVKONTROLLE: der ECHTE Ausfall bleibt Ausfall ==="
# Ohne diesen Fall waere der Fix eine Verschlechterung: er wuerde jeden echten
# Fan-out-Ausfall zu einem Buchfuehrungsproblem verharmlosen.
B="$TMP/b"; mk "$B"
OUT=$(mind_agent_bilanz "$B"); RC=$?
hat "⭐ gar nichts -> der Fan-out hat NICHT stattgefunden" "hat nicht stattgefunden" "$OUT"
fehlt "   ... und NICHT als Buchfuehrungsproblem" "QUITTUNG UNVOLLSTAENDIG" "$OUT"
pruef "Rueckgabe 2 (echter Ausfall)" 2 "$RC"

echo
echo "=== 3) Der Normalfall bleibt unveraendert ==="
C="$TMP/c"
mk "$C" \
 '{"ereignis":"dispatch","bereich":"rules","ts":"x"}' \
 '{"ereignis":"ergebnis","bereich":"rules","bytes":1800,"ts":"x"}'
OUT=$(mind_agent_bilanz "$C"); RC=$?
hat "sauberer Lauf" "DISPATCH=1 ERGEBNIS=1" "$OUT"
fehlt "   ... ohne Widerspruchsmeldung" "QUITTUNG UNVOLLSTAENDIG" "$OUT"
pruef "Rueckgabe 0" 0 "$RC"

echo
echo "=== 4) Ein LEERES Ergebnis ohne Dispatch — beides gilt ==="
# 0 Byte ist ein Ergebnis-Eintrag (so seit v5.21.2). Der Widerspruch besteht
# also auch hier, und der Bereich ist trotzdem ungeprueft.
D="$TMP/d"
mk "$D" '{"ereignis":"ergebnis","bereich":"memory","bytes":0,"ts":"x"}'
OUT=$(mind_agent_bilanz "$D")
hat "der Widerspruch wird gemeldet" "QUITTUNG UNVOLLSTAENDIG" "$OUT"
hat "⭐ und der leere Bereich BLEIBT ungeprueft" "UNGEPRUEFT: memory" "$OUT"

echo
echo "  $GRUEN gruen · $ROT rot"
[ "$ROT" -eq 0 ]
