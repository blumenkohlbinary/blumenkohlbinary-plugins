#!/bin/bash
# Claude Mind Manager — UserPromptSubmit Hook (NEU v5.1.0)
#
# Zweck: NACH einer Kompaktierung EINMAL darauf hinweisen, dass der komplette Chat
# gerettet wurde und /mind-all ihn als Quelle nehmen soll.
#
# Warum UserPromptSubmit und nicht PostCompact/SessionStart:
#   - PostCompact ist command-only -> kann KEINEN Kontext einspeisen.
#   - Eine Auto-Kompaktierung beendet die Session NICHT -> es feuert kein SessionStart.
#   - Der naechste Beruehrungspunkt ist die naechste Nachricht des Nutzers. Genau hier.
#
# EHRLICHE GRENZE: Ein Hook kann keinen Skill STARTEN. Das hier ist ein eingespeister
# Auftrag an der sichtbarsten Stelle (Kopf des naechsten Turns) — kein Automatismus.
# Der wertvolle Teil (die Rettung selbst) ist davon unabhaengig und deterministisch.
#
# WICHTIG: Dieser Hook laeuft bei JEDER Nachricht. Im Normalfall gibt er NICHTS aus.
# Ein Hook, der staendig redet, wird ignoriert oder abgeschaltet.

# stdin defensiv konsumieren (der Aufrufer pipet JSON herein)
INPUT=$(cat 2>/dev/null)

# Projekt-Dir: env-Var bevorzugt (dokumentiert), sonst aus dem JSON, sonst CWD
PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ] && command -v jq >/dev/null 2>&1; then
  PROJ=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
fi
[ -z "$PROJ" ] && PROJ="$(pwd)"

PENDING="$PROJ/.claude-mind/rescued/PENDING"

# --- SCHNELLPFAD: kein Merker -> absolut still, sofort raus ---
[ -f "$PENDING" ] || exit 0

RESCUE_PATH=$(grep -m1 '^path='   "$PENDING" 2>/dev/null | cut -d= -f2-)
RESCUE_N=$(grep    -m1 '^events=' "$PENDING" 2>/dev/null | cut -d= -f2-)
RESCUE_TS=$(grep   -m1 '^ts='     "$PENDING" 2>/dev/null | cut -d= -f2-)

# Merker zeigt ins Leere (z.B. wegrotiert)? Dann aufraeumen statt luegen.
if [ -z "$RESCUE_PATH" ] || [ ! -f "$RESCUE_PATH" ]; then
  rm -f "$PENDING" 2>/dev/null
  exit 0
fi

# --- EINMALIG ankuendigen: Merker sofort umbenennen (nicht loeschen) ---
# Umbenennen VOR der Ausgabe: bricht danach etwas ab, gibt es lieber keine
# zweite Ankuendigung als eine Endlosschleife bei jeder Folgenachricht.
mv -f "$PENDING" "${PENDING}.announced" 2>/dev/null

MSG="[Mind Manager] Der Kontext wurde soeben kompaktiert. Der VOLLSTAENDIGE Chat davor wurde gerettet:
  Datei:      ${RESCUE_PATH}
  Beitraege:  ${RESCUE_N:-?}   (gerettet ${RESCUE_TS:-?})

Der Live-Kontext enthaelt nur noch die Zusammenfassung — diese Datei ist die vollstaendige Quelle.
AUFTRAG: Fuehre jetzt /mind-all aus. Der Knowledge-Sync MUSS diese Datei als Session-Quelle
verwenden (nicht das kompaktierte Transkript) und im Bericht 'Session-Quelle: gerettet <pfad>'
ausweisen. Wenn der Nutzer gerade etwas anderes will: erst seine Frage beantworten, den Auftrag
danach nachholen und ihn dabei erwaehnen — nicht stillschweigend fallenlassen."

# JSON-Ausgabe (Context Injection ist fuer UserPromptSubmit dokumentiert).
# Ohne jq: plain-text stdout wirkt laut Referenz ebenfalls als Kontext.
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ctx "$MSG" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
else
  echo "$MSG"
fi

exit 0
