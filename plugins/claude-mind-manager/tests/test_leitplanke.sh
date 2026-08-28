#!/usr/bin/env bash
# LEITPLANKE + GATE 5 (v5.24.0) — was `cleaner_umzug.py` bisher durchliess.
#
# ⛔ DER ANLASS, gemessen am eigenen Lauf 28.08.2026. `cleaner_umzug.py` sagt im
#    eigenen Kopf "EIN UMZUG VERSCHIEBT. ER KUERZT NICHT" — also blieb
#    `workstation-fernzugriff` nach dem Umzug bei 63 Zeilen liegen, waehrend die
#    vier Geschwister bei 19-33 lagen. Kein Gate fragte danach.
#
# ⛔ FALL 3 IST DER WICHTIGSTE und der Grund fuer die ganze Sammlung:
#    Gate 1 (ERHALTUNG) zaehlt ZEILEN. Beim Kuerzen 63 -> 36 war der Skill 705
#    Zeilen lang, also 36 + 705 >= 63 — Gate 1 haelt muehelos, und der Punkt
#    "das -i ist meist noetig / gnome-session haelt einen block-Inhibitor" waere
#    trotzdem ersatzlos verschwunden. Gate 5 (INHALT) faengt genau das.
#
# ⭐ FALL 4 IST DIE LEHRE AUS DEM BAU. Die erste Fassung von Gate 5 meldete den
#    echten Fall — aber aus dem FALSCHEN GRUND: die Backtick-Regex paarte das
#    schliessende Backtick von `-i` mit dem oeffnenden von `gnome-session` und
#    fing die Prosa dazwischen ein. Die POSITIVKONTROLLE war gruen und wertlos.
#    Aufgefallen ist es erst, weil die NEGATIVKONTROLLE ebenfalls rot blieb.
#    Deshalb steht hier IMMER ein Paar, nie ein einzelner Fall.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_leitplanke.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
LP="$CLAUDE_PLUGIN_ROOT/references/cleaner_leitplanke.py"
UZ="$CLAUDE_PLUGIN_ROOT/references/cleaner_umzug.py"
SK="$CLAUDE_PLUGIN_ROOT/skills/mind-cleaner/SKILL.md"
for f in "$LP" "$UZ" "$SK"; do
  [ -f "$f" ] || { echo "fehlt: $f" >&2; exit 2; }
done
command -v cygpath >/dev/null 2>&1 && W=cygpath || W=echo
OK=0; ROT=0
janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }
w() { if [ "$W" = cygpath ]; then cygpath -w "$1"; else echo "$1"; fi; }

echo "== 1/5  cleaner_leitplanke: Selbsttest + Verdrahtung =="
janein "Selbsttest gruen" "0" "$(python "$(w "$LP")" --selbsttest >/dev/null 2>&1; echo $?)"
janein "mind-cleaner ruft cleaner_leitplanke" "1" "$(grep -c 'cleaner_leitplanke.py' "$SK")"
# ⛔ ZEILEN, DIE DEN ALTSTAND ZITIEREN, ZAEHLEN NICHT MIT. Der neue Abschnitt
#    benennt den alten Satz ausdruecklich ("Hier stand bis v5.23.1 …") — die erste
#    Fassung dieses Falls fand genau diese Widerlegung und meldete ROT.
#    Das ist heute der DRITTE Selbsttreffer dieser Art (Paket-Grep nach der
#    erfundenen Regel · $CLAUDE_PROJECT_DIR im Kommentar · dieser). Klasse
#    `instrument-misst-nichts`. Erste Frage bei jedem negativen Ergebnis bleibt:
#    hat das Instrument den Gegenstand ueberhaupt erreicht?
janein "Step 4 sagt nicht mehr 'kein Werkzeug'" "0" \
  "$(grep 'Hier gibt es kein Werkzeug' "$SK" | grep -vc 'stand bis')"
janein "Bremse-gegen-Anleitung steht im Skill" "ja" \
  "$(grep -qE 'Bremse\*\* hält dich|Bremse gegen Anleitung' "$SK" && echo ja || echo nein)"

echo "== 2/5  Formklassen: trennt es Bremse von Mechanik? =="
D=$(mktemp -d)
printf '# X\n\n```bash\nsudo -n systemctl poweroff -i\n```\n' > "$D/befehl.md"
printf '# X\n\nDie MAC 30:c5:99:aa:56:b4 traegt das LAN.\n'    > "$D/adresse.md"
printf '# X\n\nFreigabe in /etc/sudoers.d/ki-befehle.\n'        > "$D/syspfad.md"
printf '# X\n\n⛔ Die MAC 30:c5:99:aa:56:b4 NIE aendern.\n'     > "$D/bremse.md"
printf '# X\n\nRoh gemessen 834-941 MB/s, sonst Fehlmessung.\n' > "$D/zahl.md"
printf '# X\n\n```bash\nssh … "kein-suspend an <was>"\n```\n'   > "$D/platzhalter.md"
for n in befehl adresse syspfad; do
  janein "$n wird als Kandidat gemeldet" "1" \
    "$(python "$(w "$LP")" --rule "$(w "$D/$n.md")" >/dev/null 2>&1; echo $?)"
done
# ⛔ NEGATIVKONTROLLEN — ohne sie waere ein Filter, der ALLES meldet, ebenso gruen.
for n in bremse zahl platzhalter; do
  janein "$n bleibt VERSCHONT" "0" \
    "$(python "$(w "$LP")" --rule "$(w "$D/$n.md")" >/dev/null 2>&1; echo $?)"
done

echo "== 3/5  ⛔ Gate 5 faengt, was Gate 1 durchlaesst =="
mkdir -p "$D/g5"
# Alt traegt eine Marke, die NUR dort steht.
printf '# Alt\n\nMUST etwas beachten.\nDer Punkt mit `gnome-session` ist wichtig.\n' \
  > "$D/g5/alt.md"
printf '# Kurz\n\nMUST etwas beachten.\nVolltext: `~/.claude/skills/g5/SKILL.md` bzw. /g5\n' \
  > "$D/g5/kurz.md"
mkdir -p "$D/g5/skills/g5"
# Skill OHNE die Marke — aber LANG, damit Gate 1 muehelos haelt.
{ printf -- '---\ndescription: Ein Skill mit ausreichend langer Beschreibung fuer das Gate vier hier\n---\n\n# Voll\n\n'
  i=0; while [ $i -lt 60 ]; do echo "Fuellzeile $i mit Inhalt."; i=$((i+1)); done; } \
  > "$D/g5/skills/g5/SKILL.md"
AUS=$(python "$(w "$UZ")" --alt "$(w "$D/g5/alt.md")" --kurz "$(w "$D/g5/kurz.md")" \
       --skill "$(w "$D/g5/skills/g5/SKILL.md")" 2>&1)
janein "3a ERHALTUNG haelt (Zeilen reichen)" "ja" \
  "$(echo "$AUS" | grep -q 'OK.*ERHALTUNG' && echo ja || echo nein)"
janein "3b INHALT bricht auf der fehlenden Marke" "ja" \
  "$(echo "$AUS" | grep -q 'BRUCH.*INHALT' && echo ja || echo nein)"
janein "3c die Marke wird BENANNT" "ja" \
  "$(echo "$AUS" | grep -q 'gnome-session' && echo ja || echo nein)"
# ⛔ NEGATIVKONTROLLE: Marke im Skill ergaenzt -> Gate 5 MUSS halten.
echo 'Der Punkt mit `gnome-session` steht jetzt hier.' >> "$D/g5/skills/g5/SKILL.md"
AUS2=$(python "$(w "$UZ")" --alt "$(w "$D/g5/alt.md")" --kurz "$(w "$D/g5/kurz.md")" \
        --skill "$(w "$D/g5/skills/g5/SKILL.md")" 2>&1)
janein "3d nach dem Nachtrag haelt INHALT" "ja" \
  "$(echo "$AUS2" | grep -q 'OK.*INHALT' && echo ja || echo nein)"

echo "== 4/5  ⭐ Backtick-Paarung: die Marke muss ECHT sein =="
# ⛔ Die erste Fassung machte aus **Das `-i` ist meist noetig**: `gnome-session`
#    die Marke "ist meist noetig**:" — schliessendes Backtick des einen Spans mit
#    dem oeffnenden des naechsten. Gate 5 meldete den richtigen Fall aus dem
#    falschen Grund.
printf '# Alt\n\n**Das `-i` ist meist noetig**: `gnome-session` blockt.\n' > "$D/bt.md"
MARK=$(python -c "
import sys, io, importlib.util
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
s = importlib.util.spec_from_file_location('u', sys.argv[1])
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print('|'.join(sorted(m.marken(open(sys.argv[2], encoding='utf-8').read()))))
" "$(w "$UZ")" "$(w "$D/bt.md")" 2>/dev/null)
# ⛔ KEINE BACKTICKS IN DER BESCHRIFTUNG — bash fuehrt sie aus. Die erste Fassung
#    schrieb "`gnome-session` wird erkannt" und die Shell meldete
#    "gnome-session: command not found". Dokumentierte Falle, trotzdem getreten.
janein "4a Marke gnome-session wird erkannt" "ja" \
  "$(echo "$MARK" | grep -q 'gnome-session' && echo ja || echo nein)"
janein "4b die Prosa DAZWISCHEN wird es NICHT" "nein" \
  "$(echo "$MARK" | grep -q 'ist meist noetig' && echo ja || echo nein)"

echo "== 5/5  Der Command ist HINWEIS, der Pfad bleibt Gate =="
janein "5a Kurz ohne Command -> kein Bruch" "ja" \
  "$(printf '# Kurz\n\nMUST etwas.\nVolltext: `~/.claude/skills/g5/SKILL.md`\n' > "$D/g5/kurz2.md"
     python "$(w "$UZ")" --alt "$(w "$D/g5/alt.md")" --kurz "$(w "$D/g5/kurz2.md")" \
       --skill "$(w "$D/g5/skills/g5/SKILL.md")" 2>&1 \
     | grep -q 'BRUCH.*PFAD' && echo nein || echo ja)"
janein "5b Kurz ohne PFAD -> PFAD bricht sehr wohl" "ja" \
  "$(printf '# Kurz\n\nMUST etwas.\nVolltext: /g5\n' > "$D/g5/kurz3.md"
     python "$(w "$UZ")" --alt "$(w "$D/g5/alt.md")" --kurz "$(w "$D/g5/kurz3.md")" \
       --skill "$(w "$D/g5/skills/g5/SKILL.md")" 2>&1 \
     | grep -q 'BRUCH.*PFAD' && echo ja || echo nein)"
janein "5c mind-cleaner sagt: Command ersetzt den Pfad NICHT" "1" \
  "$(grep -c 'Command ersetzt den Pfad NICHT' "$SK")"

rm -rf "$D"
echo
echo "  $OK ok, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
