#!/bin/bash
# Claude Mind Manager — SessionStart Hook
# Checks MEMORY.md and CLAUDE.md line counts, rules syntax, outputs context injection.
# Exit 0 + stdout → injected as Claude context (SessionStart special behavior).

source "$(dirname "$0")/lib.sh"
mind_init "session-start"

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

# --- Paths ---
HASH=$(hash_project_dir "$PROJECT_DIR")
MEMORY_FILE="$HOME/.claude/projects/$HASH/memory/MEMORY.md"
MIND_DIR="$PROJECT_DIR/.claude-mind"

# --- Auto-migrate old backups to .claude-mind/ (one-time) ---
if [ ! -d "$MIND_DIR" ]; then
  mkdir -p "$MIND_DIR/backups"
  OLD_BACKUP_DIR="$HOME/.claude/projects/$HASH/memory/backups"
  if [ -d "$OLD_BACKUP_DIR" ]; then
    cp "$OLD_BACKUP_DIR"/*.md "$MIND_DIR/backups/" 2>/dev/null
  fi
fi

WARNINGS=""
WARN_COUNT=0

# --- Configurable thresholds via env vars (set in settings.json env:{}) ---
MEMORY_THRESHOLD="${MIND_MEMORY_WARN_THRESHOLD:-180}"
CLAUDE_MD_THRESHOLD="${MIND_CLAUDE_MD_MAX_LINES:-200}"

# --- Check MEMORY.md ---
if [ -f "$MEMORY_FILE" ]; then
  MEM_LINES=$(wc -l < "$MEMORY_FILE" | tr -d ' ')
  if [ "$MEM_LINES" -gt "$MEMORY_THRESHOLD" ]; then
    WARNINGS="${WARNINGS}MEMORY.md: ${MEM_LINES}/200 lines (threshold: ${MEMORY_THRESHOLD}). Run /mind-cleanup to free space. "
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
else
  MEM_LINES=0
fi

# --- Check project CLAUDE.md ---
for CMD_FILE in "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/.claude/CLAUDE.md"; do
  if [ -f "$CMD_FILE" ]; then
    CMD_LINES=$(wc -l < "$CMD_FILE" | tr -d ' ')
    if [ "$CMD_LINES" -gt "$CLAUDE_MD_THRESHOLD" ]; then
      REL_PATH=$(echo "$CMD_FILE" | sed "s|$PROJECT_DIR/||")
      WARNINGS="${WARNINGS}${REL_PATH}: ${CMD_LINES} lines (threshold: ${CLAUDE_MD_THRESHOLD}). Compliance may degrade (>400 lines = 71%). Run /mind-optimize. "
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
    break  # Only check first found
  fi
done

# --- Check CLAUDE.local.md deprecation ---
if [ -f "$PROJECT_DIR/CLAUDE.local.md" ]; then
  WARNINGS="${WARNINGS}CLAUDE.local.md detected. Anthropic indicates deprecation — consider migrating to @imports. Run /mind-optimize. "
  WARN_COUNT=$((WARN_COUNT + 1))
fi

# --- Check rules for paths: bug ---
RULES_DIR="$PROJECT_DIR/.claude/rules"
if [ -d "$RULES_DIR" ]; then
  BAD_RULES=$(grep -rl '^paths:' "$RULES_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$BAD_RULES" -gt 0 ]; then
    WARNINGS="${WARNINGS}${BAD_RULES} rule file(s) use 'paths:' (known bug, may be silently ignored). Run /mind-rules migrate to fix. "
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
fi

# --- Check active context ---
ACTIVE_CTX="$PROJECT_DIR/.claude/rules/active-context.md"
if [ -f "$ACTIVE_CTX" ]; then
  CTX_DATE=$(grep '^# Last updated:' "$ACTIVE_CTX" 2>/dev/null | sed 's/# Last updated: //')
  if [ -n "$CTX_DATE" ]; then
    WARNINGS="${WARNINGS}Active context from last session loaded (saved: ${CTX_DATE}). "
  fi
fi

# --- Output ---
if [ "$WARN_COUNT" -gt 0 ] || [ -f "$ACTIVE_CTX" ]; then
  ESCAPED_WARNINGS=$(echo "$WARNINGS" | sed 's/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"[Mind Manager] %d warning(s): %s"}}' \
    "$WARN_COUNT" "$ESCAPED_WARNINGS"
fi

# --- Persist env vars for session ---
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "MIND_MEMORY_LINES=${MEM_LINES}" >> "$CLAUDE_ENV_FILE"
  echo "MIND_DIR=${MIND_DIR}" >> "$CLAUDE_ENV_FILE"
fi

exit 0
