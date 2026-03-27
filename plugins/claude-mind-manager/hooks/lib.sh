#!/bin/bash
# Claude Mind Manager — Shared Hook Functions (lib.sh)
# Sourced by all hook scripts. Eliminates code duplication across hooks.
# Usage: source "$(dirname "$0")/lib.sh"

# --- Constants ---
MIND_LOG_FILE="/tmp/mind-manager.log"
MIND_LOG_MAX_LINES="${MIND_LOG_MAX_LINES:-500}"
MIND_SCRIPT_NAME="unknown"

# --- mind_log: Always-on logging with auto-rotation ---
# Logs everything for continuous debugging. Auto-trims when exceeding max lines.
# Args: $1 = level (INFO|WARN|ERROR, optional — default INFO), rest = message
mind_log() {
  local level="INFO"
  if [[ "$1" =~ ^(INFO|WARN|ERROR)$ ]]; then
    level="$1"; shift
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${level} ${MIND_SCRIPT_NAME}: $*" >> "$MIND_LOG_FILE" 2>/dev/null
  # Auto-rotate: trim to 60% when log exceeds max lines
  if [ -f "$MIND_LOG_FILE" ]; then
    local lines
    lines=$(wc -l < "$MIND_LOG_FILE" 2>/dev/null || echo 0)
    if [ "$lines" -gt "$MIND_LOG_MAX_LINES" ]; then
      local keep=$(( MIND_LOG_MAX_LINES * 3 / 5 ))
      tail -"$keep" "$MIND_LOG_FILE" > "${MIND_LOG_FILE}.tmp" 2>/dev/null && \
        mv "${MIND_LOG_FILE}.tmp" "$MIND_LOG_FILE" 2>/dev/null
    fi
  fi
}

# --- mind_init: Standard preamble for all hooks ---
# Sets: INPUT, PROJECT_DIR, TRANSCRIPT_PATH, SESSION_ID
# Args: $1 = script name (for logging)
mind_init() {
  MIND_SCRIPT_NAME="${1:-unknown}"
  if ! command -v jq &>/dev/null; then
    mind_log ERROR "jq not found in PATH"
    exit 0
  fi
  INPUT=$(cat)
  PROJECT_DIR=$(echo "$INPUT" | jq -r '.cwd // empty')
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
  mind_log "init (session=${SESSION_ID:0:8}, project=$(basename "$PROJECT_DIR" 2>/dev/null))"
}

# --- hash_project_dir: Deterministic project hash ---
# Used to locate ~/.claude/projects/<hash>/memory/
hash_project_dir() {
  echo "$1" | tr '/\\: ' '----' | sed 's/^-*//'
}

# --- Counter operations (atomic) ---

get_counter_key() {
  if [ -n "$SESSION_ID" ]; then
    echo "$SESSION_ID"
  else
    hash_project_dir "$PROJECT_DIR"
  fi
}

get_counter_file() {
  echo "/tmp/mind-msg-count-$(get_counter_key)"
}

read_counter() {
  local f
  f=$(get_counter_file)
  if [ -f "$f" ]; then
    cat "$f" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# Atomic write: write to temp then mv (prevents race conditions)
atomic_write_counter() {
  local val="$1"
  local f
  f=$(get_counter_file)
  local tmp="${f}.tmp.$$"
  echo "$val" > "$tmp"
  mv "$tmp" "$f"
}

# --- extract_assistant_text: Parse transcript JSONL for assistant messages ---
# Args: $1=transcript_path, $2=tail_lines (default 150), $3=max_bytes (default 8000)
JQ_ASSISTANT_TEXT='
  select(.type == "assistant" or .role == "assistant") |
  if .message then
    (.message.content // empty) | if type == "array" then
      map(select(.type == "text") | .text) | join("\n")
    elif type == "string" then .
    else empty end
  elif .content then
    if (.content | type) == "array" then
      .content | map(select(.type == "text") | .text) | join("\n")
    elif (.content | type) == "string" then .content
    else empty end
  else empty end
'

extract_assistant_text() {
  local transcript="$1"
  local tail_lines="${2:-150}"
  local max_bytes="${3:-8000}"
  tail -"$tail_lines" "$transcript" 2>/dev/null | \
    jq -r "$JQ_ASSISTANT_TEXT" 2>/dev/null | \
    tail -c "$max_bytes" 2>/dev/null
}

# --- create_backup: Backup MEMORY.md, CLAUDE.md, active-context.md, transcript ---
# Args: $1=project_dir, $2=transcript_path (optional, for transcript backup)
# Returns: number of files backed up (via stdout)
create_backup() {
  local project_dir="$1"
  local transcript="$2"
  local keep_count="${MIND_BACKUP_KEEP_COUNT:-5}"
  local transcript_keep="${MIND_TRANSCRIPT_KEEP_COUNT:-3}"
  local mind_dir="$project_dir/.claude-mind"
  local backup_dir="$mind_dir/backups"
  local hash
  hash=$(hash_project_dir "$project_dir")
  local memory_dir="$HOME/.claude/projects/$hash/memory"

  mkdir -p "$backup_dir"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  local count=0

  # Backup MEMORY.md
  if [ -f "$memory_dir/MEMORY.md" ]; then
    cp "$memory_dir/MEMORY.md" "$backup_dir/MEMORY-${ts}.md" 2>/dev/null && count=$((count + 1))
  fi

  # Backup CLAUDE.md (check both locations)
  for f in "$project_dir/CLAUDE.md" "$project_dir/.claude/CLAUDE.md"; do
    if [ -f "$f" ]; then
      cp "$f" "$backup_dir/CLAUDE-${ts}.md" 2>/dev/null && count=$((count + 1))
      break
    fi
  done

  # Backup active-context.md
  local ctx="$project_dir/.claude/rules/active-context.md"
  if [ -f "$ctx" ]; then
    cp "$ctx" "$backup_dir/active-context-${ts}.md" 2>/dev/null && count=$((count + 1))
  fi

  # Backup transcript (if path provided and file exists)
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    cp "$transcript" "$backup_dir/transcript-${ts}.jsonl" 2>/dev/null && count=$((count + 1))
  fi

  # Rotate: keep last N per type
  for prefix in MEMORY CLAUDE active-context; do
    ls -t "$backup_dir/${prefix}-"*.md 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -f 2>/dev/null
  done
  # Transcripts: separate rotation (larger files, keep fewer)
  ls -t "$backup_dir/transcript-"*.jsonl 2>/dev/null | tail -n +$((transcript_keep + 1)) | xargs rm -f 2>/dev/null

  echo "$count"
}

# --- atomic_append: Append to file with locking ---
# Args: $1=target_file, $2=content
atomic_append() {
  local target="$1"
  local content="$2"
  local lockfile="${target}.lock"

  if command -v flock &>/dev/null; then
    (flock -w 5 200 && echo "$content" >> "$target") 200>"$lockfile"
  else
    # Fallback for Windows git bash: mkdir-based lock
    local i=0
    while ! mkdir "$lockfile" 2>/dev/null; do
      i=$((i + 1))
      if [ "$i" -gt 50 ]; then break; fi
      sleep 0.1
    done
    echo "$content" >> "$target"
    rmdir "$lockfile" 2>/dev/null
  fi
}

# --- Learnings regex (centralized, refined for fewer false positives) ---
LEARNINGS_REGEX='(instead of|should have|fix(ed)?:|the error was|mistake was|correction:|NEVER |MUST |ALWAYS |decided to use|chose .* over|switched from|changed .* to |the issue was|root cause was|workaround:)'

# --- extract_learnings: Extract correction patterns from transcript ---
# Args: $1=transcript_path, $2=tail_lines (default 150)
# Output: formatted learnings lines (prefixed with "- ")
extract_learnings() {
  local transcript="$1"
  local tail_lines="${2:-150}"
  tail -"$tail_lines" "$transcript" 2>/dev/null | \
    jq -r "$JQ_ASSISTANT_TEXT" 2>/dev/null | \
    grep -iE "$LEARNINGS_REGEX" 2>/dev/null | \
    head -30 | \
    sed 's/^[[:space:]]*/- /' 2>/dev/null
}

# --- write_session_summary: Create session summary from transcript ---
# Args: $1=project_dir, $2=transcript_path, $3=message_count, $4=tail_lines (default 150)
write_session_summary() {
  local project_dir="$1"
  local transcript="$2"
  local msg_count="$3"
  local tail_lines="${4:-150}"
  local sessions_dir="$project_dir/.claude-mind/sessions"
  mkdir -p "$sessions_dir"

  local ts
  ts=$(date '+%Y-%m-%d-%H%M')
  local session_file="$sessions_dir/session-${ts}.md"

  local tail_data=""
  if [ -f "$transcript" ]; then
    tail_data=$(tail -"$tail_lines" "$transcript" 2>/dev/null)
  fi

  local context_text=""
  if [ -n "$tail_data" ]; then
    context_text=$(echo "$tail_data" | jq -r "$JQ_ASSISTANT_TEXT" 2>/dev/null)
  fi

  local decisions errors file_changes key_commands
  decisions=$(echo "$context_text" | grep -iE '(decided|chose|using|switched to|went with|selected)' 2>/dev/null | head -5)
  errors=$(echo "$context_text" | grep -iE '(error|failed|exception|fix|bug)' 2>/dev/null | head -5)
  file_changes=$(echo "$tail_data" | jq -r '
    select(.type == "tool_use") | select(.name == "Write" or .name == "Edit") |
    "\(.name): \(.input.file_path // "unknown" | tostring | .[0:80])"
  ' 2>/dev/null | sort -u | head -10)
  key_commands=$(echo "$tail_data" | jq -r '
    select(.type == "tool_use") | select(.name == "Bash") |
    .input.command // empty | .[0:80]
  ' 2>/dev/null | head -8)

  cat > "$session_file" <<SESSEOF
# Session Summary — ${ts}

- **Messages:** ${msg_count}
- **Project:** ${project_dir}

## Decisions
${decisions:-_No explicit decisions detected._}

## Errors Encountered
${errors:-_No errors detected._}

## File Changes
${file_changes:-_No file changes detected._}

## Key Commands
${key_commands:-_No commands detected._}
SESSEOF

  # Detect new dependencies
  local new_deps=""
  new_deps=$(echo "$tail_data" | jq -r '
    select(.type == "tool_use") | select(.name == "Bash") |
    .input.command // empty
  ' 2>/dev/null | grep -oE '(npm install|pip install|cargo add) [^ ]+' 2>/dev/null | sort -u)

  if [ -n "$new_deps" ]; then
    local suggest_file="$project_dir/.claude-mind/suggestions.md"
    mkdir -p "$project_dir/.claude-mind"
    atomic_append "$suggest_file" "
## Session ${ts}
- New dependencies: ${new_deps}"
  fi

  echo "$session_file"
}
