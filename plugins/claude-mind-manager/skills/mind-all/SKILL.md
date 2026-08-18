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

# Hook-Gesundheit (NEU v5.2.1) — meldet den stillen Hook-Tod nach einem Plugin-Update.
# Kein Abbruchgrund: /mind-all laeuft auch ohne Hooks. Aber es MUSS im Bericht stehen,
# sonst haelt der naechste Befundlauf ein totes Netz fuer ein gespanntes.
mind_hook_health "$PROJ" || HOOK_WARN="ja"

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

**Geretteter Chat (v5.1.0) + offene Schuld (v5.2.1):** Existiert `.claude-mind/rescued/OPEN`,
steht ein Sync aus. `OPEN` nennt die Rettungsdatei und den gesicherten Auftrag.
```bash
OPEN="$PROJ/.claude-mind/rescued/OPEN"
RESCUED_ALL=""; RESUME_FILE=""; COMPACTIONS=""
if [ -f "$OPEN" ]; then
  # v5.4.1: ALLE offenen Rettungen, aelteste zuerst. Bis v5.4.0 stand hier `grep -m1` —
  # bei zwei Kompaktierungen ohne Sync wurde die aeltere NIE eingespeist, obwohl ihre Datei
  # noch dalag. Belegt: 20260816-194132_chat.md, 412 KB, verwaist.
  RESCUED_ALL=$(grep '^path=' "$OPEN" | cut -d= -f2- | while IFS= read -r p; do
                  [ -n "$p" ] && [ -f "$p" ] && echo "$p"; done)
  RESUME_FILE=$(grep '^resume='      "$OPEN" | cut -d= -f2- | tail -1)   # der juengste Auftrag
  COMPACTIONS=$(grep -m1 '^compactions=' "$OPEN" | cut -d= -f2-)
fi
# Rueckfall, falls OPEN fehlt (Rettung aus einer aelteren Version)
[ -z "$RESCUED_ALL" ] && RESCUED_ALL=$(ls -t "$PROJ/.claude-mind/rescued"/*_chat.md 2>/dev/null | head -1)
RESCUED_N=$(printf '%s\n' "$RESCUED_ALL" | grep -c . 2>/dev/null)
case "$RESCUED_N" in ''|*[!0-9]*) RESCUED_N=0 ;; esac

if [ "$RESCUED_N" -gt 0 ]; then
  # NUR ZAEHLEN, NICHT LESEN — siehe Sperre unten
  # v5.2.2: BEIDE Quellen. Die Rettung endet am Kompaktierungs-Zeitpunkt; alles danach steht
  # nur im Live-Transkript — und genau das ist die Arbeit, wegen der der Lauf erzwungen wird.
  echo "Session-Quelle: gerettet+live"
  echo "  gerettet -> $RESCUED_N Rettung(en), aelteste zuerst:"
  i=0
  printf '%s\n' "$RESCUED_ALL" | while IFS= read -r r; do
    [ -n "$r" ] || continue
    i=$((i+1))
    echo "     [$i] $(basename "$r")  $(grep -c '^## \[' "$r") Beitraege"
  done
  echo "  live     -> Sampler ueber das laufende Transkript (die Zeit nach der letzten)"
  [ -n "$COMPACTIONS" ] && [ "$COMPACTIONS" -gt 1 ] 2>/dev/null && \
    echo "ACHTUNG: $COMPACTIONS Kompaktierungen seit dem letzten Sync — bereits verschleppt."
else
  echo "Session-Quelle: live"
fi
# Der Auftrags-Merker ist KLEIN (wenige KB) und wird gelesen — er wird am Ende zurueckgegeben.
[ -n "$RESUME_FILE" ] && [ -f "$RESUME_FILE" ] && \
  { echo "Unterbrochener Auftrag gefunden:"; sed -n "/^## /,\$p" "$RESUME_FILE" | head -30; }
```

> ⛔ **KONTEXT-FLUT-SPERRE (NEU v5.2.1, Hard Constraint).** Die Rettungsdatei `*_chat.md` wird
> **NIE im Hauptkontext gelesen** — kein `Read`, kein `cat`, kein `head`/`sed` auf ihren Inhalt.
> Sie ist mehrere hundert KB gross (gemessen: 417 KB / 555 Beitraege). Erlaubt sind ausschliesslich:
> **(i)** den **Pfad** an einen Subagenten uebergeben (der hat eigenen Kontext und einen
> Groessen-Guard) und **(ii)** zaehlende Shell-Aufrufe (`grep -c`, `wc`).
>
> **Warum das eine Invariante ist und keine Empfehlung:** Dieser Lauf wird per Stop-Hook direkt
> nach einer Kompaktierung erzwungen. Wer die Datei in den frisch geleerten Kontext liest,
> loest sofort die naechste Kompaktierung aus — die eine neue Rettung erzeugt, die den naechsten
> Zwangslauf ausloest. Ein `Read` auf `*_chat.md` im Hauptfluss ist ein **Abbruchgrund**, kein
> Schoenheitsfehler.

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

## Step 2.95: `listeverbesserungen.md` fortschreiben (PFLICHT, NEU v5.2.1)

**Jeder** `/mind-all`-Lauf haengt einen Abschnitt an `<projekt>/listeverbesserungen.md` an —
auch ein Handaufruf ohne Kompaktierung, auch ein Lauf ohne einen einzigen Fund.

```bash
LISTE="$PROJ/listeverbesserungen.md"
[ -f "$LISTE" ] || printf '# Verbesserungsliste\n\nAngehaengt von /mind-all. Neueste Abschnitte stehen UNTEN.\n' > "$LISTE"
# Abschnitt anhaengen (>> — niemals ueberschreiben)
```

Aufbau je Lauf — **angehaengt**, nie vorangestellt (Anhaengen kann eine bestehende Datei nicht
beschaedigen, Umschreiben schon):

```markdown
## <JJJJ-MM-TT HH:MM> — /mind-all  (Ausloeser: Kompaktierung <manual|auto> | Handaufruf)

### Probleme in diesem Lauf
- <was scheiterte: Agent ohne Ergebnis, Snapshot fehlgeschlagen, Datei unlesbar,
  Groessen-Guard gegriffen, Hook-Herzschlag veraltet, jq/cygpath fehlt, Skill abgebrochen …>

### Verbesserungsvorschlaege
- <konkret, mit Datei und Stelle — kein "koennte man mal">

### Nicht angewendet (und warum)
- <DESIGN-Befunde / >5 tote Pfade / --dry-run / Overwrite-Guard / fehlende Freigabe>
```

**Regeln, ohne die die Liste Dekoration waere:**
- `- (keine)` ist eine **zulaessige** Antwort. Ein **leerer** Abschnitt ist es nicht — ein Lauf
  ohne Eintrag gilt als nicht protokolliert.
- **Ein gescheiterter Agent ist ein PROBLEM, kein "unauffaellig".** Ein Null-Ergebnis heisst
  „ungeprueft", nicht „nichts gefunden" (`~/.claude/rules/workflow-agent-rate-limit.md`).
  Wer hier „(keine)" schreibt, obwohl ein Agent starb, macht den ganzen Mechanismus wertlos.
- Auch **eigene** Fehlgriffe gehoeren hinein (falsche Annahme, verworfener Zwischenstand) —
  die Liste ist ein Arbeitsprotokoll, keine Erfolgsmeldung.
- Im **`--dry-run`** wird die Datei **nicht** geschrieben; der Bericht sagt das ausdruecklich.

## Step 2.96: Schuld begleichen (PFLICHT, NEU v5.2.1)

Erst **nach** einem tatsaechlich gelaufenen Sync (nicht im Probelauf, nicht nach Abbruch von
mind-update) wird die offene Schuld entfernt — sonst blockt der Stop-Hook zu Recht weiter:

```bash
if [ "$DRY_RUN" = "no" ] && [ "$SYNC_LIEF" = "ja" ]; then
  OPEN="$PROJ/.claude-mind/rescued/OPEN"
  if [ -f "$OPEN" ]; then
    RF=$(grep -m1 '^resume=' "$OPEN" | cut -d= -f2-)
    [ -n "$RF" ] && [ -f "$RF" ] && mv -f "$RF" "${RF%.md}.done.md" 2>/dev/null
    rm -f "$OPEN" "${OPEN}.seen-"* 2>/dev/null
    echo "Sync-Schuld beglichen: OPEN entfernt."
  fi
fi
```

**Die Rettungsdateien `*_chat.md` bleiben liegen** — sie sind das Archiv. Entfernt wird nur
die **Schuld**, nicht der Beleg.

⛔ **v5.4.1: Teilerfolg ist kein Erfolg.** `OPEN` wird nur entfernt, wenn **ALLE** offenen
Rettungen eingespeist wurden. Bricht der Lauf nach der ersten ab, bleiben die uebrigen
`path=`-Zeilen stehen und der Stop-Hook hakt zu Recht weiter nach. Wer hier zu frueh
begleicht, wiederholt genau den Fehler, an dem v5.2.0 gescheitert ist — nur eine Ebene
tiefer.

**Wenn der Sync NICHT lief** (Abbruch, Probelauf, mind-update gescheitert): `OPEN` bleibt, und
der Schlussbericht sagt **ausdruecklich**, dass die Schuld offen bleibt und der Stop-Hook
weiter nachhaken wird. Stillschweigendes Liegenlassen ist die eine Sache, die hier nicht
passieren darf — genau daran ist v5.2.0 gescheitert.

## Step 3: Konsolidierter Schlussbericht (PFLICHT)

```
=== /mind-all — Durchlauf abgeschlossen ===
Modus: autonom | --ask | --dry-run
Hook-Gesundheit: OK (Herzschlag vor <N> min, Version <v>)  |  <Warnung woertlich>
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
*(ohne Auftrags-Merker: `⏭ Fortsetzung: kein unterbrochener Auftrag protokolliert.`)*

Dazu gehoeren zwei Pflichtzeilen (v5.2.1):
```
Verbesserungsliste: <projekt>/listeverbesserungen.md — <N> Probleme, <M> Vorschlaege angehaengt
Sync-Schuld: beglichen (OPEN entfernt)  |  BLEIBT OFFEN — <grund>, Stop-Hook hakt weiter nach
```

Umbenannt wird nach erfolgreichem Lauf `<ts>_RESUME.md` → `<ts>_RESUME.done.md` (Step 2.96).
Die Rettungsdatei `*_chat.md` **bleibt** liegen.

**Der Bericht ist die einzige Stelle, an der du siehst was passiert ist** — deshalb luegt er
nicht: jede Aenderung einzeln, jede Auslassung mit Grund, Snapshot-Pfad immer dabei.

## Hard Constraints

- **EIN `mind_snapshot` vor dem ersten Skill; Fehlschlag = kein Skill startet.**
- **Strikt sequenziell** — nie zwei Skills gleichzeitig (Anti-Burst).
- **Reihenfolge ist fest:** files → claudemd → memory → rules → update.
- **DESIGN-Befunde werden nie automatisch angewendet** (in keinem der 5).
- **ALLE geretteten Chats UND das Live-Transkript (v5.4.1, zuvor v5.2.2):** Liegen mehrere
  Rettungen vor, sind sie **alle** Session-Quelle — aelteste zuerst —, und der Bericht MUSS
  jede einzeln ausweisen. Nur die juengste zu nehmen ist ein **Befund**, kein gueltiger Lauf. Die Rettung deckt
  alles bis zur Kompaktierung ab, das Live-Transkript die Zeit danach — und das ist die Arbeit,
  wegen der der Stop-Hook den Lauf erzwingt. **`gerettet` allein ist ab v5.2.2 ein Befund.**
- **Overwrite-Guards und Tool-Bundle-Angebote aus mind-files bleiben aktiv** — Autonomie
  erzeugt keine Ausnahme fuer fremden Bestand.
- **>5 DEAD-Pfade** in mind-update bleiben gesperrt (Massenloesch-Sicherung).
- **Ein gescheiterter Skill stoppt die Kette nicht** — Fehler in den Schlussbericht. Ein
  `STOP`/`ABBRUCH`/`exit 1` **innerhalb** eines Einzel-Skills beendet NUR diesen Skill
  (z.B. mind-memory ohne MEMORY.md), nicht den Durchlauf.
- **Step 2.9 (Kettenmarke abraeumen) laeuft IMMER** — auch nach Fehlern/Abbruch.
- ⛔ **KONTEXT-FLUT-SPERRE (v5.2.1):** `*_chat.md` wird **nie** im Hauptkontext gelesen — kein
  `Read`, kein `cat`. Nur Pfad-Uebergabe an Subagenten und zaehlende Aufrufe (`grep -c`, `wc`).
  Ein `Read` darauf im Hauptfluss ist **Abbruchgrund**: dieser Lauf wird per Stop-Hook direkt
  nach einer Kompaktierung erzwungen, und ein voller Kontext loest sofort die naechste aus —
  die eine neue Rettung erzeugt, die den naechsten Zwangslauf ausloest.
- **`listeverbesserungen.md` ist Pflicht (v5.2.1)** — jeder Lauf haengt an. „(keine)" ist
  erlaubt, ein leerer Abschnitt nicht. Ein gestorbener Agent ist ein **Problem**, kein
  „unauffaellig".
- **Die Schuld wird nur bei tatsaechlich gelaufenem Sync entfernt (v5.2.1).** Bleibt sie offen,
  MUSS der Bericht das sagen — stillschweigendes Liegenlassen ist genau der Fehler, an dem
  v5.2.0 gescheitert ist.
- ⛔ **DER SYNC GEHT IMMER VOR (NEU v5.4.1, Nutzer-Entscheidung 19.08.2026).**
  Liegt eine offene Schuld vor, laeuft `/mind-all` **zuerst** — vor jedem Auftrag, ohne
  Ausnahme. *„Ich mache erst den Auftrag fertig"* ist **kein zulaessiger Grund mehr**.
  **Warum das die v5.2.0-Regel ersetzt:** Die alte Fassung („laufender Auftrag hat Vorrang")
  nannte keinen Zeitpunkt, zu dem der Sync faellig wird. Zog sich der Auftrag bis zur
  naechsten Kompaktierung, wiederholte sich dieselbe Begruendung — und bis v5.4.0 zeigte der
  Merker dann woanders hin. Der Auftrag geht dabei **nicht** verloren: er steht woertlich im
  `<ts>_RESUME.md` und kommt unten mit der `⏭ FORTSETZUNG`-Zeile zurueck.
- **`/mind-all` ist NIE ein Auftragsende (v5.2.0).** Nennt der Auftrags-Merker einen unterbrochenen
  Auftrag, MUSS der Schlussbericht mit der `⏭ FORTSETZUNG`-Zeile enden und die Arbeit danach
  wieder aufgenommen werden. Ein Context-Sync ist ein Einschub — er erledigt nichts, was der
  Nutzer beauftragt hat.
- **Kein `git commit`/`git push`** — `/mind-all` aendert Context-Dateien, nicht die Historie.
