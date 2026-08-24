#!/usr/bin/env bash
# =============================================================================
#  Urteilsbuch + Duplikaterkennung  (NEU v5.16.0)
# =============================================================================
#
# ⛔ WAS HIER ENTSCHIEDEN WIRD
#
# Nutzer-Entscheidung 24.08.2026: BEIDE Werkzeuge duerfen aufraeumen —
# `/mind-cleaner` (mit Rueckfrage) und `/mind-claudemd` (autonom bei jedem
# `/mind-all`). Ohne gemeinsamen Zustand kippt diese Entscheidung ins Gegenteil:
#
#   1. Der Cleaner laesst eine "Verdichtung + Zeiger" bewusst stehen (Zielform).
#   2. /mind-claudemd sieht zwei Stellen mit gleichem Inhalt, haelt es fuer ein
#      Duplikat und entfernt eine — AUTONOM.
#   3. Danach fehlt der Kurz-Regel ihr Inhalt, und niemand weiss warum.
#
# Diese Sammlung prueft, dass genau das NICHT passieren kann.
# =============================================================================
set -u
WURZEL="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
U="$WURZEL/references/cleaner_urteile.py"
D="$WURZEL/references/cleaner_duplikate.py"

fehler=0
pruefe() {
  if [ "$2" = "$3" ]; then
    printf '    OK   %-50s ist=%-11s soll=%s\n' "$1" "$2" "$3"
  else
    printf '    FEHL %-50s ist=%-11s soll=%s\n' "$1" "$2" "$3"
    fehler=$((fehler + 1))
  fi
}

for f in "$U" "$D"; do
  [ -f "$f" ] || { echo "ABBRUCH: $f fehlt (Wurzel: $WURZEL)"; exit 2; }
done

echo "=============================================================================="
echo "  1) Die eigenen Gegenproben"
echo "=============================================================================="
python "$U" --selbsttest >/dev/null 2>&1; pruefe "Urteilsbuch: Selbsttest" "$?" "0"
python "$D" --selbsttest >/dev/null 2>&1; pruefe "Duplikate: Selbsttest"   "$?" "0"

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/proj"
A="$T/proj/a.md"; B="$T/proj/b.md"
printf '# A\nEins\n' > "$A"
printf '# B\nZwei\n' > "$B"

echo
echo "=============================================================================="
echo "  2) ⭐ Der Vertrag — ein autonomes Werkzeug darf zielform NICHT aufheben"
echo "=============================================================================="
python "$U" "$T/proj" --orte "$A" "$B" >/dev/null 2>&1
pruefe "unbeurteilt -> Rueckgabe 1" "$?" "1"

python "$U" "$T/proj" --schreiben --orte "$A" "$B" --urteil zielform \
       --werkzeug mind-cleaner --von mensch --grund "Verdichtung + Zeiger" >/dev/null 2>&1
AUS=$(python "$U" "$T/proj" --orte "$A" "$B" 2>&1); RC=$?
pruefe "nach Eintrag -> Rueckgabe 0" "$RC" "0"
pruefe "meldet zielform"          "$(printf '%s' "$AUS" | grep -c 'Urteil:  zielform')" "1"
pruefe "autonom DARF NICHT"       "$(printf '%s' "$AUS" | grep -c 'autonom:.*DARF NICHT')" "1"

echo
echo "=============================================================================="
echo "  3) Die Gegenrichtung — sonst waere das Buch eine Fessel"
echo "=============================================================================="
# ⛔ Ohne diesen Fall wuerde ein einmal gefaelltes Urteil eine Datei EINFRIEREN.
sleep 1
printf 'Drei\nVier\nFuenf\n' >> "$B"
AUS=$(python "$U" "$T/proj" --orte "$A" "$B" 2>&1)
pruefe "Inhalt geaendert -> veraltet" "$(printf '%s' "$AUS" | grep -c 'veraltet')" "1"

# Ein `duplikat` DARF ein autonomes Werkzeug anwenden — sonst raeumt niemand auf.
C="$T/proj/c.md"; printf '# C\n' > "$C"
python "$U" "$T/proj" --schreiben --orte "$A" "$C" --urteil duplikat \
       --werkzeug mind-claudemd --von autonom --grund "gleiche Aussage" >/dev/null 2>&1
AUS=$(python "$U" "$T/proj" --orte "$A" "$C" 2>&1)
pruefe "autonom DARF duplikat anwenden" "$(printf '%s' "$AUS" | grep -c 'autonom:.*DARF ')" "1"

echo
echo "=============================================================================="
echo "  4) ⭐ Zahlendrift — der Fall, den Textaehnlichkeit NIE findet"
echo "=============================================================================="
# ⛔ Der echte Fall aus dem eigenen Bestand, nachgebaut:
#    eine Stelle fuehrt einen Regler als geltend, die andere als entfallen.
mkdir -p "$T/echt/.claude/rules"
printf -- '---\ndescription: x\n---\n# P\n\n`MIND_NOTFALL_TOKENS` steht auf 940 000 und gilt.\n' \
  > "$T/echt/CLAUDE.md"
printf -- '---\ndescription: y\n---\n# R\n\n`MIND_NOTFALL_TOKENS` ist entfallen in v5.9.3.\n' \
  > "$T/echt/.claude/rules/regler.md"
AUS=$(python "$D" --bereich "$T/echt" --nur projekt 2>&1)
pruefe "Zahlendrift erkannt" "$(printf '%s' "$AUS" | grep -cE 'zahlendrift +1$')" "1"
pruefe "und sagt: entscheidet NICHT selbst" \
       "$(printf '%s' "$AUS" | grep -c 'entscheidet dieses Werkzeug NICHT')" "1"

# ⛔ DIE NEGATIVKONTROLLE, ohne die alles obige nichts wert waere.
#    Dieselbe Marke, verschiedene DATEN daneben — das ist KEINE Drift.
#    Die erste Fassung meldete hier 11 Fehlalarme und begrub den einen echten.
mkdir -p "$T/ruhig/.claude/rules"
printf -- '---\ndescription: x\n---\n# P\n\n`MIND_SYNC_AT_TOKENS` wurde am 17.08.2026 gesetzt.\n' \
  > "$T/ruhig/CLAUDE.md"
printf -- '---\ndescription: y\n---\n# R\n\n`MIND_SYNC_AT_TOKENS` wurde am 19.08.2026 geprueft.\n' \
  > "$T/ruhig/.claude/rules/regler.md"
AUS=$(python "$D" --bereich "$T/ruhig" --nur projekt 2>&1)
pruefe "verschiedene DATEN sind keine Drift" \
       "$(printf '%s' "$AUS" | grep -c '⛔ zahlendrift    0')" "1"

echo
echo "=============================================================================="
echo "  5) ⭐ Zielform wird NICHT als Duplikat gemeldet"
echo "=============================================================================="
# Der haeufigste Fall im echten Bestand: kurze Fassung PLUS Zeiger.
mkdir -p "$T/ziel/.claude/rules"
{ echo '---'; echo 'description: x'; echo '---'; echo '# P'; echo
  echo 'Kurz zu `MIND_BACKUP_KEEP_COUNT`. Volltext: `.claude/rules/lang.md`'; } \
  > "$T/ziel/CLAUDE.md"
{ echo '---'; echo 'description: y'; echo '---'; echo '# R'; echo
  for i in 1 2 3 4 5 6 7 8; do echo "Absatz $i ueber \`MIND_BACKUP_KEEP_COUNT\`."; echo; done; } \
  > "$T/ziel/.claude/rules/lang.md"
AUS=$(python "$D" --bereich "$T/ziel" --nur projekt 2>&1)
pruefe "als zielform eingeordnet" "$(printf '%s' "$AUS" | grep -cE 'zielform +1$')" "1"
pruefe "NICHT als duplikat"       "$(printf '%s' "$AUS" | grep -cE 'duplikat +0$')" "1"

echo
echo "=== $fehler Abweichung(en) ==="
exit $((fehler > 0 ? 1 : 0))
