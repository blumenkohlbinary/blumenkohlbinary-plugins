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

# Gesicherten Auftrag mitgeben (v5.2.0) — er ueberlebt die Kompaktierung damit im Kontext,
# unabhaengig davon wie gut die automatische Zusammenfassung war.
RESUME_FILE="$(dirname "$PENDING")/RESUME.md"
RESUME_TXT=""
[ -f "$RESUME_FILE" ] && RESUME_TXT=$(sed -n '/^## /,$p' "$RESUME_FILE" | head -40)

MSG="[Mind Manager] Der Kontext wurde soeben kompaktiert. Der VOLLSTAENDIGE Chat davor wurde gerettet:
  Datei:      ${RESCUE_PATH}
  Beitraege:  ${RESCUE_N:-?}   (gerettet ${RESCUE_TS:-?})
  Auftrags-Merker: ${RESUME_FILE}

--- WORAN GEARBEITET WURDE (aus dem Protokoll gezogen, nicht erinnert) ---
${RESUME_TXT:-(kein Auftrags-Merker vorhanden)}
--- Ende Auftrags-Merker ---

REIHENFOLGE — der laufende Auftrag hat VORRANG, der Sync ist der Einschub:
1. Laeuft der Auftrag oben noch? -> WEITERARBEITEN. Der Context-Sync ist NICHT dringend:
   die Rettungsdatei bleibt liegen und laeuft nicht weg. Kontextknappheit ist kein Abbruchgrund.
2. Ist der Auftrag durch (oder lief keiner)? -> /mind-all ausfuehren; der Knowledge-Sync MUSS
   die Rettungsdatei als Session-Quelle nehmen (nicht das kompaktierte Transkript) und im
   Bericht 'Session-Quelle: gerettet <pfad>' ausweisen.
3. Nach dem Sync: den Auftrag oben WIEDER AUFNEHMEN und das ausdruecklich sagen.
   /mind-all ist nie ein Auftragsende.
Will der Nutzer gerade etwas anderes: seine Frage zuerst, das hier danach — aber nicht
stillschweigend fallenlassen."

# JSON-Ausgabe (Context Injection ist fuer UserPromptSubmit dokumentiert).
# Ohne jq: plain-text stdout wirkt laut Referenz ebenfalls als Kontext.
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ctx "$MSG" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
else
  echo "$MSG"
fi

exit 0
