#!/bin/bash
# Claude Mind Manager — PreCompact Hook
# Backs up MEMORY.md, CLAUDE.md, active-context.md, and transcript before compaction.
# Keeps last N backups (default 5) to prevent unbounded growth.

source "$(dirname "$0")/lib.sh"
mind_init "pre-compact"

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"')

# --- Create backup (with transcript) ---
BACKED_UP=$(create_backup "$PROJECT_DIR" "$TRANSCRIPT_PATH" 2>/dev/null)

# --- Report ---
if [ -n "$BACKED_UP" ] && [ "$BACKED_UP" -gt 0 ]; then
  mind_log "pre-compact backup: ${BACKED_UP} files (trigger: ${TRIGGER})"
  echo "[Mind Manager] Pre-compact backup: ${BACKED_UP} file(s) saved (trigger: ${TRIGGER})"
else
  mind_log "Pre-compact backup failed or no files to back up (trigger: ${TRIGGER})"
  echo "[Mind Manager] Pre-compact: no files backed up (trigger: ${TRIGGER})"
fi

exit 0
