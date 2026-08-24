#!/usr/bin/env bash
# SELBSTWIDERSPRUCH (v5.20.0) — eine Ergaenzung ohne Ruecknahme ist ein Widerspruch.
#
# ANLASS: der /mind-all-Lauf im Projekt `Creator` fand am 24.08.2026 SIEBEN
# Halb-Korrekturen an einem Tag. `doku-veraltet` ist mit 25 Vorkommen die
# haeufigste Projekt-Klasse im Debug-Ordner ueberhaupt.
#
# ⭐ DIESE SAMMLUNG PRUEFT DAS INSTRUMENT, NICHT NUR DAS ERGEBNIS.
#    Beim Bau waren nacheinander DREI Fassungen gruen im Selbsttest und
#    trotzdem blind:
#      1. "NOCH NICHT eingebaut" ENTHAELT "eingebaut" -> jede Zeile galt als
#         beides und flog raus. Alle Positivfaelle rot, alle Gegenproben gruen.
#      2. Ein Heredoc machte aus der Wortgrenze das Backspace-Zeichen 0x08.
#         OFFEN und TODO matchten NIE — und der Selbsttest blieb gruen, weil
#         sein Fall zusaetzlich "NOCH NICHT" enthielt.
#      3. Die Rauschfilter _NAH und _MAX_ZEILEN waren gegen EINEN Fehlalarm
#         gedreht und erschlugen dabei das Signal: der einzige echte Fall lag
#         DREI ZEICHEN ausserhalb des Fensters.
#    Gefunden hat alle drei erst eine POSITIVKONTROLLE an bekannt kaputtem
#    Material. Deshalb steht sie hier als Prueffall.
#
# ⛔ WINDOWS-PFADE: python bekommt IMMER cygpath -w. Ein MSYS-Pfad wie
#    /c/CD/... ist fuer Windows-Python bedeutungslos, und der Fehler sieht
#    aus wie ein fehlendes Modul. Genau daran ist die erste Fassung dieser
#    Sammlung gescheitert — 8 Faelle meldeten "fehler" statt eines Ergebnisses.
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
command -v cygpath >/dev/null 2>&1 || { echo "cygpath fehlt" >&2; exit 2; }
R="$CLAUDE_PLUGIN_ROOT/references"
RW=$(cygpath -w "$R")
OK=0; ROT=0
D=$(mktemp -d); DW=$(cygpath -w "$D")

janein() { # name erwartung ist
  if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
  else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi
}

# Ein Helfer als DATEI statt als python -c: keine Anfuehrungszeichen-Hoelle,
# keine Backtick-Substitution, keine Escape-Halbierung.
cat > "$D/h.py" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import cleaner_duplikate as C

was = sys.argv[2]
if was == "vorhanden":
    print("ja" if callable(C.widerspruch_in_datei)
          and callable(C.widersprueche_lauf) else "nein")
elif was == "zaehle":
    print(len(C.widerspruch_in_datei(sys.argv[3])))
elif was == "kopf":
    z = ("⛔ **NOCH NICHT IM CODE.** Der Schnitt gehoert in "
         "`qwen_vertonen.py:rand_weg()` als fester")
    print("ja" if C._naehe(z, "qwen_vertonen.py", C._OFFEN) else "nein")
elif was == "backspace":
    import os
    p = os.path.join(sys.argv[1], "cleaner_duplikate.py")
    print(open(p, encoding="utf-8").read().count(chr(8)))
elif was == "einordnen":
    a, b = sys.argv[3], sys.argv[4]
    print(C.einordnen(sys.argv[5], a, C._inhalt(a), b, C._inhalt(b))[0])
PYEOF

h() { python "$DW\\h.py" "$RW" "$@" 2>/dev/null; }

fuell() { local i; for i in $(seq 1 40); do echo "Fuelltext Absatz $i ohne Marken."; done; }
BT='`'   # Backtick als Variable — nie roh in eine gequotete Zeichenkette

echo "=== SELBSTWIDERSPRUCH ==="

# --- 1 · der eingebaute Selbsttest muss durchlaufen ----------------------
python "$(cygpath -w "$R/cleaner_duplikate.py")" --selbsttest >/dev/null 2>&1 && A=0 || A=$?
janein "cleaner_duplikate --selbsttest laeuft durch" 0 "$A"

# --- 2 · die Funktionen existieren --------------------------------------
janein "widerspruch_in_datei + widersprueche_lauf vorhanden" ja "$(h vorhanden)"

# --- 3 ⭐ POSITIVKONTROLLE: der echte Creator-Fall, im Wortlaut ----------
#     ⛔ Diese Formulierung ist NICHT ausgedacht. Sie steht so in stimme.md
#        Zeile 93 und 199 des Snapshots vom 24.08.2026, 23:10. Alle drei
#        Blindheiten oben waren gegen sie sichtbar — gegen einen
#        konstruierten Fall nicht.
{
  echo "# Stimme"; echo
  echo "⛔ **NOCH NICHT IM CODE.** Der Schnitt gehoert in ${BT}qwen_vertonen.py:rand_weg()${BT} als fester"
  echo "Vorabschnitt von **150 ms** (Reserve auf die gemessenen 120)."
  fuell
  echo "✅ ${BT}qwen_vertonen.py${BT} setzt den Seed jetzt (${BT}--seed${BT}, Vorgabe 42)."
} > "$D/stimme.md"
janein "echter Creator-Wortlaut -> Befund" 1 "$(h zaehle "$DW\\stimme.md")"

# --- 4 · das Statuszeichen steht 43 Zeichen von der Marke entfernt -------
#     Genau der Abstand, an dem die dritte Fassung scheiterte. Wer den
#     Kopf-Sonderfall entfernt, macht Fall 3 rot.
janein "Statuszeichen im Zeilenkopf regiert die Zeile" ja "$(h kopf)"

# ===== GEGENKONTROLLEN =====

# --- 5 · die Ruecknahme-Form DIESES Repos darf NIE gemeldet werden -------
{
  echo "# K"; echo
  echo "${BT}VORAB_MS${BT} ist eingebaut."
  fuell
  echo "✅ ~~${BT}VORAB_MS${BT} ist NOCH NICHT eingebaut~~ — BEHOBEN in v5.2.2."
} > "$D/gut.md"
janein "durchgestrichene Ruecknahme -> KEIN Befund" 0 "$(h zaehle "$DW\\gut.md")"

# --- 6 · eine Erzaehlung dicht untereinander ist kein Widerspruch --------
{
  echo "# K"; echo
  echo "${BT}PEGEL_MS${BT} war noch nicht eingebaut."
  echo "Jetzt ist ${BT}PEGEL_MS${BT} eingebaut."
} > "$D/erz.md"
janein "dicht beieinander -> KEIN Befund" 0 "$(h zaehle "$DW\\erz.md")"

# --- 7 · jedes Offen-Signal EINZELN, gegen die Backspace-Klasse ----------
#     Ein Prueffall mit zwei Signalen prueft nur, dass EINES davon lebt.
for W in OFFEN TODO; do
  { echo "# K"; echo; echo "${BT}PEGEL_MS${BT} ist eingebaut."; fuell
    echo "$W: ${BT}PEGEL_MS${BT} fehlt hier."; } > "$D/sig_$W.md"
  janein "Offen-Signal '$W' greift einzeln" 1 "$(h zaehle "$DW\\sig_$W.md")"
done

# --- 8 · keine Backspace-Zeichen im Quelltext (die Heredoc-Klasse) ------
janein "keine Backspace-Zeichen in der Quelldatei" 0 "$(h backspace)"

# --- 9 · statusdrift ueber ZWEI Dateien ---------------------------------
printf '# A\n\n%sKOMFORT_MS%s ist umgesetzt.\n' "$BT" "$BT" > "$D/a.md"
printf '# B\n\n%sKOMFORT_MS%s steht noch aus.\n' "$BT" "$BT" > "$D/b.md"
janein "erledigt in A, offen in B -> statusdrift" statusdrift \
       "$(h einordnen "$DW\\a.md" "$DW\\b.md" KOMFORT_MS)"

# --- 10 · GEGENKONTROLLE: zahlendrift wiegt schwerer --------------------
printf '# A\n\n%sNOTFALL_MS%s ist entfallen, also erledigt.\n' "$BT" "$BT" > "$D/c.md"
printf '# B\n\n%sNOTFALL_MS%s steht auf 940000, steht noch aus.\n' "$BT" "$BT" > "$D/d.md"
janein "zahlendrift geht vor statusdrift" zahlendrift \
       "$(h einordnen "$DW\\c.md" "$DW\\d.md" NOTFALL_MS)"

# --- 11 · die Suchpflicht steht in BEIDEN Skills ------------------------
for S in mind-claudemd mind-rules; do
  grep -q "SUCHEN, BEVOR DU ERGAENZT" "$CLAUDE_PLUGIN_ROOT/skills/$S/SKILL.md" \
    && A=ja || A=nein
  janein "$S nennt die Suchpflicht" ja "$A"
done

# --- 12 · und die GRENZE des Werkzeugs steht dabei ----------------------
#     Ein Werkzeug, dessen Grenze verschwiegen wird, gilt als vollstaendig.
#     Prosa-Widersprueche ohne gemeinsame Marke findet es NICHT.
grep -q "unsichtbar" "$CLAUDE_PLUGIN_ROOT/skills/mind-claudemd/SKILL.md" && A=ja || A=nein
janein "die Grenze des Detektors steht dabei" ja "$A"

rm -rf "$D"
echo
echo "  gruen: $OK   rot: $ROT"
[ "$ROT" -eq 0 ] || exit 1
