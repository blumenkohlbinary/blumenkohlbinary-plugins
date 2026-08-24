#!/usr/bin/env bash
# =============================================================================
#  Stille Kappungen + die Ratsche  (NEU v5.17.0)
# =============================================================================
#
# ⛔ WORUM ES GEHT
#
# Ein Aufraeum-Werkzeug, das eine stille Grenze nicht kennt, verschiebt Inhalt
# an einen Ort, wo er LAUTLOS abgeschnitten wird. Vorher war der Text zu lang,
# nachher ist er weg — und niemand merkt es, weil keine Meldung erscheint.
#
# ⭐ Die gefaehrlichste Grenze kappt keinen Inhalt: das `paths:`-Budget macht
#    eine ganze REGEL unwirksam (1000 Muster -> Muster bleibt unexpandiert ->
#    matcht nie mehr), ohne dass sich etwas Sichtbares aendert.
#
# Und die Ratsche beantwortet nicht "ist es groesser geworden?", sondern
# "ist genau das zurueck, was wir weggenommen haben?"
# =============================================================================
set -u
WURZEL="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
G="$WURZEL/references/cleaner_grenzen.py"
R="$WURZEL/references/cleaner_ratsche.py"

fehler=0
pruefe() {
  if [ "$2" = "$3" ]; then
    printf '    OK   %-50s ist=%-9s soll=%s\n' "$1" "$2" "$3"
  else
    printf '    FEHL %-50s ist=%-9s soll=%s\n' "$1" "$2" "$3"
    fehler=$((fehler + 1))
  fi
}

for f in "$G" "$R"; do
  [ -f "$f" ] || { echo "ABBRUCH: $f fehlt (Wurzel: $WURZEL)"; exit 2; }
done

echo "=============================================================================="
echo "  1) Die eigenen Gegenproben"
echo "=============================================================================="
python "$G" --selbsttest >/dev/null 2>&1; pruefe "Grenzen: Selbsttest" "$?" "0"
python "$R" --selbsttest >/dev/null 2>&1; pruefe "Ratsche: Selbsttest" "$?" "0"

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

echo
echo "=============================================================================="
echo "  2) ⭐ Grenzen — Rueckgabewerte, OHNE Pipe gemessen"
echo "=============================================================================="
# ⚠ Der Rueckgabewert wird hier bewusst ohne Pipe geholt. Eine Pipe VERSCHLUCKT
#   ihn (`befehl | head` liefert den Wert von head) — heute schon einmal
#   passiert, und der Befund sah dabei aus wie ein bestandenes Gate.
mkdir -p "$T/ok"
printf -- '---\ndescription: x\n---\n# Ruhig\n\nNichts Auffaelliges.\n' > "$T/ok/MEMORY.md"
python "$G" --ziel "$T/ok/MEMORY.md" >/dev/null 2>&1
pruefe "kleine MEMORY.md -> Rueckgabe 0" "$?" "0"

python - "$T/gross" <<'PYEOF'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
open(os.path.join(d, "MEMORY.md"), "w", encoding="utf-8", newline="\n").write(
    "# M\n" + "Zeile\n" * 300)
PYEOF
python "$G" --ziel "$T/gross/MEMORY.md" >/dev/null 2>&1
pruefe "300 Zeilen MEMORY -> Rueckgabe 1" "$?" "1"

python "$G" --ziel "$T/gibtsnicht.md" >/dev/null 2>&1
pruefe "fehlende Datei -> Rueckgabe 2 (nicht messbar)" "$?" "2"

# ⛔ Die eigentliche Frage vor einem Umzug: passt das, was ich HINZUFUEGEN will?
printf 'Neue Zeile\n' > "$T/dazu.txt"
python - "$T/knapp" <<'PYEOF'
import os, sys
d = sys.argv[1]; os.makedirs(d, exist_ok=True)
open(os.path.join(d, "MEMORY.md"), "w", encoding="utf-8", newline="\n").write(
    "# M\n" + "Zeile\n" * 199)
PYEOF
AUS=$(python "$G" --ziel "$T/knapp/MEMORY.md" --dazu "$T/dazu.txt" 2>&1)
pruefe "knapp + eine Zeile -> BRUCH gemeldet" \
       "$(printf '%s' "$AUS" | grep -c 'BRUCH\|⛔ MEMORY Zeilen')" "1"

echo
echo "=============================================================================="
echo "  3) ⭐ Die Ratsche — anschlagen UND schweigen"
echo "=============================================================================="
P="$T/proj"; mkdir -p "$P/.claude/rules" "$P/archiv"
printf -- '# Alt\n\n`MIND_ZZ_TESTMARKE` steht auf 12345.\n' > "$P/archiv/alt.md"
printf -- '# P\n\nNichts Besonderes.\n' > "$P/CLAUDE.md"

python "$R" --pruefe --projekt "$P" --nur-projekt >/dev/null 2>&1
pruefe "ohne Archiv -> Rueckgabe 2 (nicht messbar)" "$?" "2"

python "$R" --archiviere "$P/archiv/alt.md" --grund "im Code entfallen" \
       --projekt "$P" >/dev/null 2>&1
pruefe "archivieren geht durch" "$?" "0"

# ⛔ Ohne Grund gibt es keinen Eintrag — 'X ist zurueck' ohne 'warum es wegging'
#    hilft beim naechsten Mal niemandem.
python "$R" --archiviere "$P/archiv/alt.md" --projekt "$P" >/dev/null 2>&1
pruefe "ohne --grund -> abgelehnt" "$?" "2"

python "$R" --pruefe --projekt "$P" --nur-projekt >/dev/null 2>&1
pruefe "nur im Archiv -> still (Rueckgabe 0)" "$?" "0"

# ⭐ Jetzt kommt die Marke in einer GELADENEN Datei zurueck.
printf -- '# P\n\n`MIND_ZZ_TESTMARKE` steht auf 12345.\n' > "$P/CLAUDE.md"
AUS=$(python "$R" --pruefe --projekt "$P" --nur-projekt 2>&1); RC=$?
pruefe "Marke zurueck -> Rueckgabe 1" "$RC" "1"
pruefe "nennt die Marke"        "$(printf '%s' "$AUS" | grep -c 'MIND_ZZ_TESTMARKE')" "1"
pruefe "nennt den Grund"        "$(printf '%s' "$AUS" | grep -c 'im Code entfallen')" "1"
# ⚠ Der Ton zaehlt: die Ratsche meldet mit Vorgeschichte, sie urteilt nicht.
pruefe "sagt: nicht automatisch ein Fehler" \
       "$(printf '%s' "$AUS" | grep -c 'NICHT automatisch ein Fehler')" "1"

# Verlauf ist KEIN Gate — er darf nie etwas rot machen.
python "$R" --verlauf --projekt "$P" >/dev/null 2>&1
pruefe "Verlauf -> immer Rueckgabe 0" "$?" "0"

echo
echo "=============================================================================="
echo "  4) Der echte Bestand — findet es den bekannten HTML-Kommentar?"
echo "=============================================================================="
# ⛔ Gemessen 24.08.2026 von Hand: .claude/rules/hooks.md enthaelt einen
#    Kommentar mit 3 Inhaltszeilen, die das Modell nie erreichen.
AUS=$(python "$G" --bestand "$WURZEL/../../../Claude Mind Manager" 2>&1 || true)
if printf '%s' "$AUS" | grep -q "hooks.md"; then
  pruefe "HTML-Kommentar in hooks.md gefunden" \
         "$(printf '%s' "$AUS" | grep -c 'HTML-Kommentare')" "1"
else
  echo "    ⚠ uebersprungen — Workspace von hier aus nicht erreichbar"
  echo "      (kein Fehler: die Sammlung laeuft auch am gebauten Paket)"
fi

echo
echo "=== $fehler Abweichung(en) ==="
exit $((fehler > 0 ? 1 : 0))
