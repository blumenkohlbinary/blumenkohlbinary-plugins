#!/usr/bin/env bash
# v5.38.0: der Transkript-Merker bei MEHREREN Sitzungen im selben Ordner.
#
# ⛔ DER DEFEKT. `.claude-mind/transkript-pfad` ist EINE Datei je PROJEKT, soll
#    aber eine SITZUNG kennzeichnen. Jede Sitzung ueberschreibt ihn bei jedem
#    Prompt — der Letzte gewinnt. v5.34.0 hat den ls-t-Fehler behoben und dabei
#    dieses Rennen eingebaut, ohne es zu bemerken.
#
# ⭐ DIE POSITIVKONTROLLE IST FALL 5: der Merker wird MITTEN IM LAUF von einer
#    fremden Sitzung ueberschrieben, und der eingefrorene Wert muss trotzdem
#    stimmen. Ohne diesen Fall pruefte die Sammlung nur, dass Lesen funktioniert
#    — und das tat es vorher auch.
set -u
R="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
GRUEN=0; ROT=0
pruef() { if [ "$2" = "$3" ]; then GRUEN=$((GRUEN+1)); echo "  [ok ] $1"
  else ROT=$((ROT+1)); echo "  [ROT] $1 (erwartet '$2', war '$3')"; fi; }

# shellcheck disable=SC1091
. "$R/hooks/lib.sh" 2>/dev/null

P="$TMP/proj"; mkdir -p "$P/.claude-mind"
A="$TMP/sitzung-a.jsonl"; B="$TMP/sitzung-b.jsonl"
printf '%s\n' '{"message":{"model":"claude-opus-5","usage":{"input_tokens":111}}}' > "$A"
printf '%s\n' '{"message":{"model":"claude-opus-5","usage":{"input_tokens":999}}}' > "$B"

echo "=== 1) Das neue Format pfad|sid|ts ==="
printf '%s|abc-123|1757000000' "$A" > "$P/.claude-mind/transkript-pfad"
pruef "Merker mit sid und ts -> nur der Pfad kommt zurueck" "$A" "$(mind_transkript_pfad "$P")"

echo
echo "=== 2) Alte Form (nur der Pfad) bleibt lesbar ==="
printf '%s' "$A" > "$P/.claude-mind/transkript-pfad"
pruef "⛔ Rueckwaertsvertraeglich: Merker ohne | " "$A" "$(mind_transkript_pfad "$P")"

echo
echo "=== 3) Ein uebergebener Pfad schlaegt den Merker ==="
printf '%s|fremd|1' "$B" > "$P/.claude-mind/transkript-pfad"
pruef "zweites Argument gewinnt" "$A" "$(mind_transkript_pfad "$P" "$A")"
pruef "ohne zweites Argument gilt der Merker" "$B" "$(mind_transkript_pfad "$P")"

echo
echo "=== 4) Kaputter Merker -> nicht raten, sondern LEER ==="
printf '%s|x|1' "$TMP/gibtsnicht.jsonl" > "$P/.claude-mind/transkript-pfad"
# ⚠ Ohne Transkriptverzeichnis darf NICHTS zurueckkommen. Eine erfundene Datei
#   waere schlimmer als keine — eine fehlende Zahl ist keine Null.
OUT=$(mind_transkript_pfad "$P" 2>/dev/null); RC=$?
pruef "Merker zeigt ins Leere -> rc 1" 1 "$RC"
pruef "   ... und die Ausgabe ist leer" "" "$OUT"

echo
echo "=== 5) ⭐ DAS RENNEN — der eigentliche Grund fuer diesen Fix ==="
# So lief es VOR v5.38.0: die Kette liest den Merker erst spaet.
printf '%s|meine|1' "$A" > "$P/.claude-mind/transkript-pfad"   # mein Prompt
printf '%s|fremde|2' "$B" > "$P/.claude-mind/transkript-pfad"  # fremde Sitzung dazwischen
SPAET=$(mind_transkript_pfad "$P")
pruef "⛔ spaet gelesen -> FREMDES Transkript (der alte Fehler)" "$B" "$SPAET"

# So laeuft es SEIT v5.38.0: Step 0 friert ein, danach wird durchgereicht.
printf '%s|meine|1' "$A" > "$P/.claude-mind/transkript-pfad"
FROZEN=$(mind_transkript_pfad "$P")                            # Step 0
printf '%s|fremde|2' "$B" > "$P/.claude-mind/transkript-pfad"  # fremde Sitzung dazwischen
pruef "⭐ eingefroren -> weiter MEIN Transkript" "$A" "$(mind_transkript_pfad "$P" "$FROZEN")"

# Und die Zahl, die daran haengt, ist die eigene:
pruef "   ... und die Tokenzahl ist meine (111, nicht 999)" \
      111 "$(mind_kontext_tokens "$(mind_transkript_pfad "$P" "$FROZEN")")"

echo
echo "=== 6) prompt-submit.sh schreibt das neue Format ==="
P2="$TMP/proj2"; mkdir -p "$P2/.claude-mind"
printf '{"cwd":"%s","transcript_path":"%s","session_id":"sid-xyz","prompt":"hi"}' "$P2" "$A" \
  | CLAUDE_PLUGIN_ROOT="$R" CLAUDE_PROJECT_DIR="$P2" bash "$R/hooks/prompt-submit.sh" >/dev/null 2>&1
M=$(cat "$P2/.claude-mind/transkript-pfad" 2>/dev/null)
pruef "Pfad steht vorn" "$A" "${M%%|*}"
pruef "⭐ die Sitzungskennung steht dabei" "sid-xyz" "$(echo "$M" | cut -d'|' -f2)"
case "$(echo "$M" | cut -d'|' -f3)" in
  [0-9]*) GRUEN=$((GRUEN+1)); echo "  [ok ] und ein Zeitstempel" ;;
  *) ROT=$((ROT+1)); echo "  [ROT] Zeitstempel fehlt" ;;
esac
pruef "   ... und der Merker ist danach lesbar" "$A" "$(mind_transkript_pfad "$P2")"

echo
echo "  $GRUEN gruen · $ROT rot"
[ "$ROT" -eq 0 ]
