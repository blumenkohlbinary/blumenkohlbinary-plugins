#!/usr/bin/env bash
# =============================================================================
#  Belege · Aussagen · Audit-Lauf   (NEU v5.18.0)
# =============================================================================
#
# ⛔ DIE ZWEI FRAGEN, DIE HIER ENTSCHIEDEN WERDEN
#
# 1. Bleibt Gruppe 5b sichtbar? Urteils- und Prozessregeln erzeugen kaum je
#    einen maschinell loggbaren Verstoss. Sie landen in "nicht entscheidbar"
#    NICHT weil sie unbeobachtet blieben, sondern weil sie unbeobachtBAR sind.
#    Ein Bericht, der das nicht sagt, laesst Gruppe 5 wie eine Restmenge
#    aussehen — dabei ist sie der Kern.
#
# 2. Sind alle sechs Werkzeuge GEMEINSAM importierbar? Bis v5.17.0 setzte jedes
#    beim Import `sys.stdout = io.TextIOWrapper(...)`. Der zweite verwaiste den
#    ersten, und ein TextIOWrapper SCHLIESST beim Wegraeumen seinen Puffer —
#    `cleaner_audit.py` brach sofort. Sechs Fehler an einem Tag, eine Ursache.
# =============================================================================
set -u
WURZEL="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
B="$WURZEL/references/cleaner_belege.py"
S="$WURZEL/references/cleaner_aussagen.py"
A="$WURZEL/references/cleaner_audit.py"

fehler=0
pruefe() {
  if [ "$2" = "$3" ]; then
    printf '    OK   %-50s ist=%-9s soll=%s\n' "$1" "$2" "$3"
  else
    printf '    FEHL %-50s ist=%-9s soll=%s\n' "$1" "$2" "$3"
    fehler=$((fehler + 1))
  fi
}

for f in "$B" "$S" "$A"; do
  [ -f "$f" ] || { echo "ABBRUCH: $f fehlt (Wurzel: $WURZEL)"; exit 2; }
done

echo "=============================================================================="
echo "  1) Die eigenen Gegenproben"
echo "=============================================================================="
python "$B" --selbsttest >/dev/null 2>&1; pruefe "Belege: Selbsttest"   "$?" "0"
python "$S" --selbsttest >/dev/null 2>&1; pruefe "Aussagen: Selbsttest" "$?" "0"
python "$A" --selbsttest >/dev/null 2>&1; pruefe "Audit: Selbsttest"    "$?" "0"

echo
echo "=============================================================================="
echo "  2) ⭐ Alle sechs Werkzeuge GEMEINSAM importierbar"
echo "=============================================================================="
# ⛔ Genau das ging bis v5.17.0 NICHT. Jedes Modul setzte beim Import einen
#    eigenen TextIOWrapper; der zweite verwaiste den ersten, dessen __del__ den
#    Puffer schloss. Erst `reconfigure` statt Zuweisung hat die Klasse beseitigt.
python - "$WURZEL" <<'PYEOF' >/dev/null 2>&1
import sys, os
sys.path.insert(0, os.path.join(sys.argv[1], "references"))
import cleaner_duplikate, cleaner_einordnung, cleaner_belege
import cleaner_aussagen, cleaner_grenzen, cleaner_urteile, cleaner_audit
print("import ok")
PYEOF
pruefe "sechs Module in EINEM Prozess" "$?" "0"

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

echo
echo "=============================================================================="
echo "  3) Belege — die Stichwortbildung darf nicht ALLES treffen"
echo "=============================================================================="
# ⛔ Die erste Fassung zog `nicht`, `gegen`, `Regeln` aus Ueberschriften und
#    schrieb `env-vars.md` 56 von 106 Befunden zu. Eine Belegquelle, die fast
#    alles belegt, belegt nichts — und Gruppe 5b blieb dadurch LEER.
mkdir -p "$T/r"
printf -- '# Nicht gegen die Regeln handeln\n\nText ohne Bezeichner.\n' > "$T/r/haltung.md"
python - "$WURZEL" "$T/r/haltung.md" <<'PYEOF'
import sys, os
sys.path.insert(0, os.path.join(sys.argv[1], "references"))
from cleaner_belege import stichworte_aus
sw = stichworte_aus(sys.argv[2])
schlecht = [w for w in sw if w.lower() in ("nicht", "gegen", "regeln", "handeln")]
sys.exit(1 if schlecht else 0)
PYEOF
pruefe "Fliesstextwoerter NICHT als Stichwort" "$?" "0"

python - "$WURZEL" "$T/r/haltung.md" <<'PYEOF'
import sys, os
sys.path.insert(0, os.path.join(sys.argv[1], "references"))
from cleaner_belege import stichworte_aus
sys.exit(0 if "haltung" in stichworte_aus(sys.argv[2]) else 1)
PYEOF
pruefe "Dateiname BLEIBT Stichwort" "$?" "0"

echo
echo "=============================================================================="
echo "  4) Aussagen — Gebot gegen Beleg, und blinde Verweise"
echo "=============================================================================="
printf -- '# R\n\n- ⛔ NIEMALS `dist/` loeschen.\n\n- Gemessen am 21.08.2026: 267 Faelle.\n\n- Siehe `x/y.md`.\n' \
  > "$T/r/gemischt.md"
AUS=$(python "$S" "$T/r/gemischt.md" 2>&1)
pruefe "Gebot erkannt"  "$(printf '%s' "$AUS" | grep -cE 'gebot +1')" "1"
pruefe "Beleg erkannt"  "$(printf '%s' "$AUS" | grep -cE 'beleg +1')" "1"
# `Siehe` ist ein Wozu-Wort -> NICHT blind. Die Gegenrichtung:
printf -- '# R\n\n- Vergleiche `x/y.md`.\n' > "$T/r/blind.md"
AUS=$(python "$S" "$T/r/blind.md" 2>&1); RC=$?
pruefe "Verweis ohne Wozu -> Rueckgabe 1" "$RC" "1"
printf -- '# R\n\n- Details stehen in `x/y.md`.\n' > "$T/r/mitwozu.md"
python "$S" "$T/r/mitwozu.md" >/dev/null 2>&1
pruefe "Verweis MIT Wozu -> Rueckgabe 0" "$?" "0"

echo
echo "=============================================================================="
echo "  5) ⭐ Der Audit-Bericht — Gruppe 5 steht OBEN und ist geteilt"
echo "=============================================================================="
mkdir -p "$T/p/.claude/rules"
cp "$WURZEL/../../../Claude Mind Manager/.claude/rules/hooks.md" \
   "$T/p/.claude/rules/" 2>/dev/null || \
   printf -- '---\ndescription: x\n---\n# H\n\nText.\n' > "$T/p/.claude/rules/hooks.md"
printf -- '---\ndescription: y\n---\n# Plan\n\nText.\n' > "$T/p/.claude/rules/plan-mode.md"
AUS=$(python "$A" --bereich "$T/p" --nur projekt 2>&1)

# ⛔ Die Reihenfolge ist die Aussage: 5 vor 1.
Z5=$(printf '%s' "$AUS" | grep -n '5 · NICHT ENTSCHEIDBAR' | head -1 | cut -d: -f1)
Z1=$(printf '%s' "$AUS" | grep -n '1 · BELEGT NOETIG' | head -1 | cut -d: -f1)
pruefe "Gruppe 5 steht VOR Gruppe 1" "$([ -n "$Z5" ] && [ -n "$Z1" ] && [ "$Z5" -lt "$Z1" ] && echo ja || echo nein)" "ja"
pruefe "5a und 5b getrennt" \
       "$(printf '%s' "$AUS" | grep -cE '5[ab] ·')" "2"
pruefe "plan-mode landet in 5b" \
       "$(printf '%s' "$AUS" | sed -n '/5b ·/,/^  1 ·/p' | grep -c 'plan-mode')" "1"
pruefe "sagt: unbeobachtBAR, nicht unbeobachtet" \
       "$(printf '%s' "$AUS" | grep -c 'unbeobachtBAR')" "1"
pruefe "nennt, was NICHT geprueft wurde" \
       "$(printf '%s' "$AUS" | grep -c 'NICHT GEPRUEFT')" "1"
pruefe "sagt: aendert nichts" \
       "$(printf '%s' "$AUS" | grep -c 'AENDERT NICHTS')" "1"

echo
echo "=== $fehler Abweichung(en) ==="
exit $((fehler > 0 ? 1 : 0))
