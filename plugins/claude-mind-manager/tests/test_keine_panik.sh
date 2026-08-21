#!/usr/bin/env bash
# Kein Hook darf behaupten, das Kontextfenster sei voll (v5.9.3).
#
# ⛔ NUTZERBEFUND 21.08.2026, woertlich:
#    "Bei in jedem Chat behauptet der Tokens Fenster ist voll. Das stimmt nicht.
#     Ausserdem wird ab 1000K sowieso automatisch kompakt gemacht. Von Claude selber."
#
#    Die Texte waren um eine ungepruefte Annahme gebaut: dass mit
#    `autoCompactEnabled: false` gar nichts mehr auffaengt. Belegt war das nie —
#    gemessen wurde nur, dass zwischen 833k und 895k keine Kompaktierung kam.
#
#    Der Schaden war real und wiederholte sich in JEDEM Chat: derselbe Text hat am
#    selben Tag dazu gefuehrt, bei 880k die Arbeit einzustellen, obwohl 120k Luft
#    waren — und die Begruendung als "gemessen" auszugeben.
#
# ⭐ Ein Hook, der zu Vorsicht mahnt, unterliegt derselben Belegpflicht wie jede
#    andere Aussage. Eine Warnung ohne Beleg ist NICHT die sichere Seite.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_keine_panik.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
H="$CLAUDE_PLUGIN_ROOT/hooks"
OK=0; ROT=0

# Formulierungen, die eine unbelegte Endlichkeit behaupten. Sie duerfen im
# AUSGEGEBENEN TEXT nicht vorkommen — im Kommentar schon, dort erklaeren sie den Fix.
VERBOTEN='Fenster ist voll|Kontextfenster voll|Wand des Kontextfensters|KEINE Rettung|OHNE Rettung|kein Auffangnetz|NOTFALL'

echo "=== Keine unbelegten Panik-Aussagen in Hook-AUSGABEN ==="

for HOOK in stop.sh prompt-submit.sh session-start.sh pre-compact.sh; do
  [ -f "$H/$HOOK" ] || continue
  # Nur Zeilen ohne fuehrendes '#' — Kommentare duerfen die Begriffe nennen.
  TREFFER=$(grep -vE '^\s*#' "$H/$HOOK" | grep -ciE "$VERBOTEN" || true)
  if [ "${TREFFER:-0}" -eq 0 ]; then
    echo "  [ok ] $HOOK  keine Panik-Formulierung im Ausgabetext"
    OK=$((OK+1))
  else
    echo "  [ROT] $HOOK  $TREFFER Panik-Formulierung(en) im Ausgabetext:"
    grep -vE '^\s*#' "$H/$HOOK" | grep -inE "$VERBOTEN" | head -3 | sed 's/^/         /'
    ROT=$((ROT+1))
  fi
done

# --- NEGATIVKONTROLLE: erkennt der Test eine eingeschleuste Formulierung? ----
#     Ohne sie waere nicht belegt, dass die Suche ueberhaupt etwas findet.
TMP=$(mktemp -d)
printf '#!/bin/bash\n# Kommentar mit NOTFALL darf bleiben\necho "Das Fenster ist voll."\n' > "$TMP/k.sh"
T2=$(grep -vE '^\s*#' "$TMP/k.sh" | grep -ciE "$VERBOTEN" || true)
if [ "${T2:-0}" -ge 1 ]; then
  echo "  [ok ] Negativkontrolle: eingeschleuste Formulierung wird gefunden"
  OK=$((OK+1))
else
  echo "  [ROT] Negativkontrolle findet nichts — der Test misst nicht"
  ROT=$((ROT+1))
fi
# Und: ein reiner Kommentar darf NICHT anschlagen
printf '#!/bin/bash\n# hier stand mal NOTFALL und Wand des Kontextfensters\necho ok\n' > "$TMP/k2.sh"
T3=$(grep -vE '^\s*#' "$TMP/k2.sh" | grep -ciE "$VERBOTEN" || true)
if [ "${T3:-0}" -eq 0 ]; then
  echo "  [ok ] Negativkontrolle: Kommentar allein schlaegt nicht an"
  OK=$((OK+1))
else
  echo "  [ROT] Kommentar loest faelschlich aus — zu grob"
  ROT=$((ROT+1))
fi
rm -rf "$TMP"

echo
echo "=================================="
echo "  $OK bestanden, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
