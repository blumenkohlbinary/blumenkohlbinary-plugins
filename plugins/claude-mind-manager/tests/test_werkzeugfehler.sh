#!/usr/bin/env bash
# ZWEI WERKZEUGFEHLER, gefunden im /mind-cleaner-Lauf vom 25.08.2026.
#
# Beide gehoeren zur Klasse `instrument-misst-nichts` — mit 33 Vorkommen die
# haeufigste im Debug-Ordner. Beide sahen von aussen aus wie ein BEFUND ueber
# den Regelbestand und waren Fehler im Messgeraet.
#
#  A · bestandsaufnahme.py IGNORIERT ein positionales Argument.
#      Die SKILL.md dokumentiert `bestandsaufnahme.py <verzeichnis>`, das
#      Werkzeug liest aber nur `--ordner`. Ein positionaler Pfad wird STILL
#      verworfen und der globale Ordner gemessen. Aufgefallen nur, weil die
#      Projekt-Zahlen byte-gleich mit den globalen waren. Damit hat Step 1
#      fuer `--bereich projekt` NIE funktioniert.
#
#  B · LINT LEAKAGE traf ein deutsches Allerweltswort.
#      `hooks_im_projekt` gab den Namen als `sicherung.py"` zurueck — MIT
#      Anfuehrungszeichen, weil `befehl.split()[-1]` bei einem gequoteten Pfad
#      das schliessende Zeichen mitnimmt. Daraus wurde der Stamm `sicherung`,
#      und der steht als normales deutsches Wort in halb `~/.claude/rules/`.
#      Gemessen: 4 Meldungen, 1 echt, 3 Fehlalarme. `z-mount-rclone.md` sagt
#      schlicht "Vorher Sicherung."
#
# ⛔ WINDOWS-PFADE: python bekommt IMMER cygpath -w.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_werkzeugfehler.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
command -v cygpath >/dev/null 2>&1 || { echo "cygpath fehlt" >&2; exit 2; }
R="$CLAUDE_PLUGIN_ROOT/references"
RW=$(cygpath -w "$R")
OK=0; ROT=0
D=$(mktemp -d); DW=$(cygpath -w "$D")

janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

echo "=== WERKZEUGFEHLER ==="
echo "--- A · bestandsaufnahme.py und sein Argument ---"

mkdir -p "$D/klein"
printf '# Klein\n\nEine Regel.\n' > "$D/klein/a.md"
printf '# Zwei\n\nNoch eine.\n'   > "$D/klein/b.md"

# --- 1 · --ordner wird gelesen (das funktionierte schon) ----------------
A=$(python "$RW\\bestandsaufnahme.py" --ordner "$DW\\klein" 2>/dev/null \
    | sed -n 's/.*(\([0-9]*\) Dateien in.*/\1/p' | head -1)
janein "--ordner misst den angegebenen Ordner" 2 "${A:-fehler}"

# --- 2 ⭐ POSITIONAL muss dasselbe tun — DAS war der Fehler --------------
A=$(python "$RW\\bestandsaufnahme.py" "$DW\\klein" 2>/dev/null \
    | sed -n 's/.*(\([0-9]*\) Dateien in.*/\1/p' | head -1)
janein "positionaler Pfad misst denselben Ordner" 2 "${A:-fehler}"

# --- 3 ⛔ und ein UNBEKANNTES Argument muss LAUT scheitern ---------------
#     Das ist die strukturelle Haertung: still ignorieren heisst, dass der
#     naechste Aufruf-Fehler wieder wie ein Befund aussieht.
python "$RW\\bestandsaufnahme.py" --quatsch /nirgendwo >/dev/null 2>&1 && A=0 || A=1
janein "unbekanntes Argument bricht ab statt zu schweigen" 1 "$A"

# --- 4 · GEGENKONTROLLE: ohne Argument bleibt die Vorgabe ---------------
python "$RW\\bestandsaufnahme.py" >/dev/null 2>&1 && A=0 || A=$?
janein "ohne Argument laeuft die Vorgabe weiter" 0 "$A"

# --- 4a ⭐ REKURSIV — der dritte Fehler desselben Laufs ------------------
#     `os.listdir` ist FLACH, waehrend der Bericht "(REKURSIV gezaehlt)"
#     behauptete. Genau daran hing der teuerste Einzelbefund dieses
#     Werkzeugs: am 23.08.2026 kamen 267 von 920 Ladevorgaengen aus einem
#     `archive/`-Ordner, der angelegt worden war, UM den Bestand zu kuerzen.
mkdir -p "$D/klein/archive"
printf '# Alt\n\nEine archivierte Regel.\n' > "$D/klein/archive/alt.md"
A=$(python "$RW\\bestandsaufnahme.py" "$DW\\klein" 2>/dev/null \
    | sed -n 's/.*(\([0-9]*\) Dateien in.*/\1/p' | head -1)
janein "Unterordner zaehlen MIT (2 + 1 im archive/)" 3 "${A:-fehler}"

# --- 4b · und gleichnamige Dateien duerfen sich nicht ueberschreiben -----
#     Mit dem blossen Dateinamen als Schluessel wuerde archive/a.md die
#     a.md der Wurzel verdraengen — der Bestand saehe KLEINER aus, genau
#     die Richtung des Fehlers, den die Rekursion beheben soll.
printf '# Doppelt\n\nGleicher Name, anderer Ort.\n' > "$D/klein/archive/a.md"
A=$(python "$RW\\bestandsaufnahme.py" "$DW\\klein" 2>/dev/null \
    | sed -n 's/.*(\([0-9]*\) Dateien in.*/\1/p' | head -1)
janein "gleicher Dateiname in zwei Ordnern zaehlt zweimal" 4 "${A:-fehler}"
rm -rf "$D/klein/archive"

echo "--- B · LINT LEAKAGE und das Allerweltswort ---"

# Ein Projekt mit genau EINEM Hook, gequotet wie im echten settings.json.
mkdir -p "$D/proj/.claude"
cat > "$D/proj/.claude/settings.json" <<'JSONEOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Write|Edit",
        "hooks": [ { "type": "command",
                     "command": "python \"C:/CD/KOHLEKTIV/_claude_tools/hooks/sicherung.py\"" } ] }
    ]
  }
}
JSONEOF

cat > "$D/h.py" <<'PYEOF'
import os
import sys
sys.path.insert(0, sys.argv[1])
# HOME umbiegen, damit NICHT die echte ~/.claude/settings.json mitgelesen wird.
os.environ["HOME"] = sys.argv[2]
os.environ["USERPROFILE"] = sys.argv[2]
import cleaner_einordnung as E

was = sys.argv[3]
if was == "namen":
    h = E.hooks_im_projekt(sys.argv[4])
    print(",".join(sorted(h)) if h else "(leer)")
elif was == "leak":
    verd, name, _ = E.lint_leakage(sys.argv[4], sys.argv[5])
    print("%s|%s" % ("ja" if verd else "nein", name or "-"))
PYEOF

h() { python "$DW\\h.py" "$RW" "$DW\\heim" "$@" 2>/dev/null; }
mkdir -p "$D/heim/.claude"          # leeres Heim: keine zweite settings.json

# --- 5 ⭐ der Name darf KEIN Anfuehrungszeichen tragen -------------------
janein "Hook-Name wird ohne Anfuehrungszeichen gelesen" "sicherung.py" "$(h namen "$DW\\proj")"

# --- 6 ⭐ das blosse WORT 'Sicherung' ist KEIN Leak ----------------------
#     z-mount-rclone.md sagt woertlich: "Vorher Sicherung."
printf '# Z\n\nAufraeumen heisst verschieben, nie loeschen. Vorher Sicherung.\n' \
  > "$D/wort.md"
janein "nur das Wort 'Sicherung' -> KEIN Leak" "nein|-" "$(h leak "$DW\\wort.md" "$DW\\proj")"

# --- 7 · und der DATEINAME ist einer (Positivkontrolle) -----------------
#     Ohne diesen Fall waere der Fix von 6 nicht von "meldet nie etwas" zu
#     unterscheiden.
printf '# B\n\nDer Hook `_claude_tools/hooks/sicherung.py` sichert vor Write.\n' \
  > "$D/name.md"
janein "der Dateiname sicherung.py -> Leak" "ja|sicherung.py" "$(h leak "$DW\\name.md" "$DW\\proj")"

# --- 8 · GEGENKONTROLLE: eine Datei ohne beides schweigt ----------------
printf '# X\n\nEine Regel ueber ganz andere Dinge.\n' > "$D/leer.md"
janein "weder Wort noch Name -> KEIN Leak" "nein|-" "$(h leak "$DW\\leer.md" "$DW\\proj")"

rm -rf "$D"
echo
echo "  gruen: $OK   rot: $ROT"
[ "$ROT" -eq 0 ] || exit 1
