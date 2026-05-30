---
name: mind-compact
description: |
  [Mind Manager] Generiert eine /compact-Vorlage fuer Claude Code mit 4
  Erhaltungs-Kategorien (Architektonische Entscheidungen, Aktive Bugs,
  Geaenderte Dateien, Aktive Constraints) aus der laufenden Session.
  User kopiert Vorlage und ruft selbst /compact <text> auf.

  Use when the user says "mind compact", "compact prep", "compact vorlage",
  "vorlage fuer compact", "compact prepare",
  or "/mind-compact".
argument-hint: ""
context: inherit
allowed-tools: Read Glob Grep Edit Bash
---

# /compact Vorlage-Generator

Erzeugt eine 4-Kategorie-Vorlage fuer Claude Codes `/compact`-Befehl aus der
laufenden Session. Heuristik-basiert — User korrigiert die Vorlage VOR `/compact`.

## Kompatibilitaet

**Nur Claude Code CLI.** Liest die Session-JSONL aus
`~/.claude/projects/<slug>/<session-id>.jsonl`. Diese Datei existiert nur fuer
CLI-Sessions, nicht Claude Desktop.

Bei Aufruf in Desktop-Kontext: Skill bricht mit klarer Meldung ab.

## Step 1: JSONL finden (gleicher Code wie mind-session-log Step 2)

```bash
# Slug + Projects-Dir (v3.2.2: zentralisiert in lib.sh)
if [ -z "$CLAUDE_PLUGIN_ROOT" ] || [ ! -f "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" ]; then
  echo "ERROR: \$CLAUDE_PLUGIN_ROOT nicht gesetzt oder lib.sh nicht gefunden" >&2
  exit 1
fi
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
SLUG=$(hash_project_dir)
PROJECTS_DIR="$HOME/.claude/projects/$SLUG"

# Fallback: wenn Slug-Dir nicht existiert, neuestes Projekt-Dir
if [ ! -d "$PROJECTS_DIR" ]; then
  echo "WARN: Slug-Dir nicht gefunden, fallback auf neuestes Projekt-Dir"
  PROJECTS_DIR=$(ls -td "$HOME"/.claude/projects/*/ 2>/dev/null | head -1 | sed 's|/$||')
fi

# Neueste JSONL (nicht Subagent-Files)
JSONL=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | grep -v '/subagents/' | head -1)

if [ -z "$JSONL" ]; then
  echo "FEHLER: Keine Session-JSONL gefunden in $PROJECTS_DIR"
  echo "Hinweis: Skill funktioniert nur in Claude Code CLI, nicht Desktop."
  exit 1
fi

echo "JSONL: $JSONL"
```

## Step 2: Args parsen

```bash
# v3.3.0: keine Args definiert (--save-to-claudemd in v3.3.1 geplant, siehe Step 6)
# Skill akzeptiert beliebige Args ohne Verarbeitung — defensive
ARGS="${ARGUMENTS:-}"
```

## Step 3: Python-Extraktor schreiben (Heredoc, NICHT Write-Tool)

**Lesson v3.2.2:** Write-Tool crasht bei existierender `/tmp/`-Datei. Heredoc via Bash umgeht das.

**Path-Setup (cygpath Hard Requirement):**

```bash
if ! command -v cygpath &>/dev/null; then
  echo "ERROR: cygpath nicht verfuegbar — mind-compact benoetigt cygpath" >&2
  echo "Hinweis: Git-Bash / MSYS2 / Cygwin installieren, dann erneut versuchen." >&2
  exit 1
fi

EXTRACT_BASH="/tmp/mind_compact_extract.py"
EXTRACT_WIN=$(cygpath -w "$EXTRACT_BASH")
JSONL_WIN=$(cygpath -w "$JSONL")

# Output-Datei fuer JSON-Zwischenergebnis
EXTRACT_JSON_BASH="/tmp/mind_compact_data.json"
EXTRACT_JSON_WIN=$(cygpath -w "$EXTRACT_JSON_BASH")
```

```bash
cat > "$EXTRACT_BASH" << 'PYEOF'
#!/usr/bin/env python3
"""mind-compact: Extrahiere 4-Kategorie-Vorlage aus Session-JSONL.

Self-Exclusion (Plan-EC6 + A12): letzter <command-name>/mind-compact Marker
= aktueller Run. Skip alle Events ab dieser Zeile bis EOF — fruehere
mind-compact-Runs bleiben Teil der Session-History.
"""
import json
import re
import sys
from pathlib import Path

JSONL_PATH = sys.argv[1]
OUT_PATH = sys.argv[2]

# Top-N pro Kategorie (Default 10, bei langer Session reduziert)
TOP_N = 10
LONG_SESSION_TOP_N = 5
LONG_SESSION_THRESHOLD = 500  # >500 Events -> reduzieren

# Self-Exclusion Regex (namespace-tolerant)
SELF_PATTERN = re.compile(r'<command-name>/(?:[^/<]+:)?mind-compact</command-name>')

# Pattern-Klassifikation (User-Feedback EC2: False-Positive-Mitigation)
DECISION_PATTERNS_ASSISTANT = [
    re.compile(r'\bdecision\s*:', re.IGNORECASE),
    re.compile(r'\barchitekt(?:ur)?\b', re.IGNORECASE),
    re.compile(r'\bpattern\s*:', re.IGNORECASE),
    re.compile(r'\bwir\s+(?:entscheiden|nehmen\s+.{0,30}\s+statt|nutzen\s+.{0,30}\s+statt)', re.IGNORECASE),
    re.compile(r'\binstead\s+of\b', re.IGNORECASE),
    re.compile(r'\bwir\s+machen\s+.{0,40}?\b(?:weil|because|denn)\b', re.IGNORECASE),
    re.compile(r'\bentschieden\s*:', re.IGNORECASE),
]

BUG_PATTERNS = [
    re.compile(r'tool_use_error', re.IGNORECASE),
    re.compile(r'\bcancelled\s*:', re.IGNORECASE),
    re.compile(r'\bcrash(?:ed|t)?\b', re.IGNORECASE),
    re.compile(r'\bfix\s*:', re.IGNORECASE),
    re.compile(r'\bbug\s+#\d+', re.IGNORECASE),
    re.compile(r'\berror\s*:\s', re.IGNORECASE),
    re.compile(r'\bfailed\s*:', re.IGNORECASE),
    re.compile(r'Traceback', re.IGNORECASE),
]

# Constraints: NUR USER, mind. 10 Zeichen Kontext-Match
CONSTRAINT_PATTERNS_USER = [
    re.compile(r'\bMUST\b.{10,}', re.IGNORECASE),
    re.compile(r'\bNEVER\b.{10,}', re.IGNORECASE),
    re.compile(r'\bniemals\b.{10,}', re.IGNORECASE),
    re.compile(r'\bimmer\b.{10,}', re.IGNORECASE),
    re.compile(r'\bwichtig\b.{10,}', re.IGNORECASE),
    re.compile(r'\bkein(?:e[rn]?)?\s+push\b', re.IGNORECASE),
    re.compile(r'\bnicht\s+.{0,30}(?:committen|pushen|loeschen|ueberschreiben)', re.IGNORECASE),
]

# Step 1: Self-Exclusion-Marker finden (letzter mind-compact)
EXCLUDE_FROM_LINE = None
for lineno, line in enumerate(open(JSONL_PATH, encoding='utf-8'), 1):
    if SELF_PATTERN.search(line):
        EXCLUDE_FROM_LINE = lineno  # ueberschreiben -> letzter bleibt

if EXCLUDE_FROM_LINE:
    print(f"INFO: Self-Exclusion ab Zeile {EXCLUDE_FROM_LINE}", file=sys.stderr)

# Step 2: Events sammeln (USER + ASSISTANT_TEXT + TOOL_USE inputs)
total_events = 0
parse_errors = 0
user_texts = []        # (line_no, text)
assistant_texts = []   # (line_no, text)
modified_files = set() # alle Write/Edit/NotebookEdit file_paths

with open(JSONL_PATH, 'r', encoding='utf-8') as f:
    for lineno, line in enumerate(f, 1):
        # Self-Exclusion: skip aktuelle Range
        if EXCLUDE_FROM_LINE and lineno >= EXCLUDE_FROM_LINE:
            continue
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            parse_errors += 1
            continue

        # Skip Sidechains + Queue-Operations
        if obj.get('isSidechain'):
            continue
        if obj.get('type') == 'queue-operation':
            continue

        msg = obj.get('message', {}) or {}
        content = msg.get('content')

        if obj.get('type') == 'user' and isinstance(content, str):
            user_texts.append((lineno, content))
            total_events += 1
        elif obj.get('type') == 'assistant' and isinstance(content, list):
            for block in content:
                if not isinstance(block, dict):
                    continue
                btype = block.get('type')
                if btype == 'text':
                    assistant_texts.append((lineno, block.get('text', '')))
                    total_events += 1
                elif btype == 'tool_use':
                    name = block.get('name', '')
                    if name in ('Write', 'Edit', 'NotebookEdit'):
                        inp = block.get('input', {})
                        if isinstance(inp, dict):
                            fp = inp.get('file_path') or inp.get('notebook_path')
                            if fp:
                                modified_files.add(fp)

# Step 3: Top-N je nach Session-Laenge (EC2: lange Sessions)
top_n = LONG_SESSION_TOP_N if total_events > LONG_SESSION_THRESHOLD else TOP_N

# Step 4: Klassifikation
def classify_decisions():
    """Architektonische Entscheidungen — nur ASSISTANT_TEXT."""
    matches = []
    for (lineno, text) in assistant_texts:
        for p in DECISION_PATTERNS_ASSISTANT:
            m = p.search(text)
            if m:
                # Kontext: bis 200 chars um Match
                start = max(0, m.start() - 50)
                end = min(len(text), m.end() + 150)
                snippet = text[start:end].replace('\n', ' ').strip()
                matches.append((lineno, snippet[:200]))
                break  # 1 Match pro Event reicht
    # Deterministic: sort by line_no desc (letzte zuerst)
    matches.sort(key=lambda x: -x[0])
    return matches[:top_n], len(matches)

def classify_bugs():
    """Aktive Bugs — beide Quellen."""
    matches = []
    all_texts = [('U', l, t) for (l, t) in user_texts] + \
                [('A', l, t) for (l, t) in assistant_texts]
    for (src, lineno, text) in all_texts:
        for p in BUG_PATTERNS:
            m = p.search(text)
            if m:
                start = max(0, m.start() - 30)
                end = min(len(text), m.end() + 120)
                snippet = text[start:end].replace('\n', ' ').strip()
                matches.append((lineno, snippet[:180], src))
                break
    matches.sort(key=lambda x: -x[0])
    return matches[:top_n], len(matches)

def classify_constraints():
    """User-Constraints — nur USER."""
    matches = []
    for (lineno, text) in user_texts:
        for p in CONSTRAINT_PATTERNS_USER:
            m = p.search(text)
            if m:
                start = max(0, m.start() - 20)
                end = min(len(text), m.end() + 80)
                snippet = text[start:end].replace('\n', ' ').strip()
                matches.append((lineno, snippet[:160]))
                break
    matches.sort(key=lambda x: -x[0])
    return matches[:top_n], len(matches)

decisions, dec_total = classify_decisions()
bugs, bug_total = classify_bugs()
constraints, con_total = classify_constraints()
files_list = sorted(modified_files)[:top_n*3]  # mehr Files erlaubt
files_total = len(modified_files)

# Step 5: JSON-Output (Skill rendert finalen Markdown-Block)
result = {
    "total_events": total_events,
    "parse_errors": parse_errors,
    "self_exclusion_line": EXCLUDE_FROM_LINE,
    "top_n": top_n,
    "long_session": total_events > LONG_SESSION_THRESHOLD,
    "decisions": [{"line": l, "text": t} for (l, t) in decisions],
    "decisions_total": dec_total,
    "bugs": [{"line": l, "text": t, "src": s} for (l, t, s) in bugs],
    "bugs_total": bug_total,
    "files": files_list,
    "files_total": files_total,
    "constraints": [{"line": l, "text": t} for (l, t) in constraints],
    "constraints_total": con_total,
}

Path(OUT_PATH).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(f"OK: {total_events} events processed -> {OUT_PATH}")
PYEOF
```

## Step 4: Python-Extraktor aufrufen

```bash
# Python-Path-Detection
if [ -x ".venv/Scripts/python.exe" ]; then
  PYTHON=".venv/Scripts/python.exe"
elif command -v python3 &>/dev/null; then
  PYTHON="python3"
else
  PYTHON="python"
fi

# Aufruf
"$PYTHON" "$EXTRACT_WIN" "$JSONL_WIN" "$EXTRACT_JSON_WIN"

if [ ! -s "$EXTRACT_JSON_BASH" ]; then
  echo "FEHLER: Python-Extraktion fehlgeschlagen — keine JSON-Daten produziert" >&2
  exit 1
fi
```

## Step 5: Vorlage rendern (Markdown-Block fuer User-Copy)

```bash
RENDER_BASH="/tmp/mind_compact_render.py"
RENDER_WIN=$(cygpath -w "$RENDER_BASH")

cat > "$RENDER_BASH" << 'PYEOF'
#!/usr/bin/env python3
"""Render JSON-Daten als kopierbaren /compact-Block."""
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))

print("=== /compact Vorlage (kopieren und einfuegen) ===")
print()
print("/compact Keep the following:")
print()

# Architektonische Entscheidungen
print("## Architektonische Entscheidungen")
if data['decisions']:
    for d in data['decisions']:
        print(f"- {d['text']}")
    if data['decisions_total'] > data['top_n']:
        print(f"- _... {data['decisions_total'] - len(data['decisions'])} weitere ausgeblendet_")
else:
    print("- (keine erkannt)")
print()

# Aktive Bugs
print("## Aktive Bugs / Fehlermeldungen")
if data['bugs']:
    for b in data['bugs']:
        src = "U" if b['src'] == 'U' else "A"
        print(f"- [{src}] {b['text']}")
    if data['bugs_total'] > data['top_n']:
        print(f"- _... {data['bugs_total'] - len(data['bugs'])} weitere ausgeblendet_")
else:
    print("- (keine erkannt)")
print()

# Geaenderte Dateien
print("## Geaenderte Dateien")
if data['files']:
    for f in data['files']:
        print(f"- {f}")
    if data['files_total'] > len(data['files']):
        print(f"- _... {data['files_total'] - len(data['files'])} weitere ausgeblendet_")
else:
    print("- (keine erkannt)")
print()

# Aktive Constraints
print("## Aktive Constraints")
if data['constraints']:
    for c in data['constraints']:
        print(f"- {c['text']}")
    if data['constraints_total'] > data['top_n']:
        print(f"- _... {data['constraints_total'] - len(data['constraints'])} weitere ausgeblendet_")
else:
    print("- (keine erkannt)")

print()
print("=== Ende Vorlage ===")
print()
print(f"Events analysiert: {data['total_events']}", end="")
if data['parse_errors']:
    print(f" (Parse-Errors: {data['parse_errors']})", end="")
if data['long_session']:
    print(f" — LANGE SESSION (>500 Events), Top-N auf {data['top_n']} reduziert", end="")
print()
if data['self_exclusion_line']:
    print(f"Self-Exclusion: ab JSONL-Zeile {data['self_exclusion_line']}")
print()
print("**Hinweis:** Vorlage ist Heuristik-basiert. Bitte VOR /compact lesen und ggf. Bullets")
print("entfernen die nicht relevant sind oder ergaenzen die fehlen. Skill ist Assistent,")
print("kein Auto-Klassifizierer — User hat finale Kontrolle.")
PYEOF

"$PYTHON" "$RENDER_WIN" "$EXTRACT_JSON_WIN"
```

## Step 6 (optional, Skill-Review M8): CLAUDE.md `# Compact instructions` Block

**v3.3.0 STATUS:** Skill bietet KEINEN Auto-Save in CLAUDE.md. Grund: ungefilterter
Heuristik-Output in CLAUDE.md zu schreiben widerspricht "User-Direktive E: User
hat finale Kontrolle, Skill ist Assistent kein Auto-Klassifizierer".

**Stattdessen — User-Interaktion:** Nach Vorlage im Chat kann User sagen:
> "Speichere folgende Bullets dauerhaft in CLAUDE.md '# Compact instructions':
>  - <Bullet 1>
>  - <Bullet 2>"

Claude kuratiert dann manuell + nutzt Pre-Edit-Read pattern fuer den Edit.

**TODO v3.3.1 oder spaeter:** Interaktiver Curate-Modus implementieren — Skill
zeigt nummerierte Liste, User antwortet `1,3,5` zur Auswahl, Skill schreibt diese
Subset in CLAUDE.md.

## Hard Constraints

- **Nur Claude Code CLI** — JSONL-Files existieren nicht in Claude Desktop
- **Self-Exclusion (Plan EC6 + A12):** Letzter `<command-name>/mind-compact` Marker = aktueller Run, skip ab dieser Zeile bis EOF. Regex tolerant gegen Namespace-Variation
- **False-Positive-Mitigation (Plan EC2):** Pattern-spezifische Filter (DECISION nur ASSISTANT, CONSTRAINTS nur USER mit 10+ Zeichen Kontext, BUGS nur mit konkreten Markern)
- **Deterministic Top-N:** sortiert nach line_no desc, bei >N Matches Hinweis "_... N weitere ausgeblendet_"
- **Lange Session (>500 Events):** Top-N auf 5 reduziert (sonst Vorlage unhandlich)
- **KEIN Auto-`/compact`-Aufruf** — User kopiert Vorlage und ruft selbst auf (Direktive E)
- **KEIN Auto-Edit auf CLAUDE.md** — auch bei `--save-to-claudemd` nur Hinweis, User muss explizit kuratieren (Heuristik-Output ungefiltert in CLAUDE.md = Anti-Pattern)
- **User-Disclaimer im Output:** "Heuristik-basiert, bitte pruefen" — finale Kontrolle beim User
- **Heredoc statt Write-Tool** fuer `/tmp/`-Python-Files (Lesson v3.2.2)
- **cygpath Hard Requirement** auf Windows (Pattern v3.2.2)
- **`$CLAUDE_PLUGIN_ROOT` Guard** vor `source lib.sh`
