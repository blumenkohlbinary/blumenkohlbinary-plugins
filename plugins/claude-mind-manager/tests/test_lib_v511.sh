#!/usr/bin/env bash
# Prueffaelle fuer die fuenf neuen lib.sh-Funktionen (v5.11.0).
#
# ⛔ Jede Zusicherung greift auf einen RUECKGABEWERT zu, nie auf Berichtstext.
# Zu jedem Positivfall steht ein Negativfall -- eine Funktion, die immer
# dasselbe liefert, muss hier rot werden.

WURZEL="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck disable=SC1091
. "$WURZEL/hooks/lib.sh" 2>/dev/null || { echo "lib.sh nicht ladbar: $WURZEL"; exit 1; }

OK=0; ROT=0
ja() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1));
       else echo "  [ROT] $1 -> '$2', erwartet '$3'"; ROT=$((ROT+1)); fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "=== 1 - mind_pfad_lebt: die Tilde (der Fehler, der Zeilen loeschte) ==="

# REPRODUKTION des alten Verhaltens: so hat der Skill geprueft.
if [ -e "~/.claude/rules/autonom-arbeiten.md" ]; then ALT="gefunden"; else ALT="DEAD"; fi
ja "alte Pruefung meldet die Tilde-Datei als tot (Repro)" "$ALT" "DEAD"

if [ -e "$HOME/.claude/rules/autonom-arbeiten.md" ]; then
  if mind_pfad_lebt "~/.claude/rules/autonom-arbeiten.md"; then N="lebt"; else N="DEAD"; fi
  ja "NEU: dieselbe Datei wird gefunden" "$N" "lebt"
else
  echo "  [uebersprungen] autonom-arbeiten.md liegt hier nicht"
fi

# NEGATIV: eine Tilde-Datei, die es WIRKLICH nicht gibt, muss tot bleiben.
# Ohne diesen Fall waere ein `return 0` gruen.
if mind_pfad_lebt "~/.claude/rules/gibt-es-nicht-4711.md"; then N="lebt"; else N="DEAD"; fi
ja "NEGATIV: erfundene Tilde-Datei bleibt tot" "$N" "DEAD"

# Absolute und relative Pfade unveraendert
printf 'x\n' > "$TMP/da.md"
if mind_pfad_lebt "$TMP/da.md"; then N="lebt"; else N="DEAD"; fi
ja "absoluter Pfad lebt weiter" "$N" "lebt"
if mind_pfad_lebt "$TMP/weg.md"; then N="lebt"; else N="DEAD"; fi
ja "NEGATIV: absoluter Pfad ohne Datei bleibt tot" "$N" "DEAD"

echo
echo "=== 2 - mind_classify_path: die alten Klassen bleiben ==="
ja "Markdown-Link -> SKIP"      "$(mind_classify_path '[n](../x.md)')"        "SKIP"
ja "Slash-Command -> SKIP"      "$(mind_classify_path '/mind-all')"           "SKIP"
ja "Web-Adresse -> SKIP"        "$(mind_classify_path 'github.com/a/b')"      "SKIP"
ja "Platzhalter -> SKIP"        "$(mind_classify_path 'src/<name>.py')"       "SKIP"
ja "NEGATIV: /etc bleibt UNSURE" "$(mind_classify_path '/etc')"               "UNSURE"
ja "NEGATIV: echter Pfad -> CHECK" "$(mind_classify_path 'hooks/lib.sh')"     "CHECK"
ja "Tilde-Pfad -> CHECK"        "$(mind_classify_path '~/.claude/rules/a.md')" "CHECK"

echo
echo "=== 3 - mind_sync_frisch: der Merker loest sich selbst auf ==="
S="$TMP/sync-stand"

printf 'ts=x\ntokens=800000\n' > "$S"
if mind_sync_frisch "$S" 820000; then N="frisch"; else N="verbraucht"; fi
ja "20k Zuwachs -> noch frisch, schweigt"      "$N" "frisch"

if mind_sync_frisch "$S" 950000; then N="frisch"; else N="verbraucht"; fi
ja "150k Zuwachs -> verbraucht, mahnt"          "$N" "verbraucht"

# ⛔ DER FALL AUS DEM FEHLERBERICHT: Merker ohne tokens= (Fassung vor v5.11.0).
# Frueher schaltete seine blosse EXISTENZ alles dauerhaft stumm.
printf 'ts=2026-08-21 08:00:00\n' > "$S"
if mind_sync_frisch "$S" 950000; then N="frisch"; else N="verbraucht"; fi
ja "Alt-Merker ohne Zahl gilt als verbraucht"   "$N" "verbraucht"

rm -f "$S"
if mind_sync_frisch "$S" 950000; then N="frisch"; else N="verbraucht"; fi
ja "kein Merker -> verbraucht"                  "$N" "verbraucht"

# Ohne Messung nicht mahnen - dieselbe Linie wie ueberall.
printf 'ts=x\ntokens=800000\n' > "$S"
if mind_sync_frisch "$S" ""; then N="frisch"; else N="verbraucht"; fi
ja "ohne Tokenzahl wird NICHT gemahnt"          "$N" "frisch"

# Regler wirkt
if MIND_SYNC_DELTA=200000 mind_sync_frisch "$S" 950000; then N="frisch"; else N="verbraucht"; fi
ja "MIND_SYNC_DELTA=200000 macht 150k wieder frisch" "$N" "frisch"

echo
echo "=== 4 - mind_zeilenenden: Anteil, nicht Zeilenzahl ==="
printf 'a\nb\nc\n'       > "$TMP/lf.txt"
printf 'a\r\nb\r\nc\r\n' > "$TMP/crlf.txt"
ja "reine LF-Datei"   "$(mind_zeilenenden "$TMP/lf.txt")"   "0/3"
ja "reine CRLF-Datei" "$(mind_zeilenenden "$TMP/crlf.txt")" "3/3"

V=$(mind_zeilenenden "$TMP/lf.txt")
cp "$TMP/lf.txt" "$TMP/nach.txt"
if mind_zeilenenden_gleich "$V" "$(mind_zeilenenden "$TMP/nach.txt")"; then N="gleich"; else N="gekippt"; fi
ja "unveraenderte Datei -> gleich"    "$N" "gleich"

# NEGATIV, der eigentliche Fall: gleiche ZEILENZAHL, gekippte Enden.
# Eine Zusicherung auf die Zeilenzahl waere hier gruen.
printf 'a\r\nb\r\nc\r\n' > "$TMP/nach.txt"
if mind_zeilenenden_gleich "$V" "$(mind_zeilenenden "$TMP/nach.txt")"; then N="gleich"; else N="gekippt"; fi
ja "LF->CRLF bei GLEICHER Zeilenzahl -> gekippt" "$N" "gekippt"

echo
echo "=================================="
echo "  $OK bestanden, $ROT rot"
[ "$ROT" -eq 0 ]
