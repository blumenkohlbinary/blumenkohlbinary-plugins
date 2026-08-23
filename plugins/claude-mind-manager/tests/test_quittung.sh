#!/usr/bin/env bash
# =============================================================================
#  Agent-Quittung + Commit-Ausloeser  (NEU v5.14.0)
# =============================================================================
#
# ⛔ WARUM ES DIESE SAMMLUNG GIBT
#
# Zwei Debug-Klassen mit zusammen 10 Vorkommen:
#   agent-gestorben   (4x)  leere Rueckgabe nach 20 Werkzeugaufrufen
#   agent-fehlbericht (6x)  "alle zwoelf abgearbeitet" -- neun gefahren
# plus ein Einzelbefund:
#   plugin-defekt          "Sync-Ausloeser haengt allein an der Kompaktierung;
#                           11 Commits und 12 h ohne Netz"
#
# ⭐ Die Kernfrage dieser Sammlung ist NICHT "wird protokolliert?", sondern:
#    Unterscheidet die Bilanz einen Agenten, der NICHTS FAND, von einem, der
#    NICHT ZURUECKKAM? Beide sehen im Bericht identisch aus. Ohne diese
#    Unterscheidung ist die ganze Quittung wertlos.
# =============================================================================
set -u
WURZEL="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck disable=SC1091
. "$WURZEL/hooks/lib.sh"

fehler=0
pruefe() {
  if [ "$2" = "$3" ]; then
    printf '    OK   %-52s ist=%-11s soll=%s\n' "$1" "$2" "$3"
  else
    printf '    FEHL %-52s ist=%-11s soll=%s\n' "$1" "$2" "$3"
    fehler=$((fehler + 1))
  fi
}

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P"

echo "=============================================================================="
echo "  1) Agent-Quittung — der Normalfall"
echo "=============================================================================="
mind_agent_quittung_start "$P"
for b in claude-md memory rules custom-context; do
  mind_agent_dispatch "$b" "$P"
  mind_agent_ergebnis "$b" 4096 "$P"
done
AUS=$(mind_agent_bilanz "$P"); RC=$?
echo "$AUS" | sed 's/^/    | /'
pruefe "vier dispatcht, vier zurueck" "$(echo "$AUS" | head -1)" \
       "DISPATCH=4 ERGEBNIS=4 LEER=0 STUMM=0"
pruefe "Rueckgabe 0" "$RC" "0"

echo
echo "=============================================================================="
echo "  2) ⭐ Leer gegen STUMM — die eigentliche Frage"
echo "=============================================================================="
mind_agent_quittung_start "$P"
mind_agent_dispatch "claude-md" "$P";      mind_agent_ergebnis "claude-md" 4096 "$P"
mind_agent_dispatch "memory" "$P";         mind_agent_ergebnis "memory" 0 "$P"   # leer zurueck
mind_agent_dispatch "rules" "$P"                                                 # NIE zurueck
mind_agent_dispatch "custom-context" "$P"; mind_agent_ergebnis "custom-context" 800 "$P"
AUS=$(mind_agent_bilanz "$P"); RC=$?
echo "$AUS" | sed 's/^/    | /'
pruefe "Kopfzeile"  "$(echo "$AUS" | head -1)" "DISPATCH=4 ERGEBNIS=3 LEER=1 STUMM=1"
pruefe "Rueckgabe 1 bei UNGEPRUEFT" "$RC" "1"
pruefe "memory als leer gemeldet"  "$(echo "$AUS" | grep -c 'memory (leere Rueckgabe')" "1"
pruefe "rules als stumm gemeldet"  "$(echo "$AUS" | grep -c 'rules (dispatcht, nie zurueck)')" "1"
# ⛔ Die Negativhaelfte: die beiden GESUNDEN Bereiche duerfen NICHT auftauchen.
#    Ohne diese Zusicherung waere "melde einfach alles als UNGEPRUEFT" gruen.
pruefe "claude-md NICHT gemeldet"      "$(echo "$AUS" | grep -c 'UNGEPRUEFT: claude-md')" "0"
pruefe "custom-context NICHT gemeldet" "$(echo "$AUS" | grep -c 'UNGEPRUEFT: custom-context')" "0"

echo
echo "=============================================================================="
echo "  3) ⛔ GAR NICHT DISPATCHT — der Fall vom 23.08.2026"
echo "=============================================================================="
# An diesem Tag wurden die Agents nicht losgeschickt, und der Lauf lief durch,
# als waere alles geprueft. Das MUSS von "alles gruen" unterscheidbar sein.
mind_agent_quittung_start "$P"
AUS=$(mind_agent_bilanz "$P"); RC=$?
echo "$AUS" | sed 's/^/    | /'
pruefe "leere Quittung -> Rueckgabe 2" "$RC" "2"
pruefe "sagt es ausdruecklich" "$(echo "$AUS" | grep -c 'Fan-out hat nicht stattgefunden')" "1"

# Gar keine Datei = derselbe Zustand, anderer Weg dorthin.
rm -f "$P/.claude-mind/agent-quittung.jsonl"
mind_agent_bilanz "$P" >/dev/null 2>&1
pruefe "keine Quittungsdatei -> Rueckgabe 2" "$?" "2"

echo
echo "=============================================================================="
echo "  4) mind_commits_seit — Arbeit statt Fuellstand"
echo "=============================================================================="
G="$T/repo"; mkdir -p "$G"
git -C "$G" init -q 2>/dev/null
git -C "$G" config user.email t@t.de; git -C "$G" config user.name T
echo a > "$G/a.txt"; git -C "$G" add -A; git -C "$G" commit -qm "erster"

# ⚠ ZWEIMAL sleep, und das ist kein Zierrat: `git rev-list --since` arbeitet auf
#   SEKUNDEN und ist INKLUSIV. Ohne die erste Pause faellt der Commit "erster" in
#   dieselbe Sekunde wie der Nullpunkt und wird mitgezaehlt -- gemessen 4 statt 3.
#   Fuer eine Mahnschwelle von 10 ist das belanglos, fuer diese Zusicherung nicht.
sleep 1
REF="$T/stand"; : > "$REF"
sleep 1
for i in 1 2 3; do echo "$i" > "$G/f$i.txt"; git -C "$G" add -A; git -C "$G" commit -qm "c$i"; done

N=$(mind_commits_seit "$G" "$REF"); RC=$?
pruefe "drei Commits nach dem Nullpunkt" "$N" "3"
pruefe "Rueckgabe 0"                     "$RC" "0"

# ⚠ ZUR SEKUNDEN-GRENZE STEHT HIER BEWUSST KEINE ZUSICHERUNG.
#
#   Die erste Fassung behauptete "Commit in der Referenzsekunde zaehlt mit" und
#   erwartete 1. Einzeln gefahren stimmte das; im vollen Lauf unter Last kam 4
#   heraus, weil die drei Commits davor in dieselbe Sekunde fielen wie der
#   Referenzpunkt. Eine Zusicherung, deren Ergebnis von der Systemlast abhaengt,
#   ist keine Messung — genau der Vorwurf, den diese Sammlung an anderer Stelle
#   gegen `test_precompact.py` erhebt (Transkript-Lotterie).
#
#   Die Eigenschaft selbst gilt und ist harmlos: `git rev-list --since` arbeitet
#   auf SEKUNDEN und ist INKLUSIV, ein Commit in der Referenzsekunde wird also
#   mitgezaehlt. Bei einer Mahnschwelle von 10 Commits spielt das keine Rolle.
#   Sie steht hier als DOKUMENTIERTE GRENZE, nicht als Prueffall.

# Stattdessen deterministisch: ein Commit NACH dem Referenzpunkt zaehlt immer.
sleep 1
REFG="$T/stand_grenz"; : > "$REFG"
sleep 1
echo x > "$G/g.txt"; git -C "$G" add -A; git -C "$G" commit -qm "einer danach"
pruefe "genau ein Commit nach dem Referenzpunkt" "$(mind_commits_seit "$G" "$REFG")" "1"

# ⛔ NICHT ZAEHLBAR gibt NICHTS aus, nicht "0". Keine Zahl ist keine Null --
#    sonst schweigt die Mahnung genau dann, wenn die Messung kaputt ist.
N2=$(mind_commits_seit "$T/kein-repo" "$REF"); RC2=$?
pruefe "kein Git -> keine Ausgabe" "${N2:-LEER}" "LEER"
pruefe "kein Git -> Rueckgabe 1"   "$RC2" "1"
N3=$(mind_commits_seit "$G" "$T/gibtsnicht"); RC3=$?
pruefe "kein Referenzpunkt -> keine Ausgabe" "${N3:-LEER}" "LEER"
pruefe "kein Referenzpunkt -> Rueckgabe 1"   "$RC3" "1"

# Gegenrichtung: Nullpunkt NACH den Commits -> null Commits, aber zaehlbar.
sleep 1
REF2="$T/stand2"; : > "$REF2"
N4=$(mind_commits_seit "$G" "$REF2"); RC4=$?
pruefe "Nullpunkt hinter allem -> 0" "$N4" "0"
pruefe "und trotzdem zaehlbar (0)"   "$RC4" "0"

echo
echo "=== $fehler Abweichung(en) ==="
exit $((fehler > 0 ? 1 : 0))
