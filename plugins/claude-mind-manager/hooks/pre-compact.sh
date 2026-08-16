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

# Lebenszeichen (v5.2.1) — macht einen spaeteren stillen Hook-Tod nachweisbar
mind_heartbeat "$PROJECT_DIR" "PreCompact/${TRIGGER}"

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

      # --- Auftrags-Sicherung (v5.2.0; ab v5.2.1 MIT ZEITSTEMPEL) ---
      # Der laufende Auftrag wird HERAUSGEZOGEN, bevor er wegkompaktiert wird — deterministisch
      # aus dem Transkript, nicht aus dem Gedaechtnis eines Modells.
      # v5.2.1: frueher fester Name "RESUME.md" — die NAECHSTE Kompaktierung ueberschrieb damit
      # den Auftragstext der vorigen. Zwei Kompaktierungen vor einem Sync und der aeltere Auftrag
      # war weg. Jetzt zeitgestempelt; OPEN zeigt auf die richtige Datei.
      RESUME_FILE="$RESCUE_DIR/${RTS}_RESUME.md"
      if command -v cygpath >/dev/null 2>&1; then RR_WIN=$(cygpath -w "$RESUME_FILE"); else RR_WIN="$RESUME_FILE"; fi
      if "$RPY" "$RS_WIN" --orders "$RT_WIN" "$RR_WIN" >/dev/null 2>&1 && [ -s "$RESUME_FILE" ]; then
        mind_log "orders saved -> $RESUME_FILE"
        echo "[Mind Manager] Auftrag gesichert: ${RESUME_FILE##*/}"
      else
        mind_log WARN "Auftrags-Sicherung fehlgeschlagen (Chat-Rettung ist trotzdem da)"
        rm -f "$RESUME_FILE" 2>/dev/null
        RESUME_FILE=""
      fi

      # --- SCHULD-Merker OPEN (NEU v5.2.1 — loest PENDING ab) ---
      # WARUM die Umbenennung mehr ist als ein neuer Name: PENDING wurde beim ANKUENDIGEN
      # geloescht (prompt-submit.sh/session-start.sh benannten es in .announced um), nicht beim
      # ERLEDIGEN. Belegt am 2026-08-16: Ankuendigung kam an, der laufende Auftrag hatte Vorrang
      # (so will es v5.2.0) — und damit war die Sync-Schuld fuer immer unsichtbar. 417 KB
      # geretteter Chat lagen da, die nie jemand eingespeist hat.
      # OPEN wird NUR entfernt, wenn der Sync wirklich lief (/mind-all bzw. /mind-update mit
      # Rettungsquelle) oder wenn die Rettungsdatei nachweislich weg ist.
      PREV_C=0
      if [ -f "$RESCUE_DIR/OPEN" ]; then
        PREV_C=$(grep -m1 '^compactions=' "$RESCUE_DIR/OPEN" 2>/dev/null | cut -d= -f2-)
        case "$PREV_C" in ''|*[!0-9]*) PREV_C=0 ;; esac
      fi
      {
        echo "path=$RESCUE_FILE"
        echo "resume=$RESUME_FILE"
        echo "events=${RESCUE_N:-?}"
        echo "ts=$RTS"
        echo "trigger=$TRIGGER"
        echo "compactions=$((PREV_C + 1))"   # seit dem letzten erfolgreichen Sync
        echo "blocks=0"                       # Stop-Hook-Notausgang, s. hooks/stop.sh
      } > "$RESCUE_DIR/OPEN" 2>/dev/null
      # Neue Rettung -> in JEDER Sitzung neu ankuendigen, Notausgang-Zaehler auf 0
      rm -f "$RESCUE_DIR/OPEN.seen-"* 2>/dev/null
      # Altlasten aus v5.1.0/v5.2.0 wegraeumen (sonst redet niemand mehr ueber sie)
      rm -f "$RESCUE_DIR/PENDING" "$RESCUE_DIR/PENDING.announced" "$RESCUE_DIR/RESUME.md" \
            "$RESCUE_DIR/RESUME.done.md" 2>/dev/null

      mind_log "chat rescued: ${RESCUE_N:-?} Beitraege -> $RESCUE_FILE (compactions seit Sync: $((PREV_C + 1)))"
      echo "[Mind Manager] Chat gerettet: ${RESCUE_N:-?} Beitraege -> ${RESCUE_FILE##*/}"
      if [ "$PREV_C" -gt 0 ]; then
        echo "[Mind Manager] ACHTUNG: $((PREV_C + 1)) Kompaktierungen seit dem letzten /mind-all — Sync steht aus."
      fi
      # Rotation (KEIN xargs — Pfade enthalten Leerzeichen). RESUME-Dateien mitrotieren;
      # *_RESUME.done.md faellt nicht unter das Muster und bleibt als Beleg liegen.
      for pat in '*_chat.md' '*_RESUME.md'; do
        ls -t "$RESCUE_DIR"/$pat 2>/dev/null | tail -n +$((RESCUE_KEEP + 1)) | while IFS= read -r f; do
          [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
        done
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
