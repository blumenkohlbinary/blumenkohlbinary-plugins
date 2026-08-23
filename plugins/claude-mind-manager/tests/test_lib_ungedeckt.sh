#!/usr/bin/env bash
# =============================================================================
#  Die drei Funktionen, die KEIN Prueffall je angefasst hat  (NEU v5.14.0)
# =============================================================================
#
# ⛔ WIE DIESE SAMMLUNG ENTSTANDEN IST
#
# `references/negativfall_gate.py` (ebenfalls neu in v5.14.0) hat beim ersten
# Lauf gemeldet: 11 Pruef-Funktionen in lib.sh, **3 davon kommen in KEINER
# Pruefdatei vor**. Gegengeprueft mit `grep -rl` — alle drei tatsaechlich bei
# null Treffern.
#
# ⭐ Der bitterste der drei ist `mind_scan_poisoning`. Der Debug-Ordner fuehrt zu
#    genau dieser Funktion einen Befund vom 21.08.2026:
#
#      "mind_scan_poisoning mit Verzeichnis aufgerufen -> still 0,
#       '0 Befunde' gemeldet ohne zu messen"
#
#    Ein bekannter, aufgeschriebener, behobener Defekt — und die Funktion hatte
#    danach immer noch keinen einzigen Prueffall. Das ist die Klasse
#    `instrument-misst-nichts` in Reinform: der Fehler war bekannt, die Lehre
#    notiert, die Sperre nie gebaut.
#
# Die Alternative waere gewesen, die Schuld in der Ratsche einzufrieren. Eine
# Ratsche, die mit drei bekannten Luecken startet, gewoehnt an Luecken.
# =============================================================================
set -u
WURZEL="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck disable=SC1091
. "$WURZEL/hooks/lib.sh"

fehler=0
pruefe() {
  if [ "$2" = "$3" ]; then
    printf '    OK   %-50s ist=%-9s soll=%s\n' "$1" "$2" "$3"
  else
    printf '    FEHL %-50s ist=%-9s soll=%s\n' "$1" "$2" "$3"
    fehler=$((fehler + 1))
  fi
}

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

echo "=============================================================================="
echo "  1) mind_kontext_tokens — keine Zahl ist KEINE Null"
echo "=============================================================================="
# Ein Transkript mit zwei usage-Zeilen. Gezaehlt wird die LETZTE, als Summe aus
# input + cache_creation + cache_read.
TR="$T/t.jsonl"
printf '%s\n' '{"message":{"usage":{"input_tokens":10,"cache_creation_input_tokens":5,"cache_read_input_tokens":1}}}' > "$TR"
printf '%s\n' '{"message":{"usage":{"input_tokens":100,"cache_creation_input_tokens":20,"cache_read_input_tokens":3}}}' >> "$TR"
pruefe "letzte usage-Zeile, alle drei Felder summiert" "$(mind_kontext_tokens "$TR")" "123"

# ⛔ DIE ZUSICHERUNG, DIE ZAEHLT. Ein Transkript ohne usage darf NICHT 0 liefern,
#    sonst schweigen Mahnung und Zwang genau dann, wenn die Messung kaputt ist.
printf '%s\n' '{"message":{"content":"kein usage hier"}}' > "$T/leer.jsonl"
AUS=$(mind_kontext_tokens "$T/leer.jsonl"); RC=$?
pruefe "ohne usage: KEINE Ausgabe" "${AUS:-LEER}" "LEER"
pruefe "ohne usage: Rueckgabe 1"   "$RC" "1"

mind_kontext_tokens "$T/gibtsnicht.jsonl" >/dev/null 2>&1
pruefe "fehlende Datei: Rueckgabe 1" "$?" "1"
mind_kontext_tokens "" >/dev/null 2>&1
pruefe "leeres Argument: Rueckgabe 1" "$?" "1"

# Kaputte JSON-Zeilen duerfen die intakten nicht mitreissen.
printf '%s\n' 'KEIN JSON' > "$T/mix.jsonl"
printf '%s\n' '{"message":{"usage":{"input_tokens":7}}}' >> "$T/mix.jsonl"
pruefe "kaputte Zeile wird uebersprungen" "$(mind_kontext_tokens "$T/mix.jsonl")" "7"

echo
echo "=============================================================================="
echo "  2) ⭐ mind_scan_poisoning — der Debug-Befund vom 21.08.2026"
echo "=============================================================================="
mkdir -p "$T/scan"
printf 'ganz normaler Text\nzweite Zeile\n' > "$T/scan/sauber.md"
# Zero-Width Space (U+200B) — hat in einer Notizdatei keinen legitimen Zweck.
printf 'harmlos\xe2\x80\x8bversteckt\n' > "$T/scan/giftig.md"

A=$(mind_scan_poisoning "$T/scan/sauber.md" 2>/dev/null)
pruefe "saubere Datei: kein Befund" "$(printf '%s' "$A" | grep -c .)" "0"

B=$(mind_scan_poisoning "$T/scan/giftig.md" 2>/dev/null)
pruefe "unsichtbares Zeichen: gemeldet" "$(printf '%s' "$B" | grep -c .)" "1"

# ⛔ DER BEFUND SELBST: ein VERZEICHNIS muss rekursiv geprueft werden. Bis v5.7.0
#    gab der Aufruf still 0 zurueck, und der Lauf meldete "0 Befunde", ohne eine
#    einzige Datei angesehen zu haben.
#
# ⚠ Gezaehlt wird die ZAHL der BEFUND-Zeilen, NICHT der Dateiname darin.
#   Die erste Fassung dieser Zusicherung suchte `giftig.md` in der Ausgabe und
#   war rot — die Funktion war tadellos, die Kontrolle nicht: die Befundzeile
#   lautet `BEFUND|unsichtbares-zeichen|1|U+200B` und traegt gar keinen Pfad.
#   Genau der Fall aus `messung-vor-glauben.md` §1: eine Zusicherung darf nie
#   gegen die DARSTELLUNG laufen, immer gegen den MECHANISMUS.
C=$(mind_scan_poisoning "$T/scan" 2>/dev/null)
pruefe "VERZEICHNIS rekursiv: 1 Befund aus 2 Dateien" \
       "$(printf '%s' "$C" | grep -c '^BEFUND|')" "1"

# Und die Gegenrichtung: ein Verzeichnis ohne Gift bleibt still. Ohne diesen
# Fall waere "meldet immer etwas" gruen.
mkdir -p "$T/rein"; printf 'nur Text\n' > "$T/rein/a.md"
D=$(mind_scan_poisoning "$T/rein" 2>/dev/null)
pruefe "sauberes Verzeichnis: still" "$(printf '%s' "$D" | grep -c .)" "0"

# Nicht existierender Pfad: KEINE Aussage, nicht "unauffaellig".
E=$(mind_scan_poisoning "$T/gibtsnicht.md" 2>/dev/null); RCE=$?
pruefe "fehlender Pfad: sagt es ausdruecklich" "$(printf '%s' "$E" | grep -c 'nicht-lesbar')" "1"
pruefe "fehlender Pfad: Rueckgabe 1" "$RCE" "1"

echo
echo "=============================================================================="
echo "  3) mind_hook_health — schweigen heisst nicht gesund"
echo "=============================================================================="
P="$T/hp"; mkdir -p "$P/.claude-mind"

# Ohne Wurzel: UNBEKANNT, nicht "gesund".
AUS=$(CLAUDE_PLUGIN_ROOT="" mind_hook_health "$P" 2>&1); RC=$?
pruefe "ohne CLAUDE_PLUGIN_ROOT: UNBEKANNT" "$(printf '%s' "$AUS" | grep -c 'UNBEKANNT')" "1"
pruefe "ohne Wurzel: Rueckgabe 1" "$RC" "1"

# Wurzel zeigt ins Leere: TOT.
AUS=$(CLAUDE_PLUGIN_ROOT="$T/weg" mind_hook_health "$P" 2>&1); RC=$?
pruefe "Wurzel ins Leere: TOT"    "$(printf '%s' "$AUS" | grep -c 'TOT')" "1"
pruefe "Wurzel ins Leere: Rueckgabe 1" "$RC" "1"

# Halbe Installation: UNVOLLSTAENDIG — genauso toedlich, nur leiser.
H="$T/halb"; mkdir -p "$H/hooks"
touch "$H/hooks/pre-compact.sh" "$H/hooks/prompt-submit.sh"   # zwei von vier
AUS=$(CLAUDE_PLUGIN_ROOT="$H" mind_hook_health "$P" 2>&1)
pruefe "halbe Installation: UNVOLLSTAENDIG" "$(printf '%s' "$AUS" | grep -c 'UNVOLLSTAENDIG')" "1"

# ⛔ Vollstaendige Installation OHNE Herzschlag: KEIN HERZSCHLAG.
#    Das ist die Gegenprobe, die zaehlt — ohne sie waere "meldet immer
#    UNVOLLSTAENDIG" gruen.
V="$T/voll"; mkdir -p "$V/hooks"
touch "$V/hooks/pre-compact.sh" "$V/hooks/prompt-submit.sh" \
      "$V/hooks/session-start.sh" "$V/hooks/stop.sh"
AUS=$(CLAUDE_PLUGIN_ROOT="$V" mind_hook_health "$P" 2>&1); RC=$?
pruefe "vollstaendig: NICHT mehr UNVOLLSTAENDIG" "$(printf '%s' "$AUS" | grep -c 'UNVOLLSTAENDIG')" "0"
pruefe "aber kein Herzschlag: gemeldet" "$(printf '%s' "$AUS" | grep -c 'KEIN HERZSCHLAG')" "1"
pruefe "kein Herzschlag: Rueckgabe 1" "$RC" "1"

echo
echo "=== $fehler Abweichung(en) ==="
exit $((fehler > 0 ? 1 : 0))
