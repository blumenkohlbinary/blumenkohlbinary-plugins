---
name: mind-session-log
description: |
  [Mind Manager] Erzeugt vollstaendiges chronologisches Session-Transkript als
  Markdown-Datei. Liest die aktuelle Claude-Session-JSONL, parst alle Events
  (USER/ASSISTANT/TOOL_USE/TOOL_RESULT) und rendert als lesbares Markdown
  unter .claude-mind/sessions/. Default-Start: ab letztem Slash-Command.

  Use when the user says "session log", "transkript", "log session",
  "mind session log", "logge die session", "session transkript",
  or "/mind-session-log [scope]".
argument-hint: "[komplett|compact|no-truncate|conversation|ab /command]"
context: inherit
allowed-tools: Read Glob Grep Bash Write
---

# Session-Log Generator

Erzeugt chronologisches Transkript der aktuellen Claude-Code-CLI-Session.

## Kompatibilitaet

**Nur Claude Code CLI.** JSONL-Files existieren nur fuer CLI-Sessions, nicht
Claude Desktop. Bei Aufruf in Desktop-Kontext: Skill bricht mit klarer Meldung ab.

**Fuer Claude Desktop User:** Slash-Commands funktionieren generell nicht in
Desktop. Workaround: Conversation manuell exportieren oder Joplin-MCP fuer
Knowledge-Capture nutzen.

## Step 1: Argumente parsen

Check `$ARGUMENTS`. Mehrere Args kombinierbar (z.B. `compact ab /mind-claudemd`):

```bash
ARGS="${ARGUMENTS:-}"
MODE="full"
THEMA=""
START_OVERRIDE=""        # 1 = ab Zeile 1 der JSONL
START_PATTERN=""         # ab letztem Vorkommen dieses Patterns
START_TIMESTAMP=""       # ISO-8601 Timestamp

# Mode-Args
case "$ARGS" in
  *compact*)      MODE="compact" ;;
  *no-truncate*)  MODE="no-truncate" ;;
  *conversation*) MODE="conversation" ;;
esac

# "komplett" -> ab Zeile 1
echo "$ARGS" | grep -q "komplett" && START_OVERRIDE="1"

# "ab /xxx" -> Start ab letztem /xxx
START_PATTERN=$(echo "$ARGS" | grep -oE 'ab /[A-Za-z0-9:_-]+' | sed 's|^ab ||')

# "ab YYYY-MM-DD HH:MM" -> Start ab Timestamp
START_TIMESTAMP=$(echo "$ARGS" | grep -oE 'ab [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' | sed 's|^ab ||')

# Thema (optional, fuer Output-Filename) — alles vor "ab" oder Mode-Args
# Default: aus erstem gefundenen Slash-Command-Namen ableiten
```

**Optionen Uebersicht:**
- Leer -> Default: ab letztem Slash-Command, Full-Dump mit Truncation
- `komplett` -> ab Zeile 1 der JSONL
- `compact` -> Nur Statistik-Summary statt Full-Dump
- `no-truncate` -> Kein 5000-char-Limit
- `conversation` -> Nur USER + ASSISTANT_TEXT, keine Tool-Calls
- `ab /xxx` -> Start ab letztem Vorkommen von `/xxx`
- `ab YYYY-MM-DD HH:MM` -> Start ab Timestamp

## Step 2: JSONL-Datei finden

Slug-Derivation respektiert Windows-Pfad-Format. Claude-Code-CLI legt Sessions
unter `~/.claude/projects/<C--CD-KOHLEKTIV-...>` ab — Drive-Letter `C` GROSS,
fuehrender `C--`, Spaces als `-`, Doppel-Bindestriche fuer ` - `.

```bash
# Slug + Projects-Dir (v3.2.2: zentralisiert in lib.sh)
# hash_project_dir() in lib.sh kapselt cygpath
# M3-Fix: $CLAUDE_PLUGIN_ROOT Guard
if [ -z "$CLAUDE_PLUGIN_ROOT" ] || [ ! -f "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" ]; then
  echo "ERROR: \$CLAUDE_PLUGIN_ROOT nicht gesetzt oder lib.sh nicht gefunden" >&2
  exit 1
fi
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
SLUG=$(hash_project_dir)
PROJECTS_DIR="$HOME/.claude/projects/$SLUG"

# Fallback: wenn Slug-Dir nicht existiert, ls -td neueste Projekt-Dir
if [ ! -d "$PROJECTS_DIR" ]; then
  echo "WARN: Slug-Dir '$PROJECTS_DIR' nicht gefunden, fallback auf neuestes Projekt-Dir"
  PROJECTS_DIR=$(ls -td "$HOME"/.claude/projects/*/ 2>/dev/null | head -1 | sed 's|/$||')
fi

# Neueste JSONL (nicht Subagent-Files):
JSONL=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | grep -v '/subagents/' | head -1)

if [ -z "$JSONL" ]; then
  echo "FEHLER: Keine Session-JSONL gefunden in $PROJECTS_DIR"
  echo "Hinweis: Skill funktioniert nur in Claude Code CLI, nicht Desktop."
  exit 1
fi

echo "JSONL: $JSONL"
```

## Step 3: Start-Zeile bestimmen

JSONL speichert Slash-Commands als `<command-name>/xxx</command-name>` in user-content
(nicht als JSON-Property `"command-name"`). Pattern entsprechend.

```bash
if [ -n "$START_OVERRIDE" ]; then
  START_LINE=1
elif [ -n "$START_PATTERN" ]; then
  # Escape Slashes fuer grep
  PAT=$(echo "$START_PATTERN" | sed 's|/|\\/|g')
  START_LINE=$(grep -n "$PAT" "$JSONL" | tail -1 | cut -d: -f1)
elif [ -n "$START_TIMESTAMP" ]; then
  ISO=$(echo "$START_TIMESTAMP" | sed 's| |T|')
  START_LINE=$(grep -n "\"timestamp\":\"$ISO" "$JSONL" | head -1 | cut -d: -f1)
else
  # Default: letzter Slash-Command (matched <command-name>...</command-name>)
  START_LINE=$(grep -n '<command-name>' "$JSONL" | tail -1 | cut -d: -f1)
fi

# Fallback: kein Slash-Command in Session -> ab Zeile 1
if [ -z "$START_LINE" ]; then START_LINE=1; fi

echo "Start-Zeile: $START_LINE"

# Thema aus letztem Slash-Command ableiten falls nicht aus Args gesetzt
# v3.2.2: jq oder Python-Fallback statt grep — robust gegen lange JSON-Strings.
# Alter Pattern `[^<]+` matched ueber JSON-Inhalt hinaus (Bug aus Session 2026-05-29 Log 3).
if [ -z "$THEMA" ]; then
  CMD=""
  if command -v jq &>/dev/null; then
    # jq-Path: letzte Zeile mit command-name, parse Content, extract command
    CMD=$(grep '<command-name>' "$JSONL" | tail -1 | \
          jq -r '.message.content // ""' 2>/dev/null | \
          grep -oE '<command-name>/[A-Za-z0-9:_-]+' | tail -1 | \
          sed 's|<command-name>/||; s|.*:||')
  fi
  # N1-Fix v3.2.2: Fallthrough zu Python wenn jq fehlte ODER leeres Resultat lieferte
  if [ -z "$CMD" ]; then
    # Python-Fallback (in Datei, kein -c Backtick-Issue)
    cat > /tmp/extract_cmd.py << 'PYEOF'
import json
import sys
import re

last = None  # EC4: explizit initialisieren — kein NameError bei 0 matches

for line in open(sys.argv[1], encoding='utf-8'):
    if '<command-name>' not in line:
        continue
    try:
        obj = json.loads(line)
        content = obj.get('message', {}).get('content', '')
        if not isinstance(content, str):
            continue
        m = re.search(r'<command-name>/([^<]+)</command-name>', content)
        if m:
            last = m.group(1)
    except (json.JSONDecodeError, AttributeError, KeyError):
        continue

if last is not None:
    print(last.split(':')[-1] if ':' in last else last)
else:
    print('session')
PYEOF
    CMD=$(python3 /tmp/extract_cmd.py "$JSONL" 2>/dev/null)
  fi
  THEMA="${CMD:-session}"
fi
```

## Step 4: Slice + Python-Parser

**Path-Cross-Platform-Setup (NEU v3.2.1):** Auf Windows + Git-Bash mit Windows-Python
muss `/tmp/...` zu `C:\Users\...\AppData\Local\Temp\...` konvertiert werden. Sonst
findet Python das Script nicht.

```bash
# Bash-Pfade (fuer Write/Read/awk im Skill — IMMER /tmp/... egal welche Plattform)
SLICE_BASH="/tmp/session-slice.jsonl"
PARSE_BASH="/tmp/parse_session.py"

# Windows-Pfade fuer Python-Aufruf (getrennt von Bash-Pfaden)
# H3-Fix v3.2.2: cygpath als HARD REQUIREMENT statt fragiler Fallback.
# Ohne cygpath war frueheres Verhalten "wishful thinking" — Bash schreibt nach
# msys2 /tmp, Python erwartet $TMP/..., resultierte in empty/missing files.
if ! command -v cygpath &>/dev/null; then
  echo "ERROR: cygpath nicht verfuegbar — mind-session-log benoetigt cygpath" >&2
  echo "Hinweis: Git-Bash / MSYS2 / Cygwin installieren, dann erneut versuchen." >&2
  exit 1
fi

SLICE_WIN=$(cygpath -w "$SLICE_BASH")
PARSE_WIN=$(cygpath -w "$PARSE_BASH")
```

Slice JSONL ab Start-Zeile:

```bash
awk -v start="$START_LINE" 'NR>=start' "$JSONL" > "$SLICE_BASH"
echo "Slice: $(wc -l < "$SLICE_BASH") Zeilen"
```

Python-Script in Datei schreiben — **Heredoc-Pattern (v3.2.2)**, NICHT Write-Tool.

**WICHTIG (Lesson aus Session 2026-05-29 Log 3 Tool 10):** Write-Tool crasht mit
`tool_use_error: File has not been read yet` wenn `/tmp/parse_session.py` aus
früherer Session existiert. Heredoc via Bash umgeht das robust:

```bash
cat > "$PARSE_BASH" << 'PYEOF'
<Python-Code wie unten>
PYEOF
```

Heredoc-Tag `'PYEOF'` (single-quoted) verhindert Shell-Expansion in Python-Code
(`$`, Backticks bleiben literal). Kein `python3 -c` Issue weil Python in eigener
Datei landet. Kein Pre-Read-Overhead, kein Crash bei existing Files.

Python-Code (zwischen `cat > "$PARSE_BASH" << 'PYEOF'` und `PYEOF`):

```python
#!/usr/bin/env python3
"""Session-JSONL -> Markdown Transcript Renderer."""
import json
import sys
from datetime import datetime
from pathlib import Path
from collections import Counter

JSONL_PATH = sys.argv[1]
OUTPUT_PATH = sys.argv[2]
THEMA = sys.argv[3] if len(sys.argv) > 3 else "session"
MODE = sys.argv[4] if len(sys.argv) > 4 else "full"  # full|compact|conversation|no-truncate
TRUNCATE_AT = 0 if MODE == "no-truncate" else 5000


def fmt_ts(iso_ts):
    """ISO-8601 UTC -> lokales YYYY-MM-DD HH:MM:SS."""
    if not iso_ts:
        return ""
    try:
        dt = datetime.fromisoformat(iso_ts.replace('Z', '+00:00'))
        return dt.astimezone().strftime('%Y-%m-%d %H:%M:%S')
    except Exception:
        return iso_ts


def truncate(s, limit=TRUNCATE_AT):
    if not isinstance(s, str):
        s = str(s)
    if limit == 0 or len(s) <= limit:
        return s
    return s[:limit] + f"\n... [truncated, total {len(s)} chars]"


def short_id(tid):
    """toolu_01ABCDEFGHIJ -> toolu_01"""
    return tid[:8] if tid else ""


events = []
errors = 0
session_id = ""
project = ""

with open(JSONL_PATH, 'r', encoding='utf-8') as f:
    for lineno, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            errors += 1
            print(f"WARN line {lineno}: {e}", file=sys.stderr)
            continue

        # Capture session metadata
        if not session_id:
            session_id = obj.get('sessionId', '') or session_id
        if not project:
            project = obj.get('cwd', '') or project

        # Skip noise
        if obj.get('type') == 'queue-operation':
            continue
        if obj.get('isSidechain'):
            continue

        ts = obj.get('timestamp', '')
        msg = obj.get('message', {}) or {}
        content = msg.get('content')

        if obj.get('type') == 'user':
            if isinstance(content, str):
                events.append({'kind': 'USER', 'ts': ts, 'text': content})
            elif isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get('type') == 'tool_result':
                        out = block.get('content', '')
                        if not isinstance(out, str):
                            out = json.dumps(out, ensure_ascii=False)
                        events.append({
                            'kind': 'TOOL_RESULT',
                            'ts': ts,
                            'tool_id': block.get('tool_use_id', ''),
                            'output': out,
                        })

        elif obj.get('type') == 'assistant' and isinstance(content, list):
            for block in content:
                if not isinstance(block, dict):
                    continue
                btype = block.get('type')
                if btype == 'text':
                    events.append({'kind': 'ASSISTANT_TEXT', 'ts': ts, 'text': block.get('text', '')})
                elif btype == 'tool_use':
                    events.append({
                        'kind': 'TOOL_USE',
                        'ts': ts,
                        'tool_id': block.get('id', ''),
                        'name': block.get('name', ''),
                        'input': block.get('input', {}),
                    })
                # type='thinking' wird uebersprungen

# Sort by timestamp (defensiv: leere ts ans Ende, keine Vergleichs-Crashes)
events.sort(key=lambda e: (e.get('ts') or '￿', 0))

# Filter mode=conversation
if MODE == 'conversation':
    events = [e for e in events if e['kind'] in ('USER', 'ASSISTANT_TEXT')]

# Render
out = []
out.append(f"# Session-Transkript - {THEMA}")
out.append("")
out.append(f"**Datum:** {datetime.now().strftime('%Y-%m-%d')}")
out.append(f"**Projekt:** {project}")
out.append(f"**Session-ID:** {session_id}")
out.append(f"**Events:** {len(events)}")
out.append(f"**Quelle:** {JSONL_PATH}")
out.append(f"**Mode:** {MODE}")
if errors:
    out.append(f"**Parse-Errors:** {errors} (siehe stderr)")
out.append("")
out.append("---")
out.append("")

if MODE == 'compact':
    stats = Counter(e['kind'] for e in events)
    tool_stats = Counter(e['name'] for e in events if e['kind'] == 'TOOL_USE')
    out.append("## Statistik")
    out.append("")
    for k, v in stats.most_common():
        out.append(f"- **{k}:** {v}")
    out.append("")
    if tool_stats:
        out.append("### Tool-Calls")
        for n, v in tool_stats.most_common():
            out.append(f"- {n}: {v}")
else:
    for i, e in enumerate(events, 1):
        kind = e['kind']
        ts_local = fmt_ts(e['ts'])
        out.append(f"## [{i}] {kind} - {ts_local}")
        out.append("")
        if kind == 'USER':
            out.append("```text")
            out.append(truncate(e.get('text', '')))
            out.append("```")
        elif kind == 'ASSISTANT_TEXT':
            out.append(truncate(e.get('text', '')))
        elif kind == 'TOOL_USE':
            out.append(f"**Tool-ID:** {short_id(e.get('tool_id', ''))}")
            out.append(f"**Tool:** `{e.get('name', '')}`")
            out.append("")
            out.append("**Input:**")
            out.append("```json")
            out.append(truncate(json.dumps(e.get('input', {}), indent=2, ensure_ascii=False)))
            out.append("```")
        elif kind == 'TOOL_RESULT':
            out.append(f"**fuer Tool-ID:** {short_id(e.get('tool_id', ''))}")
            out.append("")
            out.append("**Output:**")
            out.append("```")
            out.append(truncate(e.get('output', '')))
            out.append("```")
        out.append("")

# Write UTF-8 ohne BOM
Path(OUTPUT_PATH).write_text('\n'.join(out), encoding='utf-8')
print(f"OK: {len(events)} events -> {OUTPUT_PATH}")
```

## Step 5: Aufruf + Verifikation

```bash
# Datum + Thema fuer Output-Pfad — Mode-aware Suffix
DATE=$(date +%Y-%m-%d)
THEMA="${THEMA:-session}"  # aus Step 3 oder Default
MODE="${MODE:-full}"

# Suffix matched MODE: full -> _full.md, compact -> _compact.md, etc.
case "$MODE" in
  conversation) SUFFIX="conv" ;;
  no-truncate)  SUFFIX="full-notrunc" ;;
  compact)      SUFFIX="compact" ;;
  *)            SUFFIX="full" ;;
esac
OUTPUT=".claude-mind/sessions/${DATE}_${THEMA}_${SUFFIX}.md"

mkdir -p ".claude-mind/sessions"

# Output auch fuer Python-Aufruf konvertieren (relative Pfade sind safe,
# absolute via cygpath konvertieren)
if command -v cygpath &>/dev/null; then
  OUTPUT_WIN=$(cygpath -w "$(realpath "$OUTPUT" 2>/dev/null || echo "$PWD/$OUTPUT")")
else
  OUTPUT_WIN="$OUTPUT"
fi

# Aufruf (probiere .venv, dann python3, dann python):
if [ -x ".venv/Scripts/python.exe" ]; then
  PYTHON=".venv/Scripts/python.exe"
elif command -v python3 &>/dev/null; then
  PYTHON="python3"
else
  PYTHON="python"
fi

# WICHTIG: Windows-Pfade an Python uebergeben (cygpath-konvertiert in Step 4)
"$PYTHON" "$PARSE_WIN" "$SLICE_WIN" "$OUTPUT_WIN" "$THEMA" "$MODE"

# Verifikation (im Chat, NICHT in Output-Datei):
echo "=== Bilanz ==="
echo "Datei: $OUTPUT"
echo "Groesse: $(wc -c < "$OUTPUT") bytes"
echo "Zeilen: $(wc -l < "$OUTPUT")"
echo "Events: $(grep -c '^## \[' "$OUTPUT")"
echo ""
echo "Tool-Statistik:"
grep -oE '\*\*Tool:\*\* `[A-Za-z_]+`' "$OUTPUT" | sort | uniq -c | sort -rn
```

## Hard Constraints

- Output-Encoding: UTF-8 OHNE BOM (encoding='utf-8' in Python, kein 'utf-8-sig')
- Truncation NUR mit `[truncated, total N chars]` Marker, hart bei 5000 chars
- KEINE Interpretation oder Zusammenfassung — Tool-Inputs/Outputs 1:1
- Thinking-Blocks werden NICHT geloggt (privacy + signal-to-noise)
- Subagent-Sidechains (`isSidechain==true`) werden gefiltert
- Bei JSON-Parse-Error: skip Zeile, count in Header dokumentieren, NIEMALS abbrechen
- Bilanz-Statistik geht NUR in Chat-Output, NICHT in die Datei
- Skill funktioniert NUR in Claude Code CLI — bei fehlender JSONL klar abbrechen
- Output-Pfad respektiert `.claude-mind/sessions/` Convention
- Output-Filename matched MODE (`_full`/`_compact`/`_conv`/`_full-notrunc`)
- Slug-Derivation per `cygpath` mit Fallback auf neuestes Projekt-Dir (mtime)
- **Path-Cross-Platform (v3.2.1):** Bash-Pfade (`/tmp/...`) NUR fuer Write/Bash-Operations.
  Fuer Python-Aufruf IMMER Windows-Pfade via `cygpath -w` konvertieren — sonst findet
  Windows-Python das Script nicht (echtes Bug aus Session 2026-05-05).
