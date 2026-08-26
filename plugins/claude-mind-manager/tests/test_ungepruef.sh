#!/usr/bin/env bash
# `ungepruef=` IST TEIL DES URTEILS (v5.21.1)
#
# ⛔ GEMESSEN im eigenen /mind-all-Lauf vom 26.08.2026:
#    4 von 4 Bereichen dispatcht, EINER kam mit 0 Byte zurueck.
#      umfang=5/5 skills 4/4 agents     -> mind_sync_voll sagte "vollstaendig"
#      ungepruef=custom-context         -> stand in DERSELBEN Datei daneben
#    `mind_sync_voll` enthielt das Wort `ungepruef` NULL MAL.
#    `pre-compact.sh:136` liest es zwar — aber erst im else-Zweig, also nur wenn
#    dieses Tor schon "teil" gesagt hat. Das Feld war unerreichbar.
#
# ⭐ Woertlich die Klasse, gegen die v5.19.0 gebaut wurde, ein Feld weiter:
#    dort loeschte ein Lauf OHNE Fan-out seine eigene Schuld, hier einer, dessen
#    Agent LEER zurueckkam. Der Unterschied zwischen "nie gestartet" und "nichts
#    geliefert" war der ganze Anlass fuer `mind_agent_bilanz` — und genau er
#    fiel an dieser Stelle durch.
#
# ⛔ DIE AENDERUNG KANN DAS TOR NUR STRENGER MACHEN. Fehlendes oder leeres Feld
#    -> unveraendert vollstaendig. Nur ein AUSGEFUELLTES Feld macht einen
#    Teilsync daraus. Deshalb war es zulaessig, sie im selben Lauf zu bauen, in
#    dem der Befund entstand: sie laesst den eigenen Lauf DURCHFALLEN, sie
#    rettet ihn nicht (messung-vor-glauben.md §2 verbietet die Gegenrichtung).
#
# ⚠ NEUE DATEI, keine Aenderung an tests/test_teilsync.sh — bestehende
#   Pruefungen bleiben unangetastet.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_ungepruef.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
. "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
OK=0; ROT=0
D=$(mktemp -d)

pruef() {
  printf '%s\n' "$2" > "$D/stand"
  if mind_sync_voll "$D/stand"; then ist=voll; else ist=teil; fi
  if [ "$ist" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
  else echo "  [ROT] $1 — ist=$ist soll=$3"; ROT=$((ROT+1)); fi
}

echo "=============================================================================="
echo "  mind_sync_voll — ein benannter ungeprueffter Bereich ist ein TEILSYNC"
echo "=============================================================================="

echo
echo "  --- der gemessene Fall (26.08.2026) ---"
pruef "4/4 Agents ABER ungepruef=custom-context -> teil" \
      "$(printf 'ts=x\numfang=5/5 skills 4/4 agents\nungepruef=custom-context')" teil
pruef "mehrere Bereiche ungeprueft -> teil" \
      "$(printf 'ts=x\numfang=5/5 skills 4/4 agents\nungepruef=rules,memory')" teil

echo
echo "  --- NEGATIVKONTROLLEN: das Tor darf nicht alles sperren ---"
pruef "ungepruef LEER -> voll" \
      "$(printf 'ts=x\numfang=5/5 skills 4/4 agents\nungepruef=')" voll
pruef "ungepruef FEHLT ganz -> voll" \
      "$(printf 'ts=x\numfang=5/5 skills 4/4 agents')" voll
# ⛔ Fail-safe-Richtung aus v5.19.0, unveraendert: ein Bestand ohne `umfang=`
#    gilt als vollstaendig. Eine faelschlich behauptete Vollstaendigkeit kostet
#    eine Mahnung; ein faelschlich behaupteter Teilsync nagelt die Sitzung an
#    einem Zwang fest, den sie selbst nicht aufloesen kann.
pruef "Altbestand ohne umfang und ohne ungepruef -> voll" "ts=2026-08-01" voll
pruef "Merker fehlt ganz -> voll" "" voll

echo
echo "  --- die alte Achse muss weiter greifen ---"
pruef "0/4 Agents -> teil (unveraendert)" \
      "$(printf 'ts=x\numfang=5/5 skills 0/4 agents')" teil
pruef "2/5 Skills -> teil (unveraendert)" \
      "$(printf 'ts=x\numfang=2/5 skills 4/4 agents')" teil

echo
echo "  --- der Sonderfall, der die Reihenfolge erzwingt ---"
# ⛔ Steht die Pruefung NACH der umfang-Auswertung, kehrt die Funktion bei
#    fehlendem `umfang=` frueh zurueck und sieht `ungepruef=` nie.
pruef "ungepruef gesetzt, umfang FEHLT -> teil" \
      "$(printf 'ts=x\nungepruef=rules')" teil

rm -rf "$D"
echo
echo "=============================================================================="
echo "  $OK ok, $ROT rot"
echo "=============================================================================="
[ "$ROT" -eq 0 ]
