#!/bin/bash
# Claude Mind Manager — SessionStart Hook (NEU v5.1.0)
#
# ZWEITES NETZ zu prompt-submit.sh: Wenn der Nutzer nach einer Kompaktierung nicht
# weiterschreibt, sondern Claude Code neu startet, feuert UserPromptSubmit erst spaeter —
# SessionStart aber sofort. Beide lesen denselben PENDING-Merker; wer zuerst kommt,
# benennt ihn um, der andere schweigt dann. Keine Doppel-Ankuendigung.
#
# Gleiche Regel wie beim Geschwister-Hook: im Normalfall NICHTS ausgeben.

INPUT=$(cat 2>/dev/null)

PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ] && command -v jq >/dev/null 2>&1; then
  PROJ=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
fi
[ -z "$PROJ" ] && PROJ="$(pwd)"

PENDING="$PROJ/.claude-mind/rescued/PENDING"
[ -f "$PENDING" ] || exit 0

RESCUE_PATH=$(grep -m1 '^path='   "$PENDING" 2>/dev/null | cut -d= -f2-)
RESCUE_N=$(grep    -m1 '^events=' "$PENDING" 2>/dev/null | cut -d= -f2-)

if [ -z "$RESCUE_PATH" ] || [ ! -f "$RESCUE_PATH" ]; then
  rm -f "$PENDING" 2>/dev/null
  exit 0
fi

mv -f "$PENDING" "${PENDING}.announced" 2>/dev/null

RESUME_FILE="$(dirname "$PENDING")/RESUME.md"
RESUME_TXT=""
[ -f "$RESUME_FILE" ] && RESUME_TXT=$(sed -n '/^## /,$p' "$RESUME_FILE" | head -40)

MSG="[Mind Manager] Aus der vorigen Sitzung liegt ein geretteter Chat vor (vor einer Kompaktierung gesichert):
  Datei:      ${RESCUE_PATH}
  Beitraege:  ${RESCUE_N:-?}

--- WORAN ZULETZT GEARBEITET WURDE (aus dem Protokoll gezogen) ---
${RESUME_TXT:-(kein Auftrags-Merker vorhanden)}
--- Ende Auftrags-Merker ---

REIHENFOLGE: Steht oben ein Auftrag, der noch nicht erledigt ist, hat ER Vorrang — dann erst
weiterarbeiten und den Sync danach nachholen. Sonst: /mind-all mit der Rettungsdatei als
Session-Quelle ausfuehren ('Session-Quelle: gerettet <pfad>' im Bericht), damit die
Erkenntnisse der letzten Sitzung in CLAUDE.md / MEMORY.md / Rules landen — und den Auftrag
danach wieder aufnehmen."

if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ctx "$MSG" \
    '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
else
  echo "$MSG"
fi

exit 0
