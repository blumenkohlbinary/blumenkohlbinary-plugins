#!/bin/bash
# Claude Mind Manager — SessionStart Hook (v5.1.0, umgebaut v5.2.1)
#
# ZWEITES NETZ zu prompt-submit.sh: Wenn der Nutzer nach einer Kompaktierung nicht
# weiterschreibt, sondern Claude Code neu startet, feuert UserPromptSubmit erst spaeter —
# SessionStart aber sofort. Beide lesen dieselbe Schuld (OPEN); wer zuerst kommt, setzt die
# Sitzungs-Sperre, der andere schweigt dann. Keine Doppel-Ankuendigung in einer Sitzung.
#
# v5.2.1: Die Schuld wird NICHT MEHR beim Ankuendigen geloescht (siehe prompt-submit.sh).
# OPEN bleibt liegen, bis /mind-all wirklich lief — in jeder neuen Sitzung wird also erneut
# darauf hingewiesen. Erzwungen wird der Sync von hooks/stop.sh.
#
# Gleiche Regel wie beim Geschwister-Hook: im Normalfall NICHTS ausgeben.

INPUT=$(cat 2>/dev/null)

PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ] && command -v jq >/dev/null 2>&1; then
  PROJ=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
fi
[ -z "$PROJ" ] && PROJ="$(pwd)"

# Lebenszeichen (v5.2.1) — belegt, dass die Hooks dieser Sitzung ueberhaupt laufen.
# Bewusst hier und nicht in prompt-submit.sh: dort waere es ein Schreibzugriff pro Nachricht
# in einem Ordner, der per rclone hochgeladen wird.
if [ -d "$PROJ" ]; then
  mkdir -p "$PROJ/.claude-mind" 2>/dev/null
  {
    echo "ts=$(date +%Y%m%d-%H%M%S)"
    echo "epoch=$(date +%s)"
    echo "event=SessionStart"
    echo "version=$([ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && basename "$CLAUDE_PLUGIN_ROOT" || echo unbekannt)"
    echo "root=${CLAUDE_PLUGIN_ROOT:-}"
  } > "$PROJ/.claude-mind/hook-heartbeat" 2>/dev/null
fi

OPEN="$PROJ/.claude-mind/rescued/OPEN"

# --- Legacy-Merker uebernehmen (NEU v5.2.2) ---
# Wer von v5.1.0/v5.2.0 aktualisiert und dabei eine OFFENE Rettung liegen hat, hatte bis eben
# einen stillen Waisen: dort hiess der Merker PENDING bzw. PENDING.announced, die v5.2.1-Hooks
# suchen aber nur OPEN — sie schwiegen, und die Rettung wurde nie eingespeist.
# Belegt am 2026-08-16 im eigenen Projekt: 412 KB / 555 Beitraege lagen unangetastet da, bis
# ein Handaufruf sie fand. Das ist genau der Fehler, den v5.2.1 beseitigen sollte — nur eine
# Version versetzt. Deshalb wird hier EINMALIG und idempotent umgeschrieben.
if [ ! -f "$OPEN" ]; then
  _RD="$PROJ/.claude-mind/rescued"
  for _leg in "$_RD/PENDING" "$_RD/PENDING.announced"; do
    [ -f "$_leg" ] || continue
    _lp=$(grep -m1 '^path=' "$_leg" 2>/dev/null | cut -d= -f2-)
    # Zeigt der Merker ins Leere (Rettung wegrotiert)? Dann gibt es nichts zu holen —
    # eine Schuld ohne Beleg waere schlimmer als keine.
    [ -n "$_lp" ] && [ -f "$_lp" ] || { mv -f "$_leg" "${_leg}.stale" 2>/dev/null; continue; }
    {
      cat "$_leg"
      [ -f "$_RD/RESUME.md" ] && echo "resume=$_RD/RESUME.md"   # alter fester Name
      echo "compactions=1"
      echo "blocks=0"
    } > "$OPEN" 2>/dev/null
    mv -f "$_leg" "${_leg}.migrated" 2>/dev/null
    break
  done
fi

[ -f "$OPEN" ] || exit 0

SID=""
command -v jq >/dev/null 2>&1 && SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && SID="nosession"
SEEN="${OPEN}.seen-${SID}"
[ -f "$SEEN" ] && exit 0

RESCUE_PATH=$(grep -m1 '^path='        "$OPEN" 2>/dev/null | cut -d= -f2-)
RESUME_FILE=$(grep -m1 '^resume='      "$OPEN" 2>/dev/null | cut -d= -f2-)
RESCUE_N=$(grep    -m1 '^events='      "$OPEN" 2>/dev/null | cut -d= -f2-)
COMPACTIONS=$(grep -m1 '^compactions=' "$OPEN" 2>/dev/null | cut -d= -f2-)

if [ -z "$RESCUE_PATH" ] || [ ! -f "$RESCUE_PATH" ]; then
  rm -f "$OPEN" "${OPEN}.seen-"* 2>/dev/null
  exit 0
fi

: > "$SEEN" 2>/dev/null

RESUME_TXT=""
[ -n "$RESUME_FILE" ] && [ -f "$RESUME_FILE" ] && RESUME_TXT=$(sed -n '/^## /,$p' "$RESUME_FILE" | head -40)

NACHHOL=""
if [ -n "$COMPACTIONS" ] && [ "$COMPACTIONS" -gt 1 ] 2>/dev/null; then
  NACHHOL="
  ⚠ ${COMPACTIONS} Kompaktierungen seit dem letzten Sync — er wurde schon einmal verschleppt."
fi

MSG="[Mind Manager] Aus einer vorigen Sitzung liegt eine OFFENE Sync-Schuld vor (vor einer
Kompaktierung gesichert):
  Datei:      ${RESCUE_PATH}
  Beitraege:  ${RESCUE_N:-?}${NACHHOL}

--- WORAN ZULETZT GEARBEITET WURDE (aus dem Protokoll gezogen) ---
${RESUME_TXT:-(kein Auftrags-Merker vorhanden)}
--- Ende Auftrags-Merker ---

REIHENFOLGE: Steht oben ein Auftrag, der noch nicht erledigt ist, hat ER Vorrang — dann erst
weiterarbeiten und den Sync danach nachholen. Sonst: /mind-all mit der Rettungsdatei als
Session-Quelle ausfuehren ('Session-Quelle: gerettet <pfad>' im Bericht) und den Auftrag
danach wieder aufnehmen.

⛔ Die Rettungsdatei NIE im Hauptkontext lesen (kein Read, kein cat) — nur den Pfad an einen
Subagenten geben oder zaehlend zugreifen (grep -c, wc).

Die Schuld bleibt bestehen, bis /mind-all gelaufen ist."

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ctx "$MSG" \
    '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
else
  echo "$MSG"
fi

exit 0
