#!/bin/bash
# Claude Mind Manager v3.0 — Shared Hook Functions (lib.sh)
# Sourced by pre-compact.sh (the only remaining hook).
# Usage: source "$(dirname "$0")/lib.sh"

# --- Constants ---
MIND_LOG_FILE="/tmp/mind-manager.log"
MIND_LOG_MAX_LINES="${MIND_LOG_MAX_LINES:-500}"
MIND_SCRIPT_NAME="unknown"

# --- _md5: Cross-platform MD5 hash (md5sum/md5/fallback) ---
# Returns hash of file, or "no-md5" if no tool available.
_md5() {
  if command -v md5sum &>/dev/null; then
    md5sum "$@" 2>/dev/null | cut -d' ' -f1
  elif command -v md5 &>/dev/null; then
    md5 -r "$@" 2>/dev/null | cut -d' ' -f1
  else
    echo "no-md5"
  fi
}

# --- mind_log: Always-on logging with auto-rotation ---
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

# --- mind_init: Standard preamble for hooks ---
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

# --- hash_project_dir: Cross-platform Slug-Derivation (v3.2.2 redesigned) ---
# Args: $1 = project_dir (oder $(pwd) wenn leer)
# Output: Slug passend zu Claude-Code's Schema
# Konvertiert Drive-Letter zu Großbuchstaben (cygpath), Backslash/Colon/Space/Klammern zu -
#
# Replaces v3.0 implementation that had Klammern-Bug + Backslash-Bug
# (alte Funktion produzierte korrupte Slugs für Windows-Pfade aus JSON-CWD).
#
# HARD REQUIREMENT: cygpath muss verfuegbar sein (Git-Bash, MSYS2, Cygwin).
# Auf reinem Linux/macOS ist das Plugin sowieso eingeschraenkt nutzbar
# (Claude Code Plugin ist primaer fuer Windows + Git-Bash designed).
# H1-Fix v3.2.2: alter sed-Fallback war broken auf BSD-sed (GNU \U Escape).
hash_project_dir() {
  local project_dir="${1:-$(pwd)}"
  local win_path

  if ! command -v cygpath &>/dev/null; then
    mind_log ERROR "cygpath nicht verfuegbar - hash_project_dir() braucht cygpath (Git-Bash/MSYS2/Cygwin)"
    echo "ERROR: cygpath required for hash_project_dir()" >&2
    # Best-effort: assume project_dir ist schon Windows-Form
    win_path="$project_dir"
  else
    win_path=$(cygpath -w "$project_dir" 2>/dev/null || echo "$project_dir")
  fi

  # Backslash, Colon, Space, Klammern → Bindestrich
  # Fuehrende Bindestriche entfernen
  echo "$win_path" | sed 's|[\\: ()]|-|g' | sed 's|^-*||'
}

# --- get_memory_dir: Project-spezifisches MEMORY-Verzeichnis (v3.2.2 NEU) ---
# Mit Fallback auf neuestes Projekt-Dir (mtime) bei Slug-Mismatch
# Args: optional $1 = project_dir (default $(pwd))
# Returns: 0 wenn primary dir gefunden, 1 wenn Fallback verwendet wurde (H2-Fix)
get_memory_dir() {
  local hash
  hash=$(hash_project_dir "$@")
  local memory_dir="$HOME/.claude/projects/$hash/memory"

  if [ -d "$memory_dir" ]; then
    echo "$memory_dir"
    return 0
  fi

  # Fallback: neuestes Projekt-Dir
  local projects_dir
  projects_dir=$(ls -td "$HOME"/.claude/projects/*/ 2>/dev/null | head -1 | sed 's|/$||')
  memory_dir="$projects_dir/memory"

  # H2-Fix: stderr-Warnung damit Skill/User mismatch erkennt
  mind_log WARN "Slug-Dir $hash nicht gefunden, fallback: $projects_dir"
  echo "WARN: get_memory_dir Fallback (Slug-Mismatch) — verwende $projects_dir statt $hash" >&2

  echo "$memory_dir"
  return 1
}

# --- _backup_if_changed: Copy file only if content differs from latest backup ---
# Args: $1=src, $2=dst, $3=prefix, $4=backup_dir
# Returns: 0 if copied, 1 if skipped (unchanged)
_backup_if_changed() {
  local src="$1" dst="$2" prefix="$3" backup_dir="$4"
  local latest=$(ls -t "$backup_dir/${prefix}-"* 2>/dev/null | head -1)
  if [ -n "$latest" ]; then
    local src_hash=$(_md5 "$src")
    local dst_hash=$(_md5 "$latest")
    if [ "$src_hash" = "$dst_hash" ] && [ "$src_hash" != "no-md5" ]; then
      mind_log "backup skipped (${prefix} unchanged)"
      return 1
    fi
  fi
  cp "$src" "$dst" 2>/dev/null
}

# --- create_backup: Backup MEMORY.md, CLAUDE.md, transcript ---
# Args: $1=project_dir, $2=transcript_path (optional)
# Returns: number of files backed up (via stdout)
create_backup() {
  local project_dir="$1"
  local transcript="$2"
  local keep_count="${MIND_BACKUP_KEEP_COUNT:-5}"
  local transcript_keep="${MIND_TRANSCRIPT_KEEP_COUNT:-3}"
  local mind_dir="$project_dir/.claude-mind"
  local backup_dir="${MIND_BACKUP_DIR:-$mind_dir/backups}"
  local hash
  hash=$(hash_project_dir "$project_dir")
  local memory_dir="$HOME/.claude/projects/$hash/memory"

  mkdir -p "$backup_dir"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  local count=0

  # Backup MEMORY.md (skip if unchanged)
  if [ -f "$memory_dir/MEMORY.md" ]; then
    _backup_if_changed "$memory_dir/MEMORY.md" "$backup_dir/MEMORY-${ts}.md" "MEMORY" "$backup_dir" && count=$((count + 1))
  fi

  # Backup CLAUDE.md (check both locations, skip if unchanged)
  for f in "$project_dir/CLAUDE.md" "$project_dir/.claude/CLAUDE.md"; do
    if [ -f "$f" ]; then
      _backup_if_changed "$f" "$backup_dir/CLAUDE-${ts}.md" "CLAUDE" "$backup_dir" && count=$((count + 1))
      break
    fi
  done

  # Backup transcript (skip if unchanged)
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    _backup_if_changed "$transcript" "$backup_dir/transcript-${ts}.jsonl" "transcript" "$backup_dir" && count=$((count + 1))
  fi

  # Rotate: keep last N per type
  for prefix in MEMORY CLAUDE; do
    ls -t "$backup_dir/${prefix}-"*.md 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -f 2>/dev/null
  done
  # Transcripts: separate rotation (larger files, keep fewer)
  ls -t "$backup_dir/transcript-"*.jsonl 2>/dev/null | tail -n +$((transcript_keep + 1)) | xargs rm -f 2>/dev/null

  echo "$count"
}
