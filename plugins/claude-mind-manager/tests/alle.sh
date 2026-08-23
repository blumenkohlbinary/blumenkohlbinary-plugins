#!/usr/bin/env bash
# =============================================================================
#  tests/alle.sh — faehrt ALLE Pruefsammlungen  (NEU v5.13.0)
# =============================================================================
#
# ⛔ WARUM ES DAS GIBT
#
# Bis v5.12.0 lagen 11 Pruefsammlungen in tests/ und es gab KEINEN Sammel-Laeufer.
# Wer pruefen wollte, rief einzelne Dateien NAMENTLICH auf — und meldete danach
# "alle Prueffaelle gruen". Am 23.08.2026 stellte sich heraus, dass
# `test_precompact.py` in keinem dieser Laeufe je dabei war.
#
# Das verletzt `fertig-heisst-fertig.md` §1 woertlich:
#   "Zahl ausgefuehrter Prueffaelle == Zahl vorhandener Prueffaelle."
#
# Und es ist die Ursache dahinter, dass zwei kaputte Messinstrumente (F2/F3 der
# v5.13.0-Runde) lange ueberlebt haben: sie hatten Prueffaelle, die niemand rief.
#
# ⚠ EINE KORREKTUR, DIE HIERHER GEHOERT: Die erste Fassung dieses Kommentars
#   behauptete, `test_precompact.py` sei ROT. Beim ersten Lauf war sie das, beim
#   zweiten gruen — ohne Codeaenderung. Grund: sie waehlt `kandidaten[1]`, das
#   zweitkleinste Transkript im Projektordner, und das ist je nach Sitzungsbestand
#   ein anderes. Ein Prueffall, dessen Urteil davon abhaengt, welche Datei er
#   zufaellig greift, kann einen Defekt ANZEIGEN, aber nie AUSSCHLIESSEN.
#   Deshalb liegt seit v5.13.0 `test_sampler_filter.py` daneben: feste Eingaben,
#   festes Urteil.
#
# ⛔ DIE BAUART, DAMIT ER NICHT DASSELBE PROBLEM BEKOMMT
#
#   1. Er FINDET die Sammlungen (find), er LISTET sie nicht auf. Eine Liste veraltet
#      in dem Moment, in dem jemand eine Datei dazulegt — genau der Fehler, den dieses
#      Skript beheben soll. Waere hier eine Liste, waere es sein eigener Vorgaenger.
#   2. Er meldet GEFUNDEN / GEFAHREN / GRUEN. Weichen die ersten beiden voneinander ab,
#      ist das ein ABBRUCH, keine Fussnote.
#   3. Er ueberschreibt CLAUDE_PLUGIN_ROOT NICHT. Drei Sammlungen taten das frueher und
#      liefen dadurch am Quellbaum statt am gebauten Paket — entgegen ihrer eigenen
#      README und entgegen `fertig-heisst-fertig.md` §1.
#
# Aufruf:
#   tests/alle.sh                  alles  (~55 s)
#   tests/alle.sh --liste          nur zeigen, was gefunden wuerde
#
# ⚠ Es gibt BEWUSST keinen Schnellmodus. Der ganze Bestand laeuft in unter einer
#   Minute, und eine Teilmenge zu fahren ist genau die Gewohnheit, aus der dieses
#   Skript entstanden ist.
#
# Rueckgabe: 0 = alles gruen · 1 = mindestens eine Sammlung rot · 2 = Zaehlung uneins
# =============================================================================
set -u

HIER="$(cd "$(dirname "$0")" && pwd)"
WURZEL="${CLAUDE_PLUGIN_ROOT:-$(cd "$HIER/.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$WURZEL"

NUR_LISTE=0
for a in "$@"; do
  case "$a" in
    --liste)   NUR_LISTE=1 ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    *) echo "unbekannte Option: $a" >&2; exit 2 ;;
  esac
done

# --- 1) FINDEN -------------------------------------------------------------
# Alles, was test_* heisst und .sh oder .py ist. Kein Muster von Hand gepflegt.
GEFUNDEN=()
while IFS= read -r f; do
  [ -n "$f" ] && GEFUNDEN+=("$f")
done < <(find "$HIER" -maxdepth 1 -type f \( -name 'test_*.sh' -o -name 'test_*.py' \) \
         | LC_ALL=C sort)

N=${#GEFUNDEN[@]}
if [ "$N" -eq 0 ]; then
  echo "ABBRUCH: keine Pruefsammlung in $HIER gefunden."
  echo "         Das ist NIE ein gutes Ergebnis — eher ein falscher Pfad."
  exit 2
fi

if [ "$NUR_LISTE" = 1 ]; then
  echo "$N Sammlungen gefunden:"
  for f in "${GEFUNDEN[@]}"; do echo "  $(basename "$f")"; done
  exit 0
fi

echo "======================================================================"
echo "  Pruefsammlungen — $(date '+%d.%m.%Y %H:%M')"
echo "  Wurzel: $WURZEL"
echo "======================================================================"
echo "  $N Sammlungen gefunden"
echo

# --- 2) FAHREN -------------------------------------------------------------
GEFAHREN=0
GRUEN=0
ROT=()
NICHT_GEFAHREN=()
LOGDIR="${TMPDIR:-/tmp}/mind-tests-$$"
mkdir -p "$LOGDIR"

for f in "${GEFUNDEN[@]}"; do
  base="$(basename "$f")"

  case "$base" in
    *.py) CMD=(python "$f") ;;
    *.sh) CMD=(bash "$f") ;;
    *)    # Kann heute nicht eintreten -- find und dieses case nennen dieselben
          # zwei Endungen. Der Zweig steht da, damit ein spaeterer `find`-Umbau
          # die Datei nicht STILL ueberspringt, sondern unten die Zaehlung reisst.
          NICHT_GEFAHREN+=("$base")
          printf '  %-28s NICHT GEFAHREN (unbekannte Endung)\n' "$base"
          continue ;;
  esac

  t0=$(date +%s)
  "${CMD[@]}" >"$LOGDIR/$base.log" 2>&1
  rc=$?
  t1=$(date +%s)
  GEFAHREN=$((GEFAHREN + 1))

  if [ "$rc" -eq 0 ]; then
    GRUEN=$((GRUEN + 1))
    printf '  %-28s GRUEN   (%ss)\n' "$base" "$((t1 - t0))"
  else
    ROT+=("$base")
    printf '  %-28s ROT     (Rueckgabe %s, %ss)\n' "$base" "$rc" "$((t1 - t0))"
  fi
done

# --- 3) ZAEHLEN ------------------------------------------------------------
# ⛔ Die eigentliche Zusicherung dieses Skripts. Sie greift auf ZAHLEN zu, nicht
#    auf Text — eine Kontrolle gegen einen formatierten Bericht ist am 21.08.2026
#    dreimal am falschen Gegenstand gescheitert.
echo
echo "----------------------------------------------------------------------"
printf '  gefunden %d · gefahren %d · gruen %d · rot %d\n' \
       "$N" "$GEFAHREN" "$GRUEN" "${#ROT[@]}"

# ⚠ EHRLICH DAZUGESAGT: Diese Zusicherung kann heute nicht ausloesen — `find`
#   und das `case` oben nennen dieselben zwei Endungen, also wird jede gefundene
#   Datei auch gefahren. Sie steht trotzdem hier, weil genau diese Annahme beim
#   naechsten Umbau kippt und der Ausfall dann STILL waere. Eine Zusicherung, die
#   heute strukturell haelt, ist billig; sie nicht zu haben, war teuer.
if [ "$GEFAHREN" -ne "$N" ]; then
  echo
  echo "⛔ ABBRUCH: gefahren ($GEFAHREN) != gefunden ($N)."
  for x in "${NICHT_GEFAHREN[@]:-}"; do [ -n "$x" ] && echo "   nicht gefahren: $x"; done
  echo "   Eine Sammlung wurde gefunden, aber nicht ausgefuehrt. Genau diese Luecke"
  echo "   ist der Grund, warum es dieses Skript gibt — sie darf nicht still bleiben."
  exit 2
fi

if [ "${#ROT[@]}" -gt 0 ]; then
  echo
  echo "  ROTE SAMMLUNGEN:"
  for r in "${ROT[@]}"; do
    echo "    - $r      Ausgabe: $LOGDIR/$r.log"
    sed -n '$p' "$LOGDIR/$r.log" | sed 's/^/        /'
  done
  echo
  echo "  ⚠ Ein roter Lauf ist ein BEFUND, kein Anlass, die Sammlung zu aendern."
  echo "    Pruefungen sind unantastbar (messung-vor-glauben.md §2)."
  exit 1
fi

echo
echo "  alles gruen. Ausgaben: $LOGDIR"
exit 0
