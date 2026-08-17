#!/bin/bash
# Claude Mind Manager — UserPromptSubmit Hook (v5.1.0, umgebaut v5.2.1)
#
# Zweck: Solange eine Sync-Schuld offen ist, EINMAL PRO SITZUNG darauf hinweisen, dass ein
# vollstaendiger Chat gerettet wurde und /mind-all ihn als Quelle nehmen soll.
#
# Warum UserPromptSubmit und nicht PostCompact/SessionStart:
#   - PostCompact ist command-only -> kann KEINEN Kontext einspeisen.
#   - Eine Auto-Kompaktierung beendet die Session NICHT -> es feuert kein SessionStart.
#   - Der naechste Beruehrungspunkt ist die naechste Nachricht des Nutzers. Genau hier.
#
# ⛔ AENDERUNG v5.2.1 — der Merker wird NICHT MEHR VERBRAUCHT.
# Bis v5.2.0 hiess der Merker PENDING und wurde beim ANKUENDIGEN in PENDING.announced
# umbenannt. Damit war die Schuld nach einer einzigen Ankuendigung fuer immer unsichtbar:
# belegt am 2026-08-16 — Ankuendigung kam an, der laufende Auftrag hatte Vorrang (so will es
# v5.2.0), und 417 KB geretteter Chat blieben liegen, die nie jemand eingespeist hat.
# Jetzt: OPEN ist die SCHULD und bleibt, bis der Sync wirklich lief. Angekuendigt wird einmal
# pro Sitzung (OPEN.seen-<session_id>) — in jeder neuen Sitzung also wieder.
# Erzwungen wird der Sync von hooks/stop.sh; dieser Hook informiert nur.
#
# EHRLICHE GRENZE: Ein Hook kann keinen Skill STARTEN. Das hier ist ein eingespeister Auftrag
# an der sichtbarsten Stelle (Kopf des naechsten Turns) — kein Automatismus.
#
# WICHTIG: Dieser Hook laeuft bei JEDER Nachricht. Im Normalfall gibt er NICHTS aus.
# Ein Hook, der staendig redet, wird ignoriert oder abgeschaltet.

# stdin defensiv konsumieren (der Aufrufer pipet JSON herein)
INPUT=$(cat 2>/dev/null)

# --- Protokoll (NEU v5.3.1) ---------------------------------------------------
# Eigener Logger statt lib.sh: dieser Hook laeuft bei JEDER Nachricht und soll schlank
# bleiben — ein `source lib.sh` je Tastendruck waere Startkosten fuer nichts. Gleiches
# Muster wie hooks/stop.sh.
#
# WARUM ueberhaupt (gemessen 2026-08-17): Dieser Hook und session-start.sh hatten zusammen
# NULL Log-Aufrufe. Auf die Frage "der Compact lief, warum ist nichts passiert?" liess sich
# nicht beantworten, ob, wann und von welchem Hook die Schuld gemeldet wurde — erschliessbar
# war es nur ueber den Zeitstempel von OPEN.seen-<sid>. Das Log, das die Frage beantworten
# sollte, schwieg.
MIND_LOG_FILE="/tmp/mind-manager.log"
_slog() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1 prompt-submit: ${*:2}" >> "$MIND_LOG_FILE" 2>/dev/null; }

# Projekt-Dir: env-Var bevorzugt (dokumentiert), sonst aus dem JSON, sonst CWD
PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ] && command -v jq >/dev/null 2>&1; then
  PROJ=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
fi
[ -z "$PROJ" ] && PROJ="$(pwd)"

OPEN="$PROJ/.claude-mind/rescued/OPEN"

# --- SCHNELLPFAD: keine Schuld -> absolut still, sofort raus ---
[ -f "$OPEN" ] || exit 0

# --- Sitzungs-Sperre: einmal pro Sitzung ankuendigen, nicht einmal ueberhaupt ---
SID=""
command -v jq >/dev/null 2>&1 && SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && SID="nosession"
SEEN="${OPEN}.seen-${SID}"
# Bewusstes Schweigen — der WICHTIGERE der beiden Eintraege: genau dieser Zustand sah in der
# Fehlersuche vom 17.08.2026 aus wie "der Hook hat gar nicht gefeuert".
[ -f "$SEEN" ] && { _slog INFO "still: Schuld besteht, aber in dieser Sitzung schon gemeldet (sid=$SID)"; exit 0; }

RESCUE_PATH=$(grep -m1 '^path='        "$OPEN" 2>/dev/null | cut -d= -f2-)
RESUME_FILE=$(grep -m1 '^resume='      "$OPEN" 2>/dev/null | cut -d= -f2-)
RESCUE_N=$(grep    -m1 '^events='      "$OPEN" 2>/dev/null | cut -d= -f2-)
RESCUE_TS=$(grep   -m1 '^ts='          "$OPEN" 2>/dev/null | cut -d= -f2-)
COMPACTIONS=$(grep -m1 '^compactions=' "$OPEN" 2>/dev/null | cut -d= -f2-)

# Merker zeigt ins Leere (z.B. wegrotiert)? Dann aufraeumen statt luegen.
if [ -z "$RESCUE_PATH" ] || [ ! -f "$RESCUE_PATH" ]; then
  _slog INFO "OPEN zeigte ins Leere -> entfernt, nichts gemeldet"
  rm -f "$OPEN" "${OPEN}.seen-"* 2>/dev/null
  exit 0
fi

# Sperre VOR der Ausgabe setzen: bricht danach etwas ab, gibt es lieber keine zweite
# Ankuendigung in DIESER Sitzung als eine Endlosschleife bei jeder Folgenachricht.
: > "$SEEN" 2>/dev/null

# Gesicherten Auftrag mitgeben — er ueberlebt die Kompaktierung damit im Kontext,
# unabhaengig davon wie gut die automatische Zusammenfassung war.
RESUME_TXT=""
[ -n "$RESUME_FILE" ] && [ -f "$RESUME_FILE" ] && RESUME_TXT=$(sed -n '/^## /,$p' "$RESUME_FILE" | head -40)

NACHHOL=""
if [ -n "$COMPACTIONS" ] && [ "$COMPACTIONS" -gt 1 ] 2>/dev/null; then
  NACHHOL="
  ⚠ ${COMPACTIONS} Kompaktierungen seit dem letzten Sync — er wurde also schon einmal verschleppt."
fi

MSG="[Mind Manager] Es liegt eine OFFENE Sync-Schuld vor. Der VOLLSTAENDIGE Chat vor der
Kompaktierung wurde gerettet:
  Datei:      ${RESCUE_PATH}
  Beitraege:  ${RESCUE_N:-?}   (gerettet ${RESCUE_TS:-?})
  Auftrags-Merker: ${RESUME_FILE:-(keiner)}${NACHHOL}

--- WORAN GEARBEITET WURDE (aus dem Protokoll gezogen, nicht erinnert) ---
${RESUME_TXT:-(kein Auftrags-Merker vorhanden)}
--- Ende Auftrags-Merker ---

REIHENFOLGE — der laufende Auftrag hat VORRANG, der Sync ist der Einschub:
1. Laeuft der Auftrag oben noch? -> WEITERARBEITEN. Kontextknappheit ist kein Abbruchgrund.
2. Ist der Auftrag durch (oder lief keiner)? -> /mind-all ausfuehren; der Knowledge-Sync MUSS
   die Rettungsdatei als Session-Quelle nehmen und im Bericht 'Session-Quelle: gerettet <pfad>'
   ausweisen.
3. Nach dem Sync: den Auftrag oben WIEDER AUFNEHMEN und das ausdruecklich sagen.
   /mind-all ist nie ein Auftragsende.

⛔ Die Rettungsdatei NIE im Hauptkontext lesen (kein Read, kein cat) — sie ist mehrere hundert
KB gross und wuerde den frisch geleerten Kontext sofort wieder fuellen. Erlaubt sind nur:
Pfad an einen Subagenten uebergeben, und zaehlende Aufrufe (grep -c, wc).

Die Schuld bleibt bestehen, bis /mind-all gelaufen ist — sie verfaellt nicht mit dieser Meldung."

# JSON-Ausgabe (Context Injection ist fuer UserPromptSubmit dokumentiert).
# Ohne jq: plain-text stdout wirkt laut Referenz ebenfalls als Kontext.
_slog INFO "Schuld gemeldet (events=${RESCUE_N:-?}, compactions=${COMPACTIONS:-?}, sid=$SID) -> $RESCUE_PATH"
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ctx "$MSG" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
else
  echo "$MSG"
fi

exit 0
