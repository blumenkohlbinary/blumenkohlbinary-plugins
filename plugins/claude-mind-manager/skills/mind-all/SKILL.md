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

## ⛔ PFLICHTSCHRITTE — dieser Skill fuehrt aus, was hier steht (NEU v5.25.0)

```
PFLICHTSCHRITTE
arbeitsstand_render
debug_auswertung
mind_agent_bilanz
mind_check_tools_have_rules
mind_debug_write
mind_hook_health
mind_snapshot
mind_zeilenenden_waechter
```

**Vor dem ersten Schritt, ohne Ausnahme:**

```bash
mind_schritt_start "$PROJ" mind-all arbeitsstand_render debug_auswertung mind_agent_bilanz mind_check_tools_have_rules mind_debug_write mind_hook_health mind_snapshot mind_zeilenenden_waechter
```

**Nach JEDEM Schritt** — auch nach einem, der entfaellt:

```bash
mind_schritt <name> gelaufen              "$(wc -c < "$AUSGABE")" "$PROJ"
mind_schritt <name> "gelaufen:5/11"       "$BYTES" "$PROJ"   # TEILABDECKUNG
mind_schritt <name> "uebersprungen:<grund>" 0      "$PROJ"
mind_schritt <name> "fehler:<grund>"      -1       "$PROJ"
```

⛔ **`uebersprungen` ist ein gueltiger Status und braucht einen GRUND.** Ein Schritt,
der legitim entfaellt (`--dry-run`, kein Git, kein Quellbaum), ist kein Fehler — aber
sein Entfallen gehoert in den Bericht statt zu verschwinden.

⭐ **`gelaufen:5/11` ist die TEILABDECKUNG und der Anlass dieses Baus.** Am 30.08.2026
lief `cleaner_leitplanke.py` ueber 5 von 11 Dateien und wurde als **Bereichspruefung**
berichtet. Der Fehler war nicht ein fehlender Aufruf, sondern ein gelaufener, der
weniger abdeckte als der Bericht behauptete. `5/11` ist eine gueltige Antwort;
sie als `11/11` zu berichten ist es nicht.

⛔ **Die Bytezahl ist Pflicht, wo ein Schritt etwas ausgeben MUSS.** Am selben Tag
lief `cleaner_belege.py` und seine Ausgabe wurde weggegreppt — aus Sicht einer
naiven Quittung waere das „gelaufen". `0` meldet die Bilanz als **LEER**; `-1`
heisst „nicht gemessen" und zaehlt nicht.

**Im Bericht, als erste Zeile des Self-Checks:**

```bash
mind_schritt_bilanz "$PROJ"
```

⛔ **Fehlt diese Zeile oder nennt sie `FEHLT`, ist der Bericht unvollstaendig** und
darf zurueckgewiesen werden. Rueckgabe **2 heisst: gar keine Quittung** — der Lauf
hat nie begonnen zu quittieren, und das ist NICHT „nichts zu melden".

⚠ **Was die Quittung nicht kann:** sie erzwingt keinen Schritt, sie macht sein Fehlen
sichtbar — wie `decision:block` und die Agent-Quittung. Und sie misst nicht die GUETE:
ein Werkzeug, das laeuft und Unsinn liefert, quittiert als `gelaufen`.

Ein Snapshot -> 5 Skills sequenziell -> alle Befunde angewendet -> ein Bericht.

## Step -1: Was ist hier schon einmal schiefgegangen? (PFLICHT, NEU v5.7.1)

```bash
mind_debug_top 3      # still, wenn MIND_DEBUG_DIR fehlt oder es keine Wiederholung gibt
```

⛔ **Das steht VOR Step 0, und das ist der ganze Punkt.** Der Debug-Ordner sammelte bis v5.7.0
nur ein — gelesen wurde er nie *vor* der Arbeit. Belegt am 21.08.2026: die Klasse
„Instrumentenkontrolle verglich nur Befund-ANZAHLEN" stand seit dem Vortag darin, und derselbe
Fehler wurde am naechsten Tag erneut gebaut. **Sichtbarkeit ohne Lese-Anlass ist wirkungslos.**

Die Ausgabe ist kein Befund und blockt nichts — sie ist eine Erinnerung an drei Zeilen.


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

  # ⛔ v5.21.3 — SAGEN, WAS NICHT DRIN IST.
  #    Befund aus `Pc Forschung` (26.08.2026): `INDEX.md`, die zentrale
  #    Projektdatei, lag nicht im Snapshot. Alle Aenderungen daran liefen ohne
  #    Netz, und die Restore-Liste im Bericht war fuer sie schlicht falsch.
  #
  #    Ihr Vorschlag war, `INDEX.md` fest einzubauen. Das waere ein
  #    projektspezifisches Pflaster in einem allgemeinen Werkzeug —
  #    `MIND_SNAPSHOT_EXTRA` loest den Fall seit v5.2.1 allgemein.
  #
  #    ⭐ GEMESSEN, warum sie das nicht wissen konnten: die Variable kommt in
  #       `hooks/lib.sh` vor und in KEINEM Skill, KEINEM Bericht, KEINER
  #       Referenz. Wer den Schlussbericht liest, sieht eine Restore-Liste und
  #       hat keinen Weg zu erfahren, dass sie erweiterbar ist. Genau dasselbe
  #       ist hier zweimal mit `knowledge/` passiert (env-vars.md).
  #
  #    ⚠ Gemeldet wird nur — welche Datei wichtig ist, weiss der Nutzer.
  #    ⚠ NUR die zuletzt GEAENDERTEN, hoechstens fuenf. Eine vollstaendige Liste
  #      waere hier 15 Namen lang (gemessen in diesem Projekt) und damit genau
  #      die Ausgabe, die man gewohnheitsmaessig ueberliest — wovor `Pc Forschung`
  #      im selben Bericht warnt. Die juengsten sind die, an denen gearbeitet wird.
  #    ⛔ Der GLOB laeuft, NICHT `$(ls -t ...)`. Eine unquotierte
  #      Befehlssubstitution zerlegt am Leerzeichen — und dieses Projekt heisst
  #      `Plugin - Entwicklung/Claude Mind Manager`. Erste Fassung meldete
  #      dadurch "79 Dateien" statt 15, mit Namen wie "Plugin - Claude Mind".
  #      Klasse `windows-pfad`, in diesem Projekt seit v5.2.1 dokumentiert
  #      ("Rotation nie mit xargs") und trotzdem wieder entstanden.
  #    ⛔ Und KEINE Pipe in die Schleife: die liefe in einer Subshell, und `_N`
  #      waere danach wieder 0 — derselbe Fehler steckt schon einmal in dieser
  #      Datei (mind_check_tools_have_rules, dort mit einer Merkdatei geloest).
  _LK=$(mind_snapshot_luecken "$PROJ" "$SNAPSHOT")
  _N="${_LK%%|*}"; _UNGEDECKT="${_LK#*|}"
  if [ "${_N:-0}" -gt 0 ] 2>/dev/null; then
    echo "  ⚠ NICHT im Snapshot ($_N Datei(en), die zuletzt geaenderten): $_UNGEDECKT"
    echo "    Ist eine davon fuer diesen Lauf tragend, VOR dem naechsten Mal setzen:"
    echo "      export MIND_SNAPSHOT_EXTRA=\"\$PWD/<pfad>\"   # ⛔ ABSOLUT, relativ wird still verworfen"
  fi
fi

# ⛔ v5.30.0: SPERRE GEGEN PARALLELE LAEUFE — direkt nach dem Snapshot, weil
#    die Laufkennung aus seinem Namen kommt.
#    Befund aus `Creator` (30.08.2026), hier unabhaengig nachgemessen:
#    `SCOPES_FILE` liegt PRO PROJEKT, der Stop-Hook feuert PRO SITZUNG. Zwei
#    Chats im selben Ordner haengen ihre `skill=`-Zeilen an DIESELBE Datei,
#    ihre Summe erreicht 5, `SYNC_LIEF` geht auf "ja" — und `rm -f "$OPEN"`
#    tilgt die Schuld fuer Arbeit, die KEIN EINZELNER Lauf geleistet hat.
#    ⚠ Kein flock (auf MSYS unzuverlaessig). `mkdir` ist atomar; auf diesem
#      Aufbau gemessen: 40 gleichzeitig -> genau 1 gewinnt, Gegenprobe
#      abgewiesen.
LAUF=$(mind_lauf_kennung "${SNAPSHOT:-}")
if [ "$DRY_RUN" = "no" ]; then
  if ! _SPERRE=$(mind_lauf_sperre "$PROJ" "$LAUF"); then
    echo "$_SPERRE" >&2
    exit 0    # ⛔ 0, NICHT 1 — kein Fehler, sondern die richtige Antwort.
              #   Ein Rueckgabewert 1 saehe im Log wie ein kaputter Lauf aus.
  fi
  trap 'mind_lauf_frei "$PROJ" "$LAUF"' EXIT
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

# ⛔ v5.19.0: Die Agent-Quittung wird HIER angelegt, nicht in mind-update.
#    Bis v5.18.0 rief `mind_agent_quittung_start` ausschliesslich mind-update
#    Step 3.5 — also GENAU DER SCHRITT, DER AUSFAELLT. Faellt er aus, faellt die
#    Quittung mit aus, und ihr FEHLEN sieht aus wie ihr SCHWEIGEN.
#    Das ist woertlich dasselbe Muster, das v5.3.1 eine Ebene tiefer behoben hat:
#    ein Hook, der schweigt weil er soll, und einer, der schweigt weil er tot ist,
#    sind im Log nicht zu unterscheiden.
#    Ab hier gilt: keine Quittung == die Kette kam nie bis zum Fan-out. Von
#    aussen messbar, weil der Anleger nicht mehr im Ausfallpfad liegt.
#    ⛔ v5.21.3: die 4 ist PFLICHT. v5.21.2 gab der Funktion den Parameter und
#       liess beide Aufrufer unveraendert — die Quittung verhielt sich damit
#       exakt wie vorher. Woertlich der v5.7.1-Fall ("es sammelte die Variable
#       und benutzte sie nie") und derselbe Halbfix wie bei classify_path am
#       selben Tag. Ohne die Zahl kann die Bilanz "nie dispatcht" nicht von
#       "ueber das Agent-Werkzeug gestartet" unterscheiden — und genau das hat
#       `Pc Forschung` am 26.08. zum ZWEITEN Mal unveraendert gemeldet.
[ "$DRY_RUN" = "no" ] && mind_agent_quittung_start "$PROJ" 4
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
  # v5.6.0: der ausfuehrliche Arbeitsstand. Er steht BEWUSST nicht in RESUME.md —
  # die Erinnerungs-Hooks kappen die dort bei 30 Zeilen, und das ist richtig so.
  ARBEITSSTAND=$(grep '^arbeitsstand=' "$OPEN" | cut -d= -f2- | tail -1)
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

# Arbeitsstand OHNE Kappung — hier gehoert der ausfuehrliche Stand hin (v5.6.0).
# Vier Kategorien: Entscheidungen, aktive Bugs, geaenderte Dateien, Constraints.
if [ -n "$ARBEITSSTAND" ] && [ -s "$ARBEITSSTAND" ]; then
  echo "Arbeitsstand vor der Kompaktierung:"
  python "$CLAUDE_PLUGIN_ROOT/references/arbeitsstand_render.py" "$ARBEITSSTAND" 2>/dev/null \
    || echo "  (Arbeitsstand nicht lesbar — der Lauf geht trotzdem weiter)"
fi
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
2. **Laufspur schreiben — PFLICHT, nach JEDEM der fuenf** (NEU v5.19.0):
   ```bash
   echo "skill=<name>|$LAUF" >> "$SCOPES_FILE"   # nach jedem der 5, ohne Ausnahme
   ```
   ⛔ **v5.30.0: die Laufkennung `|$LAUF` ist PFLICHT.** Sie ist der Teil, der
   eine Kollision **erkennbar** macht, wenn die Sperre versagt — die Sperre
   allein verhindert sie nur. Ohne die Kennung entsteht ein Instrument, das im
   Ausfall schweigt (`werkzeuge-zuerst.md`).
   ⛔ **Sie kommt aus `basename "$SNAPSHOT"`, NICHT aus `CLAUDE_SESSION_ID`.**
   Die ist in einer Skill-Bash **leer** (gemessen); ein Waechter darauf matcht
   gegen den leeren String, zaehlt **alle** Zeilen auch fremde, und **sieht aus,
   als greife er**. Das waere schlimmer als keine Sperre.
   ⛔ **Eigener Schluessel, bewusst getrennt von den Scope-Marken unten.** `skill=` sagt
   *„dieser Teil lief"*, die Scope-Marken sagen *„diese Analyse ist in diesem Modus schon
   gelaufen"* — zwei verschiedene Aussagen. Sie in einen Schluessel zu legen haette die
   Dedup-Logik in Schritt 5 mitverbogen.
   **Ohne diese Zeile ist der Lauf nicht zaehlbar**, und Step 2.96a kann `SYNC_LIEF` nicht
   ableiten. Bis v5.18.0 gab es sie nicht — der Lauf vom 24.08.2026 hinterliess deshalb
   **gar keine Spur** (gemessen: `analyzed-scopes.done` trug den Stand des Vortages).
3. **Scope-Marke schreiben — NUR mit Modus-Angabe** (M3-Fix):
   ```bash
   echo "claude-md=mind-claudemd:default" >> "$SCOPES_FILE"   # nach mind-claudemd
   echo "memory=mind-memory:default"      >> "$SCOPES_FILE"   # nach mind-memory
   # KEINE rules-Marke: mind-rules hat gar keinen `Agent` in allowed-tools und macht
   # ueberhaupt keine semantische Analyse — eine rules-Marke wuerde den rules-Agent in
   # Schritt 5 unterdruecken, ohne dass je einer gelaufen waere.
   ```
4. **Ergebnis sammeln** (angewendet / DESIGN / offen / Fehler) fuer den Schlussbericht.

**Scope-Dedup in Schritt 5 — nur bei GLEICHEM Modus (M3-Fix, kritisch):**
`mind-claudemd`/`mind-memory` dispatchen den context-analyzer mit **`mode: default`**
(Quality-Score, Duplikate — **ohne Session-Auszug**). `mind-update` Step 3.5 braucht aber
**`mode: knowledge-sync`** MIT Session-Auszug — das ist eine **andere Analyse mit anderem
Ergebnis**. Deshalb: **ein `:default`-Eintrag darf einen `knowledge-sync`-Dispatch NICHT
unterdruecken.** Uebersprungen wird nur, was mit **demselben Modus** schon lief.

Praktisch heisst das: in der Kette laufen die 4 knowledge-sync-Agents **normal**. Der Dedup
greift erst, wenn ein Skill kuenftig selbst `knowledge-sync` faehrt.

⛔ **Ein Agent mit LEERER Rueckgabe ist ein Problem, kein „unauffaellig" (NEU v5.7.1).**
Gemessen 21.08.2026: der `rules`-Agent meldete „completed" nach 163 s und 31 Werkzeugaufrufen —
und hinterliess **0 Byte**. Wer das als „nichts gefunden" verbucht, traegt eine ungeprueftes
Feld als geprueft ein.

**Pflicht bei leerer Rueckgabe:**
1. Den Bereich als **UNGEPRUEFT** in den Bericht schreiben, nicht als „keine Befunde".
2. **Sofort auf den grep-Weg zurueckfallen.** Am 21.08. hat das unter einer Minute gedauert
   und genau den Befund geliefert, den der Agent finden sollte.
3. Den Ausfall als Klasse `agent-gestorben` in die Befundzeilen aufnehmen (Step 2.95).

### ⛔ Wiederholen: HOECHSTENS EINMAL, und nur mit engerem AUFTRAG (NEU v5.21.2)

Ein zweiter Agentenlauf ist ein **eigener Versuch**, der auch scheitern kann — und er
kostet. In `Pc Forschung` am 26.08.2026: **660 000 Tokens fuer zwei Wiederholungen ohne
ein einziges Byte Ertrag.**

| erlaubt | verboten |
|---|---|
| **einmal** neu, mit **engerem AUFTRAG** | dieselbe Aufgabe mit kleinerer EINGABE |
| ein Auftrag statt zwei, 4–5 benannte Dateien | „nochmal, vielleicht klappt es" |

⛔ **Die Eingabe zu verkleinern hilft NICHT — gemessen, nicht vermutet:**

```
Lauf 1, Rettungsdatei 1049 KB   claude-md  186 674 Tok / 20 Aufrufe -> 0 Byte
                                memory     180 284 Tok / 26 Aufrufe -> 0 Byte
Lauf 2, Auszug         339 KB   rules      335 159 Tok / 20 Aufrufe -> 0 Byte
                                memory     325 160 Tok / 24 Aufrufe -> 0 Byte
```

**3,1x kleinere Eingabe, MEHR Tokens, vier von vier gleichfoermig tot.**

Nach dem zweiten leeren Agenten ist Schluss: der Bereich gilt als ungeprueft, der
grep-Rueckfall ist der Weg, und beides steht im Bericht.

⚠ Eine gelungene Wiederholung wird **quittiert** (`mind_agent_ergebnis` erneut) —
`mind_agent_bilanz` wertet seit v5.21.2 den **letzten** Eintrag je Bereich und meldet den
Verlauf als `WIEDERHOLT`. Der gestorbene Agent verschwindet damit nicht spurlos.


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
# ⛔ v5.30.0: Sperre freigeben — NUR die eigene. `mind_lauf_frei` prueft die
#    Kennung; ein abbrechender Zweitlauf raeumt dem Erstlauf nichts weg.
#    ⚠ Der `trap` aus Step 0 faengt den Abbruchfall; dieser Aufruf ist der
#      Normalweg und macht die Freigabe im Bericht sichtbar.
[ "$DRY_RUN" = "no" ] && mind_lauf_frei "$PROJ" "${LAUF:-}" \
  && echo "Sperre freigegeben (Lauf ${LAUF:-?})."
```

**Warum das kein Beiwerk ist:** Die Einzel-Skills erkennen die Kette an dieser Datei und
ueberspringen dann ihren eigenen Snapshot. Bleibt sie liegen, haelt sich **jeder spaetere
Einzellauf** faelschlich fuer einen Kettenlauf und editiert **ohne Netz** — dauerhaft.
Deshalb: aufraeumen auch dann, wenn ein Skill vorher gescheitert ist (dieser Schritt laeuft
IMMER, er haengt an keinem Erfolg).

## Step 2.95: `listeverbesserungen.md` fortschreiben (PFLICHT, NEU v5.2.1)

**Jeder** `/mind-all`-Lauf haengt einen Abschnitt an `<projekt>/listeverbesserungen.md` an —
auch ein Handaufruf ohne Kompaktierung, auch ein Lauf ohne einen einzigen Fund.

⛔ **Hier stand bis v5.6.0 nur eine Markdown-Vorlage und kein ausfuehrbarer Code** — deshalb
schrieb jeder Lauf das Anhaengen von Hand, mit `>>` und ohne Ruecksicht auf die Zeilenenden.
Seit v5.7.0 ist es Code, und der Abschnitt geht **zusaetzlich zentral** hinaus.

```bash
LISTE="$PROJ/listeverbesserungen.md"
[ -f "$LISTE" ] || printf '# Verbesserungsliste\n\nAngehaengt von /mind-all. Neueste Abschnitte stehen UNTEN.\n' > "$LISTE"

# 1) Abschnitt in eine Zwischendatei schreiben (Aufbau siehe unten), dann anhaengen.
#    mind_append statt '>>' — es erhaelt die Zeilenenden der Zieldatei.
ABSCHNITT="$PROJ/.claude-mind/lauf-abschnitt.md"
# ... Abschnitt nach "$ABSCHNITT" schreiben ...
[ "$DRY_RUN" = "no" ] && mind_append "$LISTE" < "$ABSCHNITT"

# 2) Befunde MASCHINENLESBAR danebenlegen — eine Zeile je Befund.
#    Ohne die feste Klassenliste heisst derselbe Fehler dreimal anders und wird nie als
#    Wiederholung erkannt. Gueltige Klassen stehen in references/debug_auswertung.py.
BEFUNDE="$PROJ/.claude-mind/lauf-befunde.jsonl"
: > "$BEFUNDE"
# je Befund eine Zeile, z.B.:
#   {"ts":"2026-08-21 01:20","projekt":"<PROJ>","klasse":"instrument-nachgebaut",
#    "kurz":"Pipeline statt claudemd_pipeline.py nachgebaut","lauf":"<ts>"}

# 3) zentral melden (still, wenn MIND_DEBUG_DIR nicht gesetzt ist)
[ "$DRY_RUN" = "no" ] && mind_debug_write "$PROJ" "$AUSLOESER" "$ABSCHNITT" "$BEFUNDE"
rm -f "$ABSCHNITT" "$BEFUNDE" 2>/dev/null
```

**Die elf Ursachenklassen** (feste Liste, nicht erweitern ohne `debug_auswertung.py`):
`instrument-nachgebaut` · `instrument-misst-nichts` · `windows-pfad` · `zeilenenden` ·
`agent-fehlbericht` · `agent-gestorben` · `plugin-defekt` · `doku-veraltet` · `sichtbarkeit` ·
`ungeklaerter-widerspruch` · `sonstiges`

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

## Step 2.95: Zeilenenden-Waechter (PFLICHT, NEU v5.11.0)

**Nach der Kette, vor dem Bericht.** Kein einzelner Fix darf die Zeilenenden einer Datei
kippen.

```bash
# Der Snapshot aus Step 0 ist der Vorher-Stand — er wird hier zum Messinstrument.
MEMDIR=$(get_memory_dir "$PROJ" 2>/dev/null) || MEMDIR=""
mind_zeilenenden_waechter "$MIND_SNAPSHOT_DIR" "$PROJ" "$MEMDIR"
RC=$?
[ "$RC" = 2 ] && echo "⛔ WAECHTER UNGUELTIG — Zeilenenden in diesem Lauf NICHT geprueft."
```

⛔ **Rueckgabe 2 ist ein BEFUND, kein Nebensatz.** Sie heisst: der Waechter hat hoechstens
eine Datei verglichen und damit **nichts** geprueft. Das gehoert als offener Punkt in den
Bericht — niemals als „keine Abweichung".

⛔ **Bis v5.12.0 stand hier ein 12-zeiliger Codeblock**, der `$PROJ/$z` fuer **jeden**
Snapshot-Pfad bildete. Ein Snapshot hat aber vier Zweige (`project/`, `rules/`, `global/`,
`memory/`), und keiner liegt unter `$PROJ/<zweig>/`. Uebrig blieb die eine Datei in der
Snapshot-Wurzel: **gemessen 1 von 68** (Zustellplan, 22.08.2026). Der Waechter meldete
„keine Abweichung" und hatte 67 Dateien nie angesehen.

⚠ **Warum das so lange hielt:** Ein Codeblock in einer Markdown-Datei ist von keinem
Prueffall aufrufbar. Die Logik liegt deshalb seit v5.13.0 in `lib.sh`
(`mind_zeilenenden_waechter`, `mind_schnappziel`) und wird von `tests/test_zeilenenden.sh`
gefahren — mit einem kuenstlichen Snapshot, in dem **genau eine** Datei gekippt ist.

⛔ **Gemessen wird der CRLF-ANTEIL, nicht die Zeilenzahl.** Eine Zusicherung „Zeilenzahl
unveraendert" ist bei genau diesem Fehler **gruen** — sie hat ihn schon einmal durchgelassen.

**Warum es das gibt:** Eine Reparaturrunde kippte in `APP - Zustellplan` **4 Quelldateien**
von LF nach CRLF, gegen deren `.editorconfig`. Der Diff wuchs auf **6417/6152 Zeilen statt
311/46** — der eigentliche Fix darin war winzig und im Rauschen nicht mehr auffindbar.
Ein zweiter Fall riss einen Ersetzungsanker, weil die Zieldatei CRLF trug und das Muster LF.

⚠ **Gekippte Zeilenenden werden GEMELDET, nicht stillschweigend zurueckgedreht.**
Zurueckdrehen waere ein zweiter unbeauftragter Eingriff — und in einem Projekt, das
bewusst CRLF fuehrt, der falsche. Der Bericht nennt Datei und Anteil; der Snapshot aus
Step 0 macht die Ruecknahme in einem Schritt moeglich.

## Step 2.96a: `sync-stand` setzen (PFLICHT, NEU v5.7.0)

**Direkt nach einem tatsaechlich gelaufenen Sync** — und zwar unabhaengig davon, ob eine
Schuld bestand:

### ⛔ v5.19.0: `SYNC_LIEF` wird ABGELEITET, nicht behauptet

Bis v5.18.0 stand hier `[ "$SYNC_LIEF" = "ja" ]` — und **kein Code im ganzen Plugin hat
diese Variable je zugewiesen** (gemessen 24.08.2026: 2 Lesezugriffe, **0 Zuweisungen**).
Sie wurde vom ausfuehrenden Modell aus Absicht gesetzt. Das ist woertlich
Selbsteinschaetzung — genau das, was `cleaner_belege.py` seit v5.18.0 ueberall sonst als
untaugliche Belegquelle ersetzt.

```bash
# --- Was ist tatsaechlich gelaufen? Aus der Spur, nicht aus der Erinnerung. ---
_SF="$SCOPES_FILE"; [ -f "$_SF" ] || _SF="${SCOPES_FILE}.done"   # Step 2.9 hat umbenannt
# ⛔ v5.30.0: NUR DIE EIGENEN MARKEN ZAEHLEN. Vorher zaehlte `grep -c '^skill='`
#    jede Zeile der geteilten Datei — auch die eines fremden Laufs. Genau daraus
#    entstand die Gefahr: zwei Laeufe, deren Summe 5 erreicht, tilgen gemeinsam
#    eine Schuld, die keiner von beiden abgearbeitet hat.
#    ⚠ Faellt `$LAUF` aus (leer), wird auf die alte Zaehlung zurueckgefallen —
#      fail-safe Richtung "eher Teilsync": lieber eine Mahnung zu viel.
if [ -n "${LAUF:-}" ]; then
  _SKILL_IST=$(grep -c "^skill=.*|$LAUF\$" "$_SF" 2>/dev/null)
else
  _SKILL_IST=$(grep -c '^skill=' "$_SF" 2>/dev/null)
fi
_SKILL_IST=${_SKILL_IST:-0}
_SKILL_SOLL=5

_BILANZ="$PROJ/.claude-mind/lauf-bilanz.txt"
mind_agent_bilanz "$PROJ" > "$_BILANZ" 2>/dev/null; _BRC=$?
_DIS=$(sed -n 's/.*DISPATCH=\([0-9]*\).*/\1/p' "$_BILANZ" | head -1); _DIS=${_DIS:-0}
# Soll: 4 Bereiche. 3, wenn custom-context mangels Dateien entfaellt (die EINZIGE
# erlaubte Auslassung, mind-update Step 3.5). 0 nur bei --quick.
_AGENT_SOLL="${AGENT_SOLL:-4}"

# ⛔ Der Rueckgabewert der Bilanz REICHT NICHT — am Code gemessen, 24.08.2026.
#    mind_agent_bilanz zaehlt nur, was in der Quittung STEHT. Ein Agent, der nie
#    dispatcht wurde, hinterlaesst gar keine Zeile und ist unsichtbar. "2 dispatcht,
#    beide mit Ergebnis" ergibt deshalb Rueckgabe 0 — "alles gut" — und waere als
#    vollstaendig durchgewunken worden. Das ist exakt der Creator-Lauf vom 24.08.
#    Deshalb entscheidet die ZAHL, nicht der Zustand. (tests/test_teilsync.sh, Fall 18)
if [ "$_SKILL_IST" -eq 0 ] 2>/dev/null; then
  SYNC_LIEF="nein"
elif [ "$_BRC" = 0 ] && [ "$_DIS" -ge "$_AGENT_SOLL" ] 2>/dev/null \
     && [ "$_SKILL_IST" -ge "$_SKILL_SOLL" ] 2>/dev/null; then
  SYNC_LIEF="ja"
else
  SYNC_LIEF="teil"
fi
# v5.22.0: der Bestands-Pass zaehlt mit. Jeder der fuenf Skills quittiert
# `bestand=<skill>:<geprueft>/<stichprobe>` in `analyzed-scopes`; fehlt eine
# Quittung, hat der Skill seinen Bestand nicht angesehen.
#
# ⭐ Es braucht KEIN neues Feld und KEINE Aenderung an mind_sync_voll: die
#    zerlegt `umfang=` schon in a/b-Paare und macht aus jedem a<b einen
#    Teilsync. Ein angehaengtes `<n>/5 bestand` wirkt damit sofort.
#
# ⛔ Gezaehlt wird in `.done`, falls Step 2.9 die Marke schon umbenannt hat —
#    sonst zaehlt dieser Block je nach Reihenfolge mal 5 und mal 0, und das
#    saehe wie ein Befund ueber die Skills aus statt wie ein Lesefehler.
_SC="$PROJ/.claude-mind/analyzed-scopes"
[ -f "$_SC" ] || _SC="$PROJ/.claude-mind/analyzed-scopes.done"
_BEST=$(grep -c '^bestand=' "$_SC" 2>/dev/null); _BEST=${_BEST:-0}
case "$_BEST" in ''|*[!0-9]*) _BEST=0 ;; esac

UMFANG="$_SKILL_IST/$_SKILL_SOLL skills $_DIS/$_AGENT_SOLL agents $_BEST/5 bestand"

# ⚠ Ein Skill OHNE Quittung ist ungeprueft — und das muss im Merker stehen,
#   nicht nur in der Zahl. Sonst weiss der naechste Lauf, DASS etwas fehlte,
#   aber nicht WAS: derselbe blinde Fleck, den v5.19.0 bei den Agents behoben hat.
for _s in mind-claudemd mind-memory mind-rules mind-files mind-update; do
  grep -q "^bestand=$_s:" "$_SC" 2>/dev/null || UNGEPRUEFT_BESTAND="${UNGEPRUEFT_BESTAND:-}bestand-$_s,"
done
UNGEPRUEFT_BESTAND="${UNGEPRUEFT_BESTAND%,}"

# Welche Bereiche gelten als ungeprueft? Zwei Quellen, weil sie VERSCHIEDENE
# Ausfaelle sehen: die Bilanz kennt leere und stumme Rueckgaben, aber einen nie
# dispatchten Bereich kennt nur die Abwesenheit in der Quittung.
_Q="$PROJ/.claude-mind/agent-quittung.jsonl"; UNGEPRUEFT=""
for _b in claude-md memory rules custom-context; do
  if ! grep -q "\"bereich\":\"$_b\"" "$_Q" 2>/dev/null \
     || grep -q "UNGEPRUEFT: $_b" "$_BILANZ" 2>/dev/null; then
    UNGEPRUEFT="${UNGEPRUEFT}${_b},"
  fi
done
UNGEPRUEFT="${UNGEPRUEFT%,}"
# v5.22.0: fehlende Bestands-Quittungen kommen dazu. `ungepruef=` ist seit
# v5.21.1 selbst ein Teilsync-Grund — ein ausgefuelltes Feld macht das Tor
# strenger, ein leeres aendert nichts. Fail-safe-Richtung bleibt also gleich.
if [ -n "${UNGEPRUEFT_BESTAND:-}" ]; then
  UNGEPRUEFT="${UNGEPRUEFT:+$UNGEPRUEFT,}$UNGEPRUEFT_BESTAND"
fi
```

⚠ **`nein` und `teil` sind verschiedene Dinge.** `nein` heisst: kein einziger Skill lief
(Abbruch in Step 0/1) — dann entsteht kein Merker und die Schuld bleibt unberuehrt
bestehen. `teil` heisst: die Kette lief, der Fan-out nicht — dann entsteht ein Merker,
**der seine eigene Unvollstaendigkeit traegt**.

```bash
if [ "$DRY_RUN" = "no" ] && [ "$SYNC_LIEF" != "nein" ]; then
  mkdir -p "$PROJ/.claude-mind/rescued"
  # v5.11.0: `tokens=` ist PFLICHT. Ohne die Zahl gilt der Merker beim naechsten
  # Lauf als verbraucht (mind_sync_frisch) -- lieber eine Mahnung zu viel als
  # eine Kette, die dauerhaft schweigt.
  _STOK=""
  if type mind_kontext_tokens >/dev/null 2>&1; then
    _STP=$(ls -t "$HOME/.claude/projects/$(hash_project_dir "$PROJ")"/*.jsonl 2>/dev/null | head -1)
    [ -n "$_STP" ] && _STOK=$(mind_kontext_tokens "$_STP" 2>/dev/null)
  fi
  # v5.19.0: `umfang=` ist der Beleg, `ungepruef=` sagt WAS fehlt. Ohne beide
  # sieht ein Teilsync im Merker aus wie ein Vollsync — und pre-compact.sh
  # loescht dann die Schuld fuer Arbeit, die nie stattgefunden hat.
  printf 'ts=%s\ntokens=%s\numfang=%s\nungepruef=%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "${_STOK:-0}" "$UMFANG" "$UNGEPRUEFT" \
    > "$PROJ/.claude-mind/rescued/sync-stand"
  [ "$SYNC_LIEF" = "teil" ] && \
    echo "⚠ TEILSYNC: $UMFANG — ungeprueft: ${UNGEPRUEFT:-(nichts)}. Die Schuld bleibt bestehen."

  # v5.7.5: War dies ein Sync WEGEN der Token-Schwelle? Dann ist die Kompaktierung faellig.
  # Ein Handaufruf bei 100k Kontext soll NICHT zum Kompaktieren draengen — daher die
  # Bedingung. Ohne sie laege der Merker nach jedem Probelauf im Weg.
  _MTOK=""
  if type mind_kontext_tokens >/dev/null 2>&1; then
    _MTP=$(ls -t "$HOME/.claude/projects/$(hash_project_dir "$PROJ")"/*.jsonl 2>/dev/null | head -1)
    [ -n "$_MTP" ] && _MTOK=$(mind_kontext_tokens "$_MTP" 2>/dev/null)
  fi
  _MSCHW="${MIND_SYNC_AT_TOKENS:-0}"
  if [ -n "$_MTOK" ] && [ "$_MSCHW" -gt 0 ] 2>/dev/null && [ "$_MTOK" -ge "$_MSCHW" ] 2>/dev/null; then
    printf 'ts=%s\ntokens=%s\nblocks=0\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_MTOK" \
      > "$PROJ/.claude-mind/rescued/COMPACT-FAELLIG"
    echo "Kompaktierung faellig: Kontext bei $_MTOK Tokens."
  fi
fi
```

⛔ **Seit v5.11.0 zaehlt der ZUWACHS, nicht die Existenz.** `sync-stand` traegt
`tokens=<stand beim Sync>`; Mahnung und Zwang schweigen nur, solange der Kontext um
weniger als `MIND_SYNC_DELTA` (Vorgabe 60 000 — die Kosten eines Syncs) gewachsen ist.

**Warum das geaendert wurde:** Der einzige Verbraucher des Merkers ist `pre-compact.sh`,
und der feuert seit `autoCompactEnabled: false` (v5.7.7) nur noch bei einem **von Hand
getippten** `/compact`. Ein einziger `/mind-all`-Lauf schaltete die ganze Kette damit
**dauerhaft** stumm. **Gemessen 21.08.2026:** der Merker lag seit 08:00 in
`APP - Palvedo`, die Sitzung dort stand bei **950 000 Tokens**, und auf die Frage, warum
kein `/mind-all` komme, lautete die Antwort korrekt *„mechanisch steht nichts aus"*.
Die Mechanik hat die Wahrheit gesagt — der Merker war schuld.

⚠ **Ein Merker ohne `tokens=` gilt als verbraucht.** Damit heilt sich der Bestand beim
ersten Lauf selbst, statt eine Altlast weiterzutragen.

*(Bis v5.10.0 galt hier:)* Solange er liegt, schweigen Token-Mahnung
(`prompt-submit.sh`) und Token-Zwang (`stop.sh`) — der Sync ist ja erledigt. `pre-compact.sh`
verbraucht ihn bei der naechsten Kompaktierung und erzeugt deshalb **keine neue Schuld**; damit
ist der Ausloeser fuer den naechsten Zyklus automatisch wieder scharf.

## Step 2.96b: Die Kompaktierung ist der NAECHSTE Schritt (NEU v5.7.5)

Liegt `COMPACT-FAELLIG`, endet die Antwort mit **genau dieser Bitte, als letztem Satz**:

```
Bitte jetzt /compact eingeben — der Sync hat den Kontext um 40-60k Tokens gefuellt, und
ohne Kompaktierung wandert genau das in das naechste Kontextfenster.
```

⛔ **Nicht umformulieren zu „die Kompaktierung kommt von selbst".** Genau so stand es bis
v5.7.4, und genau das war der Fehler: sie kommt nur, wenn der Sync teuer genug ausfaellt, um
den Kontext ueber die Schwelle zu schieben. Faellt er billig aus, bleibt sein Ertrag stehen —
und wird in die naechste Zusammenfassung uebernommen, statt von ihr ersetzt zu werden.

⚠ **Auslosen kann das Plugin sie nicht** — drei unabhaengige Belege (Hook-Doku, Werkzeugliste,
CLI-Binaerdatei). **Auch der Assistent kann es nicht**: es gibt kein Werkzeug fuer `/compact`.
Der Merker erzwingt deshalb nicht die Kompaktierung, sondern nur, dass die Bitte an der
richtigen Stelle steht. `stop.sh` blockt dafuer bis zu `MIND_COMPACT_MAX_BLOCKS` (Vorgabe 2)
Mal; danach gibt er auf, damit niemand festgenagelt wird, der bewusst nicht kompaktieren will.


## Step 2.96: Schuld begleichen (PFLICHT, NEU v5.2.1)

Erst **nach** einem tatsaechlich gelaufenen Sync (nicht im Probelauf, nicht nach Abbruch von
mind-update) wird die offene Schuld entfernt — sonst blockt der Stop-Hook zu Recht weiter:

⛔ **Hier steht `= "ja"` und bleibt dabei — anders als in Step 2.96a.** Ein Teilsync setzt
zwar einen Merker (der seine Unvollstaendigkeit selbst traegt), begleicht aber **keine
Schuld**. Der Unterschied ist der ganze Zweck von v5.19.0: `sync-stand` sagt „so weit bin
ich gekommen", `OPEN` sagt „das steht noch aus". Wer beides an dieselbe Bedingung haengt,
hat wieder zwei Zustaende statt drei.

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

# ⛔ v5.28.0: Die PLAN-PAUSE wird IMMER aufgehoben — ausserhalb des
#    SYNC_LIEF-Blocks und auch, wenn gar keine Schuld bestand.
#    Sonst liefe ein von Hand gestarteter Sync waehrend eines Plans zwar
#    durch, der Merker bliebe aber liegen und legte die naechsten Stunden
#    still. Ein Merker, der einen erledigten Zustand behauptet, ist genau
#    der `PENDING`-Fehler aus v5.2.1 — eine Quittung fuers Reden statt einer
#    fuer die Arbeit.
#    ⚠ Auch im Probelauf: `--dry-run` aendert keine Context-Datei, aber der
#      Merker ist Ablaufzustand, kein Inhalt.
if command -v mind_plan_frei >/dev/null 2>&1 \
   && [ -f "$PROJ/.claude-mind/PLAN-AKTIV" ]; then
  mind_plan_frei "$PROJ" && echo "Plan-Pause aufgehoben (PLAN-AKTIV entfernt)."
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
Ausfuehrungstiefe: <UMFANG>          ⛔ PFLICHT, v5.19.0 — aus $UMFANG, nicht aus dem Kopf
NICHT GEFAHREN:    <was und warum>   ⛔ PFLICHT — "(nichts)" ist die Antwort bei 5/5 + 4/4
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

### ⛔ `Ausfuehrungstiefe` und `NICHT GEFAHREN` sind PFLICHT (NEU v5.19.0)

**Ein kurzer Bericht kann zwei voellig verschiedene Dinge heissen:** „es war nichts zu tun"
oder „es wurde abgekuerzt". Bis v5.18.0 waren die beiden **von aussen nicht
unterscheidbar** — auch nicht an der Laufzeit, denn die haengt an der Zahl der Befunde.

Genau daran ist am 24.08.2026 die Frage *„mind all war ziemlich schnell, woran liegt das?"*
haengengeblieben. Die ehrliche Antwort war: **0 von 4 Agents gelaufen** — aber im Bericht
stand davon nichts, weil es dafuer keine Zeile gab.

```
Ausfuehrungstiefe: 5/5 skills 0/4 agents
NICHT GEFAHREN:    knowledge-sync (Kontext 914k) -> claude-md, memory, rules, custom-context
                   Diese Bereiche gelten als UNGEPRUEFT, nicht als unauffaellig.
```

- Beide Zeilen kommen aus `$UMFANG` und `$UNGEPRUEFT` (Step 2.96a) — **aus der Spur, nicht
  aus der Erinnerung.**
- `NICHT GEFAHREN: (nichts)` ist die zulaessige Antwort bei einem vollstaendigen Lauf.
  **Ein leerer Wert ist es nicht** — dieselbe Regel wie bei `listeverbesserungen.md`.
- Ein Teilsync gehoert zusaetzlich als Befund der Klasse **`lauf-unvollstaendig`** in die
  Befundzeilen von Step 2.95. Nicht als `agent-gestorben`: dort lieferte ein **gestarteter**
  Agent nichts, hier wurde nie einer gestartet. Der Unterschied ist nicht akademisch —
  am 24.08.2026 wurde derselbe Vorfall in zwei Projekten **verschieden** einsortiert, und
  solange ein Ereignis zwei Namen traegt, sieht die Wiederholungserkennung kein Muster.

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
