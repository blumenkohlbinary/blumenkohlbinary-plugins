#!/usr/bin/env bash
# ROLLBACK-LAYOUT (v5.21.0) — der Rueckweg war kaputt, nicht knapp.
#
# ⛔ ZWEI FEHLER UEBEREINANDER, gefunden im Plan-Review am 25.08.2026:
#
#   1. rollback.py sucht in `.claude-mind/backups` (BACKUP_TARGET-Vorgabe),
#      mind_snapshot schreibt aber nach `.claude-mind/snapshots`.
#      -> `rollback.py list` findet die Snapshots GAR NICHT.
#
#   2. restore() macht `PROJECT_ROOT / rel` mit rel = Pfad im Snapshot.
#      Ein Snapshot hat aber vier Zweige (rules/, global/, memory/, project/),
#      und KEINER liegt unter `<projekt>/<zweig>/`. Ein Restore von
#      `rules/hooks.md` landet in `<projekt>/rules/hooks.md` statt in
#      `<projekt>/.claude/rules/hooks.md`. NUR die blanke CLAUDE.md stimmt.
#
# ⛔ WARUM DAS DER GEFAEHRLICHSTE PUNKT WAR: `~/.claude/rules/` liegt in KEINEM
#    Repo. Dort ist der Snapshot der einzige Stand — und `.claude-mind/` ist
#    gitignore't bei keep=3. Drei Laeufe, und der Stand von vorher ist weg.
#
# Die richtige Zuordnung stand die ganze Zeit dokumentiert, in
# skills/mind-all/SKILL.md Step 3 ("Restore (Ziele liegen NICHT alle im Projekt!)").
# Sie war nur nie implementiert.
#
# ⛔ WINDOWS-PFADE: python bekommt IMMER cygpath -w.
# ⛔ HOME wird umgebogen — dieser Test darf NIE die echten ~/.claude/rules anfassen.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_rollback_layout.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
command -v cygpath >/dev/null 2>&1 || { echo "cygpath fehlt" >&2; exit 2; }
RB="$CLAUDE_PLUGIN_ROOT/references/backup-system-templates/tools/rollback.py"
[ -f "$RB" ] || { echo "rollback.py-Vorlage fehlt: $RB" >&2; exit 2; }
RBW=$(cygpath -w "$RB")
OK=0; ROT=0

janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

# --- Ein kuenstliches Projekt MIT kuenstlichem HOME --------------------------
bau() {                       # -> Pfad des Projekts (echo)
  local d; d=$(mktemp -d)
  mkdir -p "$d/heim/.claude/rules"
  mkdir -p "$d/proj/.claude/rules"
  local S="$d/proj/.claude-mind/snapshots/20260825_000000_pre-test"
  mkdir -p "$S/rules" "$S/global/rules" "$S/memory" "$S/project/knowledge"
  printf 'ALT-projektregel\n'      > "$S/rules/hooks.md"
  printf 'ALT-globalregel\n'       > "$S/global/rules/plan-mode.md"
  printf 'ALT-projekt-claudemd\n'  > "$S/CLAUDE.md"
  printf 'ALT-global-claudemd\n'   > "$S/global/CLAUDE.md"
  # ⛔ v5.32.0: seit mind_snapshot auch `global/skills/` sichert, MUSS der
  #    Rueckweg ihn kennen. Vorher fiel er auf `PROJECT_ROOT / r` durch und
  #    haette die Commands nach <projekt>/global/skills/... geschrieben —
  #    woertlich der Fehler, den backup-usage.md fuer `rules/` beschreibt.
  mkdir -p "$S/global/skills/z-mount-rclone"
  printf 'ALT-command-volltext\n'  > "$S/global/skills/z-mount-rclone/SKILL.md"
  printf 'ALT-memory\n'            > "$S/memory/thema.md"
  printf 'ALT-extra\n'             > "$S/project/knowledge/x.md"
  # Der lebende Stand, den der Restore ueberschreiben soll
  printf 'NEU-projektregel\n'      > "$d/proj/.claude/rules/hooks.md"
  printf 'NEU-globalregel\n'       > "$d/heim/.claude/rules/plan-mode.md"
  printf 'NEU-projekt-claudemd\n'  > "$d/proj/CLAUDE.md"
  # Und ein ALTES Backup daneben, das weiterhin gefunden werden MUSS
  mkdir -p "$d/proj/.claude-mind/backups/20260820_000000_alt"
  printf 'x\n' > "$d/proj/.claude-mind/backups/20260820_000000_alt/CLAUDE.md"
  printf '%s' "$d"
}
rb() {                        # projektwurzel heim  args...
  local p="$1" h="$2"; shift 2
  ( cd "$p" && HOME=$(cygpath -w "$h") USERPROFILE=$(cygpath -w "$h") \
      python "$RBW" "$@" 2>&1 )
}

echo "=== ROLLBACK-LAYOUT ==="
echo "--- A · findet list die Snapshots? ---"

D=$(bau)
O=$(rb "$D/proj" "$D/heim" list)
printf '%s' "$O" | grep -q "20260825_000000_pre-test" && A=ja || A=nein
janein "list findet den Snapshot in snapshots/" ja "$A"

# --- GEGENKONTROLLE: die alten backups/ duerfen NICHT verschwinden ----------
printf '%s' "$O" | grep -q "20260820_000000_alt" && A=ja || A=nein
janein "list findet weiterhin die alten backups/" ja "$A"
rm -rf "$D"

echo "--- B · landet der Restore am richtigen Ort? ---"

D=$(bau)
rb "$D/proj" "$D/heim" restore 20260825_000000_pre-test >/dev/null 2>&1

# ⭐ Der Kernfall: rules/ gehoert nach .claude/rules/, nicht nach rules/
grep -q "ALT-projektregel" "$D/proj/.claude/rules/hooks.md" 2>/dev/null && A=ja || A=nein
janein "rules/hooks.md -> .claude/rules/hooks.md" ja "$A"

# und NICHT am falschen Ort
[ -f "$D/proj/rules/hooks.md" ] && A=ja || A=nein
janein "landet NICHT unter <projekt>/rules/" nein "$A"

# global/rules/ gehoert nach ~/.claude/rules/
grep -q "ALT-globalregel" "$D/heim/.claude/rules/plan-mode.md" 2>/dev/null && A=ja || A=nein
janein "global/rules/ -> ~/.claude/rules/" ja "$A"

# global/CLAUDE.md gehoert nach ~/.claude/CLAUDE.md
grep -q "ALT-global-claudemd" "$D/heim/.claude/CLAUDE.md" 2>/dev/null && A=ja || A=nein
janein "global/CLAUDE.md -> ~/.claude/CLAUDE.md" ja "$A"

# ⭐ v5.32.0: global/skills/ gehoert nach ~/.claude/skills/ — der Volltext der
#    fuenf Commands liegt seit dem 23.08.2026 dort und in KEINEM Repo.
grep -q "ALT-command-volltext" "$D/heim/.claude/skills/z-mount-rclone/SKILL.md" 2>/dev/null && A=ja || A=nein
janein "⭐ global/skills/ -> ~/.claude/skills/" ja "$A"

# ⛔ GEGENPROBE: er darf NICHT im Projekt landen. Ohne sie waere die Zusicherung
#    darueber auch dann gruen, wenn zusaetzlich eine Kopie am falschen Ort liegt.
[ -e "$D/projekt/global" ] && A=ja || A=nein
janein "⛔ NICHTS unter <projekt>/global/ gelandet" nein "$A"

# GEGENKONTROLLE: die blanke CLAUDE.md war schon immer richtig
grep -q "ALT-projekt-claudemd" "$D/proj/CLAUDE.md" 2>/dev/null && A=ja || A=nein
janein "CLAUDE.md -> <projekt>/CLAUDE.md (war schon richtig)" ja "$A"

# project/ sind die Extra-Pfade, relativ zur Projektwurzel
grep -q "ALT-extra" "$D/proj/knowledge/x.md" 2>/dev/null && A=ja || A=nein
janein "project/knowledge/x.md -> <projekt>/knowledge/x.md" ja "$A"
rm -rf "$D"

echo "--- C · memory/ wird NICHT blind geschrieben ---"

# ⛔ get_memory_dir faellt bei Slug-Mismatch auf das NEUESTE FREMDE Projekt
#    zurueck (lib.sh:545-548). mind_snapshot sichert dagegen ab, indem es den
#    Pfad nur nimmt, wenn GENAU DIESES Verzeichnis existiert. Derselbe Schutz
#    gilt hier: existiert das Ziel nicht, wird NICHT geschrieben.
D=$(bau)
O=$(rb "$D/proj" "$D/heim" restore 20260825_000000_pre-test)
# Zielverzeichnis existiert im kuenstlichen HOME nicht -> nichts angelegt
find "$D/heim/.claude/projects" -name "thema.md" 2>/dev/null | grep -q . && A=ja || A=nein
janein "memory/ ohne vorhandenes Ziel -> NICHT geschrieben" nein "$A"
printf '%s' "$O" | grep -qi "memory" && A=ja || A=nein
janein "und der Lauf sagt es ausdruecklich" ja "$A"
rm -rf "$D"

echo "--- D · bestehendes Verhalten bleibt ---"

# Pfad-Traversal-Schutz (war schon da, darf nicht verlorengehen)
D=$(bau)
S="$D/proj/.claude-mind/snapshots/20260825_000000_pre-test"
mkdir -p "$S/rules"
printf 'boese\n' > "$S/rules/..-..-entwischt.md"
rb "$D/proj" "$D/heim" restore 20260825_000000_pre-test >/dev/null 2>&1
[ -f "$D/entwischt.md" ] && A=ja || A=nein
janein "kein Schreiben ausserhalb der Wurzel" nein "$A"

# Pre-Rollback-Schnappschuss: der alte Stand muss auffindbar bleiben
# ⚠ Der Ordner heisst `<ts>_pre-rollback-from-<name>`. Die erste Fassung
#   dieses Falls suchte `pre-rollback_*` und war deshalb rot — mein
#   Pruefstand, nicht der Code.
find "$D/proj/.claude-mind" -type d -name "*pre-rollback-from-*" 2>/dev/null | grep -q . && A=ja || A=nein
janein "Pre-Rollback-Schnappschuss wird angelegt" ja "$A"
rm -rf "$D"

echo
echo "  gruen: $OK   rot: $ROT"
[ "$ROT" -eq 0 ] || exit 1
