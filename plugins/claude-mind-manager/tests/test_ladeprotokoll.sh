#!/usr/bin/env bash
# Prueffaelle fuer hooks/instructions-loaded.sh (v5.12.0).
#
# ⛔ Zu jedem Positivfall steht ein Negativfall. Ein Hook, der IMMER eine Zeile
#    schreibt, waere hier gruen und trotzdem wertlos -- deshalb wird geprueft,
#    dass er bei unbekanntem Schema ANDERS schreibt statt still leer.

WURZEL="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
HOOK="$WURZEL/hooks/instructions-loaded.sh"
[ -f "$HOOK" ] || { echo "Hook nicht gefunden: $HOOK"; exit 1; }

OK=0; ROT=0
ja() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1));
       else echo "  [ROT] $1 -> '$2', erwartet '$3'"; ROT=$((ROT+1)); fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
LOG="$T/lade.log"

ruf() { printf '%s' "$1" | MIND_LADEPROTOKOLL="$LOG" bash "$HOOK" >/dev/null 2>&1; echo $?; }

echo "=== 1 - der Normalfall ==="
rc=$(ruf '{"session_id":"abcdef1234","file_path":"/c/Users/x/.claude/rules/a.md","reason":"session_start"}')
ja "Rueckgabewert 0"                    "$rc" "0"
ja "genau EINE Zeile geschrieben"       "$(wc -l < "$LOG" | tr -d ' ')" "1"
ja "Grund steht drin"                   "$(grep -c 'session_start' "$LOG")" "1"
ja "Pfad steht drin"                    "$(grep -c 'rules/a.md' "$LOG")" "1"
ja "KEIN Schema-Marker"                 "$(grep -c 'SCHEMA?' "$LOG")" "0"

echo
echo "=== 2 - alternative Feldnamen (Schema ist undokumentiert) ==="
: > "$LOG"
ruf '{"path":"/x/b.md","matcher":"path_glob_match"}' >/dev/null
ja "path/matcher werden auch erkannt"   "$(grep -c 'path_glob_match' "$LOG")" "1"
ja "auch hier kein Schema-Marker"       "$(grep -c 'SCHEMA?' "$LOG")" "0"

echo
echo "=== 3 - NEGATIV: unbekanntes Schema muss AUFFALLEN ==="
# ⛔ Der wichtigste Fall. Waeren hier meine Feldnamen falsch geraten, duerfte der
#    Hook NICHT still eine leere Zeile schreiben -- sonst haelt man ein kaputtes
#    Instrument fuer ein leeres Ergebnis.
: > "$LOG"
ruf '{"voellig":"andere","felder":123}' >/dev/null
ja "Schema-Marker gesetzt"              "$(grep -c 'SCHEMA?' "$LOG")" "1"
ja "die ROHE Zeile steht dabei"         "$(grep -c 'voellig' "$LOG")" "1"

echo
echo "=== 4 - NEGATIV: nur Pfad, kein Grund -> ebenfalls Schema-Marker ==="
: > "$LOG"
ruf '{"file_path":"/x/c.md"}' >/dev/null
ja "halbes Schema faellt auch auf"      "$(grep -c 'SCHEMA?' "$LOG")" "1"

echo
echo "=== 5 - Robustheit: nichts darf abstuerzen ==="
ja "leere Eingabe"                      "$(ruf '')" "0"
ja "kaputtes JSON"                      "$(ruf '{nicht: [json')" "0"
ja "sehr grosse Eingabe"                "$(ruf "{\"file_path\":\"$(head -c 3000 /dev/zero | tr '\0' 'x')\"}")" "0"

echo
echo "=== 6 - Rotation greift ==="
: > "$LOG"
for i in $(seq 1 40); do printf 'fuellzeile %s\n' "$i" >> "$LOG"; done
printf '%s' '{"file_path":"/x/d.md","reason":"session_start"}' \
  | MIND_LADEPROTOKOLL="$LOG" MIND_LADEPROTOKOLL_MAX=20 bash "$HOOK" >/dev/null 2>&1
N=$(wc -l < "$LOG" | tr -d ' ')
if [ "$N" -le 20 ] 2>/dev/null; then echo "  [ok ] auf <= 20 Zeilen gekuerzt (jetzt $N)"; OK=$((OK+1));
else echo "  [ROT] Rotation griff nicht: $N Zeilen"; ROT=$((ROT+1)); fi
ja "die NEUE Zeile ueberlebt die Rotation" "$(grep -c 'rules\?/\?d.md\|/x/d.md' "$LOG")" "1"

echo
echo "=== 7 - GEGENPROBE: sabotierter Hook muss ROT werden ==="
# Ohne diesen Fall koennte die ganze Sammlung an einem Hook gruen sein,
# der nie etwas schreibt.
SAB="$T/sabotiert.sh"
sed 's|^INPUT=$(cat)|INPUT=$(cat); exit 0|' "$HOOK" > "$SAB"
: > "$LOG"
printf '%s' '{"file_path":"/x/e.md","reason":"session_start"}' \
  | MIND_LADEPROTOKOLL="$LOG" bash "$SAB" >/dev/null 2>&1
N=$(wc -l < "$LOG" | tr -d ' ')
if [ "$N" -eq 0 ]; then echo "  [ok ] sabotierter Hook schreibt NICHTS -> Sammlung kann scheitern"; OK=$((OK+1));
else echo "  [ROT] sabotierter Hook schrieb trotzdem $N Zeilen"; ROT=$((ROT+1)); fi

echo
echo "=================================="
echo "  $OK bestanden, $ROT rot"
[ "$ROT" -eq 0 ]
