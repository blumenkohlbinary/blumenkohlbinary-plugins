#!/usr/bin/env bash
# KONTEXT-BILANZ (v5.22.0) — was der Dauerkontext wirklich kostet.
#
# ⛔ WOZU. Gemessen 27.08.2026 wuchs der immer geladene Satz eines Projekts an
#    EINEM Tag um +19 460 B (+21 %). Bemerkt hat es niemand, weil ihn niemand
#    misst. `mind_kontext_bilanz` misst ihn; diese Sammlung misst die Messung.
#
# ⛔ DIE WICHTIGSTE PRUEFUNG IST DIE NEGATIVKONTROLLE (Fall 2). Eine Bilanz, die
#    immer "±0" meldet, ist von einer richtigen nicht zu unterscheiden — und
#    genau diese Sorte Stille hat dieses Projekt schon dreimal getaeuscht
#    (Rauschfilter v5.20.0, Zaehl-Gate, V0-Gate). Deshalb wird hier eine Datei
#    absichtlich um 1 000 Byte vergroessert, und die Bilanz MUSS das sehen.
#
# ⛔ DIE ZWEITWICHTIGSTE IST FALL 7. Topic-Dateien duerfen NICHT mitzaehlen: sie
#    laden hoechstens 5 pro Anfrage, ihr Wuchs kostet Auffindbarkeit statt Tokens.
#    Wer sie mitzaehlt, bekommt eine Zahl, die zwei verschiedene Dinge summiert
#    und fuer beide unbrauchbar ist.
#
# ⛔ HOME WIRD UMGEBOGEN. Diese Sammlung liest `$HOME/.claude/rules` und darf die
#    echten Regeln des Nutzers NIE anfassen — auch nicht lesend, sonst haengt das
#    Ergebnis an seinem Regelbestand und schwankt von Tag zu Tag.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_kontext_bilanz.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
LIB="$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
[ -f "$LIB" ] || { echo "lib.sh fehlt: $LIB" >&2; exit 2; }
OK=0; ROT=0

janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

groesser() { # $1=Name  $2=Untergrenze(exklusiv)  $3=Istwert
  if [ "$3" -gt "$2" ] 2>/dev/null; then echo "  [ok ] $1"; OK=$((OK+1))
  else echo "  [ROT] $1 — erwartet >$2, bekommen '$3'"; ROT=$((ROT+1)); fi; }

feld() { echo "$1" | head -1 | tr ' ' '\n' | grep -m1 "^$2=" | cut -d= -f2; }

# --- Wegwerf-Welt: eigenes Projekt UND eigenes HOME --------------------------
bau() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/heim/.claude/rules" "$d/proj/.claude/rules"
  printf '# Heim\n\nALWAYS die globale Regel beachten.\n' > "$d/heim/.claude/CLAUDE.md"
  printf -- '---\ndescription: globale Testregel\nglobs: ["**/*"]\n---\n\n# G\n\nMUST global gelten.\n' \
    > "$d/heim/.claude/rules/global.md"
  printf '# Projekt\n\nNEVER blind loeschen.\n' > "$d/proj/CLAUDE.md"
  printf -- '---\ndescription: Projektregel\nglobs: ["**/*"]\n---\n\n# P\n\nMUST hier gelten.\n' \
    > "$d/proj/.claude/rules/projekt.md"
  echo "$d"
}

bilanz() { # $1=HOME-Wurzel $2=Projekt  [$3=Modus]  -> volle Ausgabe
  ( export HOME="$1"; export CLAUDE_PLUGIN_ROOT
    # shellcheck disable=SC1090
    . "$LIB" >/dev/null 2>&1
    mind_kontext_bilanz "$2" "${3:-}" 2>/dev/null )
}

echo "== 1/10  Grundmessung: die vier Dateien werden gefunden =="
D=$(bau)
A=$(bilanz "$D/heim" "$D/proj")
janein "4 Dateien gezaehlt (2x CLAUDE.md, 2x rules)" "4" "$(feld "$A" DATEIEN)"
groesser "Zeilen > 0" "0" "$(feld "$A" ZEILEN)"
janein "3 Anweisungszeilen (ALWAYS, MUST, NEVER, MUST)" "4" "$(feld "$A" ANWEISUNGEN)"

echo "== 2/10  NEGATIVKONTROLLE: +1000 Byte MUESSEN sichtbar werden =="
VOR_B=$(feld "$A" BYTES); VOR_Z=$(feld "$A" ZEILEN)
bilanz "$D/heim" "$D/proj" --merken >/dev/null
# genau 1000 Byte anhaengen, verteilt auf 20 Zeilen a 50 Byte
i=0; while [ $i -lt 20 ]; do
  printf '%s\n' "0123456789012345678901234567890123456789012345678" \
    >> "$D/proj/.claude/rules/projekt.md"; i=$((i+1)); done
B=$(bilanz "$D/heim" "$D/proj" --vergleichen)
NEU_B=$(feld "$B" BYTES); NEU_Z=$(feld "$B" ZEILEN)
janein "BYTES exakt +1000" "$((VOR_B + 1000))" "$NEU_B"
janein "ZEILEN exakt +20"  "$((VOR_Z + 20))"   "$NEU_Z"
janein "Berichtszeile nennt den Zuwachs" "ja" \
  "$(echo "$B" | grep -q 'Dauerkontext:.*(+20)' && echo ja || echo nein)"
rm -rf "$D"

echo "== 3/10  Lauf OHNE Aenderung meldet +0 =="
D=$(bau)
bilanz "$D/heim" "$D/proj" --merken >/dev/null
C=$(bilanz "$D/heim" "$D/proj" --vergleichen)
janein "Zeilen ±0" "ja" "$(echo "$C" | grep -q '(+0)' && echo ja || echo nein)"
rm -rf "$D"

echo "== 4/10  Grenzfall: Projekt OHNE .claude/rules/ stuerzt nicht ab =="
D=$(bau); rm -rf "$D/proj/.claude"
E=$(bilanz "$D/heim" "$D/proj"); RC=$?
janein "Rueckgabe 0 (Heim-Dateien sind ja da)" "0" "$RC"
janein "2 Dateien (Projekt-CLAUDE.md + Heim)" "3" "$(feld "$E" DATEIEN)"
rm -rf "$D"

echo "== 5/10  Grenzfall: voellig leeres Projekt UND leeres Heim -> Rueckgabe 1 =="
D=$(mktemp -d); mkdir -p "$D/heim" "$D/proj"
F=$(bilanz "$D/heim" "$D/proj"); RC=$?
janein "Rueckgabe 1 = nichts messbar" "1" "$RC"
janein "DATEIEN=0" "0" "$(feld "$F" DATEIEN)"
rm -rf "$D"

echo "== 6/10  Grenzfall: CRLF veraendert die Zeilenzahl NICHT =="
D=$(bau)
G=$(bilanz "$D/heim" "$D/proj"); LF_Z=$(feld "$G" ZEILEN)
# dieselbe Datei auf CRLF drehen
python -c "
import sys
p = sys.argv[1]
b = open(p,'rb').read().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
open(p,'wb').write(b)
" "$D/proj/.claude/rules/projekt.md"
H=$(bilanz "$D/heim" "$D/proj"); CRLF_Z=$(feld "$H" ZEILEN)
janein "Zeilenzahl bei CRLF unveraendert" "$LF_Z" "$CRLF_Z"
rm -rf "$D"

echo "== 7/10  NEGATIVKONTROLLE: Topic-Dateien zaehlen NICHT mit =="
D=$(bau)
SLUG=$( export HOME="$D/heim"; . "$LIB" >/dev/null 2>&1; hash_project_dir "$D/proj" )
MEM="$D/heim/.claude/projects/$SLUG/memory"
mkdir -p "$MEM"
printf '# Memory\n\n- [Thema A](thema-a.md) — kurz\n' > "$MEM/MEMORY.md"
I=$(bilanz "$D/heim" "$D/proj"); MIT_INDEX=$(feld "$I" DATEIEN)
janein "MEMORY.md zaehlt MIT (5 statt 4)" "5" "$MIT_INDEX"
# jetzt 30 Topic-Dateien mit je 40 Zeilen dazu — die Bilanz darf sich NICHT ruehren
Z_VOR=$(feld "$I" ZEILEN)
n=0; while [ $n -lt 30 ]; do
  { printf -- '---\nname: t%s\ndescription: Testthema %s\n---\n\n' "$n" "$n"
    k=0; while [ $k -lt 40 ]; do echo "MUST Zeile $k"; k=$((k+1)); done
  } > "$MEM/thema-$n.md"; n=$((n+1)); done
J=$(bilanz "$D/heim" "$D/proj")
janein "DATEIEN unveraendert trotz 30 Topic-Dateien" "$MIT_INDEX" "$(feld "$J" DATEIEN)"
janein "ZEILEN unveraendert trotz 1200 Topic-Zeilen" "$Z_VOR" "$(feld "$J" ZEILEN)"
rm -rf "$D"

echo "== 8/10  Datei OHNE abschliessenden Umbruch verliert keine Zeile =="
D=$(mktemp -d); mkdir -p "$D/heim/.claude" "$D/proj"
printf 'Zeile1\nZeile2\nZeile3' > "$D/proj/CLAUDE.md"   # KEIN \n am Ende
K=$(bilanz "$D/heim" "$D/proj")
janein "3 Zeilen trotz fehlendem Umbruch" "3" "$(feld "$K" ZEILEN)"
rm -rf "$D"

echo "== 9/10  Unparsbarer Vorstand erzeugt KEINEN Scheinzuwachs =="
# ⛔ JE FALL GENAU EIN SIGNAL. Die erste Fassung schrieb 'kaputt\nZEILEN=abc' —
#    da fehlte ANWEISUNGEN= ganz, der Fall bestand also aus ZWEI Gruenden, und
#    eine Sabotage am ZEILEN-Zweig blieb unsichtbar (Gegenkontrolle S3, gefunden
#    27.08.2026). Jetzt ist ANWEISUNGEN gueltig und NUR ZEILEN kaputt.
D=$(bau)
mkdir -p "$D/proj/.claude-mind"
printf 'ZEILEN=abc\nANWEISUNGEN=4\nDATEIEN=4\nBYTES=300\n' \
  > "$D/proj/.claude-mind/kontext-bilanz"
L=$(bilanz "$D/heim" "$D/proj" --vergleichen)
janein "9a nur ZEILEN kaputt -> 'Vorstand unlesbar'" "ja" \
  "$(echo "$L" | grep -q 'Vorstand unlesbar' && echo ja || echo nein)"
janein "9a nennt KEINE Pfeil-Differenz" "ja" \
  "$(echo "$L" | grep -q ' -> ' && echo nein || echo ja)"
rm -rf "$D"
# zweiter Fall, EIN anderes Signal: nur ANWEISUNGEN kaputt
D=$(bau)
mkdir -p "$D/proj/.claude-mind"
printf 'ZEILEN=10\nANWEISUNGEN=xyz\nDATEIEN=4\nBYTES=300\n' \
  > "$D/proj/.claude-mind/kontext-bilanz"
L2=$(bilanz "$D/heim" "$D/proj" --vergleichen)
janein "9b nur ANWEISUNGEN kaputt -> 'Vorstand unlesbar'" "ja" \
  "$(echo "$L2" | grep -q 'Vorstand unlesbar' && echo ja || echo nein)"
rm -rf "$D"
# dritter Fall: gar keine Standdatei -> "erster Lauf", NICHT "unlesbar"
D=$(bau)
L3=$(bilanz "$D/heim" "$D/proj" --vergleichen)
janein "9c ohne Standdatei -> 'erster Lauf'" "ja" \
  "$(echo "$L3" | grep -q 'erster Lauf' && echo ja || echo nein)"
rm -rf "$D"

echo "== 10/10  --merken schreibt den Stand, --vergleichen liest ihn =="
D=$(bau)
bilanz "$D/heim" "$D/proj" --merken >/dev/null
janein "Standdatei existiert" "ja" \
  "$([ -f "$D/proj/.claude-mind/kontext-bilanz" ] && echo ja || echo nein)"
janein "Standdatei traegt einen Zeitstempel" "ja" \
  "$(grep -q '^TS=' "$D/proj/.claude-mind/kontext-bilanz" && echo ja || echo nein)"
# ohne Modus wird NICHT geschrieben
rm -f "$D/proj/.claude-mind/kontext-bilanz"
bilanz "$D/heim" "$D/proj" >/dev/null
janein "ohne Modus wird NICHTS geschrieben" "nein" \
  "$([ -f "$D/proj/.claude-mind/kontext-bilanz" ] && echo ja || echo nein)"
rm -rf "$D"

echo
echo "  $OK ok, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
