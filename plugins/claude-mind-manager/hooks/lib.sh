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

# --- _mind_rotate: aelteste Staende wegraeumen, NIE mit xargs (NEU v5.2.1) ---
# Args: $1 = Pfad-Praefix, $2 = Endung, $3 = wie viele behalten
# WARUM eigene Funktion: "ls -t … | xargs rm -f 2>/dev/null" sieht richtig aus, zerlegt aber
# Pfade an Leerzeichen und loescht dann gar nichts — lautlos. Das hat hier 32 MB Altlasten
# angesammelt. Eine Aufraeumung, die stillschweigend nichts tut, ist von einer, die nichts zu
# tun hat, nicht unterscheidbar; deshalb gibt es sie nur noch an einer Stelle.
_mind_rotate() {
  local prefix="$1" suffix="$2" keep="${3:-3}" old
  case "$keep" in ''|*[!0-9]*) keep=3 ;; esac
  ls -t "$prefix"*"$suffix" 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r old; do
    [ -n "$old" ] && [ -f "$old" ] && rm -f "$old"
  done
}

# --- mind_check_tools_have_rules: die "No Dead Tools"-Invariante MESSEN (NEU v5.2.1) ---
# Bis v5.2.0 stand die Invariante als Prosa im Self-Check-Block von mind-files ("1:1
# Tool->Rule-Nachweis") — und Prosa kann sich nicht selbst pruefen. Gemeldet 2026-08-16 als
# "Self-Check-Block nicht durchsetzbar". Das stimmt und laesst sich nicht wegargumentieren;
# ersetzbar ist aber die BEHAUPTUNG durch eine MESSUNG, die scheitern kann.
# Prueft je installiertem Tool, ob eine .claude/rules/*.md es NAMENTLICH nennt UND per
# frontmatter-`globs:` ueberhaupt getriggert wird. Ohne globs waere die Rule tot.
# Rueckgabe 1, sobald ein Tool ohne Rule dasteht.
#
# ⚠ EHRLICHE GRENZE: geprueft wird die ERREICHBARKEIT (Rule existiert, nennt das Tool, hat
#   Globs) — nicht, ob die Rule je gelesen oder befolgt wird. Das bleibt Prosa.
mind_check_tools_have_rules() {
  local project_dir="$1" rc=0 tool base r rulehit found=0
  local tools_dir="$project_dir/tools"
  if [ ! -d "$tools_dir" ]; then
    echo "  Tool->Rule-Nachweis: kein tools/ vorhanden — nichts zu pruefen"
    return 0
  fi
  for tool in "$tools_dir"/*.py "$tools_dir"/*.sh; do
    [ -f "$tool" ] || continue
    found=$((found + 1))
    base=$(basename "$tool")
    rulehit=""
    for r in "$project_dir/.claude/rules"/*.md; do
      [ -f "$r" ] || continue
      # ⛔ FIX v5.2.2 — hier stand nur:  grep -q -- "$base" "$r"  … && break
      # Das nahm JEDE Nennung des Dateinamens und brach beim ERSTEN Treffer ab. Gemessen im
      # /mind-all-Lauf 2026-08-16: fuer mutation_guard.py schlug architecture.md an — eine
      # blosse Aufzaehlung in einer Versions-Historie, alphabetisch vor backup-usage.md — und
      # die Pruefung meldete PASS, obwohl die Companion-Rule das Tool gar nicht nennt.
      # Ein gruener Nachweis ueber einen Zufallstreffer ist kein Nachweis.
      # Jetzt: die AUFRUFFORM "tools/<name>" verlangen. Eine Nutzungs-Rule nennt den Aufrufpfad
      # ("python tools/backup_tools.py verify …"), eine Historie nennt nur den Namen.
      grep -q -- "tools/$base" "$r" 2>/dev/null || continue
      head -12 "$r" | grep -qi '^globs:' || continue    # ohne Globs triggert die Rule nie
      # KEIN break: alle Treffer sammeln, damit Mehrdeutigkeit sichtbar wird statt verdeckt.
      rulehit="${rulehit}${rulehit:+, }$(basename "$r")"
    done
    if [ -n "$rulehit" ]; then
      echo "  PASS  $base  ->  .claude/rules/$rulehit"
    else
      echo "  FAIL  $base  ->  KEINE glob-getriggerte Rule nennt 'tools/$base' (totes Tool)"
      rc=1
    fi
  done
  [ "$found" -eq 0 ] && echo "  Tool->Rule-Nachweis: tools/ vorhanden, aber keine .py/.sh darin"
  return "$rc"
}

# --- mind_heartbeat: Lebenszeichen der Hooks (NEU v5.2.1) ---
# WARUM: Wird das Cache-Verzeichnis der LAUFENDEN Plugin-Version geloescht (Marketplace-Update
# waehrend einer offenen Sitzung), zeigt CLAUDE_PLUGIN_ROOT ins Leere und ALLE Hooks sterben —
# lautlos, weil die Skriptdatei selbst weg ist. Gemessen 2026-08-16: Cache enthielt nur noch
# 5.2.0, waehrend laufende Sitzungen auf 5.0.0 zeigten.
# Ein Skript kann sich nicht selbst wiederbeleben. Der Tod SICHTBAR machen laesst sich aber:
# jeder Hook-Lauf stempelt hier Version, Zeit und Ereignis, die Skills lesen das Alter.
# Args: $1 = project_dir, $2 = Ereignis (optional, sonst Skriptname)
mind_heartbeat() {
  local project_dir="$1" event="${2:-$MIND_SCRIPT_NAME}"
  [ -n "$project_dir" ] && [ -d "$project_dir" ] || return 1
  local root="${CLAUDE_PLUGIN_ROOT:-}" ver="unbekannt"
  [ -n "$root" ] && ver=$(basename "$root")
  mkdir -p "$project_dir/.claude-mind" 2>/dev/null || return 1
  {
    echo "ts=$(date +%Y%m%d-%H%M%S)"
    echo "epoch=$(date +%s)"
    echo "event=$event"
    echo "version=$ver"
    echo "root=$root"
  } > "$project_dir/.claude-mind/hook-heartbeat" 2>/dev/null
}

# --- mind_hook_health: Sind die Hooks dieser Sitzung ueberhaupt am Leben? (NEU v5.2.1) ---
# Gegenstueck zu mind_heartbeat. Erkennt den stillen Hook-Tod nach einem Plugin-Update.
# ⚠ EHRLICHE GRENZE: Das hier ERKENNT, es verhindert nichts. Verhindert wird der Tod nur davon,
#   dass die Update-Prozedur das in Benutzung stehende Versionsverzeichnis stehen laesst.
# Gibt Zeilen fuer den Bericht aus; Rueckgabe 1, wenn etwas faul ist.
mind_hook_health() {
  local project_dir="$1" hb rc=0 now age epoch ver root
  hb="$project_dir/.claude-mind/hook-heartbeat"
  root="${CLAUDE_PLUGIN_ROOT:-}"

  if [ -z "$root" ]; then
    echo "Hook-Gesundheit: UNBEKANNT — CLAUDE_PLUGIN_ROOT ist nicht gesetzt"
    return 1
  fi
  if [ ! -d "$root" ]; then
    echo "Hook-Gesundheit: TOT — CLAUDE_PLUGIN_ROOT zeigt ins Leere: $root"
    echo "  Ursache: das Versionsverzeichnis wurde geloescht, waehrend diese Sitzung laeuft."
    echo "  Folge:   ALLE Hooks dieser Sitzung sind stumm (auch die Chat-Rettung vor Kompaktierung)."
    echo "  Abhilfe: Claude Code neu starten. Ein Skript kann sich nicht selbst wiederbeleben."
    return 1
  fi
  # Fehlt eine der Hook-Dateien, ist die Installation halb -> genauso toedlich, nur leiser
  local missing=""
  for f in pre-compact.sh prompt-submit.sh session-start.sh stop.sh; do
    [ -f "$root/hooks/$f" ] || missing="$missing $f"
  done
  [ -n "$missing" ] && { echo "Hook-Gesundheit: UNVOLLSTAENDIG — fehlende Skripte:$missing"; rc=1; }

  if [ ! -f "$hb" ]; then
    echo "Hook-Gesundheit: KEIN HERZSCHLAG — $hb fehlt (Hooks liefen in diesem Projekt noch nie)"
    return 1
  fi
  epoch=$(grep -m1 '^epoch='   "$hb" 2>/dev/null | cut -d= -f2-)
  ver=$(grep   -m1 '^version=' "$hb" 2>/dev/null | cut -d= -f2-)
  case "$epoch" in ''|*[!0-9]*) epoch=0 ;; esac
  now=$(date +%s); age=$(( (now - epoch) / 60 ))

  if [ "$ver" != "$(basename "$root")" ]; then
    echo "Hook-Gesundheit: VERSIONSSPRUNG — Herzschlag von '$ver', laufend ist '$(basename "$root")'"
    echo "  Das Plugin wurde waehrend der Sitzung aktualisiert. Nach einem Neustart passt es wieder."
    rc=1
  fi
  if [ "$age" -gt 1440 ]; then
    echo "Hook-Gesundheit: VERDAECHTIG — letzter Herzschlag vor ${age} min (>24 h)"
    rc=1
  fi
  [ "$rc" -eq 0 ] && echo "Hook-Gesundheit: OK (Herzschlag vor ${age} min, Version $ver)"
  return "$rc"
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
  local keep_count="${MIND_BACKUP_KEEP_COUNT:-3}"   # v5.2.1: 5 -> 3 (rclone-Pfad, s. backup-usage.md)
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
  # ⛔ FIX v5.2.1 — hier stand "| xargs rm -f 2>/dev/null".
  # xargs zerlegt an Leerzeichen; der Backup-Pfad enthaelt sie regelmaessig
  # ("Plugin - Entwicklung/Claude Mind Manager"). rm bekam Bruchstuecke, loeschte nichts,
  # und 2>/dev/null verschluckte jede Beschwerde. Ergebnis, gemessen 2026-08-16:
  # 9 Transkript-Kopien (32 MB) bei transcript_keep=3, 11 CLAUDE-Staende bei keep_count=5 —
  # in einem Ordner, den rclone nach Z: hochlaedt.
  # Es ist derselbe Fehler, der in mind_snapshot schon einmal gefunden wurde (M2-Fix v5.0.0):
  # eine stillschweigend fehlschlagende Aufraeumung sieht genauso aus wie eine, die nichts
  # zu tun hat. Deshalb jetzt ueberall _mind_rotate statt xargs.
  for prefix in MEMORY CLAUDE active-context; do
    _mind_rotate "$backup_dir/${prefix}-" ".md" "$keep_count"
  done
  # Transcripts: separate rotation (larger files, keep fewer).
  # Laeuft UNBEDINGT — auch wenn v5.0.0 keine neuen mehr anlegt, muessen Altlasten weg.
  _mind_rotate "$backup_dir/transcript-" ".jsonl" "$transcript_keep"

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
  # v5.2.1: eigener Regler — ein Snapshot ist deutlich groesser als eine Einzeldatei-Kopie
  local keep="${MIND_SNAPSHOT_KEEP_COUNT:-${MIND_BACKUP_KEEP_COUNT:-3}}"
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
  #
  # ⛔ FIX v5.2.1 — der Schutz war zu grob und hat das Netz ganz weggenommen.
  # Bis v5.2.0 wurde get_memory_dir aufgerufen und bei rc!=0 das Memory KOMPLETT ausgelassen.
  # Gemeldet 2026-08-16: "0 Treffer fuer memory/ im Manifest" — ausgerechnet bei mind-memory,
  # dem Skill, dessen einziger Zweck das Bearbeiten dieser Dateien ist. Der Fallback greift
  # naemlich auch dann, wenn schlicht der Slug nicht passt.
  # Jetzt: den Pfad DIREKT aus hash_project_dir bilden und nur nehmen, wenn genau DIESES
  # Verzeichnis existiert. Kein Fallback = keine Fremd-Gefahr, und gesichert wird immer dann,
  # wenn es etwas zu sichern gibt.
  local mem_slug
  mem_slug=$(hash_project_dir "$project_dir" 2>/dev/null)
  memory_dir=""
  if [ -n "$mem_slug" ] && [ "${mem_slug#ERROR}" = "$mem_slug" ]; then
    if [ -d "$HOME/.claude/projects/$mem_slug/memory" ]; then
      memory_dir="$HOME/.claude/projects/$mem_slug/memory"
    else
      mind_log INFO "mind_snapshot: kein Memory-Verzeichnis fuer Slug '$mem_slug' (nichts zu sichern)"
    fi
  else
    mind_log WARN "mind_snapshot: Slug nicht bestimmbar (cygpath?) — Memory NICHT gesichert"
    echo "WARN: Projekt-Slug nicht bestimmbar — Memory aus diesem Snapshot ausgenommen" >&2
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

  # 3b) ZUSAETZLICHE Projektdateien (NEU v5.2.1, Befund 3)
  # Custom-Context wie INDEX.md, PROTOKOLL.md oder recherche/ wird von mind-update
  # nachweislich EDITIERT, lag aber ausserhalb des Netzes. Der aufrufende Skill uebergibt
  # die Pfade, die er anzufassen gedenkt — als Argumente ab $3 oder in MIND_SNAPSHOT_EXTRA
  # (eine Zeile je Pfad).
  # ⛔ Nur Pfade INNERHALB des Projekts werden genommen. Ein Snapshot, der beliebige
  #    Systempfade einsammelt, waere beim Restore eine Waffe statt eines Netzes.
  local extras="" e rel
  if [ "$#" -gt 2 ]; then
    local a
    for a in "${@:3}"; do [ -n "$a" ] && extras="${extras}${a}
"; done
  fi
  [ -n "${MIND_SNAPSHOT_EXTRA:-}" ] && extras="${extras}${MIND_SNAPSHOT_EXTRA}
"
  if [ -n "$extras" ]; then
    while IFS= read -r e; do
      [ -z "$e" ] && continue
      e="${e%/}"                     # Schraegstrich am Ende stoert den Mustervergleich
      [ -e "$e" ] || continue
      case "$e" in
        "$project_dir"/*) rel="${e#"$project_dir"/}" ;;
        *) mind_log WARN "mind_snapshot: Extra-Pfad ausserhalb des Projekts uebersprungen: $e"; continue ;;
      esac
      # v5.2.1: schon durch 1)-3) abgedeckt? Dann NICHT nochmal. Gemessen 2026-08-16 lagen
      # CLAUDE.md und project/CLAUDE.md byte-gleich im selben Snapshot — doppelter Platz und
      # beim Restore zwei Quellen fuer dieselbe Datei, was die Wiederherstellung mehrdeutig macht.
      case "$e" in
        "$project_dir/CLAUDE.md"|"$project_dir/.claude/CLAUDE.md"|"$project_dir/.claude/rules"|"$project_dir/.claude/rules"/*)
          mind_log INFO "mind_snapshot: Extra-Pfad bereits abgedeckt, uebersprungen: $rel"
          continue ;;
      esac
      mkdir -p "$snap/project/$(dirname "$rel")" 2>/dev/null
      if [ -d "$e" ]; then
        cp -r "$e" "$snap/project/$(dirname "$rel")/" 2>/dev/null && count=$((count+1))
      else
        cp "$e" "$snap/project/$rel" 2>/dev/null && count=$((count+1))
      fi
    done <<EOF
$extras
EOF
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
  #
  # v5.2.1: aber NICHT bei jedem Lauf. Gemessen 2026-08-16: die globalen Dateien waren
  # 73 % eines Snapshots (124 KB von 171 KB) und lagen bei 3 vorgehaltenen Staenden dreimal
  # byte-gleich da — auch bei Laeufen, die sie gar nicht erreichen koennen.
  # ⛔ Die Auswahl faellt FAIL-SAFE aus: nur ausdruecklich als lokal bekannte Labels lassen
  #    global weg. Jedes unbekannte Label sichert MIT — ein zu grosser Snapshot kostet Platz,
  #    ein zu kleiner ist ein Loch. Wer einem Skill globale Schreibrechte gibt und dieses
  #    case vergisst, faellt damit auf die sichere Seite.
  local want_global
  case "$label" in
    pre-memory|pre-files) want_global="nein" ;;
    *)                    want_global="ja" ;;
  esac
  [ "${MIND_SNAPSHOT_GLOBAL:-}" = "immer" ] && want_global="ja"

  if [ "$want_global" = "ja" ]; then
    if [ -f "$HOME/.claude/CLAUDE.md" ]; then
      mkdir -p "$snap/global"; cp "$HOME/.claude/CLAUDE.md" "$snap/global/CLAUDE.md" 2>/dev/null && count=$((count+1))
    fi
    if [ -d "$HOME/.claude/rules" ]; then
      mkdir -p "$snap/global/rules"
      for f in "$HOME/.claude/rules"/*.md; do
        [ -f "$f" ] && { cp "$f" "$snap/global/rules/" 2>/dev/null && count=$((count+1)); }
      done
    fi
  else
    mind_log INFO "mind_snapshot: global ausgelassen (label=$label kann ~/.claude nicht schreiben)"
  fi

  # 5) MANIFEST mit SHA-256 (Grundlage fuer Restore-Verifikation)
  {
    echo "# mind_snapshot MANIFEST"
    echo "# label=$label  ts=$ts  project=$project_dir  files=$count"
    # Ausgelassenes AUSWEISEN — sonst raetselt beim Restore jemand, wo global geblieben ist
    [ "$want_global" = "ja" ] || echo "# global=AUSGELASSEN (label=$label erreicht ~/.claude nicht; MIND_SNAPSHOT_GLOBAL=immer erzwingt es)"
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
