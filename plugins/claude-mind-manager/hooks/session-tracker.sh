#!/bin/bash
# Claude Mind Manager — UserPromptSubmit Hook (Session Tracker)
# Increments a per-session message counter in /tmp for the Stop hook.
# No stdout — UserPromptSubmit output goes to context and we don't want noise.

source "$(dirname "$0")/lib.sh"
mind_init "session-tracker"

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

COUNT=$(read_counter)
COUNT=$((COUNT + 1))
atomic_write_counter "$COUNT"

exit 0
