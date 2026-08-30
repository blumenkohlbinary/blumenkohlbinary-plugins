#!/usr/bin/env bash
# SCHRITT-QUITTUNG (v5.25.0) — fuehrt ein Lauf aus, was in seinem Skill steht?
#
# ⛔ DER ANLASS ist ein eigener /mind-cleaner-Lauf am 30.08.2026: vollstaendig
#    aussehender Bericht, und dabei cleaner_audit.py nie aufgerufen,
#    cleaner_belege.py gestartet und die Ausgabe weggegreppt, cleaner_leitplanke.py
#    ueber 5 von 11 Dateien als BEREICHSpruefung berichtet.
#    Der Bericht war nicht falsch — er war unvollstaendig, und das sah man ihm nicht an.
#
# ⛔ FALL 6 IST DER WICHTIGSTE: gar keine Quittung muss Rueckgabe 2 geben, nicht 0.
#    "Keine Auffaelligkeit" und "nie begonnen zu quittieren" duerfen sich nicht
#    gleich anfuehlen — genau diese Ununterscheidbarkeit ist der ganze Anlass
#    (v5.3.1: zwei Hooks mit 0 Log-Aufrufen · v5.19.0: Quittung im Ausfallpfad).
#
# ⭐ FALL 8 IST DIE POSITIVKONTROLLE AN ECHTEM MATERIAL: der Lauf vom 30.08. wird
#    nachgestellt, und die Bilanz MUSS "FEHLT: audit belege" und
#    "TEILABDECKUNG: leitplanke 5/11" melden. Ein konstruierter Fall bildet die
#    eigene Erwartung ab; dieser bildet ab, was wirklich passiert ist.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_schritt_quittung.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
LIB="$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
[ -f "$LIB" ] || { echo "lib.sh fehlt: $LIB" >&2; exit 2; }
OK=0; ROT=0
janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

# Jeder Fall in einer eigenen Subshell mit eigenem Wegwerf-Projekt.
lauf() {  # $1 = Skriptrumpf, der die Quittung fuellt -> Ausgabe der Bilanz
  ( D=$(mktemp -d); export D
    # shellcheck disable=SC1090
    . "$LIB" >/dev/null 2>&1
    eval "$1" >/dev/null 2>&1
    mind_schritt_bilanz "$D"; RC=$?
    echo "RC=$RC"
    rm -rf "$D" )
}

echo "== 1/9  Vollstaendiger Lauf =="
A=$(lauf 'mind_schritt_start "$D" x a b; mind_schritt a gelaufen 10 "$D"; mind_schritt b gelaufen 20 "$D"')
janein "Zeile 1 stimmt" "ERWARTET=2 GELAUFEN=2 UEBERSPRUNGEN=0 FEHLER=0 LEER=0" "$(echo "$A" | head -1)"
janein "Rueckgabe 0" "RC=0" "$(echo "$A" | grep '^RC=')"
# ⛔ NEGATIVKONTROLLE: ein vollstaendiger Lauf darf NICHTS melden.
janein "meldet KEIN FEHLT" "nein" "$(echo "$A" | grep -q 'FEHLT' && echo ja || echo nein)"

echo "== 2/9  Fehlender Schritt wird BENANNT =="
B=$(lauf 'mind_schritt_start "$D" x audit belege leitplanke; mind_schritt leitplanke gelaufen 5 "$D"')
janein "FEHLT nennt beide Namen" "ja" \
  "$(echo "$B" | grep -q 'FEHLT.*audit' && echo "$B" | grep -q 'FEHLT.*belege' && echo ja || echo nein)"
janein "Rueckgabe 1" "RC=1" "$(echo "$B" | grep '^RC=')"

echo "== 3/9  uebersprungen ist gueltig — mit Grund =="
C=$(lauf 'mind_schritt_start "$D" x a b; mind_schritt a gelaufen 10 "$D"; mind_schritt b "uebersprungen:kein Git" 0 "$D"')
janein "als UEBERSPRUNGEN gezaehlt" "1" "$(echo "$C" | head -1 | tr ' ' '\n' | grep '^UEBERSPRUNGEN=' | cut -d= -f2)"
janein "der GRUND steht dabei" "ja" "$(echo "$C" | grep -q 'kein Git' && echo ja || echo nein)"
# ⛔ Ein legitim entfallener Schritt ist KEIN Fehler — und 0 Bytes bei
#    uebersprungen darf nicht als LEER zaehlen.
janein "uebersprungen bricht nicht" "RC=0" "$(echo "$C" | grep '^RC=')"

echo "== 4/9  fehler: bricht =="
E=$(lauf 'mind_schritt_start "$D" x a; mind_schritt a "fehler:jq fehlt" -1 "$D"')
janein "FEHLER mit Grund" "ja" "$(echo "$E" | grep -q 'FEHLER:.*jq fehlt' && echo ja || echo nein)"
janein "Rueckgabe 1" "RC=1" "$(echo "$E" | grep '^RC=')"

echo "== 5/9  0 Bytes ist ein ERGEBNIS, kein fehlender Eintrag =="
F=$(lauf 'mind_schritt_start "$D" x a; mind_schritt a gelaufen 0 "$D"')
janein "als GELAUFEN gezaehlt" "1" "$(echo "$F" | head -1 | tr ' ' '\n' | grep '^GELAUFEN=' | cut -d= -f2)"
janein "UND als LEER gemeldet" "ja" "$(echo "$F" | grep -q 'LEER (lief' && echo ja || echo nein)"
janein "Rueckgabe 1" "RC=1" "$(echo "$F" | grep '^RC=')"
# ⛔ NEGATIVKONTROLLE: -1 heisst "nicht gemessen" und darf NICHT als LEER zaehlen.
G=$(lauf 'mind_schritt_start "$D" x a; mind_schritt a gelaufen "" "$D"')
janein "nicht gemessen ist NICHT leer" "nein" "$(echo "$G" | grep -q 'LEER (lief' && echo ja || echo nein)"

echo "== 6/9  ⛔ GAR KEINE Quittung -> Rueckgabe 2, nicht 0 =="
H=$(lauf 'true')
janein "Rueckgabe 2" "RC=2" "$(echo "$H" | grep '^RC=')"
janein "sagt ausdruecklich KEINE QUITTUNG" "ja" "$(echo "$H" | grep -q 'KEINE QUITTUNG' && echo ja || echo nein)"
janein "und dass das NICHT 'nichts zu melden' ist" "ja" \
  "$(echo "$H" | grep -q "NICHT 'nichts zu melden'" && echo ja || echo nein)"

echo "== 7/9  Skill ohne Pflichtaufrufe: ERWARTET=0, aber MIT Quittung =="
I=$(lauf 'mind_schritt_start "$D" mind-compact')
janein "ERWARTET=0" "0" "$(echo "$I" | head -1 | tr ' ' '\n' | grep '^ERWARTET=' | cut -d= -f2)"
janein "Rueckgabe 0" "RC=0" "$(echo "$I" | grep '^RC=')"
# ⛔ Das ist der Unterschied zu Fall 6: ERWARTET=0 heisst "nichts zu tun",
#    keine Quittung heisst "nie begonnen". Beides muss unterscheidbar bleiben.
janein "unterscheidet sich von Fall 6" "nein" \
  "$(echo "$I" | grep -q 'KEINE QUITTUNG' && echo ja || echo nein)"

echo "== 8/9  ⭐ POSITIVKONTROLLE: der /mind-cleaner-Lauf vom 30.08.2026 =="
# Genau das, was wirklich passiert ist: 10 Pflichtschritte deklariert, audit und
# belege nie quittiert, leitplanke ueber 5 von 11 Dateien.
J=$(lauf 'mind_schritt_start "$D" mind-cleaner snapshot fremdklon bestand laden einordnung leitplanke belege duplikate audit protokoll
  mind_schritt snapshot   gelaufen 200 "$D"
  mind_schritt fremdklon  gelaufen 60  "$D"
  mind_schritt bestand    gelaufen 900 "$D"
  mind_schritt laden      gelaufen 700 "$D"
  mind_schritt einordnung gelaufen 800 "$D"
  mind_schritt leitplanke "gelaufen:5/11" 600 "$D"
  mind_schritt duplikate  gelaufen 500 "$D"
  mind_schritt protokoll  gelaufen 80  "$D"')
janein "8a FEHLT nennt audit" "ja" "$(echo "$J" | grep -q 'FEHLT.*audit' && echo ja || echo nein)"
janein "8b FEHLT nennt belege" "ja" "$(echo "$J" | grep -q 'FEHLT.*belege' && echo ja || echo nein)"
janein "8c TEILABDECKUNG leitplanke 5/11" "ja" \
  "$(echo "$J" | grep -q 'TEILABDECKUNG: leitplanke 5/11' && echo ja || echo nein)"
janein "8d Rueckgabe 1 — der Lauf war unvollstaendig" "RC=1" "$(echo "$J" | grep '^RC=')"

echo "== 9/9  Verdrahtung: deklariert jeder Skill seine Pflichtschritte? =="
N=0; OHNE=""
for s in "$CLAUDE_PLUGIN_ROOT"/skills/*/SKILL.md; do
  N=$((N+1))
  # DIE MARKE, nicht das WORT. Es steht zweimal im Block (Ueberschrift und
  # Marke); ein grep auf das Wort kann "traegt den Block" nicht von "erwaehnt
  # ihn" unterscheiden. Gefunden von der Gegenkontrolle: eine Sabotage, die nur
  # die Ueberschrift zerstoerte, blieb unsichtbar. Zeilenende-tolerant wegen der zwei
  # CRLF-Skills.
  grep -qE '^PFLICHTSCHRITTE[[:space:]]*$' "$s" || OHNE="$OHNE $(basename "$(dirname "$s")")"
done
janein "alle $N Skills haben einen PFLICHTSCHRITTE-Block" "" "$OHNE"
# ⛔ KEIN HTML-Kommentar: mind-cleaner Step 5b sagt, HTML-Kommentare werden vor
#    der Injektion ENTFERNT. Ein dort abgelegter Block waere unsichtbar.
janein "kein Block als HTML-Kommentar abgelegt" "0" \
  "$(grep -l '<!-- PFLICHTSCHRITTE' "$CLAUDE_PLUGIN_ROOT"/skills/*/SKILL.md 2>/dev/null | wc -l)"
janein "alle rufen mind_schritt_start" "" \
  "$(for s in "$CLAUDE_PLUGIN_ROOT"/skills/*/SKILL.md; do
       grep -q 'mind_schritt_start' "$s" || printf ' %s' "$(basename "$(dirname "$s")")"; done)"
janein "alle weisen die Bilanz im Bericht aus" "" \
  "$(for s in "$CLAUDE_PLUGIN_ROOT"/skills/*/SKILL.md; do
       grep -q 'mind_schritt_bilanz' "$s" || printf ' %s' "$(basename "$(dirname "$s")")"; done)"

echo
echo "  $OK ok, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
