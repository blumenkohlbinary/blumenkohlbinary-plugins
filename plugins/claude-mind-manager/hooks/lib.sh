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
  # ⛔ v5.7.3 — der zweite Anlauf. Befund aus dem Zustellplan-Lauf vom 21.08.2026:
  #    Diese Pruefung sah NUR das Verzeichnis tools/. Ein Projekt mit Werkzeugen im
  #    Wurzelverzeichnis bekam einen LEEREN Nachweis, und der Lauf meldete trotzdem "OK".
  #
  #    v5.7.1 hat das ANGEBLICH behoben: es sammelte `_wurzel_py` — und benutzte die
  #    Variable nie. Zwei Zeilen darunter stieg die Funktion bei fehlendem tools/ mit
  #    `return 0` aus. Der Kommentar behauptete den Fix, der Code hatte ihn nicht.
  #    Das war SCHLECHTER als vorher: vorher log die Pruefung nicht ueber sich selbst.
  #
  #    Zwei Regeln daraus, die hier verdrahtet sind statt aufgeschrieben:
  #    1. Kein frueher `return 0`, solange noch Kandidaten offen sind.
  #    2. Ein Werkzeug im WURZELVERZEICHNIS zaehlt nur, wenn CLAUDE.md es namentlich
  #       nennt. Sonst waeren setup.py, conftest.py und jedes Wegwerfskript ein Befund.
  local project_dir="$1" rc=0 tool base r rulehit found=0 kandidaten="" muster
  local tools_dir="$project_dir/tools"

  for tool in "$tools_dir"/*.py "$tools_dir"/*.sh; do
    [ -f "$tool" ] && kandidaten="${kandidaten}${tool}"$'\n'
  done
  # Wurzelverzeichnis: nur was CLAUDE.md ausdruecklich nennt = ein dokumentiertes Werkzeug.
  if [ -f "$project_dir/CLAUDE.md" ]; then
    for tool in "$project_dir"/*.py "$project_dir"/*.sh; do
      [ -f "$tool" ] || continue
      base=$(basename "$tool")
      grep -q -- "$base" "$project_dir/CLAUDE.md" 2>/dev/null \
        && kandidaten="${kandidaten}${tool}"$'\n'
    done

    # ⛔ v5.21.2 — DRITTER Ort, und zwar der allgemeine Fall.
    #    Bis hierher sah die Pruefung NUR `tools/` und die Projektwurzel.
    #    Gemessen 26.08.2026: drei Werkzeuge unter `Learnings/` waren unsichtbar,
    #    zwei davon standen in KEINER Context-Datei — und die Pruefung meldete
    #    `PASS`. Das liest sich wie "alle Werkzeuge erreichbar" und war es nicht.
    #
    #    ⭐ Keine dritte Sonderregel, sondern die VERALLGEMEINERUNG der zweiten:
    #       im Wurzelverzeichnis zaehlt, was CLAUDE.md namentlich nennt — jetzt
    #       gilt dasselbe fuer jeden Unterordner. Nennt CLAUDE.md die AUFRUFFORM
    #       `Learnings/zaehl_gate.py`, ist es ein dokumentiertes Werkzeug.
    _rel=$(grep -oE '[A-Za-z0-9_.@+-]+/[A-Za-z0-9_.@+-]+\.(py|sh)' \
             "$project_dir/CLAUDE.md" 2>/dev/null | sort -u)
    for r in $_rel; do
      case "$r" in tools/*) continue ;; esac      # schon oben eingesammelt
      [ -f "$project_dir/$r" ] || continue
      case "$kandidaten" in
        *"$project_dir/$r"$'\n'*) ;;
        *) kandidaten="${kandidaten}${project_dir}/${r}"$'\n' ;;
      esac
    done
  fi

  if [ -z "$kandidaten" ]; then
    if [ -d "$tools_dir" ]; then
      echo "  Tool->Rule-Nachweis: tools/ vorhanden, aber keine .py/.sh darin"
    else
      echo "  Tool->Rule-Nachweis: kein tools/ und kein in CLAUDE.md genanntes Werkzeug im Wurzelverzeichnis"
    fi
    return 0
  fi

  # ⚠ Sagen, WO gesucht wurde. Ein `PASS` ohne diese Angabe behauptet mehr, als
  #   die Pruefung weiss — genau der Eindruck, der den Befund vom 26.08. verdeckt hat.
  echo "  Tool->Rule-Nachweis geprueft in: tools/ · Projektwurzel · jede in CLAUDE.md genannte Aufrufform (<ordner>/<datei>.py|.sh)"

  printf '%s' "$kandidaten" | while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    base=$(basename "$tool")
    case "$tool" in
      "$project_dir"/*/*)
        # Aufrufform verlangen — eine Nutzungs-Rule nennt den PFAD, eine Historie nur den Namen.
        # ⭐ v5.21.2: gilt fuer JEDEN Unterordner, nicht mehr nur fuer tools/.
        #    Fuer `$project_dir/tools/x.py` ergibt das `tools/x.py` — identisch zur
        #    frueheren Hartkodierung. Eine Sonderregel weniger, gleiche Wirkung.
        muster="${tool#$project_dir/}" ;;
      *)
        # Im Wurzelverzeichnis gibt es keinen Pfad-Praefix. Ersatz: ein Aufrufwort davor.
        muster="\(python3\?\|bash\|sh\|\./\)[[:space:]]*$base" ;;
    esac
    rulehit=""
    for r in "$project_dir/.claude/rules"/*.md; do
      [ -f "$r" ] || continue
      grep -q -- "$muster" "$r" 2>/dev/null || continue
      head -12 "$r" | grep -qi '^globs:' || continue    # ohne Globs triggert die Rule nie
      # KEIN break: alle Treffer sammeln, damit Mehrdeutigkeit sichtbar wird statt verdeckt.
      rulehit="${rulehit}${rulehit:+, }$(basename "$r")"
    done
    if [ -n "$rulehit" ]; then
      echo "  PASS  $base  ->  .claude/rules/$rulehit"
      # ⛔ v5.21.2 (B6) — PASS sagt: die Rule ist ERREICHBAR. Nicht: sie stimmt noch.
      #    Gemessen 26.08.2026: `backup-usage.md` beschrieb `rollback.py` im Stand
      #    VOR dem Fix desselben Tages, und die Pruefung meldete durchgehend PASS.
      #    Eine Rule, die das Werkzeug von gestern beschreibt, ist von einer
      #    richtigen nicht zu unterscheiden.
      #
      #    ⚠ Aktualitaet ist nicht mechanisch entscheidbar. Das Aenderungsdatum ist
      #      ein VERDACHT, kein Beweis: ein Werkzeug kann sich aendern, ohne dass
      #      seine Nutzung sich aendert. Deshalb PRUEFEN statt FAIL und KEIN
      #      Einfluss auf den Rueckgabewert — sonst entsteht die naechste Pruefung,
      #      der man gewohnheitsmaessig nicht mehr glaubt.
      for r in $(printf '%s' "$rulehit" | tr ',' ' '); do
        _rp="$project_dir/.claude/rules/$r"
        [ -f "$_rp" ] || continue
        if [ "$tool" -nt "$_rp" ]; then
          echo "        PRUEFEN: $base ist juenger als $r — beschreibt die Rule noch den heutigen Stand? (Verdacht, kein Befund)"
        fi
      done
    else
      echo "  FAIL  $base  ->  KEINE glob-getriggerte Rule ruft '$base' auf (totes Tool)"
      echo "__MIND_TOOLRULE_FAIL__" >> "${TMPDIR:-/tmp}/.mind_toolrule_$$"
    fi
  done

  # ⛔ Die Schleife laeuft in einer Subshell (Pipe) — `rc=1` darin waere verloren.
  #    Genau daran ist schon einmal ein Rueckgabewert stillschweigend verschwunden.
  if [ -f "${TMPDIR:-/tmp}/.mind_toolrule_$$" ]; then
    rc=1; rm -f "${TMPDIR:-/tmp}/.mind_toolrule_$$"
  fi
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
    # v5.21.0: REKURSIV. Vorher `*.md` -- flach. Ein Unterordner (etwa ein
    # `archive/`) war damit fuer die LESER sichtbar, fuer das NETZ aber nicht.
    # Genau der Fall, der am 23.08.2026 267 von 920 Ladevorgaengen erzeugte:
    # ein archive/-Ordner, angelegt UM den Bestand zu kuerzen, der ihn
    # stattdessen verdoppelte. Der relative Pfad bleibt erhalten, sonst
    # verdraengt `archive/env-vars.md` die `env-vars.md` der Wurzel.
    while IFS= read -r f; do
      [ -n "$f" ] && [ -f "$f" ] || continue
      _rel="${f#$project_dir/.claude/rules/}"
      mkdir -p "$snap/rules/$(dirname "$_rel")" 2>/dev/null
      cp "$f" "$snap/rules/$_rel" 2>/dev/null && count=$((count+1))
    done <<EOF_RULES
$(find "$project_dir/.claude/rules" -name '*.md' -type f 2>/dev/null)
EOF_RULES
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
      # v5.21.0: REKURSIV -- siehe Begruendung bei den Projekt-Rules oben.
      while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        _rel="${f#$HOME/.claude/rules/}"
        mkdir -p "$snap/global/rules/$(dirname "$_rel")" 2>/dev/null
        cp "$f" "$snap/global/rules/$_rel" 2>/dev/null && count=$((count+1))
      done <<EOF_GRULES
$(find "$HOME/.claude/rules" -name '*.md' -type f 2>/dev/null)
EOF_GRULES
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


# ==========================================================================
# mind_sync_voll  (NEU v5.19.0)
# ==========================================================================
# Ist der `sync-stand`-Merker der Beleg fuer einen VOLLSTAENDIGEN Lauf?
#
# ANLASS -- dreimal an zwei Tagen gemessen, in drei Projekten:
#   23.08. Claude Mind Manager  Knowledge-Sync-Agents nicht dispatcht (Kontext)
#   24.08. Claude Mind Manager  Knowledge-Sync-Agents nicht dispatcht (914k)
#   24.08. Creator              nur 2 von 4 gefahren (888k)
# Alle drei setzten den Merker, alle drei erzeugten KEINE Schuld, und in allen
# drei Faellen verschwand der ungepruefte Bereich spurlos. Der Ablauf kannte
# nur "Sync lief" und "Sync lief nicht" -- der Normalfall bei hohem Kontext,
# "Sync lief UNVOLLSTAENDIG", hatte gar keinen Zustand.
#
# Gelesen wird eine Zeile der Form
#   umfang=5/5 skills 0/4 agents
# Jedes <n>/<m> zaehlt; ein einziges n < m macht den Lauf zum Teilsync.
#
# Rueckgabe 0 = vollstaendig  ·  1 = Teilsync
#
# ⛔ FAIL-SAFE ist hier "vollstaendig" -- die UMGEKEHRTE Richtung als bei
#    mind_sync_frisch, und das ist Absicht. Eine faelschlich behauptete
#    Vollstaendigkeit kostet eine Mahnung. Ein faelschlich behaupteter
#    Teilsync nagelt die Sitzung an einem Zwang fest, den sie selbst nicht
#    aufloesen kann -- und ein unaufloesbarer Zwang kostet die Sitzung
#    (dieselbe Linie wie der Notausgang in stop.sh, v5.7.6).
#    Als vollstaendig gilt deshalb:
#      - kein Merker           (nicht unsere Frage)
#      - Merker ohne umfang=   (jeder Bestand aus v5.18.0 und aelter)
#      - unparsbares umfang=   (ein Formatfehler darf nicht festnageln)
mind_sync_voll() {
  local stand="${1:-}" u paar a b teil=0 _glob=0 _ung
  [ -f "$stand" ] || return 0

  # v5.21.1: `ungepruef=` ist Teil des Urteils, nicht nur Beiwerk.
  #    Bis hierher entschied AUSSCHLIESSLICH `umfang=`. Gemessen am eigenen
  #    /mind-all-Lauf vom 26.08.2026: 4 von 4 Bereichen dispatcht, EINER kam
  #    mit 0 Byte zurueck. `umfang=4/4 agents` hiess damit "vollstaendig",
  #    waehrend `ungepruef=custom-context` in DERSELBEN Datei danebenstand.
  #    pre-compact.sh:136 liest das Feld zwar -- aber erst im else-Zweig,
  #    also nur wenn dieses Tor hier schon "teil" gesagt hat. Unerreichbar.
  #
  #    Woertlich die Klasse, gegen die v5.19.0 gebaut wurde, ein Feld weiter:
  #    dort loeschte ein Lauf OHNE Fan-out seine eigene Schuld, hier einer,
  #    dessen Agent LEER zurueckkam. Der Unterschied zwischen "nie gestartet"
  #    und "nichts geliefert" war der ganze Anlass fuer mind_agent_bilanz.
  #
  #    FAIL-SAFE unveraendert: FEHLT das Feld (Bestand aus v5.18.0 und
  #    aelter) oder ist es leer, bleibt es bei "vollstaendig". Nur ein
  #    AUSGEFUELLTES Feld macht daraus einen Teilsync -- diese Pruefung kann
  #    das Tor also nur STRENGER machen, nie milder.
  #
  #    Sie steht VOR der umfang-Auswertung, weil die bei fehlendem umfang=
  #    frueh zurueckkehrt: sonst waere ein Merker mit ungepruef= und ohne
  #    umfang= wieder unsichtbar.
  _ung=$(grep -m1 '^ungepruef=' "$stand" 2>/dev/null | cut -d= -f2-)
  [ -n "$_ung" ] && return 1

  u=$(grep -m1 '^umfang=' "$stand" 2>/dev/null | cut -d= -f2-)
  [ -n "$u" ] || return 0

  # Wortzerlegung ist gewollt, Dateinamen-Expansion NICHT: ein `*` im Wert
  # wuerde sonst gegen das Arbeitsverzeichnis aufgeloest.
  case "$-" in *f*) _glob=1 ;; esac
  set -f
  for paar in $u; do
    case "$paar" in
      *[!0-9/]*) continue ;;   # etwas anderes als Ziffern und /
      */*/*)     continue ;;   # mehr als ein /
      */*)       ;;            # genau ein / -> Kandidat
      *)         continue ;;   # gar kein /
    esac
    a="${paar%%/*}"; b="${paar##*/}"
    [ -n "$a" ] && [ -n "$b" ] || continue        # faengt "/4" und "5/"
    [ "$a" -lt "$b" ] 2>/dev/null && teil=1
  done
  [ "$_glob" = 1 ] || set +f

  [ "$teil" -eq 0 ]
}

# ==========================================================================
# mind_sync_frisch  (NEU v5.11.0)
# ==========================================================================
# ⛔ Ein Merker, dessen Verbraucher nie laeuft, ist eine Dauersperre.
#
# `sync-stand` wird AUSSCHLIESSLICH von pre-compact.sh weggeraeumt. Seit
# v5.7.7 (`autoCompactEnabled: false`, Nutzerentscheidung) feuert der aber nur
# noch bei einem VON HAND getippten /compact. Wer den nie tippt, hat nach dem
# ersten /mind-all einen Merker, der ewig liegen bleibt -- und Token-Mahnung
# wie Token-Zwang schweigen dauerhaft.
#
# GEMESSEN 21.08.2026: der Merker lag seit 08:00 in `APP - Palvedo`, die
# Sitzung dort lief auf 950 000 Tokens, und auf die Frage, warum kein
# /mind-all komme, war die Antwort korrekt "mechanisch steht nichts aus".
# Die Mechanik hat die Wahrheit gesagt; der Merker war schuld.
#
# Deshalb zaehlt nicht mehr die EXISTENZ des Merkers, sondern der ZUWACHS
# seit dem Sync. Das misst, was der Merker eigentlich meint -- "gerade eben
# gelaufen, nicht schon wieder mahnen" -- und loest sich von selbst auf,
# sobald wieder Arbeit dazugekommen ist.
#
# Rueckgabe 0 = frisch (schweigen)  ·  1 = verbraucht (mahnen/blocken)
mind_sync_frisch() {
  local stand="$1" jetzt="$2" delta="${MIND_SYNC_DELTA:-60000}" beim
  [ -f "$stand" ] || return 1
  # v5.19.0: ein TEILSYNC ist kein Sync. Er darf die Mahnung nicht stumm
  # schalten -- sonst schweigt die Kette genau dann, wenn am meisten fehlt.
  # Wirkt sofort in derselben Sitzung, ohne Umweg ueber eine Kompaktierung.
  mind_sync_voll "$stand" || return 1
  beim=$(grep -m1 '^tokens=' "$stand" 2>/dev/null | cut -d= -f2-)
  # Merker aus einer Fassung vor v5.11.0 traegt keine Zahl. Ihn als "frisch"
  # zu behandeln waere genau die Dauersperre -- also gilt er als VERBRAUCHT.
  # Der Bestand heilt sich damit beim ersten Lauf selbst.
  case "$beim" in ''|*[!0-9]*) return 1;; esac
  # Ohne Messung wird NICHT gemahnt (dieselbe Linie wie ueberall sonst:
  # keine Zahl ist keine Null).
  case "$jetzt" in ''|*[!0-9]*) return 0;; esac
  [ $((jetzt - beim)) -lt "$delta" ]
}

# ==========================================================================
# mind_classify_path / mind_pfad_lebt  (NEU v5.11.0)
# ==========================================================================
# ⛔ Diese Funktion stand als BASH-QUELLTEXT in mind-update/SKILL.md und wurde
# vom ausfuehrenden Modell nachgebaut statt aufgerufen. Klasse
# `instrument-nachgebaut`, 7 Vorkommen im Debug-Index -- einmal ergab der
# Nachbau 11 Slash-Commands als tote Pfade. Wer Prosa liest, baut nach.
# Sie liegt deshalb hier: eine Definition, aufrufbar, nicht nacherzaehlbar.
#
# Klassen:  SKIP = kein Dateipfad  ·  UNSURE = nur melden, nie anwenden
#           CHECK = auf Existenz pruefbar
mind_classify_path() {
  local p="$1"
  echo "$p" | grep -qiE '(^|/)([a-z0-9-]+\.)+(com|de|org|net|io|dev|ai|co|eu|info)(/|$)' && { echo SKIP; return; }
  echo "$p" | grep -qiE '^(https?|ftp|mailto|file)://' && { echo SKIP; return; }
  # v5.3.1: '['']('  = Markdown-Link-Syntax. Fehlte sie, wurde `[n](../x.md)`
  # zu CHECK -> nicht gefunden -> DEAD -> bei <=5 AUTONOM GELOESCHT.
  case "$p" in
    *'…'*|*'...'*|*'<'*'>'*|*'{'*'}'*|*'$'*|*'*'*|*'['*']('*) echo SKIP; return;;
  esac
  # v5.3.1: Slash-Command. Kriterium bewusst ENG (fuehrender /, GENAU ein
  # Segment, mit Bindestrich), sonst verschluckt es /etc, /tmp, /usr, /var.
  case "$p" in
    */*/*) : ;;
    /*-*)  echo SKIP; return;;
  esac
  case "$p" in
    /[a-z]/*|/) : ;;
    /*) echo UNSURE; return;;
  esac
  echo CHECK
}

# Existenzpruefung fuer einen CHECK-Pfad. Rueckgabe 0 = lebt, 1 = tot.
#
# ⛔ HIER SASS DER FEHLER, DEN v5.11.0 BEHEBT.
# Bash expandiert `~` in Anfuehrungszeichen NICHT. `test -e "~/.claude/rules/x.md"`
# ist damit immer falsch -- die Datei mag mit 68 Zeilen dort liegen, die
# Pruefung meldet DEAD, und bei <=5 DEAD wird die Zeile AUTONOM GELOESCHT.
# Betroffen war jede Kontextdatei, die auf die globalen Regeln zeigt.
# Gemessen und reproduziert 21.08.2026 (Befund aus `APP - Palvedo`).
# Es ist derselbe Fehlertyp wie der Markdown-Link-Bug oben -- zwei Zeilen
# darueber steht seine Warnung, und der naechste Fall lief trotzdem daneben.
mind_pfad_lebt() {
  local p="$1" basis="${2:-$CLAUDE_PROJECT_DIR}"
  case "$p" in
    '~')      p="$HOME";;
    '~/'*)    p="$HOME/${p#\~/}";;
  esac
  [ -e "$p" ] && return 0
  # ⛔ Auf Windows heisst eine ausfuehrbare Datei `.exe`. `.venv/Scripts/python`
  # existiert dort NICHT -- `.venv/Scripts/python.exe` schon. Ein Existenztest
  # ohne die Endung meldet einen funktionierenden Interpreter als toten Pfad.
  # Gemessen in `APP - Zustellplan`.
  [ -e "$p.exe" ] && return 0
  # Relative Pfade gegen das PROJEKT aufloesen, nicht gegen das CWD.
  case "$p" in
    /*|[A-Za-z]:*) return 1;;
  esac
  [ -n "$basis" ] && { [ -e "$basis/$p" ] || [ -e "$basis/$p.exe" ]; }
}

# ==========================================================================
# mind_zeilenenden / mind_zeilenenden_gleich  (NEU v5.11.0)
# ==========================================================================
# Gibt den CRLF-Anteil einer Datei als "crlf/gesamt" aus.
#
# ⛔ NIE mit `grep -c $'\r'` zaehlen -- das zaehlt in Git Bash JEDE Zeile,
# auch in einer Datei ganz ohne CR. Byte-genau zaehlen ist der einzige Weg.
mind_zeilenenden() {
  local f="$1"
  [ -f "$f" ] || { echo "0/0"; return 1; }
  if command -v python >/dev/null 2>&1; then
    python -c "import sys;b=open(sys.argv[1],'rb').read();c=b.count(b'\r\n');print('%d/%d'%(c,b.count(b'\n')))" "$f" 2>/dev/null && return 0
  fi
  local c t
  c=$(tr -dc '\r' < "$f" 2>/dev/null | wc -c | tr -d ' ')
  t=$(tr -dc '\n' < "$f" 2>/dev/null | wc -c | tr -d ' ')
  echo "$c/$t"
}

# Waechter fuers Editieren: hat ein Fix die Zeilenenden gekippt?
# Rueckgabe 0 = unveraendert, 1 = gekippt (dann MELDEN, nicht schweigen).
#
# BELEGT: eine Reparaturrunde kippte 4 Quelldateien in `APP - Zustellplan`
# von LF nach CRLF gegen deren .editorconfig -- der Diff wuchs auf 6417/6152
# Zeilen statt 311/46. Der eigentliche Fix darin war winzig und im Rauschen
# nicht mehr auffindbar.
# ⚠ Gemessen wird der ANTEIL, nicht die Zeilenzahl: eine Zusicherung
# "Zeilenzahl unveraendert" ist bei genau diesem Fehler gruen.
#
# ⛔ v5.13.0 — BIS HIERHER TAT DIESE FUNKTION DAS GEGENTEIL IHRES EIGENEN
#    KOMMENTARS. Sie lautete:
#        [ "${vorher%%/*}" = "${nachher%%/*}" ]
#    `%%/*` schneidet ab dem ersten `/` ab und liefert damit den ZAEHLER --
#    die absolute CRLF-Zahl. Eine Datei, die von 155 auf 157 Zeilen waechst
#    und durchgehend CRLF ist, ergibt "155/155" gegen "157/157" und wurde als
#    GEKIPPT gemeldet. Befund aus dem Zustellplan-Lauf vom 22.08.2026, genau
#    mit diesen Zahlen.
#
#    ⭐ Das ist die bittere Pointe: diese Funktion IST die Sperre gegen die
#    Fehlerklasse `zeilenenden` -- und war selbst ein `instrument-misst-nichts`,
#    die groesste Klasse im Debug-Ordner (23 Vorkommen). Eine Sperre, die
#    niemand gegenprueft, ist eine Klasse, die man nicht mehr sieht.
#
# ⚠ Verglichen wird ueber KREUZ, nicht in Prozent: a_crlf*b_ges == b_crlf*a_ges.
#    Prozentrechnung mit Ganzzahlen wuerde eine einzelne gekippte Zeile in einer
#    grossen Datei wegrunden (1 von 1000 = 0 %), und genau die einzelne Zeile
#    ist der Fall, der einen Ersetzungsanker reisst.
#
# Rueckgabe: 0 = Anteil gleich · 1 = gekippt · 2 = NICHT MESSBAR
# ⚠ Nicht messbar wird als Befund behandelt, nicht als "unveraendert". Ein
#   Fehlalarm kostet eine Zeile im Bericht; ein uebersehener Kipp kostet einen
#   Diff von 6417 Zeilen, in dem der eigentliche Fix unauffindbar ist.
mind_zeilenenden_gleich() {
  local vorher="$1" nachher="$2"
  # Format muss "zahl/zahl" sein -- ohne Schraegstrich ist es keine Messung.
  case "$vorher"  in */*) ;; *) return 2 ;; esac
  case "$nachher" in */*) ;; *) return 2 ;; esac
  local ac="${vorher%%/*}" ag="${vorher##*/}"
  local bc="${nachher%%/*}" bg="${nachher##*/}"
  # ⛔ JEDEN Wert EINZELN pruefen. Die erste Fassung verkettete sie zu
  #    "$ac$ag$bc$bg" -- bei ("" , "0/50") ergab das "050", war damit rein
  #    numerisch und rutschte durch; die Funktion meldete "gleich" fuer eine
  #    Eingabe, die sie gar nicht messen konnte. Beim Bau der Gegenprobe
  #    aufgefallen, in derselben Stunde wie die drei anderen Faelle dieser
  #    Bauart. Eine Verkettung kann nicht sagen, WELCHER Teil leer war.
  local x
  for x in "$ac" "$ag" "$bc" "$bg"; do
    case "$x" in ''|*[!0-9]*) return 2 ;; esac
  done
  [ $(( ac * bg )) -eq $(( bc * ag )) ]
}

# ==========================================================================
# mind_schnappziel — Snapshot-Pfad auf die ECHTE Datei abbilden (NEU v5.13.0)
# ==========================================================================
# Ein Snapshot hat VIER Zweige plus die Wurzel:
#
#   CLAUDE.md            -> $PROJ/CLAUDE.md
#   project/<pfad>       -> $PROJ/<pfad>
#   rules/<datei>        -> $PROJ/.claude/rules/<datei>
#   global/<pfad>        -> $HOME/.claude/<pfad>
#   memory/<datei>       -> <Memory-Verzeichnis>/<datei>
#
# ⛔ WARUM DAS EINE EIGENE FUNKTION IST: Der Zeilenenden-Waechter in
#    mind-all Step 2.95 bildete bis v5.12.0 stumpf `$PROJ/$z` fuer JEDEN
#    Snapshot-Pfad. Fuer `project/knowledge/x.md` ergab das
#    `$PROJ/project/knowledge/x.md` -- ein Pfad, den es nicht gibt -> `continue`.
#    Uebrig blieb die eine Datei in der Snapshot-Wurzel. GEMESSEN im
#    Zustellplan-Lauf vom 22.08.2026: **1 von 68 Dateien verglichen**, Meldung
#    "keine Abweichung".
#
# Rueckgabe: 0 + Pfad auf stdout · 1 = kein abbildbares Ziel (MELDEN, nicht raten)
mind_schnappziel() {
  local rel="$1" proj="$2" memdir="${3:-}"
  case "$rel" in
    MANIFEST.sha256|MANIFEST.*) return 1 ;;   # Snapshot-Metadaten, kein Projektfile
    global/*)  printf '%s\n' "$HOME/.claude/${rel#global/}" ;;
    memory/*)  [ -n "$memdir" ] || return 1
               printf '%s\n' "$memdir/${rel#memory/}" ;;
    project/*) printf '%s\n' "$proj/${rel#project/}" ;;
    rules/*)   printf '%s\n' "$proj/.claude/rules/${rel#rules/}" ;;
    */*)       return 1 ;;                    # unbekannter Zweig -> melden statt raten
    *)         printf '%s\n' "$proj/$rel" ;;  # Wurzel = Projektwurzel
  esac
}

# ==========================================================================
# mind_zeilenenden_waechter — der ganze Durchlauf (NEU v5.13.0)
# ==========================================================================
# Vergleicht jede .md des Snapshots mit ihrem echten Gegenstueck.
#
# ⛔ Diese Logik stand bis v5.12.0 als Codeblock in `mind-all/SKILL.md`. Dort
#    war sie NICHT PRUEFBAR -- kein Prueffall kann einen Absatz in einer
#    Markdown-Datei aufrufen. Genau deshalb konnte sie ein Jahr lang 1 von 68
#    Dateien vergleichen, ohne dass etwas rot wurde. Sie liegt jetzt hier,
#    damit `tests/test_zeilenenden.sh` sie direkt fahren kann.
#
# Ausgabe (stdout), maschinell lesbar als erste Zeile:
#   VERGLICHEN=<n> OHNE_ZIEL=<n> GEKIPPT=<n>
# danach je gekippter Datei eine Zeile "  <rel>: <vorher> -> <nachher>".
#
# Rueckgabe: 0 = alles gleich · 1 = mindestens eine gekippt
#            2 = UNGUELTIG (<= 1 Datei verglichen -- der Waechter hat nichts geprueft)
mind_zeilenenden_waechter() {
  local snap="$1" proj="$2" memdir="${3:-}"
  local v z ziel a b vergl=0 ohne=0 kipp=0 liste=""

  [ -n "$snap" ] && [ -d "$snap" ] || { echo "VERGLICHEN=0 OHNE_ZIEL=0 GEKIPPT=0"; return 2; }

  while IFS= read -r v; do
    [ -n "$v" ] || continue
    z="${v#"$snap"/}"
    ziel=$(mind_schnappziel "$z" "$proj" "$memdir") || { ohne=$((ohne + 1)); continue; }
    # Fehlt das Ziel, ist die Datei geloescht oder umbenannt -- ein anderer
    # Befund, nicht Sache dieses Waechters.
    [ -f "$ziel" ] || { ohne=$((ohne + 1)); continue; }
    a=$(mind_zeilenenden "$v"); b=$(mind_zeilenenden "$ziel")
    vergl=$((vergl + 1))
    mind_zeilenenden_gleich "$a" "$b" || {
      kipp=$((kipp + 1))
      liste="${liste}  ${z}: ${a} -> ${b}"$'\n'
    }
  done < <(find "$snap" -type f -name '*.md' 2>/dev/null)

  echo "VERGLICHEN=$vergl OHNE_ZIEL=$ohne GEKIPPT=$kipp"
  [ -n "$liste" ] && printf '%s' "$liste"

  # ⛔ DIE ZUSICHERUNG AUF DIE ZAHL. Ein Waechter, der fast nichts prueft, sieht
  #    von aussen aus wie einer, der nichts zu beanstanden hat. Deshalb ist eine
  #    zu kleine Vergleichszahl ein eigener Rueckgabewert und keine Fussnote.
  [ "$vergl" -le 1 ] && return 2
  [ "$kipp" -gt 0 ] && return 1
  return 0
}

# ==========================================================================
# Agent-Quittung — ein toter Agent ist ein ABBRUCH, kein Absatz (NEU v5.14.0)
# ==========================================================================
#
# ⛔ WARUM ES DAS GIBT
#
# Debug/BEFUNDE.md, zwei Klassen mit zusammen 10 Vorkommen:
#   agent-gestorben   (4x)  "Knowledge-Sync memory: leere Rueckgabe nach
#                            20 Werkzeugaufrufen / 199s"
#   agent-fehlbericht (6x)  "belegte mit 'alle zwoelf Eintraege abgearbeitet';
#                            neun gefahren, drei zurueckgestellt"
#
# Der Umgang damit stand als PROSA in mind-all/SKILL.md: "den Bereich als
# UNGEPRUEFT in den Bericht schreiben". Prosa hat es nicht verhindert — am
# 23.08.2026 wurden die Agents GAR NICHT ERST losgeschickt, und der Lauf lief
# durch, als waere alles geprueft.
#
# ⛔ Der Kern: ein Agent, der stirbt, und ein Agent, der nichts findet, sehen im
#    Bericht identisch aus. Nur eine Quittung VOR dem Start unterscheidet sie.
#    Deshalb wird der Dispatch protokolliert, bevor er passiert — ein Merker, den
#    nur ein zurueckgekehrter Agent wieder aufloest.
#
# Ablage: $projekt/.claude-mind/agent-quittung.jsonl, pro Lauf neu.

_mind_quittung_pfad() {
  local proj="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
  printf '%s\n' "$proj/.claude-mind/agent-quittung.jsonl"
}

# Zu Beginn eines Laufs: alte Quittungen wegraeumen.
# $1 = Projekt, $2 = wie viele Agenten GEPLANT sind (optional).
#
# ⛔ v5.21.2: die Erwartungszahl ist der einzige Weg, "nie dispatcht" von
#    "dispatcht, aber nie quittiert" zu unterscheiden. `mind_agent_dispatch`
#    ist eine PROSA-Anweisung in mind-update/SKILL.md, die ein Modell abtippen
#    muss — und am 26.08.2026 hat ein Lauf im Projekt `Pc Forschung` vier
#    Agenten gefahren und DISPATCH=0 gemeldet, weil niemand quittiert hat.
#    Ein Bash-Aufruf kann keinen Agenten STARTEN; die Quittung ist also nicht
#    vollstaendig automatisierbar. Ihr FEHLEN ist es.
#
# ⚠ Ohne $2 verhaelt sich alles wie bisher — kein Bestand wird ungueltig.
# $1 = Projekt, $2 = Snapshot-Verzeichnis
# Ausgabe: "<anzahl>|<bis zu fuenf Namen, durch Leerzeichen>"  — leer, wenn alles gedeckt.
#
# ⛔ v5.21.3 — BEFUND aus `Pc Forschung`, 26.08.2026:
#    "INDEX.md liegt NICHT im /mind-all-Snapshot. Alle Aenderungen daran hatten
#     kein Netz, und der Restore-Weg im Bericht ist fuer sie falsch."
#    Ihr Vorschlag war, `INDEX.md` fest einzubauen. Das waere ein
#    projektspezifisches Pflaster in einem allgemeinen Werkzeug —
#    `MIND_SNAPSHOT_EXTRA` loest den Fall seit v5.2.1 allgemein.
#
#    ⭐ GEMESSEN, warum sie das nicht wissen konnten: die Variable kommt in
#       `hooks/lib.sh` vor und in KEINEM Skill, KEINEM Bericht, KEINER Referenz.
#       Wer den Schlussbericht liest, sieht eine Restore-Liste und hat keinen
#       Weg zu erfahren, dass sie erweiterbar ist. Klasse `sichtbarkeit`.
#       Dasselbe ist hier zweimal mit `knowledge/` passiert (env-vars.md).
#
# ⚠ NUR die fuenf zuletzt GEAENDERTEN. Die volle Liste waere in diesem Projekt
#   15 Namen lang und damit die Ausgabe, die man gewohnheitsmaessig ueberliest —
#   wovor `Pc Forschung` im selben Bericht warnt. Die Gesamtzahl bleibt sichtbar.
#
# ⛔ Der GLOB laeuft, NICHT `$(ls -t ...)`: eine unquotierte Befehlssubstitution
#   zerlegt am Leerzeichen, und dieses Projekt heisst `Plugin - Entwicklung/...`.
#   Erste Fassung meldete dadurch "79 Dateien" statt 15, mit Namen wie
#   "Plugin - Claude Mind". Klasse `windows-pfad`, seit v5.2.1 dokumentiert.
# ⛔ Und KEINE Pipe in die Schleife — die liefe in einer Subshell, und der
#   Zaehler waere danach wieder 0.
mind_snapshot_luecken() {
  local projekt="${1:-}" snap="${2:-}" f b mt n=0 namen=""
  [ -d "$projekt" ] || { echo "0|"; return 0; }
  [ -d "$snap" ] || { echo "0|"; return 0; }
  mt="${TMPDIR:-/tmp}/.mind_luecke_$$"; : > "$mt" || { echo "0|"; return 0; }
  for f in "$projekt"/*.md; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    [ "$b" = "CLAUDE.md" ] && continue
    [ -f "$snap/project/$b" ] && continue
    printf '%s\t%s\n' "$(date -r "$f" +%s 2>/dev/null || echo 0)" "$b" >> "$mt"
  done
  n=$(grep -c . "$mt" 2>/dev/null); n=${n:-0}
  namen=$(sort -rn "$mt" 2>/dev/null | head -5 | cut -f2 | tr '\n' ' ')
  rm -f "$mt"
  echo "${n}|${namen}"
}


mind_agent_quittung_start() {
  local q; q=$(_mind_quittung_pfad "${1:-}")
  local erwartet="${2:-}"
  mkdir -p "$(dirname "$q")" 2>/dev/null || return 1
  : > "$q" || return 1
  case "$erwartet" in
    ''|*[!0-9]*) ;;
    *) printf '{"ereignis":"start","erwartet":%s,"ts":"%s"}\n' \
         "$erwartet" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$q" ;;
  esac
}

# VOR dem Start des Agents aufrufen.
mind_agent_dispatch() {
  local bereich="$1" q
  q=$(_mind_quittung_pfad "${2:-}")
  mkdir -p "$(dirname "$q")" 2>/dev/null
  printf '{"ereignis":"dispatch","bereich":"%s","ts":"%s"}\n' \
    "$bereich" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$q"
}

# NACH der Rueckkehr aufrufen, mit der Bytezahl der Rueckgabe.
# ⚠ 0 Bytes ist ein ERGEBNIS-Eintrag, kein fehlender. Der Unterschied zwischen
#   "leer zurueckgekommen" und "nie zurueckgekommen" ist genau das, was hier
#   sichtbar werden soll.
mind_agent_ergebnis() {
  local bereich="$1" bytes="${2:-0}" q
  q=$(_mind_quittung_pfad "${3:-}")
  case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
  printf '{"ereignis":"ergebnis","bereich":"%s","bytes":%s,"ts":"%s"}\n' \
    "$bereich" "$bytes" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$q"
}

# Bilanz fuer den Self-Check-Block.
# Ausgabe Zeile 1 (maschinell):  DISPATCH=n ERGEBNIS=n LEER=n STUMM=n
# danach je stummem/leerem Bereich eine Zeile "  UNGEPRUEFT: <bereich> (<grund>)".
#
# Rueckgabe: 0 = alle dispatcht und alle mit Inhalt zurueck
#            1 = mindestens ein Bereich UNGEPRUEFT (leer oder stumm)
#            2 = GAR NICHT DISPATCHT — der Fan-out hat nicht stattgefunden
mind_agent_bilanz() {
  local q; q=$(_mind_quittung_pfad "${1:-}")
  local d=0 e=0 leer=0 stumm=0 zeile b bereich liste=""

  if [ ! -f "$q" ]; then
    echo "DISPATCH=0 ERGEBNIS=0 LEER=0 STUMM=0"
    echo "  UNGEPRUEFT: keine Quittung vorhanden — der Fan-out hat nicht stattgefunden"
    return 2
  fi

  # Bereiche sammeln. Bewusst ohne jq: die Bilanz muss auch dann funktionieren,
  # wenn jq fehlt — sonst faellt genau die Pruefung aus, die den Ausfall melden soll.
  local dispatcht="" mit_ergebnis="" erwartet="" wdh=0 nachtrag=""
  erwartet=$(sed -n 's/.*"ereignis":"start".*"erwartet":\([0-9]*\).*/\1/p' "$q" | head -1)
  while IFS= read -r zeile; do
    [ -n "$zeile" ] || continue
    bereich=$(printf '%s' "$zeile" | sed -n 's/.*"bereich":"\([^"]*\)".*/\1/p')
    [ -n "$bereich" ] || continue
    case "$zeile" in
      *'"ereignis":"dispatch"'*)
        case " $dispatcht " in
          *" $bereich "*) ;;                      # Wiederholung, kein neuer Bereich
          *) d=$((d + 1)); dispatcht="${dispatcht}${bereich} " ;;
        esac ;;
      *'"ereignis":"ergebnis"'*)
        e=$((e + 1))
        case " $mit_ergebnis " in
          *" $bereich "*) ;;
          *) mit_ergebnis="${mit_ergebnis}${bereich} " ;;
        esac ;;
    esac
  done < "$q"

  # ⛔ v5.21.2 (B2): je Bereich zaehlt der LETZTE Ergebniseintrag, nicht jeder.
  #    Gemessen 26.08.2026: ein zweiter, engerer Dispatch lieferte ein Ergebnis,
  #    die Bilanz blieb bei LEER=1 — der Bereich war geprueft, das Instrument
  #    konnte es nicht sagen.
  #    ⚠ Der Verlauf bleibt SICHTBAR (Zeile "WIEDERHOLT"): ein gestorbener Agent
  #      darf nicht spurlos verschwinden, das ist der Zweck der ganzen Quittung.
  #    ⚠ Alle Faelle in tests/test_quittung.sh haben genau EIN Ergebnis je
  #      Bereich — dort ist "letzter" mit "jeder" identisch, die Kopfzeile bleibt.
  for bereich in $mit_ergebnis; do
    local _alle _letzte _erste
    _alle=$(grep '"ereignis":"ergebnis"' "$q" 2>/dev/null | grep "\"bereich\":\"$bereich\"")
    _letzte=$(printf '%s\n' "$_alle" | tail -1 | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')
    _erste=$(printf '%s\n' "$_alle" | head -1 | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')
    if [ "${_letzte:-0}" -eq 0 ] 2>/dev/null; then
      leer=$((leer + 1))
      liste="${liste}  UNGEPRUEFT: ${bereich} (leere Rueckgabe — 0 Byte ist kein Befund)"$'\n'
    elif [ "${_erste:-0}" -eq 0 ] 2>/dev/null; then
      wdh=$((wdh + 1))
      nachtrag="${nachtrag}  WIEDERHOLT: ${bereich} (erst 0 Byte, dann ${_letzte} — geprueft, aber ein Agent ist gestorben)"$'\n'
    fi
  done

  # Stumm = dispatcht, aber nie zurueckgemeldet.
  for bereich in $dispatcht; do
    case " $mit_ergebnis " in
      *" $bereich "*) ;;
      *) stumm=$((stumm + 1)); liste="${liste}  UNGEPRUEFT: ${bereich} (dispatcht, nie zurueck)"$'\n' ;;
    esac
  done

  echo "DISPATCH=$d ERGEBNIS=$e LEER=$leer STUMM=$stumm"
  [ -n "$erwartet" ] && echo "  ERWARTET=$erwartet"
  [ -n "$liste" ] && printf '%s' "$liste"
  [ -n "$nachtrag" ] && printf '%s' "$nachtrag"

  [ "$d" -eq 0 ] && {
    echo "  UNGEPRUEFT: kein einziger Agent dispatcht — der Fan-out hat nicht stattgefunden"
    # ⛔ v5.21.2 (B1): mit Erwartungszahl ist diese Aussage EHRLICHER zu machen.
    #    Ein Modell, das die Agenten fuhr und nur nicht quittierte, sieht hier
    #    genauso aus wie einer, der sie nie startete. Gemessen 26.08.2026 in
    #    `Pc Forschung`: DISPATCH=0 bei vier gelaufenen Agenten.
    [ -n "$erwartet" ] && [ "$erwartet" -gt 0 ] 2>/dev/null && \
      echo "  ⛔ $erwartet waren geplant. 0 quittiert heisst ENTWEDER nie gestartet ODER gestartet und nicht quittiert — das ist von hier aus NICHT unterscheidbar."
    return 2
  }
  # Weniger quittiert als geplant: derselbe Zweifel, kleinere Dosis.
  if [ -n "$erwartet" ] && [ "$d" -lt "$erwartet" ] 2>/dev/null; then
    echo "  ⛔ nur $d von $erwartet Bereichen quittiert — die uebrigen sind ungeprueft ODER unquittiert"
    return 1
  fi
  [ $((leer + stumm)) -gt 0 ] && return 1
  return 0
}

# ==========================================================================
# mind_commits_seit — der Ausloeser, der NICHT an der Kompaktierung haengt
# ==========================================================================
# (NEU v5.14.0)
#
# ⛔ WARUM ES DAS GIBT
#
# Debug-Befund vom 21.08.2026, Projekt Palvedo, woertlich:
#   "Sync-Ausloeser haengt allein an der Kompaktierung; ein Neustart setzt den
#    Tokenzaehler zurueck -- 11 Commits und 12 h ohne Netz."
#
# Beide vorhandenen Ausloeser messen den KONTEXT: prompt-submit.sh mahnt ab
# MIND_SYNC_AT_TOKENS, stop.sh blockt ab MIND_SYNC_FORCE_TOKENS. Beide zaehlen
# ab dem Sitzungsstart wieder bei null. Wer neu startet und dann zwoelf Stunden
# arbeitet, ohne die Schwelle zu reissen, hat nie einen Sync — und nichts merkt es.
#
# Gezaehlt wird deshalb ARBEIT, nicht Fuellstand: Commits seit dem letzten Sync.
#
# Gibt die Zahl auf stdout aus.
# Rueckgabe: 0 = gezaehlt · 1 = nicht zaehlbar (kein git, kein Referenzpunkt)
# ⚠ "nicht zaehlbar" gibt NICHTS aus, nicht "0". Keine Zahl ist keine Null —
#   dieselbe Regel wie bei mind_kontext_tokens.
mind_commits_seit() {
  local proj="$1" ref="$2" epoch iso n
  [ -n "$proj" ] && [ -d "$proj/.git" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  [ -f "$ref" ] || return 1
  epoch=$(stat -c %Y "$ref" 2>/dev/null) || return 1
  case "$epoch" in ''|*[!0-9]*) return 1 ;; esac
  iso=$(date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || return 1
  n=$(git -C "$proj" rev-list --count --since="$iso" HEAD 2>/dev/null) || return 1
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$n"
}


# --- mind_kontext_bilanz: wie gross ist der IMMER geladene Kontext? -----------
#
# ⛔ WOZU. Gemessen 27.08.2026 wuchs der Dauerkontext dieses Projekts an EINEM Tag
#    um +19 460 B (+21 %), auf 2 570 Zeilen und 137 Anweisungen. Bemerkt hat es
#    niemand — weil ihn niemand misst. `references/budget-thresholds.md` nennt
#    >400 Zeilen als die Schwelle, ab der die Befolgung auf 71 % faellt, und
#    ~100-150 als die Zahl der Anweisungen, die ein Modell verlaesslich haelt.
#    Beides war um ein Vielfaches ueberschritten, ohne dass irgendwo eine Zahl stand.
#
# ⭐ Bei ausgeschoepftem Budget ist Anhaengen kein Zuwachs mehr, sondern ein
#    TAUSCH: jede neue Anweisung verdraengt eine alte. Diese Funktion macht den
#    Tausch sichtbar. Sie entscheidet ihn NICHT — wie die Agent-Quittung erzwingt
#    sie keine Arbeit, sie macht deren Fehlen messbar. Das hat dort gereicht.
#
# ⚠ TOPIC-DATEIEN ZAEHLEN NICHT MIT. Sie laden hoechstens 5 pro Anfrage, ueber
#   einen Auswaehler, der nur Name und `description` sieht (am Binaerprogramm
#   2.1.237 nachgelesen). Ihr Wuchs kostet AUFFINDBARKEIT, kaum Tokens — eine
#   voellig andere Groesse. Beides in eine Zahl zu legen macht beide unbrauchbar.
#   `MEMORY.md` selbst zaehlt sehr wohl mit: die laedt jede Sitzung vollstaendig.
#
# ⚠ Die Anweisungszahl ist eine HEURISTIK: Zeilen, die `MUST`, `NEVER`, `ALWAYS`
#   oder ⛔ enthalten. Gezaehlt werden ZEILEN, nicht Vorkommen. Die echte Zahl
#   liegt eher hoeher — Anweisungen ohne Marke gibt es reichlich. Als Trend ist
#   sie brauchbar, als Absolutwert nicht. Steht so auch in der Ausgabe.
#
# Aufruf:  mind_kontext_bilanz <projekt> [--merken|--vergleichen]
# Ausgabe: Zeile 1 maschinell:  ZEILEN=n ANWEISUNGEN=n DATEIEN=n BYTES=n
#          mit --vergleichen und vorhandenem Vorstand zusaetzlich die Berichtszeile
# Rueckgabe: 0 = gemessen  ·  1 = nichts messbar (keine einzige Datei gefunden)
mind_kontext_bilanz() {
  local projekt="${1:-}" modus="${2:-}"
  local liste zeilen=0 anw=0 bytes=0 dateien=0 f n a b
  local stand="$projekt/.claude-mind/kontext-bilanz"

  [ -n "$projekt" ] || { echo "ZEILEN=0 ANWEISUNGEN=0 DATEIEN=0 BYTES=0"; return 1; }

  liste="${TMPDIR:-/tmp}/.mind_bilanz_$$"
  : > "$liste" || { echo "ZEILEN=0 ANWEISUNGEN=0 DATEIEN=0 BYTES=0"; return 1; }

  # ── Der immer geladene Satz ────────────────────────────────────────────────
  # ⛔ KEINE Pipe in die Sammelschleife und KEIN `for f in $(ls …)`. Beides
  #    zerlegt an Leerzeichen, und dieses Projekt heisst
  #    "Plugin - Entwicklung/Claude Mind Manager". Genau daran ist die Rotation
  #    in v5.2.1 still gescheitert (9 Kopien bei KEEP=3) und die Luecken-Meldung
  #    in v5.21.3 beim ersten Anlauf ("79 Dateien" statt 15). Der Glob laeuft.
  for f in "$projekt/CLAUDE.md" "$projekt/.claude/CLAUDE.md" \
           "$HOME/.claude/CLAUDE.md"; do
    [ -f "$f" ] && printf '%s\n' "$f" >> "$liste"
  done
  for f in "$projekt"/.claude/rules/*.md "$HOME"/.claude/rules/*.md; do
    [ -f "$f" ] && printf '%s\n' "$f" >> "$liste"
  done
  # MEMORY.md ja, Topic-Dateien nein — siehe Kopf.
  local mem
  mem=$(get_memory_dir "$projekt" 2>/dev/null)
  [ -n "$mem" ] && [ -f "$mem/MEMORY.md" ] && printf '%s\n' "$mem/MEMORY.md" >> "$liste"

  # ── Zaehlen ────────────────────────────────────────────────────────────────
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # ⛔ `wc -l` zaehlt NEWLINES, nicht Zeilen: eine Datei ohne abschliessenden
    #    Umbruch faellt um eins zu niedrig aus. awk zaehlt Datensaetze und nimmt
    #    die letzte unvollstaendige Zeile mit. Bei CRLF stimmt beides, weil das
    #    \r vor dem \n steht und der Trenner das \n bleibt.
    n=$(awk 'END{print NR}' "$f" 2>/dev/null); case "$n" in ''|*[!0-9]*) n=0 ;; esac
    # ⛔ Kein `grep -F` auf UTF-8: das ist auf Git-Bash/MSYS schon einmal mit
    #    einem core dump ausgestiegen und hat 24 Scheinbefunde erzeugt (v4.1.0).
    a=$(grep -cE '(MUST|NEVER|ALWAYS|⛔)' "$f" 2>/dev/null); case "$a" in ''|*[!0-9]*) a=0 ;; esac
    b=$(wc -c < "$f" 2>/dev/null); case "$b" in ''|*[!0-9]*) b=0 ;; esac
    zeilen=$((zeilen + n)); anw=$((anw + a)); bytes=$((bytes + b))
    dateien=$((dateien + 1))
  done < "$liste"
  rm -f "$liste"

  echo "ZEILEN=$zeilen ANWEISUNGEN=$anw DATEIEN=$dateien BYTES=$bytes"
  [ "$dateien" -eq 0 ] && return 1

  # ── Vergleich gegen den gemerkten Vorstand ─────────────────────────────────
  if [ "$modus" = "--vergleichen" ] && [ -f "$stand" ]; then
    local vz va vb dz da db pz
    vz=$(grep -m1 '^ZEILEN=' "$stand" 2>/dev/null | cut -d= -f2)
    va=$(grep -m1 '^ANWEISUNGEN=' "$stand" 2>/dev/null | cut -d= -f2)
    vb=$(grep -m1 '^BYTES=' "$stand" 2>/dev/null | cut -d= -f2)
    case "$vz" in ''|*[!0-9]*) vz="" ;; esac
    case "$va" in ''|*[!0-9]*) va="" ;; esac
    case "$vb" in ''|*[!0-9]*) vb="" ;; esac
    if [ -n "$vz" ] && [ -n "$va" ]; then
      dz=$((zeilen - vz)); da=$((anw - va))
      [ "$dz" -ge 0 ] && dz="+$dz"
      [ "$da" -ge 0 ] && da="+$da"
      printf 'Dauerkontext: %s -> %s Zeilen (%s) · Anweisungen %s -> %s (%s)\n' \
        "$vz" "$zeilen" "$dz" "$va" "$anw" "$da"
      if [ -n "$vb" ]; then
        db=$((bytes - vb)); [ "$db" -ge 0 ] && db="+$db"
        printf '              %s B (%s B seit dem letzten Lauf)\n' "$bytes" "$db"
      fi
    else
      # ⛔ Ein unparsbarer Vorstand wird als FEHLEND behandelt, nie als "0".
      #    Sonst meldete der naechste Lauf einen Zuwachs von 2570 Zeilen und
      #    jemand suchte eine Ursache, die es nicht gibt.
      printf 'Dauerkontext: %s Zeilen · %s Anweisungen (Vorstand unlesbar — kein Vergleich)\n' \
        "$zeilen" "$anw"
    fi
  elif [ "$modus" = "--vergleichen" ]; then
    printf 'Dauerkontext: %s Zeilen · %s Anweisungen (erster Lauf, kein Vorstand)\n' \
      "$zeilen" "$anw"
  fi

  # ── Merken ─────────────────────────────────────────────────────────────────
  if [ "$modus" = "--merken" ] || [ "$modus" = "--vergleichen" ]; then
    mkdir -p "$(dirname "$stand")" 2>/dev/null
    {
      echo "ZEILEN=$zeilen"
      echo "ANWEISUNGEN=$anw"
      echo "DATEIEN=$dateien"
      echo "BYTES=$bytes"
      echo "TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$stand" 2>/dev/null
  fi
  return 0
}


# --- Schritt-Quittung: fuehrt ein Lauf aus, was in seinem Skill steht? --------
#
# ⛔ WOZU. Gemessen 30.08.2026 am Paket v5.24.0: das Wort PFLICHT steht **67 mal**
#    in den Skills und ist 67 mal Prosa. Eine Schritt-Quittung gab es in 2 von 10
#    Skills; `mind-cleaner` mit 15 Pflichtaufrufen hatte keine einzige.
#
#    Der Anlass ist ein eigener `/mind-cleaner`-Lauf am selben Tag: vollstaendig
#    aussehender Bericht, und dabei `cleaner_audit.py` nie aufgerufen,
#    `cleaner_belege.py` gestartet und die Ausgabe weggegreppt,
#    `cleaner_leitplanke.py` ueber 5 von 11 Dateien als Bereichspruefung berichtet.
#    Der Bericht war nicht falsch — er war unvollstaendig, und das sah man ihm nicht an.
#
# ⭐ DAS VORBILD IST DIE AGENT-QUITTUNG (v5.19.0), die dasselbe Problem eine Ebene
#    tiefer geloest hat. Von dort kommen die drei tragenden Entscheidungen:
#
#    1. Die ERWARTUNG wird VOR dem ersten Schritt gesetzt. Bis v5.18.0 lag die
#       Agent-Quittung im Ausfallpfad: fiel der Schritt aus, fiel die Quittung mit
#       aus — und **ihr Fehlen war von ihrem Schweigen nicht zu unterscheiden**.
#       Wer am Ende zaehlt, zaehlt nur, was gelaufen ist.
#    2. Erwartet wird eine LISTE VON NAMEN, keine Zahl. Nur so kann die Bilanz
#       sagen, WELCHER Schritt fehlt — "3 von 5" schickt niemanden an die richtige
#       Stelle.
#    3. 0 Bytes ist ein ERGEBNIS, kein fehlender Eintrag. Der Unterschied zwischen
#       "lief und lieferte nichts" und "lief nie" ist der ganze Zweck.
#
# ⛔ WAS SIE NICHT KANN. Sie erzwingt keinen Schritt — wie `decision:block` und die
#    Agent-Quittung macht sie das FEHLEN sichtbar. Und sie misst nicht die GUETE:
#    ein Werkzeug, das laeuft und Unsinn liefert, quittiert als `gelaufen`.
#
# Ablage: <projekt>/.claude-mind/schritt-quittung.jsonl

_mind_schritt_pfad() {
  local p="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
  echo "$p/.claude-mind/schritt-quittung.jsonl"
}

# VOR dem ersten Schritt. Namen der Pflichtschritte, durch Leerzeichen getrennt.
# ⛔ Eine LEERE Liste ist gueltig und bedeutet ERWARTET=0 — nicht "keine Quittung".
#    mind-compact und mind-session-log haben null Pflichtaufrufe; sie bekommen
#    trotzdem einen Start-Eintrag. Ein Skill ohne Quittung waere von einem mit
#    vergessener Quittung nicht zu unterscheiden.
mind_schritt_start() {
  local q; q=$(_mind_schritt_pfad "${1:-}")
  local skill="${2:-unbekannt}"; shift 2 2>/dev/null || shift $#
  mkdir -p "$(dirname "$q")" 2>/dev/null || return 1
  : > "$q" || return 1
  printf '{"ereignis":"start","skill":"%s","erwartet":"%s","ts":"%s"}\n' \
    "$skill" "$*" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$q"
}

# NACH jedem Schritt. status = gelaufen | gelaufen:<a>/<b> | uebersprungen:<grund>
#                              | fehler:<grund>
# ⚠ `uebersprungen` ist ein GUELTIGER Status und braucht einen Grund. Ein Schritt,
#   der legitim entfaellt (--dry-run, kein Git, kein Quellbaum), ist kein Fehler —
#   aber sein Entfallen gehoert in den Bericht statt zu verschwinden.
# ⭐ `gelaufen:5/11` ist die TEILABDECKUNG und der eigentliche Anlass dieses Baus:
#   der Fehler war nicht ein fehlender Aufruf, sondern ein gelaufener, der weniger
#   abdeckte als der Bericht behauptete.
mind_schritt() {
  local q; q=$(_mind_schritt_pfad "${4:-}")
  local name="${1:-?}" status="${2:-gelaufen}" bytes="${3:-}"
  case "$bytes" in ''|*[!0-9]*) bytes=-1 ;; esac
  mkdir -p "$(dirname "$q")" 2>/dev/null
  printf '{"ereignis":"schritt","name":"%s","status":"%s","bytes":%s,"ts":"%s"}\n' \
    "$name" "$status" "$bytes" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$q"
}

# Bilanz fuer den Self-Check-Block.
# Zeile 1 (maschinell): ERWARTET=n GELAUFEN=n UEBERSPRUNGEN=n FEHLER=n LEER=n
# danach je Auffaelligkeit eine Zeile.
#
# Rueckgabe: 0 = jeder erwartete Schritt ist quittiert und keiner gescheitert
#            1 = mindestens einer fehlt, scheiterte oder kam leer zurueck
#            2 = GAR KEINE QUITTUNG — der Lauf hat nie begonnen zu quittieren
mind_schritt_bilanz() {
  local q; q=$(_mind_schritt_pfad "${1:-}")
  local erwartet="" n_erw=0 gel=0 ueb=0 feh=0 leer=0
  local zeile name status bytes fehlt="" teil="" ueberliste="" fehlliste="" leerliste=""

  if [ ! -f "$q" ]; then
    echo "ERWARTET=? GELAUFEN=0 UEBERSPRUNGEN=0 FEHLER=0 LEER=0"
    echo "  ⛔ KEINE QUITTUNG — der Lauf hat nie begonnen zu quittieren."
    echo "     Das ist NICHT 'nichts zu melden': mind_schritt_start fehlt."
    return 2
  fi

  erwartet=$(grep -m1 '"ereignis":"start"' "$q" 2>/dev/null \
             | sed 's/.*"erwartet":"\([^"]*\)".*/\1/')
  # ⛔ Merkdatei statt Pipe: eine `while ... | read`-Schleife laeuft in einer
  #    Subshell, und alle Zaehler waeren danach wieder 0. Derselbe Fehler steckt
  #    schon zweimal in dieser Datei (mind_check_tools_have_rules, Step 0 von
  #    mind-all) und ist beide Male teuer gewesen.
  local mt="${TMPDIR:-/tmp}/.mind_schritt_$$"
  grep '"ereignis":"schritt"' "$q" 2>/dev/null > "$mt"

  while IFS= read -r zeile; do
    [ -n "$zeile" ] || continue
    name=$(echo "$zeile"   | sed 's/.*"name":"\([^"]*\)".*/\1/')
    status=$(echo "$zeile" | sed 's/.*"status":"\([^"]*\)".*/\1/')
    bytes=$(echo "$zeile"  | sed 's/.*"bytes":\(-\?[0-9]*\).*/\1/')
    case "$status" in
      uebersprungen*) ueb=$((ueb+1)); ueberliste="$ueberliste $name(${status#uebersprungen:})" ;;
      fehler*)        feh=$((feh+1)); fehlliste="$fehlliste $name(${status#fehler:})" ;;
      gelaufen:*)     gel=$((gel+1)); teil="$teil $name ${status#gelaufen:}" ;;
      *)              gel=$((gel+1)) ;;
    esac
    # 0 Bytes ist ein ERGEBNIS. -1 heisst "nicht gemessen" und zaehlt nicht.
    case "$status" in uebersprungen*) ;; *)
      [ "$bytes" = "0" ] && { leer=$((leer+1)); leerliste="$leerliste $name"; } ;;
    esac
  done < "$mt"

  # Welche erwarteten Namen wurden nie quittiert?
  for name in $erwartet; do
    n_erw=$((n_erw+1))
    grep -q "\"name\":\"$name\"" "$mt" 2>/dev/null || fehlt="$fehlt $name"
  done
  rm -f "$mt"

  echo "ERWARTET=$n_erw GELAUFEN=$gel UEBERSPRUNGEN=$ueb FEHLER=$feh LEER=$leer"
  [ -n "$ueberliste" ] && echo "  UEBERSPRUNGEN:$ueberliste"
  # ⭐ Teilabdeckung ist ein EIGENER Zustand, nicht "gelaufen". 5/11 ist eine
  #    gueltige Antwort; sie als 11/11 zu berichten ist es nicht.
  [ -n "$teil" ] && echo "  TEILABDECKUNG:$teil"
  [ -n "$leerliste" ] && echo "  LEER (lief, gab nichts aus):$leerliste"
  [ -n "$fehlliste" ] && echo "  FEHLER:$fehlliste"
  [ -n "$fehlt" ] && echo "  ⛔ FEHLT:$fehlt"

  [ -z "$fehlt" ] && [ "$feh" -eq 0 ] && [ "$leer" -eq 0 ]
}

# ===== v5.28.0: Plan-Pause — /mind-all schweigt, solange ein Plan laeuft ======
#
# Nutzer-Auftrag 31.08.2026, woertlich: "wenn er einen plan abarbeitet soll er
# kein mind all machen bis der plan durch ist — aber nur bei einem offiziellen
# plan im planmodus, plan.md".
#
# ⛔ DIE SCHULD WIRD NICHT GELOESCHT. Nur der DRUCK pausiert. `OPEN` bleibt
#    liegen, die Rettungsdatei bleibt liegen, `sync-stand` wird nicht gesetzt.
#    Eine Pause, die die Schuld tilgt, waere genau der v5.2.1-Fehler
#    ("PENDING verschwand beim Ankuendigen") in neuer Verkleidung.
#
# ⛔ DER AUSLOESER IST MECHANISCH, DAS ENDE NICHT. `ExitPlanMode` sagt "Plan
#    freigegeben"; NICHTS sagt "Plan fertig". Deshalb sind die drei Ausstiege
#    unten der echte Abbruch und kein Feinschliff — ohne sie fraesse die Pause
#    die Rettung.
#
# ⚠ Warum die Dateizahl KEIN Kriterium ist: `plan.md` liegt in diesem Projekt
#   dauerhaft herum (gemessen 31.08.2026: 10 Plan-Dateien, KEINE mit
#   Checkboxen). "Datei existiert" haette den Sync fuer immer stillgelegt,
#   "offene Checkbox" haette nie gefeuert. Beides waere ein Filter, der sich
#   auf Stille kalibriert (werkzeuge-zuerst.md).

MIND_PLAN_PAUSE_HOURS="${MIND_PLAN_PAUSE_HOURS:-8}"
MIND_PLAN_MAX_COMPACTIONS="${MIND_PLAN_MAX_COMPACTIONS:-2}"

mind_plan_merken() {
  # $1 = Projekt, $2 = Planname (optional)
  local proj="${1:-}" name="${2:-}" d
  [ -n "$proj" ] || return 1
  d="$proj/.claude-mind"
  mkdir -p "$d" 2>/dev/null || return 1
  printf 'ts=%s\nplan=%s\n' "$(date +%s)" "$name" > "$d/PLAN-AKTIV" || return 1
  return 0
}

mind_plan_frei() {
  # Hebt die Pause auf. /mind-all ruft das am Ende auf.
  local proj="${1:-}"
  [ -n "$proj" ] || return 1
  rm -f "$proj/.claude-mind/PLAN-AKTIV" 2>/dev/null
  return 0
}

mind_plan_pause() {
  # -> 0 = PAUSE GILT (schweigen)   1 = keine Pause (normal weiter)
  # Gibt bei aktiver Pause eine Begruendungszeile auf stdout aus.
  #
  # ⛔ FAIL-SAFE-RICHTUNG: alles Unklare heisst KEINE Pause. Ein fehlender,
  #    unlesbarer, unparsbarer oder abgelaufener Merker faellt auf das heutige
  #    Verhalten zurueck. Eine faelschlich ausbleibende Pause kostet eine
  #    Mahnung; eine faelschlich geltende kostet die Rettungsdatei.
  local proj="${1:-}" f ts alter h grenze n plan
  [ -n "$proj" ] || return 1
  f="$proj/.claude-mind/PLAN-AKTIV"
  [ -f "$f" ] || return 1

  ts=$(grep -m1 '^ts=' "$f" 2>/dev/null | cut -d= -f2-)
  case "$ts" in ''|*[!0-9]*) return 1 ;; esac      # unparsbar -> keine Pause
  plan=$(grep -m1 '^plan=' "$f" 2>/dev/null | cut -d= -f2-)

  # --- Ausstieg 1: zu alt ---------------------------------------------------
  alter=$(( $(date +%s) - ts ))
  h="$MIND_PLAN_PAUSE_HOURS"
  case "$h" in ''|*[!0-9]*) h=8 ;; esac
  grenze=$(( h * 3600 ))
  if [ "$alter" -ge "$grenze" ] 2>/dev/null; then
    rm -f "$f" 2>/dev/null
    return 1
  fi

  # --- Ausstieg 2: Kompaktierungen seit Pausenbeginn -------------------------
  # ⛔ Das ist der wichtigere der beiden Ausstiege. Jede Kompaktierung waehrend
  #    der Pause erzeugt eine NEUE Rettungsdatei; ab der zweiten liegen zwei
  #    ungesyncte Staende herum, und die aeltere ist als naechste dran,
  #    wegrotiert zu werden (MIND_RESCUE_KEEP_COUNT). Dann ist die Pause
  #    teurer als der Plan.
  n=0
  for r in "$proj/.claude-mind/rescued"/*_chat.md; do
    [ -f "$r" ] || continue
    [ "$r" -nt "$f" ] && n=$((n+1))
  done
  grenze="$MIND_PLAN_MAX_COMPACTIONS"
  case "$grenze" in ''|*[!0-9]*) grenze=2 ;; esac
  if [ "$n" -ge "$grenze" ] 2>/dev/null; then
    rm -f "$f" 2>/dev/null
    return 1
  fi

  printf 'Plan-Pause aktiv seit %d min%s — %d Kompaktierung(en) seit Beginn (Grenze %d), Ablauf in %d min\n' \
    "$(( alter / 60 ))" "${plan:+ ($plan)}" "$n" "$grenze" "$(( (h * 3600 - alter) / 60 ))"
  return 0
}
