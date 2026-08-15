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

# --- mind_snapshot: Voller Context-Satz-Snapshot vor autonomen Edits (NEU v5.0.0) ---
# Args: $1=project_dir, $2=label (z.B. "pre-mind-all", "pre-claudemd")
# Returns: Snapshot-Pfad via stdout, Exit 0 = OK / 1 = FEHLGESCHLAGEN (Skill MUSS abbrechen)
#
# Warum zusaetzlich zu create_backup: create_backup sichert nur CLAUDE.md/MEMORY.md/Transkript.
# Die Skills editieren aber auch .claude/rules/*.md und MEMORY-Topic-Files. Im Autonom-Modus
# (v5.0.0) muss der GESAMTE Context-Satz als EINE revertierbare Einheit gesichert sein.
mind_snapshot() {
  local project_dir="$1"
  local label="${2:-snapshot}"
  local keep="${MIND_BACKUP_KEEP_COUNT:-5}"
  local ts snap_root snap memory_dir count=0
  ts=$(date +%Y%m%d_%H%M%S)
  snap_root="$project_dir/.claude-mind/snapshots"
  snap="$snap_root/${ts}_${label}"

  mkdir -p "$snap" 2>/dev/null || { echo "SNAPSHOT-FEHLER: kann $snap nicht anlegen" >&2; return 1; }

  # 1) CLAUDE.md (beide moeglichen Orte)
  # M1-Fix: beide Orte haben denselben Basenamen -> getrennte Zielnamen, sonst
  # ueberschreibt der zweite den ersten waehrend count 2 zaehlt (Manifest luegt).
  [ -f "$project_dir/CLAUDE.md" ] && { cp "$project_dir/CLAUDE.md" "$snap/CLAUDE.md" 2>/dev/null && count=$((count+1)); }
  [ -f "$project_dir/.claude/CLAUDE.md" ] && { cp "$project_dir/.claude/CLAUDE.md" "$snap/dot-claude-CLAUDE.md" 2>/dev/null && count=$((count+1)); }
  # 2) MEMORY.md + ALLE Topic-Files
  # WICHTIG (Negativkontrolle 2026-08-15): get_memory_dir faellt bei Slug-Mismatch auf das
  # NEUESTE FREMDE Projekt zurueck (rc=1). Ein Snapshot darf NIE fremde Memory sichern —
  # ein spaeterer Restore wuerde die Daten eines anderen Projekts einspielen.
  local mem_rc
  memory_dir=$(get_memory_dir "$project_dir" 2>/dev/null); mem_rc=$?
  if [ "$mem_rc" -ne 0 ]; then
    mind_log WARN "mind_snapshot: get_memory_dir-Fallback — Memory NICHT gesichert (Fremd-Projekt-Gefahr)"
    echo "WARN: Memory-Dir nicht eindeutig aufloesbar — Memory aus diesem Snapshot ausgenommen" >&2
    memory_dir=""
  fi
  if [ -n "$memory_dir" ] && [ -d "$memory_dir" ]; then
    mkdir -p "$snap/memory"
    for f in "$memory_dir"/*.md; do
      [ -f "$f" ] && { cp "$f" "$snap/memory/" 2>/dev/null && count=$((count+1)); }
    done
  fi
  # 3) Projekt-Rules (die editieren die Skills ebenfalls)
  if [ -d "$project_dir/.claude/rules" ]; then
    mkdir -p "$snap/rules"
    for f in "$project_dir/.claude/rules"/*.md; do
      [ -f "$f" ] && { cp "$f" "$snap/rules/" 2>/dev/null && count=$((count+1)); }
    done
  fi

  # C4-Fix: Frisches Projekt (mind-files' Hauptfall) hat noch KEINEN Context-Satz.
  # "Nichts zu schuetzen" ist KEIN Fehler — nur "vorhanden aber nicht sicherbar" ist einer.
  if [ "$count" -eq 0 ]; then
    if [ -e "$project_dir/CLAUDE.md" ] || [ -e "$project_dir/.claude/CLAUDE.md" ] ||        [ -d "$project_dir/.claude/rules" ] || { [ -n "$memory_dir" ] && [ -d "$memory_dir" ]; }; then
      echo "SNAPSHOT-FEHLER: Context-Dateien vorhanden, aber 0 gesichert (Rechte? Platte voll?)" >&2
      return 1
    fi
    echo "# LEER: kein Context-Satz vorhanden (frisches Projekt) — nichts zu sichern" > "$snap/LEER"
    mind_log INFO "mind_snapshot: LEER (frisches Projekt, nichts zu sichern) -> $snap"
    echo "$snap"; return 0
  fi

  # 4) GLOBALE Context-Dateien (C3-Fix): /mind-claudemd global editiert ~/.claude/CLAUDE.md,
  #    mind-update fixt ~/.claude/rules/*.md, mind-rules migrate schreibt User-Rules um.
  #    Das ist der wertvollste, am schwersten ersetzbare Kontext — er MUSS ins Netz.
  if [ -f "$HOME/.claude/CLAUDE.md" ]; then
    mkdir -p "$snap/global"; cp "$HOME/.claude/CLAUDE.md" "$snap/global/CLAUDE.md" 2>/dev/null && count=$((count+1))
  fi
  if [ -d "$HOME/.claude/rules" ]; then
    mkdir -p "$snap/global/rules"
    for f in "$HOME/.claude/rules"/*.md; do
      [ -f "$f" ] && { cp "$f" "$snap/global/rules/" 2>/dev/null && count=$((count+1)); }
    done
  fi

  # 5) MANIFEST mit SHA-256 (Grundlage fuer Restore-Verifikation)
  {
    echo "# mind_snapshot MANIFEST"
    echo "# label=$label  ts=$ts  project=$project_dir  files=$count"
    (cd "$snap" && find . -type f ! -name MANIFEST.sha256 -exec sha256sum {} \; 2>/dev/null)
  } > "$snap/MANIFEST.sha256" 2>/dev/null
  command -v sha256sum >/dev/null 2>&1 || echo "WARN: sha256sum fehlt — MANIFEST ohne Hashes, Restore nicht verifizierbar" >&2

  # 5) Rotation
  # M2-Fix: KEIN xargs — jeder Pfad hier enthaelt Leerzeichen ("Plugin - Entwicklung").
  # xargs wortsplittet und feuerte rm -rf auf Fragmente relativ zum CWD.
  ls -td "$snap_root"/*/ 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done

  mind_log INFO "mind_snapshot: $count Dateien -> $snap"
  echo "$snap"
  return 0
}
