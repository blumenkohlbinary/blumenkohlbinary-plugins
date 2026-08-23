#!/usr/bin/env bash
# =============================================================================
#  Das Negativfall-Gate — kann die Sperre selbst rot werden?  (NEU v5.14.0)
# =============================================================================
#
# ⛔ DIE FRAGE, DIE HIER ENTSCHIEDEN WIRD
#
# `references/negativfall_gate.py` ist die Sperre gegen `instrument-misst-nichts`
# (23 Vorkommen im Debug-Ordner, groesste Klasse). Eine Sperre gegen blinde
# Instrumente, die selbst blind ist, waere die vollkommenste Form dieses Fehlers.
#
# Deshalb steht hier NICHT "laeuft das Gate durch?", sondern:
#   Wird es ROT, wenn eine Pruef-Funktion ohne Prueffall dazukommt?
#
# ⚠ Gebaut wird dafuer ein KUENSTLICHER Baum in /tmp. Der echte Quellbaum wird
#   nicht angefasst — eine Gegenprobe, die die geprueften Dateien veraendert,
#   verletzt `messung-vor-glauben.md` §2.
# =============================================================================
set -u
WURZEL="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
GATE="$WURZEL/references/negativfall_gate.py"

fehler=0
pruefe() {
  if [ "$2" = "$3" ]; then
    printf '    OK   %-50s ist=%-9s soll=%s\n' "$1" "$2" "$3"
  else
    printf '    FEHL %-50s ist=%-9s soll=%s\n' "$1" "$2" "$3"
    fehler=$((fehler + 1))
  fi
}

[ -f "$GATE" ] || { echo "ABBRUCH: $GATE fehlt"; exit 2; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

baue() {  # $1 = Wurzel, $2 = zusaetzliche Funktion (oder leer)
  local r="$1" extra="${2:-}"
  mkdir -p "$r/hooks" "$r/tests" "$r/references"
  {
    echo 'mind_check_alpha() { return 0; }'
    echo 'mind_zeilenenden_gleich() { return 0; }'
    [ -n "$extra" ] && echo "$extra() { return 0; }"
  } > "$r/hooks/lib.sh"
  # Ein Prueffall, der beide Grundfunktionen nennt UND eine Gegenprobe hat.
  {
    echo '#!/usr/bin/env bash'
    echo '# Gegenprobe: mind_check_alpha muss ROT werden'
    echo 'mind_check_alpha; mind_zeilenenden_gleich'
    echo 'pruefe "x" "1" "soll=1"'
  } > "$r/tests/test_grund.sh"
}

echo "=============================================================================="
echo "  1) Sauberer Baum — alles gedeckt"
echo "=============================================================================="
A="$T/sauber"; baue "$A"
CLAUDE_PLUGIN_ROOT="$A" python "$GATE" --stand-setzen > "$T/a1.log" 2>&1
pruefe "Stand setzen geht durch" "$?" "0"
CLAUDE_PLUGIN_ROOT="$A" python "$GATE" > "$T/a2.log" 2>&1
pruefe "unveraendert -> Rueckgabe 0" "$?" "0"
pruefe "meldet 0 ungetestet" "$(grep -c '0 UNGETESTET' "$T/a2.log")" "1"

echo
echo "=============================================================================="
echo "  2) ⭐ DIE GEGENPROBE — eine ungedeckte Funktion kommt dazu"
echo "=============================================================================="
# Neue Pruef-Funktion (Name enthaelt "check"), die kein Prueffall nennt.
baue "$A" "mind_check_neu_und_ungeprueft"
CLAUDE_PLUGIN_ROOT="$A" python "$GATE" > "$T/a3.log" 2>&1
RC=$?
sed -n '4,10p' "$T/a3.log" | sed 's/^/    | /'
pruefe "neue ungedeckte Funktion -> Rueckgabe 1" "$RC" "1"
pruefe "nennt sie beim Namen" \
       "$(grep -c 'mind_check_neu_und_ungeprueft' "$T/a3.log")" "1"

echo
echo "=============================================================================="
echo "  3) Abbau wird erkannt, aber nicht selbst festgeschrieben"
echo "=============================================================================="
# ⛔ Eine Ratsche, die sich selbst nachzieht, ist keine Ratsche. Der Abbau muss
#    ABSICHTLICH festgeschrieben werden, sonst faellt er beim naechsten Lauf
#    unbemerkt zurueck.
baue "$A"   # Funktion wieder weg -> 0 ungetestet, Stand steht auf 1
echo "1" > "$A/tests/.negativfall-stand"
CLAUDE_PLUGIN_ROOT="$A" python "$GATE" > "$T/a4.log" 2>&1
pruefe "Abbau -> trotzdem Rueckgabe 0" "$?" "0"
pruefe "sagt, dass festgeschrieben werden muss" \
       "$(grep -c 'stand-setzen' "$T/a4.log")" "1"
pruefe "Stand steht UNVERAENDERT auf 1" "$(cat "$A/tests/.negativfall-stand")" "1"

echo
echo "=============================================================================="
echo "  4) Messung unmoeglich ist KEIN gutes Ergebnis"
echo "=============================================================================="
# ⚠ Ein Gate, das bei falscher Wurzel gruen meldet, ist schlimmer als keins.
CLAUDE_PLUGIN_ROOT="$T/gibtsnicht" python "$GATE" > "$T/a5.log" 2>&1
pruefe "leere Wurzel -> Rueckgabe 2" "$?" "2"
pruefe "sagt es ausdruecklich" "$(grep -c 'Messung unmoeglich' "$T/a5.log")" "1"

# Baum ohne erkennbare Pruef-Funktion: ebenfalls 2, nicht 0.
B="$T/leer"; mkdir -p "$B/hooks" "$B/tests"
echo 'mind_log() { return 0; }' > "$B/hooks/lib.sh"
CLAUDE_PLUGIN_ROOT="$B" python "$GATE" > "$T/a6.log" 2>&1
pruefe "keine Pruef-Funktion erkannt -> Rueckgabe 2" "$?" "2"

echo
echo "=============================================================================="
echo "  5) Der ECHTE Baum — die Ratsche haelt"
echo "=============================================================================="
CLAUDE_PLUGIN_ROOT="$WURZEL" python "$GATE" > "$T/echt.log" 2>&1
RCE=$?
grep -E '(Pruef-Funktionen|UNGETESTET|ROT:|unveraendert)' "$T/echt.log" | sed 's/^/    | /'
pruefe "echter Baum -> Rueckgabe 0" "$RCE" "0"

echo
echo "=== $fehler Abweichung(en) ==="
exit $((fehler > 0 ? 1 : 0))
