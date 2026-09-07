#!/usr/bin/env bash
# v5.40.0: ist D1 EINGEHAENGT oder nur EINGEBAUT?
#
# ⛔ DER UNTERSCHIED IST DER GANZE PUNKT. "D1 laeuft nur, wenn jemand --wohin
#    tippt" ist woertlich die Definition eines TOTEN WERKZEUGS nach der
#    Kern-Invariante dieses Plugins. Der Debug-Ordner fuehrt
#    `instrument-nachgebaut` mit 7 Vorkommen, weil genau das mehrfach passiert
#    ist. Ein neuntes Tor, das niemand ruft, ist kein Tor.
#
# ⭐ DIE POSITIVKONTROLLE (Abschnitt 3) ist die eigentliche Pruefung: eine
#    Aussage, die NACHWEISLICH am falschen Ort steht, muss im Lauf als solche
#    herauskommen. Kommt sie nicht, ist D1 nicht eingehaengt, sondern nur
#    eingebaut — und die Abschnitte 1 und 2 waeren gruen, ohne etwas zu belegen.
set -u
R="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
EIN="$R/references/cleaner_einordnung.py"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
GRUEN=0; ROT=0
pruef() { if [ "$2" = "$3" ]; then GRUEN=$((GRUEN+1)); echo "  [ok ] $1"
  else ROT=$((ROT+1)); echo "  [ROT] $1 (erwartet '$2', war '$3')"; fi; }
hat() { case "$3" in *"$2"*) GRUEN=$((GRUEN+1)); echo "  [ok ] $1";;
  *) ROT=$((ROT+1)); echo "  [ROT] $1 — '$2' fehlt";; esac; }

echo "=== 1) Jeder Skill mit Kontext-Tor ruft auch D1 ==="
FEHLT=0; MIT=0
for f in "$R"/skills/*/SKILL.md; do
  grep -q 'cleaner_tor.py' "$f" || continue
  MIT=$((MIT+1))
  n=$(basename "$(dirname "$f")")
  if grep -q 'cleaner_einordnung.py" --wohin' "$f"; then
    echo "      ok   $n"
  else
    echo "      ⛔   $n ruft das Tor, aber NICHT D1"; FEHLT=$((FEHLT+1))
  fi
done
pruef "kein Skill ruft das Tor ohne D1" 0 "$FEHLT"
pruef "und es sind alle fuenf" 5 "$MIT"

echo
echo "=== 2) Die Doktrin steht dabei, nicht nur der Aufruf ==="
D=$(cat "$R"/skills/*/SKILL.md)
hat "D1 MELDET, es entscheidet nicht" "MELDET, es entscheidet nicht" "$D"
hat "UNBESTIMMT -> Ort bleibt, wo er war" "Ort bleibt, wo er war" "$D"
hat "die Quittung wird um D1 erweitert" "C1/C2:D1=" "$D"
hat "die bekannte Schwaeche ist genannt" "Aussage ueber den **Leser**" "$D"

echo
echo "=== 3) ⭐ POSITIVKONTROLLE: eine Aussage am FALSCHEN Ort ==="
# Eine Datei, die in `.claude/rules/` liegen wuerde — also IMMER laedt — und
# deren Inhalt reine Anleitung und reiner Beleg ist. Kein Satz davon muss vor
# dem Nachschlagen bekannt sein. D1 MUSS das melden.
cat > "$TMP/falsch-platziert.md" <<'MD'
# Durchsatz der Workstation

Der Aufruf lautet `iperf3 -c 10.10.10.1 -P 4 --json`.

Gemessen am 21.08.2026 lagen die Werte zwischen 834 und 941 MB/s.

Die Gegenprobe mit `dd if=/dev/zero of=/tmp/x bs=1M count=4096` bestaetigte das.
MD
AUS=$(python "$EIN" --wohin "$TMP/falsch-platziert.md" 2>&1)
# Die Ueberschrift von D1, nicht die von debug_auswertung. Die erste Fassung
# suchte "Art und Status" - das ist ein ANDERES Werkzeug, und der Fall war
# rot, obwohl D1 korrekt lief.
hat "D1 laeuft ueber die Datei" "wohin gehoert diese AUSSAGE" "$AUS"
B=$(printf '%s\n' "$AUS" | grep -E '^    BREMSE' | awk '{print $2}')
A=$(printf '%s\n' "$AUS" | grep -E '^    ANLEITUNG' | awk '{print $2}')
L=$(printf '%s\n' "$AUS" | grep -E '^    BELEG' | awk '{print $2}')
echo "      gemessen: BREMSE=$B ANLEITUNG=$A BELEG=$L"
pruef "⭐ KEINE Bremse — nichts davon muss immer laden" 0 "${B:-?}"
if [ "${A:-0}" -gt 0 ] 2>/dev/null || [ "${L:-0}" -gt 0 ] 2>/dev/null; then
  GRUEN=$((GRUEN+1)); echo "  [ok ] ⭐ und es wird als Anleitung/Beleg AUSGEWIESEN"
else
  ROT=$((ROT+1)); echo "  [ROT] alles UNBESTIMMT — D1 haette nichts gemeldet"
fi

echo
echo "=== 4) ⛔ NEGATIVKONTROLLE: eine echte Leitplanke bleibt ==="
# Sie MUSS Bremse melden. Ein D1, das ueberall "kann weg" sagt, waere schlimmer
# als keines — es wuerde Leitplanken auslagern.
cat > "$TMP/echte-leitplanke.md" <<'MD'
# Z: — die Leitplanke

⛔ NIEMALS mit Edit oder Write direkt auf `Z:` schreiben.

⛔ Aufraeumen heisst verschieben in Quarantaene, NIE loeschen.
MD
AUS2=$(python "$EIN" --wohin "$TMP/echte-leitplanke.md" 2>&1)
B2=$(printf '%s\n' "$AUS2" | grep -E '^    BREMSE' | awk '{print $2}')
echo "      gemessen: BREMSE=$B2"
if [ "${B2:-0}" -gt 0 ] 2>/dev/null; then
  GRUEN=$((GRUEN+1)); echo "  [ok ] ⭐ die Leitplanke wird als BREMSE erkannt"
else
  ROT=$((ROT+1)); echo "  [ROT] eine echte Leitplanke gilt als verschiebbar"
fi

echo
echo "  $GRUEN gruen · $ROT rot"
[ "$ROT" -eq 0 ]
