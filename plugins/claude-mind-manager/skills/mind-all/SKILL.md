---
name: mind-all
description: |
  [Mind Manager] Fuehrt ALLE Context-Management-Commands autonom nacheinander aus:
  mind-files -> mind-claudemd -> mind-memory -> mind-rules -> mind-update.
  Alle gefundenen Befunde werden automatisch angewendet (ausser DESIGN), ein
  gemeinsamer Snapshot macht den ganzen Durchlauf als EINE Einheit rueckholbar,
  am Ende steht EIN konsolidierter Bericht.

  Use when the user says "mind all", "alles pruefen", "kompletter context-sweep",
  "fuehre alle mind commands aus", "context komplett aktualisieren",
  or "/mind-all [--ask|--dry-run]".
argument-hint: "[--ask|--dry-run]"
context: inherit
allowed-tools: Read Glob Grep Edit Write Bash Agent
---

# Alle Context-Commands autonom nacheinander

Ein Snapshot -> 5 Skills sequenziell -> alle Befunde angewendet -> ein Bericht.

## Step 0: Modus + EIN Snapshot fuer den ganzen Durchlauf (PFLICHT)

```bash
ARGS="${ARGUMENTS:-}"; AUTO_MODE="yes"; DRY_RUN="no"
echo "$ARGS" | grep -qE '(^|[[:space:]])--(ask|interactive)([[:space:]]|$)' && AUTO_MODE="no"
echo "$ARGS" | grep -qE '(^|[[:space:]])--dry-run([[:space:]]|$)' && { DRY_RUN="yes"; AUTO_MODE="no"; }

[ -z "$CLAUDE_PLUGIN_ROOT" ] && { echo "ERROR: \$CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 1; }
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
PROJ="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if [ "$DRY_RUN" = "no" ]; then
  SNAPSHOT=$(mind_snapshot "$PROJ" "pre-mind-all") || {
    echo "ABBRUCH: Snapshot fehlgeschlagen — KEIN Skill wird gestartet." >&2; exit 1; }
  echo "Snapshot fuer den gesamten Durchlauf: $SNAPSHOT"
fi

# Scope-Dedup-Marke fuer diesen Lauf zuruecksetzen (Befund 5)
SCOPES_FILE="$PROJ/.claude-mind/analyzed-scopes"
mkdir -p "$(dirname "$SCOPES_FILE")"; : > "$SCOPES_FILE"
echo "run_started=$(date +%Y%m%d_%H%M%S)" >> "$SCOPES_FILE"
```

**EIN Snapshot fuer alle 5** — nicht fuenf einzelne. Damit ist der komplette Durchlauf als
eine Einheit zurueckrollbar. Die Einzel-Skills erkennen den laufenden `/mind-all` an der
`analyzed-scopes`-Datei und legen **keinen** zweiten Snapshot an.

**Schlaegt der Snapshot fehl: kein einziger Skill startet.**

## Step 1: Reihenfolge (fest, begruendet)

| # | Skill | Warum an dieser Stelle |
|---|---|---|
| 1 | `mind-files` | Legt fehlende Context-Dateien ueberhaupt erst an — die folgenden koennen nur auditieren, was existiert |
| 2 | `mind-claudemd` | CLAUDE.md ist die Wurzel; Version/Struktur muss stimmen, bevor andere darauf verweisen |
| 3 | `mind-memory` | MEMORY.md + Topic-Files, haeufig Ziel von claude-md-Auslagerungen |
| 4 | `mind-rules` | Rules-Syntax/-Inhalt, oft Ziel von Modularisierungen aus Schritt 2 |
| 5 | `mind-update` | **Zuletzt** — der uebergreifende Sweep + Knowledge-Sync; profitiert davon, dass 1-4 sauber sind, und deckt den Rest ab |

**Strikt sequenziell.** Nie zwei Skills gleichzeitig, nie ein Skill parallel zu Agents eines
anderen (Anti-Burst-Regel `~/.claude/rules/workflow-agent-rate-limit.md`: nie ≥3 Agents
gleichzeitig; innerhalb eines Skills gilt dessen eigene Grenze).

## Step 2: Ausfuehrung je Skill

Fuer jeden der 5 in der Reihenfolge oben:

1. **Skill-Logik ausfuehren** wie in seiner `SKILL.md` beschrieben — mit den durchgereichten
   Flags (`AUTO_MODE`/`DRY_RUN`). Kein erneuter Snapshot (Step 0 hat ihn).
2. **Scope-Marke schreiben**, sobald ein Skill einen Bereich semantisch analysiert hat:
   ```bash
   echo "claude-md=mind-claudemd" >> "$SCOPES_FILE"   # nach mind-claudemd
   echo "memory=mind-memory"     >> "$SCOPES_FILE"   # nach mind-memory
   echo "rules=mind-rules"       >> "$SCOPES_FILE"   # nach mind-rules
   ```
3. **Ergebnis sammeln** (angewendet / DESIGN / offen / Fehler) fuer den Schlussbericht.

**Scope-Dedup in Schritt 5 (Befund 5, spart ~50 % der Subagent-Token):**
`mind-update` Step 3.5 liest `analyzed-scopes` und **ueberspringt** jeden dort eingetragenen
Scope. Im Self-Check erscheint dann statt eines Dispatches:
`scope=claude-md → bereits durch mind-claudemd abgedeckt (analyzed-scopes)`.
Der Scope `custom-context` ist nie abgedeckt und laeuft immer.

**Fehler-Verhalten:** Scheitert ein Skill, laufen die **restlichen weiter**. Der Fehler kommt
in den Schlussbericht (`FEHLGESCHLAGEN: <skill> — <grund>`). Ein toter Skill darf die Kette
nicht killen — sonst bleibt der Context halb aktualisiert zurueck.

## Step 3: Konsolidierter Schlussbericht (PFLICHT)

```
=== /mind-all — Durchlauf abgeschlossen ===
Modus: autonom | --ask | --dry-run
Snapshot: <pfad>   (Restore: cp -r "<pfad>"/* zurueck; MANIFEST.sha256 zum Verifizieren)

| # | Skill          | Status | Angewendet | Offen/DESIGN | Fehler |
|---|----------------|--------|-----------|--------------|--------|
| 1 | mind-files     | OK     | 2         | 1 (Tool-Bundle) | — |
| 2 | mind-claudemd  | OK     | 5         | 0            | — |
| 3 | mind-memory    | OK     | 1         | 0            | — |
| 4 | mind-rules     | OK     | 0         | 0            | — |
| 5 | mind-update    | OK     | 7         | 2 (DESIGN)   | — |

Angewendet gesamt: <N> Aenderungen in <M> Dateien
  <datei:zeile>  <vorher> -> <nachher>
  ... (jede Aenderung einzeln; geloeschte Zeilen WOERTLICH als "Entfernt: <zeile>")

NICHT angewendet (bewusst):
  [DESIGN]  <datei:zeile> — Regel "<marker>" sagt: nicht anfassen
  [OFFEN]   <was> — <grund> (z.B. Overwrite-Guard, Tool-Bundle-Angebot, >5 DEAD-Pfade)

Scope-Dedup: <k> Agent-Dispatches gespart (bereits abgedeckte Scopes)
```

**Der Bericht ist die einzige Stelle, an der du siehst was passiert ist** — deshalb luegt er
nicht: jede Aenderung einzeln, jede Auslassung mit Grund, Snapshot-Pfad immer dabei.

## Hard Constraints

- **EIN `mind_snapshot` vor dem ersten Skill; Fehlschlag = kein Skill startet.**
- **Strikt sequenziell** — nie zwei Skills gleichzeitig (Anti-Burst).
- **Reihenfolge ist fest:** files → claudemd → memory → rules → update.
- **DESIGN-Befunde werden nie automatisch angewendet** (in keinem der 5).
- **Overwrite-Guards und Tool-Bundle-Angebote aus mind-files bleiben aktiv** — Autonomie
  erzeugt keine Ausnahme fuer fremden Bestand.
- **>5 DEAD-Pfade** in mind-update bleiben gesperrt (Massenloesch-Sicherung).
- **Ein gescheiterter Skill stoppt die Kette nicht** — Fehler in den Schlussbericht.
- **Kein `git commit`/`git push`** — `/mind-all` aendert Context-Dateien, nicht die Historie.
