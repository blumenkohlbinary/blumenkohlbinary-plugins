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

# Kettenmarke — NUR wenn ein Snapshot existiert (C2-Fix: im Probelauf keine Marke,
# sonst behauptet sie ein Netz, das es nicht gibt). Enthaelt den Snapshot-PFAD, damit die
# Einzel-Skills pruefen koennen ob er wirklich da ist.
SCOPES_FILE="$PROJ/.claude-mind/analyzed-scopes"
if [ "$DRY_RUN" = "no" ]; then
  mkdir -p "$(dirname "$SCOPES_FILE")"; : > "$SCOPES_FILE"
  echo "run_started=$(date +%s)"   >> "$SCOPES_FILE"
  echo "snapshot=$SNAPSHOT"        >> "$SCOPES_FILE"
else
  rm -f "$SCOPES_FILE"   # Probelauf hinterlaesst KEINE Marke
fi
```

**Geretteter Chat (NEU v5.1.0):** Existiert `.claude-mind/rescued/*_chat.md`, wurde der
Kontext zuvor kompaktiert und der volle Chat gerettet. Dann ist **diese Datei** die
Session-Quelle fuer den Knowledge-Sync in Schritt 5 — nicht das kompaktierte Live-Transkript.
```bash
RESCUED=$(ls -t "$PROJ/.claude-mind/rescued"/*_chat.md 2>/dev/null | head -1)
if [ -n "$RESCUED" ] && [ -s "$RESCUED" ]; then
  echo "Session-Quelle: gerettet -> $RESCUED ($(grep -c '^## \[' "$RESCUED") Beitraege)"
else
  echo "Session-Quelle: live"
fi
```

**Unterbrochener Auftrag (NEU v5.2.0):** Existiert `.claude-mind/rescued/RESUME.md`, wurde
dieser Lauf durch eine Kompaktierung ausgeloest und der davor laufende Auftrag ist dort
gesichert. **Jetzt lesen** — er wird am Ende zurueckgegeben:
```bash
RESUME_FILE="$PROJ/.claude-mind/rescued/RESUME.md"
[ -f "$RESUME_FILE" ] && { echo "Unterbrochener Auftrag gefunden:"; sed -n "/^## /,\$p" "$RESUME_FILE" | head -30; }
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
| 4 | `mind-rules check` **+** `migrate` | Rules-Syntax/-Inhalt. **Subcommand PFLICHT:** ohne Argument macht mind-rules nur `list` (zeigt eine Tabelle, fixt nichts) — in der Kette waere das ein Leerlauf |
| 5 | `mind-update` | **Zuletzt** — der uebergreifende Sweep + Knowledge-Sync; profitiert davon, dass 1-4 sauber sind, und deckt den Rest ab |

**Strikt sequenziell.** Nie zwei Skills gleichzeitig, nie ein Skill parallel zu Agents eines
anderen (Anti-Burst-Regel `~/.claude/rules/workflow-agent-rate-limit.md`: nie ≥3 Agents
gleichzeitig; innerhalb eines Skills gilt dessen eigene Grenze).

## Step 2: Ausfuehrung je Skill

Fuer jeden der 5 in der Reihenfolge oben:

1. **ZUERST die SKILL.md des Skills lesen** — `$CLAUDE_PLUGIN_ROOT/skills/<name>/SKILL.md` —
   und sie dann **vollstaendig** ausfuehren (inkl. Self-Check-Bloecken und Pflicht-Schritten).
   Nicht aus der Beschreibung improvisieren. **Skill-Logik ausfuehren** wie dort beschrieben — mit den durchgereichten
   Flags (`AUTO_MODE`/`DRY_RUN`). Kein erneuter Snapshot (Step 0 hat ihn).
2. **Scope-Marke schreiben — NUR mit Modus-Angabe** (M3-Fix):
   ```bash
   echo "claude-md=mind-claudemd:default" >> "$SCOPES_FILE"   # nach mind-claudemd
   echo "memory=mind-memory:default"      >> "$SCOPES_FILE"   # nach mind-memory
   # KEINE rules-Marke: mind-rules hat gar keinen `Agent` in allowed-tools und macht
   # ueberhaupt keine semantische Analyse — eine rules-Marke wuerde den rules-Agent in
   # Schritt 5 unterdruecken, ohne dass je einer gelaufen waere.
   ```
3. **Ergebnis sammeln** (angewendet / DESIGN / offen / Fehler) fuer den Schlussbericht.

**Scope-Dedup in Schritt 5 — nur bei GLEICHEM Modus (M3-Fix, kritisch):**
`mind-claudemd`/`mind-memory` dispatchen den context-analyzer mit **`mode: default`**
(Quality-Score, Duplikate — **ohne Session-Auszug**). `mind-update` Step 3.5 braucht aber
**`mode: knowledge-sync`** MIT Session-Auszug — das ist eine **andere Analyse mit anderem
Ergebnis**. Deshalb: **ein `:default`-Eintrag darf einen `knowledge-sync`-Dispatch NICHT
unterdruecken.** Uebersprungen wird nur, was mit **demselben Modus** schon lief.

Praktisch heisst das: in der Kette laufen die 4 knowledge-sync-Agents **normal**. Der Dedup
greift erst, wenn ein Skill kuenftig selbst `knowledge-sync` faehrt.

**Ersparnis ist KEIN Skip-Grund** (M4-Fix): Wenn der Modus nicht uebereinstimmt, wird
dispatcht — egal was das kostet. Der Knowledge-Sync ist laut `mind-update` Teil der
Identitaet des Skills, nicht seine Kuer.

**Fehler-Verhalten:** Scheitert ein Skill, laufen die **restlichen weiter**. Der Fehler kommt
in den Schlussbericht (`FEHLGESCHLAGEN: <skill> — <grund>`). Ein toter Skill darf die Kette
nicht killen — sonst bleibt der Context halb aktualisiert zurueck.

## Step 2.9: Kettenmarke abraeumen (PFLICHT, C1-Fix)

**Direkt nach dem letzten Skill, VOR dem Bericht:**

```bash
[ -f "$SCOPES_FILE" ] && mv -f "$SCOPES_FILE" "${SCOPES_FILE}.done" 2>/dev/null
```

**Warum das kein Beiwerk ist:** Die Einzel-Skills erkennen die Kette an dieser Datei und
ueberspringen dann ihren eigenen Snapshot. Bleibt sie liegen, haelt sich **jeder spaetere
Einzellauf** faelschlich fuer einen Kettenlauf und editiert **ohne Netz** — dauerhaft.
Deshalb: aufraeumen auch dann, wenn ein Skill vorher gescheitert ist (dieser Schritt laeuft
IMMER, er haengt an keinem Erfolg).

## Step 3: Konsolidierter Schlussbericht (PFLICHT)

```
=== /mind-all — Durchlauf abgeschlossen ===
Modus: autonom | --ask | --dry-run
Session-Quelle: gerettet <pfad> (<N> Beitraege)  |  live
Snapshot: <pfad>
  Restore (Ziele liegen NICHT alle im Projekt!):
    <pfad>/CLAUDE.md            -> <projekt>/CLAUDE.md
    <pfad>/dot-claude-CLAUDE.md -> <projekt>/.claude/CLAUDE.md
    <pfad>/rules/*.md           -> <projekt>/.claude/rules/
    <pfad>/memory/*.md          -> ~/.claude/projects/<slug>/memory/
    <pfad>/global/CLAUDE.md     -> ~/.claude/CLAUDE.md
    <pfad>/global/rules/*.md    -> ~/.claude/rules/
  Verifikation: cd <pfad> && sha256sum -c MANIFEST.sha256

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

```
⏭ FORTSETZUNG — hier war die Arbeit unterbrochen:
   <Auftragstext aus RESUME.md — woertlich, nicht zusammengefasst>
   -> Jetzt wieder aufnehmen. Dieser Sync war ein EINSCHUB, kein Abschluss.
```
*(ohne RESUME.md: `⏭ Fortsetzung: kein unterbrochener Auftrag protokolliert.`)*

Nach erfolgreichem Lauf: `RESUME.md` → `RESUME.done.md` umbenennen (kein Dauer-Nachhaken).
Die Rettungsdatei `*_chat.md` **bleibt** liegen.

**Der Bericht ist die einzige Stelle, an der du siehst was passiert ist** — deshalb luegt er
nicht: jede Aenderung einzeln, jede Auslassung mit Grund, Snapshot-Pfad immer dabei.

## Hard Constraints

- **EIN `mind_snapshot` vor dem ersten Skill; Fehlschlag = kein Skill startet.**
- **Strikt sequenziell** — nie zwei Skills gleichzeitig (Anti-Burst).
- **Reihenfolge ist fest:** files → claudemd → memory → rules → update.
- **DESIGN-Befunde werden nie automatisch angewendet** (in keinem der 5).
- **Geretteter Chat schlaegt Live-Transkript** (v5.1.0): liegt eine Rettungsdatei vor, ist sie
  die Session-Quelle — und der Bericht MUSS das ausweisen. Nach einer Kompaktierung waere das
  Live-Transkript nur noch die Zusammenfassung; ein Sync darauf verpasst genau das, was
  gerettet werden sollte.
- **Overwrite-Guards und Tool-Bundle-Angebote aus mind-files bleiben aktiv** — Autonomie
  erzeugt keine Ausnahme fuer fremden Bestand.
- **>5 DEAD-Pfade** in mind-update bleiben gesperrt (Massenloesch-Sicherung).
- **Ein gescheiterter Skill stoppt die Kette nicht** — Fehler in den Schlussbericht. Ein
  `STOP`/`ABBRUCH`/`exit 1` **innerhalb** eines Einzel-Skills beendet NUR diesen Skill
  (z.B. mind-memory ohne MEMORY.md), nicht den Durchlauf.
- **Step 2.9 (Kettenmarke abraeumen) laeuft IMMER** — auch nach Fehlern/Abbruch.
- **`/mind-all` ist NIE ein Auftragsende (v5.2.0).** Nennt `RESUME.md` einen unterbrochenen
  Auftrag, MUSS der Schlussbericht mit der `⏭ FORTSETZUNG`-Zeile enden und die Arbeit danach
  wieder aufgenommen werden. Ein Context-Sync ist ein Einschub — er erledigt nichts, was der
  Nutzer beauftragt hat.
- **Kein `git commit`/`git push`** — `/mind-all` aendert Context-Dateien, nicht die Historie.
