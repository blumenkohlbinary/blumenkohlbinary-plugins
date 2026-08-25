#!/usr/bin/env bash
# SNAPSHOT REKURSIV (v5.21.0) — das Netz muss so weit reichen wie die Leser.
#
# ⛔ DER ANLASS, gemessen: am 23.08.2026 kamen **267 von 920** Ladevorgaengen aus
#    einem `archive/`-Ordner unter `rules/`, der angelegt worden war, UM den
#    Bestand zu KUERZEN. Die Kuerzung hatte ihn verdoppelt.
#
# ⛔ WARUM DAS HIER ZUERST KOMMT: `mind_snapshot` sicherte flach
#    (`for f in "$dir/.claude/rules"/*.md`). Macht man die LESER rekursiv, ohne
#    das NETZ rekursiv zu machen, entsteht ein Fenster, in dem Unterordner
#    gelesen, aber nicht gesichert werden — und `~/.claude/rules/` liegt in
#    KEINEM Repo.
#
# ⛔ HOME wird umgebogen. Dieser Test darf die echten ~/.claude/rules nie anfassen.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_snapshot_rekursiv.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
OK=0; ROT=0
janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

echo "=== SNAPSHOT REKURSIV ==="

lauf() {                          # -> Snapshot-Pfad auf stdout
  local d="$1"
  ( unset MIND_SNAPSHOT_EXTRA
    export HOME="$d/heim"
    # shellcheck disable=SC1090
    . "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" 2>/dev/null
    MIND_LOG_FILE="$d/log" mind_snapshot "$d/proj" "pre-mind-all" 2>/dev/null )
}

D=$(mktemp -d)
mkdir -p "$D/proj/.claude/rules/archive" "$D/heim/.claude/rules/archiv-global"
printf 'wurzel\n'         > "$D/proj/.claude/rules/env-vars.md"
printf 'im-unterordner\n' > "$D/proj/.claude/rules/archive/alt.md"
# ⭐ GLEICHER NAME in zwei Ordnern — ohne relativen Pfad verdraengt einer den anderen
printf 'archiv-fassung\n' > "$D/proj/.claude/rules/archive/env-vars.md"
printf 'g-wurzel\n'       > "$D/heim/.claude/rules/plan-mode.md"
printf 'g-unterordner\n'  > "$D/heim/.claude/rules/archiv-global/alt.md"
printf '# P\n'            > "$D/proj/CLAUDE.md"
printf '# G\n'            > "$D/heim/.claude/CLAUDE.md"

S=$(lauf "$D")
[ -n "$S" ] && [ -d "$S" ] && A=ja || A=nein
janein "Snapshot wurde angelegt" ja "$A"

# --- 1 ⭐ Der Kernfall: Unterordner wird MITGESICHERT ----------------------
[ -f "$S/rules/archive/alt.md" ] && A=ja || A=nein
janein "rules/archive/alt.md ist im Snapshot" ja "$A"

# --- 2 · GEGENKONTROLLE: die Wurzeldatei ist weiterhin da ------------------
grep -q "wurzel" "$S/rules/env-vars.md" 2>/dev/null && A=ja || A=nein
janein "rules/env-vars.md (Wurzel) unveraendert dabei" ja "$A"

# --- 3 ⭐ Gleichnamige Dateien verdraengen sich NICHT ----------------------
grep -q "archiv-fassung" "$S/rules/archive/env-vars.md" 2>/dev/null && A=ja || A=nein
janein "archive/env-vars.md steht NEBEN der Wurzelfassung" ja "$A"

# --- 4 · dasselbe global ---------------------------------------------------
[ -f "$S/global/rules/archiv-global/alt.md" ] && A=ja || A=nein
janein "global/rules/<unterordner>/ ist im Snapshot" ja "$A"
grep -q "g-wurzel" "$S/global/rules/plan-mode.md" 2>/dev/null && A=ja || A=nein
janein "globale Wurzeldatei unveraendert dabei" ja "$A"

# --- 5 · GEGENKONTROLLE: nichts Fremdes eingesammelt ----------------------
#     Ohne diese Probe koennte ein zu weites `find` halbe Festplatten sichern.
printf 'nicht-md\n' > "$D/proj/.claude/rules/notiz.txt"
mkdir -p "$D/proj/.claude/rules/tief/tiefer"
printf 'sehr-tief\n' > "$D/proj/.claude/rules/tief/tiefer/x.md"
S2=$(lauf "$D")
[ -f "$S2/rules/notiz.txt" ] && A=ja || A=nein
janein "nicht-.md wird NICHT gesichert" nein "$A"
[ -f "$S2/rules/tief/tiefer/x.md" ] && A=ja || A=nein
janein "auch zwei Ebenen tief wird gesichert" ja "$A"

# --- 6 · Das MANIFEST muss die neuen Dateien kennen -----------------------
#     Sonst ist die Integritaetspruefung blind fuer genau das Neue.
if [ -f "$S2/MANIFEST.sha256" ]; then
  grep -q "archive/alt.md" "$S2/MANIFEST.sha256" && A=ja || A=nein
else
  A="kein-manifest"
fi
janein "MANIFEST enthaelt die Unterordner-Datei" ja "$A"

rm -rf "$D"
echo
echo "  gruen: $OK   rot: $ROT"
[ "$ROT" -eq 0 ] || exit 1
