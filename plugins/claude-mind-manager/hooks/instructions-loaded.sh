#!/usr/bin/env bash
# =============================================================================
# InstructionsLoaded -> Ladeprotokoll                              (NEU v5.12.0)
# =============================================================================
# Schreibt EINE Zeile je geladener Context-Datei, mit dem Ladegrund.
#
# ⛔ WARUM ES DAS GIBT. Bis hierher war die Frage "welche Regeldatei laedt wann
#    und warum" nur zu RATEN. Zwei Messversuche sind an ihrem eigenen Instrument
#    gescheitert:
#      1. das Minimum der `usage`-Werte ueber heterogene Sitzungen genommen und
#         fuer "Startkontext" gehalten -- ergab eine Anomalie, die es nicht gibt
#      2. den Regeltext im Transkript gesucht; die Gegenprobe fand die EIGENEN
#         Suchbefehle. Der Kontextblock steht dort nur in FORTGESETZTEN Sitzungen
#    Dieses Ereignis beantwortet die Frage direkt, an der Quelle.
#
# ⚠ `InstructionsLoaded` IGNORIERT den Rueckgabewert und kann NICHT blocken.
#    Dieser Hook kann also nichts kaputt machen -- er sieht nur zu.
#
# ⛔ DER ERSTE LAUF LEGT DAS SCHEMA OFFEN. Die Feldnamen der Eingabe sind nicht
#    dokumentiert. Findet das Skript Pfad oder Grund nicht, haengt es die ROHE
#    JSON-Zeile an -- damit sagt die erste Messung selbst, wie sie zu lesen ist,
#    statt still leere Zeilen zu schreiben.
#
# Ablage:  ${MIND_LADEPROTOKOLL}  ODER  ${MIND_DEBUG_DIR}/ladeprotokoll.log
#          ODER  /tmp/mind-ladeprotokoll.log
# =============================================================================

INPUT=$(cat)

LOG="${MIND_LADEPROTOKOLL:-}"
if [ -z "$LOG" ]; then
  if [ -n "$MIND_DEBUG_DIR" ] && [ -d "$MIND_DEBUG_DIR" ]; then
    LOG="$MIND_DEBUG_DIR/ladeprotokoll.log"
  else
    LOG="/tmp/mind-ladeprotokoll.log"
  fi
fi
mkdir -p "$(dirname "$LOG")" 2>/dev/null

TS=$(date '+%Y-%m-%d %H:%M:%S')

# Ohne jq wird NICHT geraten -- eine Zeile, die sagt warum, ist mehr wert als
# eine leere Zeile, die wie ein Befund aussieht.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\tKEIN-JQ\t(Protokoll nicht auswertbar)\n' "$TS" >> "$LOG" 2>/dev/null
  exit 0
fi

# Feldnamen sind UNDOKUMENTIERT -- mehrere Kandidaten der Reihe nach probieren.
PFAD=$(printf '%s' "$INPUT" | jq -r '
  .file_path // .path // .instructions_path // .file //
  .hook_input.file_path // .source_path // empty' 2>/dev/null)

GRUND=$(printf '%s' "$INPUT" | jq -r '
  .reason // .matcher // .source // .trigger // .load_reason //
  .hookSpecificOutput.reason // empty' 2>/dev/null)

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

if [ -n "$PFAD" ] && [ -n "$GRUND" ]; then
  printf '%s\t%s\t%s\t%s\n' "$TS" "$GRUND" "$PFAD" "${SID:0:8}" >> "$LOG" 2>/dev/null
else
  # ⛔ Schema unbekannt: die rohe Zeile anhaengen, damit die MESSUNG SELBST sagt,
  #    wie sie zu lesen ist. Auf eine Zeile begrenzt, damit das Protokoll nicht
  #    von einem einzigen grossen Ereignis geflutet wird.
  ROH=$(printf '%s' "$INPUT" | tr '\n' ' ' | cut -c1-600)
  printf '%s\tSCHEMA?\t%s\n' "$TS" "$ROH" >> "$LOG" 2>/dev/null
fi

# Rotation -- ein Protokoll, das die Platte fuellt, wird abgeschaltet statt gelesen.
MAX="${MIND_LADEPROTOKOLL_MAX:-4000}"
if [ -f "$LOG" ]; then
  N=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
  case "$N" in ''|*[!0-9]*) N=0;; esac
  if [ "$N" -gt "$MAX" ] 2>/dev/null; then
    BEHALTEN=$((MAX * 6 / 10))
    tail -n "$BEHALTEN" "$LOG" > "$LOG.tmp" 2>/dev/null \
      && mv -f "$LOG.tmp" "$LOG" 2>/dev/null
    rm -f "$LOG.tmp" 2>/dev/null
  fi
fi

exit 0
