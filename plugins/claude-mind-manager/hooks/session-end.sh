#!/bin/bash
# Claude Mind Manager — SessionEnd Hook
# Creates a final session summary and detects new dependencies.
# Resets the per-session message counter.

source "$(dirname "$0")/lib.sh"
mind_init "session-end"

if [ -z "$PROJECT_DIR" ] || [ -z "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# --- Read message count ---
MSG_COUNT=$(read_counter)

# Skip trivially short sessions (< 3 messages)
if [ "$MSG_COUNT" -lt 3 ]; then
  rm -f "$(get_counter_file)"
  exit 0
fi

# --- Final backup (incl. transcript) ---
BACKED_UP=$(create_backup "$PROJECT_DIR" "$TRANSCRIPT_PATH")

# --- Write session summary ---
SUMMARY_FILE=$(write_session_summary "$PROJECT_DIR" "$TRANSCRIPT_PATH" "$MSG_COUNT")

# --- Reset counter ---
rm -f "$(get_counter_file)"

# --- Report ---
echo "[Mind Manager] Session ended: ${MSG_COUNT} messages, ${BACKED_UP} file(s) backed up -> $(basename "$SUMMARY_FILE")"

exit 0
