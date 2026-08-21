#!/bin/bash
# Claude Mind Manager v3.0 — Shared Hook Functions (lib.sh)
# Sourced by pre-compact.sh (the only remaining hook).
# Usage: source "$(dirname "$0")/lib.sh"

# --- Constants ---
MIND_LOG_FILE="${MIND_LOG_FILE:-/tmp/mind-manager.log}"   # v5.7.0: war fest verdrahtet
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

# --- mind_append: anhaengen, OHNE die Zeilenenden der Zieldatei zu zerstoeren (NEU v5.7.0) ---
#
# ⛔ WARUM ES DIESE FUNKTION GIBT. lib.sh hatte bis v5.7.0 KEINE Schreibhilfe — mind_log,
#    create_backup und mind_snapshot bauen ihr Schreiben jeweils selbst. Ein blankes '>>' an
#    eine CRLF-Datei schreibt LF und macht sie GEMISCHT. Genau diese Fehlerklasse steht in
#    beiden listeverbesserungen.md rund 18-mal: Anker "0x gefunden", Falsch-Rot, abgebrochene
#    Skripte. Am 21.08.2026 kostete sie erneut zwei Anlaeufe an hooks.md (130 CRLF / 25 LF).
#
# ⚠ Der Mehrheitsentscheid laeuft ueber ROHE BYTES. 'file -b' meldet bei gemischten Dateien
#    nur die Mehrheit und taugt als Instrument nicht (globale CLAUDE.md, 18.08.2026).
#
# Args: $1 = Zieldatei (wird samt Verzeichnis angelegt)  ·  Text kommt auf stdin
# Rueckgabe: 0 = geschrieben · 1 = kein Ziel angegeben / nicht anlegbar
mind_append() {
  local ziel="$1" cr lf_n
  [ -n "$ziel" ] || return 1
  mkdir -p "$(dirname "$ziel")" 2>/dev/null
  [ -f "$ziel" ] || : > "$ziel" 2>/dev/null || return 1

  # Rohe Bytes zaehlen. $'\r' waere hier FALSCH: in Git Bash kommt es nicht als
  # Wagenruecklauf an — genau dieser Fehlgriff meldete am 18.08.2026 „CRLF in allen Hooks“
  # (byte-genau: 0). Deshalb printf, das die Sequenz nachweislich uebersetzt.
  cr=$(tr -cd "$(printf '\r')" < "$ziel" 2>/dev/null | wc -c); cr=${cr// /}
  lf_n=$(tr -cd "$(printf '\n')" < "$ziel" 2>/dev/null | wc -c); lf_n=${lf_n// /}
  case "$cr" in ''|*[!0-9]*) cr=0 ;; esac
  case "$lf_n" in ''|*[!0-9]*) lf_n=0 ;; esac

  # Mehrheit CRLF? Doppelt gewichtet, damit einzelne Streuner nicht kippen.
  if [ "$cr" -gt 0 ] && [ $(( cr * 2 )) -gt "$lf_n" ]; then
    sed "s/$/$(printf '\r')/" >> "$ziel"
  else
    cat >> "$ziel"
  fi
}

# --- mind_kontext_tokens: wie voll ist der Kontext GERADE? (NEU v5.7.0) ---
#
# Liest die letzte Zeile des Transkripts, die ein 'usage'-Objekt traegt, und summiert
# input_tokens + cache_creation_input_tokens + cache_read_input_tokens.
#
# ⛔ references/token-budget-formulas.md behauptete bis v5.7.0 "No Programmatic Token Access"
#    und "token counts are undocumented". BEIDES WIDERLEGT, gemessen 21.08.2026: 2 062 von
#    5 044 Transkriptzeilen tragen 'usage', die Summe der letzten ergab 401 533 — plausibel
#    und mit dem Verlauf konsistent.
#
# ⚠ KEINE Zahl ist KEINE Null. Ist nichts lesbar, gibt die Funktion NICHTS aus und
#    Rueckgabewert 1 zurueck. Wer hier 0 zurueckgaebe, meldete "Kontext leer" statt "unbekannt"
#    — und der Ausloeser wuerde nie feuern, ohne dass es auffiele.
#
# Args: $1 = Transkript-Pfad (JSONL)
# Ausgabe: die Tokenzahl auf stdout · Rueckgabe: 0 = gemessen · 1 = keine Aussage moeglich
mind_kontext_tokens() {
  local tp="$1" py out
  [ -n "$tp" ] && [ -f "$tp" ] || return 1
  py=$(command -v python3 2>/dev/null || command -v python 2>/dev/null) || return 1
  [ -n "$py" ] || return 1
  out=$("$py" -c '
import json, sys
letzte = None
try:
    with open(sys.argv[1], "rb") as f:
        for roh in f:
            try: e = json.loads(roh.decode("utf-8", "replace"))
            except Exception: continue
            u = (e.get("message") or {}).get("usage") or e.get("usage")
            if isinstance(u, dict) and u.get("input_tokens") is not None:
                letzte = u
except Exception:
    sys.exit(1)
if not letzte: sys.exit(1)
print(sum(int(letzte.get(k) or 0) for k in
          ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")))
' "$tp" 2>/dev/null) || return 1
  case "$out" in ''|*[!0-9]*) return 1 ;; esac
  echo "$out"
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
  # ⛔ v5.7.1, Befund aus dem Zustellplan-Lauf vom 21.08.2026:
  #    Diese Pruefung sah bis dahin NUR das Verzeichnis tools/. Ein Projekt, das seine
  #    Werkzeuge im Wurzelverzeichnis liegen hat, bekam einen LEEREN Nachweis — und der
  #    Lauf meldete trotzdem "OK". Ein leerer Nachweis ist kein bestandener Nachweis.
  #    Deshalb zaehlt jetzt auch, was im Wurzelverzeichnis liegt und in CLAUDE.md oder
  #    einer Rule namentlich genannt wird.
  local _wurzel_py
  _wurzel_py=$(ls "$1"/*.py 2>/dev/null | head -20)
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

  # ⛔ JEDES Nicht-Alphanumerische wird zu '-' (v5.7.0). Vorher: nur [\: ()].
  #    GEMESSEN 21.08.2026 gegen 117 reale Verzeichnisse und 24 reale Claude-Code-Ordner:
  #    alte Regel 0 Treffer, diese Regel 18, Verluste 0.
  #    Verloren gingen konkret: '&' (Entwicklung&Forschung -> get_memory_dir fiel in den
  #    Fallback, Warnung bei JEDEM Lauf), '_' (_claude_vm -> -claude-vm) und '.'
  #    (.claude-worktrees -> -claude-worktrees).
  #    Gegenprobe liegt als references/slug_regression.py bei und MUSS 18/0 melden.
  echo "$win_path" | sed 's|[^A-Za-z0-9]|-|g' | sed 's|^-*||'
}

# --- _resolve_memory_dir: die EINZIGE Stelle, die den Memory-Pfad bildet (NEU v6) ---
#
# ⛔ WARUM ES DIESE FUNKTION GIBT. Der Pfad wurde bis v5.4.1 an VIER Stellen unabhaengig
#    zusammengesetzt: get_memory_dir (2x), create_backup und mind_snapshot. Wer nur eine
#    davon erweitert, laesst die anderen auf den alten Pfad zeigen — der Skill faende das
#    verlegte Verzeichnis, die SICHERUNG aber sicherte weiter das Falsche, ohne Fehler.
#    Gefunden bei der Phase-4-Pruefung des v6-Plans (Pruefung 4O, "geteilte Ressource").
#
# Drei Wege koennen den Ort verlegen, keinen kannte hash_project_dir():
#   1. CLAUDE_CODE_REMOTE_MEMORY_DIR  (Umgebungsvariable, im Bundle v2.1.81 belegt)
#   2. autoMemoryDirectory            (settings.json, jeder Scope; ab v2.1.198 dokumentiert)
#   3. Worktrees                      (Slug aus dem GIT-REPO, nicht aus dem Arbeitsverzeichnis)
#
# ⛔ REIHENFOLGE IST SICHERHEIT, NICHT GESCHMACK: Der bisherige Pfad wird ZUERST geprueft.
#    Nur wenn er NICHT existiert, kommen die neuen Wege dran. Sonst wuerde die
#    Worktree-Ableitung (Repo-Wurzel statt cwd) bei jedem Projekt, das in einem Unterordner
#    eines Repos liegt, auf einen ANDEREN Slug zeigen — und die vorhandenen Erinnerungen
#    waeren von einem Tag auf den anderen unauffindbar. Additiv, nie ersetzend.
#
# Args:    $1 = project_dir (default $(pwd))
# Ausgabe: der Pfad
# Rueckgabe: 0 = echtes Verzeichnis gefunden · 1 = nichts gefunden, Pfad ist nur geraten
_resolve_memory_dir() {
  local project_dir="${1:-$(pwd)}"
  local slug cand root common

  slug=$(hash_project_dir "$project_dir")

  # (0) Der bisherige Weg zuerst — bricht garantiert nichts.
  cand="$HOME/.claude/projects/$slug/memory"
  [ -d "$cand" ] && { echo "$cand"; return 0; }

  # (1) CLAUDE_CODE_REMOTE_MEMORY_DIR
  if [ -n "$CLAUDE_CODE_REMOTE_MEMORY_DIR" ]; then
    cand="$CLAUDE_CODE_REMOTE_MEMORY_DIR/projects/$slug/memory"
    [ -d "$cand" ] && { mind_log INFO "memory-dir via CLAUDE_CODE_REMOTE_MEMORY_DIR: $cand"; echo "$cand"; return 0; }
  fi

  # (2) autoMemoryDirectory aus settings.json — Projekt-Scope vor User-Scope.
  # ⚠ UNGEPRUEFT, ob der Schluessel das WURZEL- oder das Projektverzeichnis meint. Hier als
  #   fertiger Memory-Pfad behandelt; erweist sich das als falsch, ist es EINE Zeile.
  if command -v jq >/dev/null 2>&1; then
    local s v
    for s in "$project_dir/.claude/settings.local.json" "$project_dir/.claude/settings.json" \
             "$HOME/.claude/settings.json"; do
      [ -f "$s" ] || continue
      v=$(jq -r '.autoMemoryDirectory // empty' "$s" 2>/dev/null)
      [ -z "$v" ] && continue
      case "$v" in "~/"*) v="$HOME/${v#\~/}" ;; esac
      [ -d "$v" ] && { mind_log INFO "memory-dir via autoMemoryDirectory ($s): $v"; echo "$v"; return 0; }
    done
  fi

  # (3) Worktree: Slug aus der Repo-Wurzel. --git-common-dir zeigt beim Worktree auf das
  #     HAUPT-.git; dessen Elternverzeichnis ist die Wurzel, aus der Claude Code den Pfad
  #     ableitet ("derived from the git repository").
  if command -v git >/dev/null 2>&1; then
    common=$(git -C "$project_dir" rev-parse --git-common-dir 2>/dev/null)
    if [ -n "$common" ]; then
      case "$common" in /*|[A-Za-z]:*) : ;; *) common="$project_dir/$common" ;; esac
      root=$(dirname "$common")
      if [ "$root" != "$project_dir" ]; then
        cand="$HOME/.claude/projects/$(hash_project_dir "$root")/memory"
        [ -d "$cand" ] && { mind_log INFO "memory-dir via Git-Repo-Wurzel ($root): $cand"; echo "$cand"; return 0; }
      fi
    fi
  fi

  # Nichts gefunden — Pfad zurueckgeben, aber ehrlich mit Rueckgabewert 1.
  echo "$HOME/.claude/projects/$slug/memory"
  return 1
}

# --- get_memory_dir: Project-spezifisches MEMORY-Verzeichnis (v3.2.2 NEU) ---
# Mit Fallback auf neuestes Projekt-Dir (mtime) bei Slug-Mismatch
# Args: optional $1 = project_dir (default $(pwd))
# Returns: 0 wenn primary dir gefunden, 1 wenn Fallback verwendet wurde (H2-Fix)
get_memory_dir() {
  local hash resolved
  hash=$(hash_project_dir "$@")

  # v6: alle Wege ueber die gemeinsame Funktion. Findet sie ein echtes Verzeichnis,
  # sind wir fertig — sie deckt auch den frueheren Direkt-Pfad ab (Weg 0).
  if resolved=$(_resolve_memory_dir "$@") && [ -n "$resolved" ]; then
    echo "$resolved"
    return 0
  fi

  # Ab hier: nichts gefunden. Fallback auf das neueste Projekt-Verzeichnis — unveraendert
  # seit v3.2.2, samt Rueckgabewert 1 und stderr-Warnung.
  local memory_dir projects_dir
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
  # v6: ueber die gemeinsame Aufloesung, nicht mehr selbst zusammengesetzt. Sonst sichert
  # create_backup weiter den alten Pfad, waehrend der Skill schon am neuen arbeitet.
  local memory_dir
  memory_dir=$(_resolve_memory_dir "$project_dir" 2>/dev/null) || memory_dir=""

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
  # v6: ueber _resolve_memory_dir. Deren Rueckgabewert 0 heisst "echtes Verzeichnis
  # gefunden" — genau die Bedingung, die hier seit v5.2.1 gilt. Der Fremd-Projekt-Schutz
  # bleibt damit erhalten: die Funktion faellt NIE auf ein fremdes Projekt zurueck.
  local mem_slug
  mem_slug=$(hash_project_dir "$project_dir" 2>/dev/null)
  memory_dir=""
  if [ -n "$mem_slug" ] && [ "${mem_slug#ERROR}" = "$mem_slug" ]; then
    if memory_dir=$(_resolve_memory_dir "$project_dir" 2>/dev/null); then
      : # gefunden
    else
      memory_dir=""
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

# --- mind_debug_top: was ist hier schon einmal schiefgegangen? (NEU v5.7.1) ---
#
# ⛔ WARUM ES DIESE FUNKTION GIBT — belegt am eigenen Fehler, 21.08.2026.
#    Der Debug-Ordner hatte bis dahin nur einen SCHREIB-Anlass. Er hatte die Klasse
#    "Instrumentenkontrolle verglich nur Befund-ANZAHLEN" seit dem 20.08. sauber
#    aufgezeichnet — und ich habe exakt denselben Fehler am naechsten Tag wiederholt,
#    weil niemand vor der Arbeit hineinsieht. Sichtbarkeit ohne Lese-Anlass ist wirkungslos.
#
# Args: $1 = wie viele Klassen (Vorgabe 3)
# Ausgabe: je eine Zeile, oder NICHTS wenn MIND_DEBUG_DIR fehlt / es keine Wiederholung gibt
mind_debug_top() {
  local n="${1:-3}" dir="${MIND_DEBUG_DIR:-}" py
  [ -n "$dir" ] && [ -f "$dir/index.jsonl" ] || return 0
  py=$(command -v python3 2>/dev/null || command -v python 2>/dev/null) || return 0
  [ -n "$py" ] || return 0
  "$py" -c '
import json, sys
from collections import Counter
c, bsp = Counter(), {}
try:
    for roh in open(sys.argv[1], "rb"):
        try: e = json.loads(roh.decode("utf-8", "replace"))
        except Exception: continue
        k = e.get("klasse")
        if k:
            c[k] += 1
            bsp.setdefault(k, e.get("kurz", ""))
except Exception:
    sys.exit(0)
top = [(k, v) for k, v in c.most_common(int(sys.argv[2])) if v >= 2]
if not top: sys.exit(0)
print("Schon dagewesen — die haeufigsten Wiederholungen aus dem Debug-Ordner:")
for k, v in top:
    print("  %-26s %dx   z.B. %s" % (k, v, bsp.get(k, "")[:88]))
print("  -> vor dem Bauen einer Pruefung hier hineinsehen, nicht danach.")
' "$dir/index.jsonl" "$n" 2>/dev/null
}


# --- mind_scan_poisoning: Kontext-Dateien auf Vergiftung pruefen (NEU v5.5.0) ---
#
# Der ungeprueft bei jedem Start geladene Speicher faellt unter OWASP ASI06
# "Memory and Context Poisoning" (Agentic Top 10 2026). Anders als klassische
# Prompt-Injection UEBERDAUERT die Vergiftung Sitzungen — sie wirkt Tage nach dem Schreiben.
#
# ⛔ WARUM HIER UND NICHT IM SKILL: dieselbe Bedrohung betrifft .claude/rules/*.md und
#    CLAUDE.md genauso wie memory/*.md. Einmal bauen, dreifach nutzen — sonst muss die
#    Logik beim naechsten Skill dupliziert werden.
#
# ⛔ MELDET NUR, LOESCHT NIE. Ein Fehltreffer, der autonom Inhalt entfernt, waere
#    schlimmer als der Fund.
#
# Args:    $1 = Datei
# Ausgabe: je Fund eine Zeile "BEFUND|<art>|<zeile>|<detail>" bzw. "HINWEIS|..."
# Rueckgabe: immer 0 — der AUFRUFER wertet die Zeilen aus. Ein Rueckgabewert waere hier
#            irrefuehrend, weil die Unterpruefungen in Subshells laufen (Pipes) und ihre
#            Zaehler nicht zurueckgeben koennen. Lieber ehrlich als scheingenau.
# --- mind_debug_write: Befunde eines /mind-all-Laufs ZENTRAL melden (NEU v5.7.0) ---
#
# WOZU. Die Befunde jedes Laufs landeten bisher nur projektlokal in listeverbesserungen.md.
# Gemessen: 6 Projekte, 28 Laeufe, verstreut. Dass ein Fehler zum DRITTEN Mal auftritt, sah
# niemand — und genau das ist passiert: derselbe classify_path()-Nachbau, dreimal in Folge.
#
# WOHIN. $MIND_DEBUG_DIR/laeufe/<ts>_<slug>.md  (der Bericht, unveraendert wie er ankommt)
#        $MIND_DEBUG_DIR/index.jsonl            (eine Zeile je Befund, maschinenlesbar)
#        $MIND_DEBUG_DIR/BEFUNDE.md             (die Auswertung, neu erzeugt)
#
# ⛔ VORGABE IST AUS. Ohne gesetztes MIND_DEBUG_DIR passiert NICHTS und die Funktion gibt 0
#    zurueck. Das Plugin setzt die Variable NIE selbst — claude-mem (#2836) hat mit einer
#    still gesetzten Umgebungsvariablen 75 Erinnerungen unsichtbar gemacht.
#
# Args: $1 = Projektpfad  ·  $2 = Ausloeser  ·  $3 = Bericht (.md)  ·  $4 = Befunde (.jsonl)
# Rueckgabe: 0 = geschrieben oder bewusst aus  ·  1 = Ziel nicht schreibbar
mind_debug_write() {
  local proj="$1" ausloeser="$2" bericht="$3" befunde="$4"
  local dir="${MIND_DEBUG_DIR:-}"
  [ -n "$dir" ] || return 0

  local slug ts py
  slug=$(hash_project_dir "$proj")
  ts=$(date '+%Y-%m-%d_%H%M')

  mkdir -p "$dir/laeufe" 2>/dev/null || { mind_log WARN "Debug-Ordner nicht anlegbar: $dir"; return 1; }

  if [ -f "$bericht" ]; then
    cp "$bericht" "$dir/laeufe/${ts}_${slug}.md" 2>/dev/null \
      || { mind_log WARN "Debug-Bericht nicht schreibbar"; return 1; }
  fi

  # index.jsonl: eine Zeile je Befund. Anhaengen ueber mind_append, damit die Zeilenenden
  # der bestehenden Datei erhalten bleiben.
  if [ -f "$befunde" ] && [ -s "$befunde" ]; then
    mind_append "$dir/index.jsonl" < "$befunde"
  fi

  # Auswertung neu erzeugen — sie ist der eigentliche Zweck.
  py=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)
  if [ -n "$py" ] && [ -f "$CLAUDE_PLUGIN_ROOT/references/debug_auswertung.py" ]; then
    "$py" "$CLAUDE_PLUGIN_ROOT/references/debug_auswertung.py" "$dir" >/dev/null 2>&1 \
      || mind_log WARN "debug_auswertung.py fehlgeschlagen (Bericht liegt trotzdem)"
  fi
  mind_log "Debug zentral gemeldet: $dir/laeufe/${ts}_${slug}.md (Ausloeser: $ausloeser)"
}


mind_scan_poisoning() {
  local f="$1"

  # ⛔ v5.7.0: Verzeichnisse werden rekursiv geprueft. Vorher stand hier
  #    "[ -f "$f" ] || return 0" — ein Aufruf mit einem VERZEICHNIS gab damit still 0 zurueck.
  #    Am 21.08.2026 wurde auf genau diesem Weg "0 Befunde" gemeldet, ohne dass eine einzige
  #    Datei angesehen worden waere; aufgefallen ist es nur, weil die Negativkontrolle danach
  #    ebenfalls schwieg. Eine Pruefung, die nicht scheitern KANN, ist keine Pruefung
  #    (messung-vor-glauben.md §1).
  if [ -d "$f" ]; then
    find "$f" -type f -name '*.md' 2>/dev/null | while IFS= read -r _mp; do
      mind_scan_poisoning "$_mp"
    done
    return 0
  fi
  if [ ! -f "$f" ]; then
    echo "HINWEIS|nicht-lesbar|0|$f existiert nicht — KEINE Aussage, nicht ‘unauffaellig’"
    return 1
  fi

  # 1) Unsichtbare Zeichen — Zero-Width, Bidi-Steuerung, Tag-Zeichen.
  #    Das ist der einzige Fund, der praktisch nie ein Fehlalarm ist: solche Zeichen
  #    haben in einer Notizdatei keinen legitimen Zweck.
  if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
    local PY; PY=$(command -v python3 || command -v python)
    "$PY" - "$f" <<'PYEOF'
import io, sys
p = sys.argv[1]
UNSICHTBAR = set(range(0x200B, 0x2010)) | {0xFEFF} | set(range(0x202A, 0x202F)) \
           | set(range(0x2066, 0x206A)) | set(range(0xE0000, 0xE0080))
try:
    zeilen = open(p, encoding="utf-8", errors="replace").read().split("\n")
except Exception:
    sys.exit(0)
for i, z in enumerate(zeilen, 1):
    treffer = sorted({ord(c) for c in z if ord(c) in UNSICHTBAR})
    if treffer:
        print("BEFUND|unsichtbares-zeichen|%d|%s" % (i, " ".join("U+%04X" % t for t in treffer)))
PYEOF
  fi

  # 2) Zugangsdaten — echter Befund, gleiche Muster wie in mind-claudemd v5.4.0
  grep -nE 'sk-ant-|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|password[[:space:]]*=' "$f" 2>/dev/null \
    | while IFS=: read -r ln _; do echo "BEFUND|zugangsdaten|$ln|Muster erkannt"; done

  # 3) Abfluss-Versuche — Netzwerkaufrufe in einer Notizdatei sind erklaerungsbeduerftig
  grep -nE '(curl|wget)[[:space:]]+[^|]*https?://|data:[a-z/]+;base64,' "$f" 2>/dev/null \
    | while IFS=: read -r ln _; do echo "BEFUND|abfluss|$ln|Netzwerk-/Daten-URL"; done

  # 4) Anweisungs-Formulierungen — NUR HINWEIS.
  # ⛔ Formulierungen wie "NIEMALS" oder "ab jetzt gilt" sind in anweisungsreichen
  #    deutschen Regeldateien ALLTAG. Als Befund waere eine Fehlalarm-Flut der
  #    wahrscheinlichste Fehlschlag dieses ganzen Checks — deshalb bewusst herabgestuft.
  grep -niE '^[[:space:]]*(ignoriere|vergiss|ab jetzt gilt|system:|disregard|ignore (all|previous))' "$f" 2>/dev/null \
    | while IFS=: read -r ln _; do echo "HINWEIS|anweisungsform|$ln|pruefen, ob beabsichtigt"; done

  return 0
}
