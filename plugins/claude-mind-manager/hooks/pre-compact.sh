#!/bin/bash
# Claude Mind Manager — PreCompact Hook
# Backs up MEMORY.md + CLAUDE.md before compaction. Transcript: POINTER only (v5.0.0),
# keine Kopie mehr — sie wuchs auf 32 MB/Workspace und wurde per rclone hochgeladen.
# Keeps last N backups (default 5) to prevent unbounded growth.

source "$(dirname "$0")/lib.sh"
mind_init "pre-compact"

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"')

# --- Create backup (OHNE Transkript-Kopie, v5.0.0) ---
# Frueher: create_backup "$PROJECT_DIR" "$TRANSCRIPT_PATH" -> kopierte das VOLLE Transkript in
# den Projektordner. Gemessen 2026-08-15: 32 MB in EINEM Workspace (Einzeldateien 4-7 MB), bei
# 3 vorgehaltenen Staenden bis ~60 MB — und unter C:\CD\KOHLEKTIV laedt rclone das nach Z: hoch.
# Das Transkript ist unveraenderlich und liegt ohnehin unter ~/.claude/projects/<slug>/.
# Deshalb: nur noch ZEIGER statt Kopie.
BACKED_UP=$(create_backup "$PROJECT_DIR" "" 2>/dev/null)

# --- Transkript-Zeiger statt Kopie ---
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  POINTER_DIR="${MIND_BACKUP_DIR:-$PROJECT_DIR/.claude-mind/backups}"
  mkdir -p "$POINTER_DIR" 2>/dev/null
  {
    echo "# Transkript-Zeiger (v5.0.0 — keine Kopie, Datei liegt unveraendert am Originalort)"
    echo "ts=$(date +%Y%m%d-%H%M%S)  trigger=${TRIGGER}"
    echo "path=$TRANSCRIPT_PATH"
    echo "size_bytes=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null)"
    echo "sha256=$(sha256sum "$TRANSCRIPT_PATH" 2>/dev/null | cut -d' ' -f1)"
  } > "$POINTER_DIR/transcript-pointer.txt" 2>/dev/null
fi

# --- VOLL-RETTUNG des Gespraechs (NEU v5.1.0) ---
# Warum hier: PreCompact feuert genau am Auto-Kompaktierungs-Schwellwert (Standard ~850K).
# Gleich danach ist der Gespraechsverlauf im Live-Kontext weg. Das Transkript auf Platte bleibt
# zwar vollstaendig, ist aber zu gross zum Lesen (12 MB Roh-JSONL). Der reine Gespraechs-Anteil
# sind ~350-400 KB — genau das retten wir, lesbar und ungekuerzt.
# Das ist der DETERMINISTISCHE Teil: er haengt an keiner Entscheidung eines Modells.
RESCUE_DIR="$PROJECT_DIR/.claude-mind/rescued"
RESCUE_KEEP="${MIND_RESCUE_KEEP_COUNT:-3}"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  SAMPLER="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/references/session_sampler.py"
  if [ -f "$SAMPLER" ]; then
    mkdir -p "$RESCUE_DIR" 2>/dev/null
    RTS=$(date +%Y%m%d-%H%M%S)
    RESCUE_FILE="$RESCUE_DIR/${RTS}_chat.md"
    # Python-Pfad (venv bevorzugt, wie im Skill)
    if [ -x ".venv/Scripts/python.exe" ]; then RPY=".venv/Scripts/python.exe"
    elif command -v python3 >/dev/null 2>&1; then RPY="python3"
    else RPY="python"; fi
    # cygpath fuer Windows-Pfade, sonst direkt
    if command -v cygpath >/dev/null 2>&1; then
      RS_WIN=$(cygpath -w "$SAMPLER"); RT_WIN=$(cygpath -w "$TRANSCRIPT_PATH"); RO_WIN=$(cygpath -w "$RESCUE_FILE")
    else
      RS_WIN="$SAMPLER"; RT_WIN="$TRANSCRIPT_PATH"; RO_WIN="$RESCUE_FILE"
    fi
    if RESCUE_OUT=$("$RPY" "$RS_WIN" --full "$RT_WIN" "$RO_WIN" 2>&1) && [ -s "$RESCUE_FILE" ]; then
      RESCUE_N=$(echo "$RESCUE_OUT" | grep -oE '[0-9]+ Beitraege' | grep -oE '[0-9]+' | head -1)
      # PENDING-Merker: wird vom UserPromptSubmit-Hook gelesen und EINMAL angekuendigt
      {
        echo "path=$RESCUE_FILE"
        echo "events=${RESCUE_N:-?}"
        echo "ts=$RTS"
        echo "trigger=$TRIGGER"
      } > "$RESCUE_DIR/PENDING" 2>/dev/null
      rm -f "$RESCUE_DIR/PENDING.announced" 2>/dev/null   # neue Rettung -> neu ankuendigen
      # --- Auftrags-Sicherung (NEU v5.2.0) ---
      # Der laufende Auftrag wird HERAUSGEZOGEN, bevor er wegkompaktiert wird — deterministisch
      # aus dem Transkript, nicht aus dem Gedaechtnis eines Modells. Ohne das steht nach der
      # Kompaktierung zwar der Chat zur Verfuegung, aber niemand weiss mehr, woran gearbeitet wurde.
      if command -v cygpath >/dev/null 2>&1; then RR_WIN=$(cygpath -w "$RESCUE_DIR/RESUME.md"); else RR_WIN="$RESCUE_DIR/RESUME.md"; fi
      if "$RPY" "$RS_WIN" --orders "$RT_WIN" "$RR_WIN" >/dev/null 2>&1 && [ -s "$RESCUE_DIR/RESUME.md" ]; then
        rm -f "$RESCUE_DIR/RESUME.done.md" 2>/dev/null
        mind_log "orders saved -> $RESCUE_DIR/RESUME.md"
      else
        mind_log WARN "Auftrags-Sicherung fehlgeschlagen (Chat-Rettung ist trotzdem da)"
      fi

      mind_log "chat rescued: ${RESCUE_N:-?} Beitraege -> $RESCUE_FILE"
      echo "[Mind Manager] Chat gerettet: ${RESCUE_N:-?} Beitraege -> ${RESCUE_FILE##*/}"
      # Rotation (KEIN xargs — Pfade enthalten Leerzeichen)
      ls -t "$RESCUE_DIR"/*_chat.md 2>/dev/null | tail -n +$((RESCUE_KEEP + 1)) | while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
      done
    else
      # Rettung fehlgeschlagen: KEIN PENDING-Merker (lieber keine Marke als eine ins Leere).
      # Der Hook laeuft trotzdem weiter — die Backups sind wichtiger als der Extrakt.
      mind_log WARN "chat rescue fehlgeschlagen: ${RESCUE_OUT:0:200}"
      echo "[Mind Manager] WARN: Chat-Rettung fehlgeschlagen (Backups sind trotzdem da)"
      rm -f "$RESCUE_FILE" 2>/dev/null
    fi
  else
    mind_log WARN "session_sampler.py nicht gefunden: $SAMPLER"
  fi
fi

# --- Report ---
if [ -n "$BACKED_UP" ] && [ "$BACKED_UP" -gt 0 ]; then
  mind_log "pre-compact backup: ${BACKED_UP} files (trigger: ${TRIGGER})"
  echo "[Mind Manager] Pre-compact backup: ${BACKED_UP} file(s) saved (trigger: ${TRIGGER})"
else
  mind_log "Pre-compact backup failed or no files to back up (trigger: ${TRIGGER})"
  echo "[Mind Manager] Pre-compact: no files backed up (trigger: ${TRIGGER})"
fi

exit 0
