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

## Step 3: Ausgelieferten Extraktor benutzen (v5.6.0 — KEIN Heredoc mehr)

⛔ **Hier stand bis v5.5.2 ein Heredoc**, der den Extraktor zur Laufzeit nach `/tmp`
schrieb — mit der Begruendung *„Lesson v3.2.2: Write-Tool crasht bei existierender
`/tmp`-Datei“*. Diese Begruendung war **gegenlaeufig zu Befund 9** (v5.0.0), der genau
diesen Weg fuer `session_sampler.py` bereits als Windows-fragil verworfen hatte (Pfade mit
`&`, Leerzeichen, Umlauten). Das Plugin widersprach sich damit an zwei Stellen selbst.

**Seit v5.6.0** liefert `references/session_sampler.py` den Modus `--arbeitsstand` mit
**byte-gleicher** Ausgabe. Belegt: Byte-Diff gegen die alte Heredoc-Fassung ueber drei
echte Transkripte (287 / 9 062 / 4 587 Bytes, alle identisch).

**Path-Setup (cygpath Hard Requirement):**

```bash
if ! command -v cygpath &>/dev/null; then
  echo "ERROR: cygpath nicht verfuegbar — mind-compact benoetigt cygpath" >&2
  echo "Hinweis: Git-Bash / MSYS2 / Cygwin installieren, dann erneut versuchen." >&2
  exit 1
fi

# v5.6.0: ausgelieferte Datei statt /tmp-Heredoc (Befund 9)
SAMPLER_BASH="$CLAUDE_PLUGIN_ROOT/references/session_sampler.py"
[ -f "$SAMPLER_BASH" ] || { echo "ERROR: session_sampler.py fehlt: $SAMPLER_BASH" >&2; exit 1; }
SAMPLER_WIN=$(cygpath -w "$SAMPLER_BASH")
JSONL_WIN=$(cygpath -w "$JSONL")

# Output-Datei fuer JSON-Zwischenergebnis
EXTRACT_JSON_BASH="/tmp/mind_compact_data.json"
EXTRACT_JSON_WIN=$(cygpath -w "$EXTRACT_JSON_BASH")
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
"$PYTHON" "$SAMPLER_WIN" --arbeitsstand "$JSONL_WIN" "$EXTRACT_JSON_WIN" mind-compact

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
- **Extraktor kommt aus der ausgelieferten Datei** (`references/session_sampler.py --arbeitsstand`), NICHT aus einem `/tmp`-Heredoc — Befund 9, v5.6.0. Der **Renderer** ist noch einer; das ist ein offener Punkt, kein Vorbild
- **cygpath Hard Requirement** auf Windows (Pattern v3.2.2)
- **`$CLAUDE_PLUGIN_ROOT` Guard** vor `source lib.sh`
