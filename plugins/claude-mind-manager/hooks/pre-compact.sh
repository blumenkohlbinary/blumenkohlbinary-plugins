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

# --- Report ---
if [ -n "$BACKED_UP" ] && [ "$BACKED_UP" -gt 0 ]; then
  mind_log "pre-compact backup: ${BACKED_UP} files (trigger: ${TRIGGER})"
  echo "[Mind Manager] Pre-compact backup: ${BACKED_UP} file(s) saved (trigger: ${TRIGGER})"
else
  mind_log "Pre-compact backup failed or no files to back up (trigger: ${TRIGGER})"
  echo "[Mind Manager] Pre-compact: no files backed up (trigger: ${TRIGGER})"
fi

exit 0
