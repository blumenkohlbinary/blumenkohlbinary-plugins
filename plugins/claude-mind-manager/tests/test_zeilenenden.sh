#!/usr/bin/env bash
# =============================================================================
#  Der Zeilenenden-Waechter — die Sperre, die selbst kaputt war  (NEU v5.13.0)
# =============================================================================
#
# ⛔ WARUM ES DIESE SAMMLUNG GIBT
#
# `mind_zeilenenden_gleich` ist die Sperre gegen die Fehlerklasse `zeilenenden`
# (4 Vorkommen im Debug-Ordner). Sie wurde in v5.11.0 gebaut — und hatte ZWEI
# Defekte, die zusammen dafuer sorgten, dass sie praktisch nichts geprueft hat:
#
#   1. Sie verglich `${vorher%%/*}` — den ZAEHLER, also die absolute CRLF-Zahl.
#      Eine gewachsene Datei (155/155 -> 157/157) galt als GEKIPPT.
#      Ihr eigener Kommentar behauptete drei Zeilen darueber das Gegenteil.
#   2. Der Aufrufer bildete `$PROJ/$z` fuer jeden Snapshot-Pfad. Ein Snapshot
#      hat vier Zweige, keiner davon liegt unter `$PROJ/<zweig>/`.
#      GEMESSEN: 1 von 68 Dateien verglichen, Meldung "keine Abweichung".
#
# ⭐ Beide zusammen sind ein `instrument-misst-nichts` — die groesste Klasse im
#    Debug-Ordner (23 Vorkommen). Eine Sperre gegen eine Fehlerklasse, die
#    selbst zu dieser Fehlerklasse gehoert.
#
# Deshalb prueft diese Sammlung BEIDE RICHTUNGEN und zusaetzlich die ZAHL:
# ein Waechter, der fast nichts vergleicht, muss ROT werden, nicht gruen.
# =============================================================================
set -u
WURZEL="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck disable=SC1091
. "$WURZEL/hooks/lib.sh"

fehler=0
pruefe() {  # name ist soll
  if [ "$2" = "$3" ]; then
    printf '    OK   %-50s ist=%-9s soll=%s\n' "$1" "$2" "$3"
  else
    printf '    FEHL %-50s ist=%-9s soll=%s\n' "$1" "$2" "$3"
    fehler=$((fehler + 1))
  fi
}

echo "=============================================================================="
echo "  1) mind_zeilenenden_gleich — der ANTEIL, nicht die Zahl"
echo "=============================================================================="

# ⛔ DER FALL, DER DEN DEFEKT AUSGELOEST HAT. Datei waechst von 155 auf 157
#    Zeilen, durchgehend CRLF. Der Anteil ist unveraendert -> GLEICH.
mind_zeilenenden_gleich "155/155" "157/157"; pruefe "gewachsen, durchgehend CRLF" "$?" "0"
mind_zeilenenden_gleich "0/155"   "0/157";   pruefe "gewachsen, durchgehend LF"   "$?" "0"

# Die andere Richtung: die Kontrolle muss SCHEITERN KOENNEN.
mind_zeilenenden_gleich "0/100"   "100/100"; pruefe "LF komplett nach CRLF gekippt" "$?" "1"
mind_zeilenenden_gleich "100/100" "0/100";   pruefe "CRLF komplett nach LF gekippt" "$?" "1"

# ⚠ EINE einzelne gekippte Zeile in einer grossen Datei. Mit Prozentrechnung
#   in Ganzzahlen (1 von 1000 = 0 %) waere das unsichtbar — und genau die eine
#   Zeile reisst einen Ersetzungsanker.
mind_zeilenenden_gleich "1000/1000" "999/1000"; pruefe "EINE Zeile von 1000 gekippt" "$?" "1"

# Grenzfaelle
mind_zeilenenden_gleich "0/0" "0/0";   pruefe "zwei leere Dateien"          "$?" "0"
mind_zeilenenden_gleich "0/0" "0/50";  pruefe "leer gegen reines LF (0 %)"  "$?" "0"
mind_zeilenenden_gleich "x/y" "0/50";  pruefe "unlesbar -> NICHT MESSBAR"   "$?" "2"
mind_zeilenenden_gleich ""    "0/50";  pruefe "leer -> NICHT MESSBAR"       "$?" "2"

echo
echo "=============================================================================="
echo "  2) mind_schnappziel — alle vier Zweige"
echo "=============================================================================="
P="/tmp/zzproj"; M="/tmp/zzmem"
pruefe "Wurzel"    "$(mind_schnappziel 'CLAUDE.md' "$P" "$M")"                 "$P/CLAUDE.md"
pruefe "project/"  "$(mind_schnappziel 'project/knowledge/a.md' "$P" "$M")"    "$P/knowledge/a.md"
pruefe "rules/"    "$(mind_schnappziel 'rules/hooks.md' "$P" "$M")"            "$P/.claude/rules/hooks.md"
pruefe "global/"   "$(mind_schnappziel 'global/rules/x.md' "$P" "$M")"         "$HOME/.claude/rules/x.md"
pruefe "memory/"   "$(mind_schnappziel 'memory/MEMORY.md' "$P" "$M")"          "$M/MEMORY.md"
# Ohne Memory-Verzeichnis darf er NICHT raten.
mind_schnappziel 'memory/MEMORY.md' "$P" "" >/dev/null 2>&1
pruefe "memory/ ohne Verzeichnis -> kein Ziel" "$?" "1"
mind_schnappziel 'MANIFEST.sha256' "$P" "$M" >/dev/null 2>&1
pruefe "MANIFEST ist kein Projektfile"         "$?" "1"
mind_schnappziel 'unbekannt/x.md' "$P" "$M" >/dev/null 2>&1
pruefe "unbekannter Zweig -> melden statt raten" "$?" "1"

echo
echo "=============================================================================="
echo "  3) Der ganze Durchlauf gegen einen kuenstlichen Snapshot"
echo "=============================================================================="

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
SNAP="$T/snap"; PROJ="$T/proj"; MEM="$T/mem"
mkdir -p "$SNAP/project/knowledge" "$SNAP/rules" "$SNAP/memory" \
         "$PROJ/knowledge" "$PROJ/.claude/rules" "$MEM"

# Vorher-Stand: vier Dateien, alle LF.
printf 'a\nb\nc\n' > "$SNAP/CLAUDE.md"
printf 'a\nb\nc\n' > "$SNAP/project/knowledge/wissen.md"
printf 'a\nb\nc\n' > "$SNAP/rules/regel.md"
printf 'a\nb\nc\n' > "$SNAP/memory/MEMORY.md"

# Nachher: drei unveraendert (eine davon GEWACHSEN — darf nicht anschlagen),
# GENAU EINE nach CRLF gekippt.
printf 'a\nb\nc\n'            > "$PROJ/CLAUDE.md"
printf 'a\nb\nc\nd\ne\n'      > "$PROJ/knowledge/wissen.md"     # gewachsen, LF
printf 'a\r\nb\r\nc\r\n'      > "$PROJ/.claude/rules/regel.md"  # GEKIPPT
printf 'a\nb\nc\n'            > "$MEM/MEMORY.md"

AUS=$(mind_zeilenenden_waechter "$SNAP" "$PROJ" "$MEM"); RC=$?
echo "$AUS" | sed 's/^/    | /'
KOPF=$(echo "$AUS" | head -1)
pruefe "alle vier Zweige verglichen" "${KOPF%% *}" "VERGLICHEN=4"
pruefe "genau eine gekippt"          "$(echo "$KOPF" | grep -o 'GEKIPPT=[0-9]*')" "GEKIPPT=1"
pruefe "die richtige Datei gemeldet" "$(echo "$AUS" | grep -c 'rules/regel.md')"  "1"
pruefe "gewachsene Datei NICHT gemeldet" "$(echo "$AUS" | grep -c 'wissen.md')"   "0"
pruefe "Rueckgabe 1 bei Kipp"        "$RC" "1"

# --- Negativkontrolle A: nichts gekippt -> muss GRUEN sein --------------------
printf 'a\nb\nc\n' > "$PROJ/.claude/rules/regel.md"
AUS2=$(mind_zeilenenden_waechter "$SNAP" "$PROJ" "$MEM"); RC2=$?
pruefe "ohne Kipp Rueckgabe 0" "$RC2" "0"
pruefe "ohne Kipp GEKIPPT=0"   "$(echo "$AUS2" | head -1 | grep -o 'GEKIPPT=[0-9]*')" "GEKIPPT=0"

# --- Negativkontrolle B: DER FALL, DER DURCHGERUTSCHT IST ---------------------
# Nur die Wurzeldatei ist abbildbar -> der Waechter hat praktisch nichts
# geprueft und MUSS das als eigenen Zustand melden (2), nicht als "gruen".
SNAP2="$T/snap2"; mkdir -p "$SNAP2"
printf 'a\nb\n' > "$SNAP2/CLAUDE.md"
AUS3=$(mind_zeilenenden_waechter "$SNAP2" "$PROJ" "$MEM"); RC3=$?
pruefe "nur 1 Datei -> UNGUELTIG (2)" "$RC3" "2"
pruefe "und sagt die Zahl"            "$(echo "$AUS3" | head -1 | cut -d' ' -f1)" "VERGLICHEN=1"

# --- Negativkontrolle C: kein Snapshot ---------------------------------------
mind_zeilenenden_waechter "$T/gibtsnicht" "$PROJ" "$MEM" >/dev/null 2>&1
pruefe "fehlender Snapshot -> UNGUELTIG (2)" "$?" "2"

echo
echo "=== $fehler Abweichung(en) ==="
exit $((fehler > 0 ? 1 : 0))
