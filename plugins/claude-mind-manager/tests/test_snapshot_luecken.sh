#!/usr/bin/env bash
# WAS DER SNAPSHOT NICHT ABDECKT (v5.21.3)
#
# ⛔ BEFUND aus `Pc Forschung`, 26.08.2026 23:02:
#    "INDEX.md liegt NICHT im /mind-all-Snapshot. Alle Aenderungen daran hatten
#     kein Netz, und der im Bericht genannte Restore-Weg ist fuer sie falsch."
#    Ihr Vorschlag: `INDEX.md` fest in `mind_snapshot` einbauen.
#
# ⭐ DAS WAERE DIE FALSCHE ANTWORT. `MIND_SNAPSHOT_EXTRA` loest den Fall seit
#    v5.2.1 allgemein. GEMESSEN, warum sie das nicht wissen konnten: die
#    Variable kommt in `hooks/lib.sh` vor — und in KEINEM Skill, KEINEM Bericht,
#    KEINER Referenz. Klasse `sichtbarkeit`. Also meldet der Lauf die Luecke und
#    nennt den Mechanismus, statt eine fremde Dateinamen-Konvention zu erraten.
#
# ⛔ WARUM DIE LOGIK IN lib.sh LIEGT UND NICHT IM SKILL:
#    Ein Codeblock in einer Markdown-Datei ist von KEINEM Prueffall aufrufbar.
#    Genau daran ist der Zeilenenden-Waechter gescheitert — er verglich 1 von 68
#    Dateien und meldete "keine Abweichung" (v5.13.0 holte ihn nach lib.sh).
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_snapshot_luecken.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
. "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
OK=0; ROT=0
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

pruefe() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — ist '$2', soll '$3'"; ROT=$((ROT+1)); fi; }

# $1 = Projektname (darf Leerzeichen enthalten)
bau() {
  P="$T/$1"; S="$T/snap_$$"
  rm -rf "$P" "$S"; mkdir -p "$P" "$S/project"
  printf '# C\n' > "$P/CLAUDE.md"
}

echo "=============================================================================="
echo "  mind_snapshot_luecken — sagen, was NICHT gesichert ist"
echo "=============================================================================="

echo
echo "  --- Grundfaelle ---"
bau einfach
printf 'x\n' > "$P/INDEX.md"
printf 'x\n' > "$P/README.md"
A=$(mind_snapshot_luecken "$P" "$S")
pruefe "zwei ungedeckte Dateien -> 2" "${A%%|*}" "2"
case "$A" in *INDEX.md*) pruefe "INDEX.md wird genannt" ja ja ;;
             *) pruefe "INDEX.md wird genannt" ja nein ;; esac

# ⛔ CLAUDE.md liegt im Snapshot-Wurzelverzeichnis, nicht unter project/ —
#    sie darf NIE als Luecke gelten, sonst meldet jeder Lauf einen Fehlalarm.
pruefe "CLAUDE.md zaehlt NIE als Luecke" \
       "$(case "$A" in *CLAUDE.md*) echo doch ;; *) echo nein ;; esac)" "nein"

echo
echo "  --- ⛔ NEGATIVKONTROLLE: alles gedeckt -> STILL ---"
bau gedeckt
printf 'x\n' > "$P/INDEX.md"
printf 'x\n' > "$S/project/INDEX.md"
A=$(mind_snapshot_luecken "$P" "$S")
pruefe "gedeckte Datei -> 0" "${A%%|*}" "0"
pruefe "und keine Namen" "${A#*|}" ""

bau leer
A=$(mind_snapshot_luecken "$P" "$S")
pruefe "gar keine .md ausser CLAUDE.md -> 0" "${A%%|*}" "0"

echo
echo "  --- ⛔ PFADE MIT LEERZEICHEN — der Fehler, der beim Bau passierte ---"
# Die erste Fassung lief ueber `$(ls -t "$PROJ"/*.md)`. Unquotierte
# Befehlssubstitution zerlegt am Leerzeichen: aus 15 Dateien wurden "79", mit
# Namen wie "Plugin - Claude Mind". Klasse `windows-pfad`, in diesem Projekt
# seit v5.2.1 dokumentiert ("Rotation nie mit xargs") und trotzdem wieder
# entstanden — deshalb steht der Fall hier.
bau "Plugin - Entwicklung"
printf 'x\n' > "$P/INDEX.md"
printf 'x\n' > "$P/PROTOKOLL.md"
A=$(mind_snapshot_luecken "$P" "$S")
pruefe "Projektpfad mit Leerzeichen -> genau 2" "${A%%|*}" "2"
pruefe "keine zerlegten Namen" \
       "$(case "${A#*|}" in *Plugin*|*Entwicklung*) echo zerlegt ;; *) echo heil ;; esac)" "heil"

# Auch ein DATEIname mit Leerzeichen darf nicht zerfallen.
bau "Plugin - Entwicklung"
printf 'x\n' > "$P/mein plan.md"
A=$(mind_snapshot_luecken "$P" "$S")
pruefe "Dateiname mit Leerzeichen -> 1" "${A%%|*}" "1"

echo
echo "  --- hoechstens fuenf Namen, Gesamtzahl bleibt sichtbar ---"
# Eine volle Liste waere hier 15 Namen lang (gemessen) und damit die Ausgabe,
# die man gewohnheitsmaessig ueberliest.
bau viele
for i in 1 2 3 4 5 6 7 8; do printf 'x\n' > "$P/datei$i.md"; done
A=$(mind_snapshot_luecken "$P" "$S")
pruefe "acht ungedeckt -> Zahl sagt 8" "${A%%|*}" "8"
pruefe "aber hoechstens 5 Namen" "$(printf '%s' "${A#*|}" | wc -w | tr -d ' ')" "5"

echo
echo "  --- fehlende Verzeichnisse brechen nicht ---"
A=$(mind_snapshot_luecken "$T/gibtesnicht" "$S")
pruefe "totes Projekt -> 0, kein Absturz" "${A%%|*}" "0"
A=$(mind_snapshot_luecken "$P" "$T/keinsnapshot")
pruefe "toter Snapshot -> 0, kein Absturz" "${A%%|*}" "0"

echo
echo "=============================================================================="
echo "  $OK ok, $ROT rot"
echo "=============================================================================="
[ "$ROT" -eq 0 ]
