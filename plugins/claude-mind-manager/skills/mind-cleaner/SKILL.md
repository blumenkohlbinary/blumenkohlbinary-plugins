---
name: mind-cleaner
description: |
  [Mind Manager] Raeumt Regelbestaende auf: misst, was da ist und was wirklich laedt,
  ordnet jede Regeldatei in Hook · Skill · Slash-Command · bleibt-Rule ein und zieht
  auf Ansage GENAU EINE Datei um — mit Erhaltungs-Gate, Pfad-Gate und Rueckweg.

  ⛔ Der Vorgabelauf AENDERT NICHTS. Er berichtet. Ein Plan entsteht erst auf "ok",
  angewendet wird erst nach Freigabe des Plans. Hooks werden nur GEMELDET, nie
  gebaut — dafuer gibt es --hook-bauen auf ausdrueckliche Ansage.

  Use when the user says "mind cleaner", "regeln aufraeumen", "startkontext kuerzen",
  "was kann weg aus den rules", "regel zu skill machen", or "/mind-cleaner".
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# /mind-cleaner — Regelbestände aufräumen

## ⛔ PFLICHTSCHRITTE — dieser Skill fuehrt aus, was hier steht (NEU v5.25.0)

```
PFLICHTSCHRITTE
bestandsaufnahme
cleaner_audit
cleaner_einordnung
cleaner_grenzen
cleaner_leitplanke
cleaner_ratsche
cleaner_rebuild
cleaner_tor
cleaner_umzug
cleaner_wirkung
ladeprotokoll_auswertung
mind_debug_write
mind_snapshot
```

**Vor dem ersten Schritt, ohne Ausnahme:**

```bash
mind_schritt_start "$PROJ" mind-cleaner bestandsaufnahme cleaner_audit cleaner_einordnung cleaner_grenzen cleaner_leitplanke cleaner_ratsche cleaner_rebuild cleaner_umzug ladeprotokoll_auswertung mind_debug_write mind_snapshot
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

## ⛔ Der Ablauf ist dreistufig, und jede Stufe braucht ein OK

```
1. BERICHT     /mind-cleaner [--bereich global|projekt|alles]     aendert NICHTS
      ↓  Nutzer sagt ok
2. PLAN        /mind-cleaner --plan [--bereich …]                  schreibt einen Plan
      ↓  Nutzer gibt den Plan frei
3. ANWENDEN    /mind-cleaner --umzug <datei>                       GENAU EINE Datei
               /mind-cleaner --rebuild <datei> [--auto]           GENAU EINE Datei
```

**Nutzer-Entscheidung 24.08.2026, wörtlich:** *„er soll erstmal berichten dann wenn ich
ok gebe plan schreiben und anwenden"*.

⛔ **Das weicht bewusst von den v5.0.0-Skills ab**, die autonom anwenden. Der Grund steht
im Entwurf und gilt: hier wird die **Wissensbasis zerschnitten**, nicht eine Zahl korrigiert.
Ein falsch herausgeschnittener Satz fällt erst auf, wenn er gebraucht wird — und dann fehlt er.

Weitere Aufrufe:

```
/mind-cleaner --audit              der Fuenf-Gruppen-Bericht (NEU v5.18.0)
/mind-cleaner --nachmessen         nach einer NEUEN Sitzung: hat der Umzug gewirkt?
/mind-cleaner --hook-bauen <datei> Hook erzeugen — NUR auf ausdrueckliche Ansage
```

## ⭐ `--audit` — der Bericht, in dem alles zusammenläuft

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_audit.py" \
       --bereich "$PROJ" --nur global|projekt|alles
```

Er fährt **alle sechs Werkzeuge** und legt fünf Gruppen vor — **Gruppe 5 zuerst:**

```
5a  kein Verstoss vorliegend            vielleicht spaeter messbar
5b  GRUNDSAETZLICH NICHT LOGGBAR        ⭐ der Kern, nicht der Rest
1   belegt noetig                       bleibt, wo es ist
2   falsch platziert                    Ort A -> Ort B, mit Zielpfad
3   doppelt                             eine Stelle wird Zeiger
4   belegt veraltet                     ins Archiv, mit Beleg
```

⛔ **Gruppe 5 steht oben, nicht unten.** Sie ist das ehrliche Maß dafür, wie viel der Lauf
wirklich wusste. Ein Bericht, der sie ans Ende schiebt, behauptet Sicherheit, die er nicht hat.

⭐ **Und 5b ist der Kern.** Urteils- und Prozessregeln (`keine-annahmen`, `plan-mode`,
`ursache-vor-reparatur`, `fertig-heisst-fertig`) erzeugen kaum je einen maschinell
erfassbaren Verstoß. Sie landen dort **nicht weil sie unbeobachtet blieben, sondern weil sie
unbeobachtBAR sind.** Wer 5b für eine Restmenge hält, liest den Bericht falsch.

**Zwei Belegquellen statt Selbsteinschätzung** (`cleaner_belege.py`):

| Quelle | was sie zeigt |
|---|---|
| `Debug/index.jsonl` | datierte Verstöße — wie viele, wie alt, wann zuletzt |
| Git-Historie | **Ein-Commit** = seit Anlage nie überarbeitet („Init Fossilization") |

⛔ **Die Modell-Alterung ist NICHT eingebaut — die Behauptung stand hier zu Unrecht.**
Bis v5.20.1 warb dieser Abschnitt mit *„hören sie an einem Modellwechsel auf?"*. Das Wort
*Modell* kam in `cleaner_belege.py` **null mal** vor.

**Gemessen 25.08.2026, warum es (noch) nicht lohnt:**

```
Modellwechsel sind ableitbar   claude-opus-4-7  ab 29.05. · 4-8 ab 04.06. · 5 ab 29.07.
Debug-Befunde                  142, ältester 20.08., jüngster 25.08.
davon VOR dem letzten Wechsel  0
```

**Trennschärfe heute: null.** Jede Regel wäre „nicht entscheidbar". Der Bau ist
zurückgestellt, bis das Debug-Fenster einen Modellwechsel überspannt — die Datenquelle
(`~/.claude/projects/<slug>/*.jsonl`, Feld `message.model`) ist dann ohne Handpflege da.

⛔ **Die Frage *„würdest du das auch ohne die Regel tun?"* wird NICHT gestellt.** Sie ist
nicht zuverlässig beantwortbar: am 24.08.2026 wurden **vier Regeln gebrochen, die wörtlich in
der geladenen `CLAUDE.md` standen**. Vorher hätte die Selbsteinschätzung bei jeder gelautet:
*„das mache ich sowieso richtig."*

⚠ **Die Stichwortbildung war zuerst viel zu locker** — `nicht`, `gegen`, `Regeln` als
Stichworte schrieben `env-vars.md` **56 von 106** Befunden zu, und Gruppe 5b blieb **leer**.
**Eine Belegquelle, die fast alles belegt, belegt nichts.**

---

## Step 0: Bereich bestimmen

`--bereich` steuert, wo gearbeitet wird. **Nutzer-Entscheidung 24.08.2026:** *„alles aber
ich kann dann angeben ob global oder lokal nur der projekt ordner"*.

| Wert | Bestand |
|---|---|
| `global` | `~/.claude/rules/` + `~/.claude/CLAUDE.md` |
| `projekt` | `$CLAUDE_PROJECT_DIR/.claude/rules/` + `CLAUDE.md` des Projekts |
| `alles` *(Vorgabe)* | beides |

⛔ **Fremdklon-Schutz ist Pflicht, nicht Kür.** Vor jeder Datei:

```bash
python -c "import sys; sys.path.insert(0,'$CLAUDE_PLUGIN_ROOT/references');
from learnings_quellen import upstream_datei; print(upstream_datei(PROJ, PFAD))"
```

Gehört die Datei nicht dem Nutzer (Upstream, Fremdklon), wird sie **gelistet, nie angefasst**.

---

## Step 1: Messen, was da ist

```bash
python "$CLAUDE_PLUGIN_ROOT/references/bestandsaufnahme.py" --ordner <verzeichnis>
# oder positional: ... bestandsaufnahme.py <verzeichnis>   (beides seit v5.20.1)
```

Größe, Dateizahl, Zusammensetzung. Die Kontrolle des Werkzeugs ist ein **synthetischer
Prüftext**, keine echte Datei — die erste Fassung kontrollierte gegen zwei benannte Dateien
und verweigerte dadurch die Arbeit an jedem anderen Ordner. Sie prüfte den **Ordner** statt
das **Instrument**.

## Step 2: Messen, was wirklich lädt

```bash
python "$CLAUDE_PLUGIN_ROOT/references/ladeprotokoll_auswertung.py"
```

⛔ **„Nicht im Protokoll" heißt NICHT „lädt nicht".** Gezählt werden **Ladevorgänge, keine
Tokens** — ein Budget lässt sich daraus nicht ableiten.

⭐ **Der teuerste Einzelbefund dieses Werkzeugs:** Unterverzeichnisse in `rules/` **laden
mit**. Am 23.08. kamen **267 von 920** Ladevorgängen aus einem `archive/`-Ordner, der
angelegt worden war, **um den Bestand zu kürzen**. Die Kürzung hatte ihn verdoppelt.
Wer den Umfang eines Regelbestands misst, misst **rekursiv**.

## Step 3: Einordnen

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_einordnung.py" --verzeichnis <pfad>
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_einordnung.py" --selbsttest
```

Vier Wege, nach dem **Moment der Erkennbarkeit**:

| woran erkennbar? | → |
|---|---|
| am **Werkzeugaufruf** (Pfad, Endung, Befehlswort) | **Hook** |
| an der **Aufgabe**, oder der Nutzer ruft es **beim Namen** | **Command** (`/name`) |
| **gar nicht**, gilt vor jedem Eingriff | **bleibt Rule** |

⛔ **Hier standen bis v5.27.0 VIER Wege — „Skill" und „Slash-Command" getrennt.**
Das sind nicht zwei Dinge: ein Command **ist** das, was du mit `/name` tippst, und
`lokal`/`global` sagt nur, wo seine Datei liegt. Nutzer-Befund, wörtlich: *„ich will
keine Skill-Typen, woher soll ich wissen dass es 2 gibt."*
⚠ **Und die Prosa versprach mehr als der Code hatte:** `cleaner_einordnung.py` gab
nie eine Klasse `SLASH-COMMAND` aus — nur `HOOK-KANDIDAT`, `COMMAND`, `UNKLAR`. Wer
auf das vierte Urteil wartete, wartete auf eines, das es nicht gibt.

⛔ **Die harte Kante: was ERZWUNGEN werden muss, wird NIE ein Command.** Das ist keine
Vorsicht, sondern Herstelleraussage — die Skills-Doku sagt bei nachlassender Wirkung
*„…or use hooks to enforce behavior deterministically"*.

⛔ **Das Werkzeug nennt seine eigenen Fehlurteile.** Zwei sind gemessen und stehen dauerhaft
in seiner Ausgabe:

- `autonom-arbeiten.md` → Vorschlag **COMMAND**, Imperativdichte **0,00** — die Datei enthält
  **null** Imperativ-Wörter und ist trotzdem eine der direktivsten des Bestands.
  **Deutsche Prosa befiehlt ohne Schlüsselwort.**
- `keine-annahmen.md` → Vorschlag **HOOK-KANDIDAT**, weil sie **andere Regeldateien
  zitiert**. Eine Zitierung ist kein Aufruf-Anker.

**Daraus folgt und ist nicht verhandelbar:** ein COMMAND-Vorschlag wird **nie ohne menschliche
Bestätigung** angewendet.

## Step 4: Die Leitplanke herausschneiden — der schwierigste Teil

**Was bleibt, muss allein tragen; was geht, muss vollständig sein.**

**Was in der Kurz-Rule bleibt:** das Verbot · die Entscheidung in einem Satz · die Zahl, die
man vor dem Anfangen wissen muss · **der Pfad zum Volltext** · **der Command-Aufruf**.
**Was in den Command geht:** Herleitung · Belege · Messreihen · Fallen · Beispiele.

⭐ **Die Trennlinie in einem Satz — Bremse gegen Anleitung:**

> Eine **Bremse** hält dich vom Falschen ab, **bevor** du merkst, dass du nachschlagen
> solltest — sie muss in der Rule stehen, sonst kommt sie zu spät. Eine **Anleitung**
> brauchst du erst, **während** du arbeitest; dann hast du den Command ohnehin geladen.

*„suspend nur auf ausdrückliche Ansage"* ist eine Bremse — wer aufräumen will, lädt keinen
Skill dafür. *„834–941 MB/s, wer weniger misst, hat seinen Aufbau gemessen"* ist Anleitung.

### Werkzeug (NEU v5.24.0) — es legt Kandidaten vor, es schneidet nicht

⛔ **Hier stand bis v5.23.1 „Hier gibt es kein Werkzeug."** Das stimmte, und es war der Grund,
warum `workstation-fernzugriff` nach dem Umzug mit **63 Zeilen** liegenblieb, während die
vier Geschwister bei 19–33 lagen — mit MAC-Adressen, Durchsatztabellen und
`sudoers`-Dateinamen darin. Kein Gate hat je danach gefragt.

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_leitplanke.py" \
       --verzeichnis "$ZIEL_RULES" --skills "$HOME/.claude/skills"
```

Es meldet drei Formklassen als **Kandidaten**: `adresse` (IP/MAC) · `syspfad` (`/etc`, `/usr`,
`/var`) · `befehl` (Codezeile mit konkreten Argumenten, ohne `<platzhalter>`/`$VARIABLE`).
Dazu Zeilenzahl gegen die **im Lauf gemessene** Korpus-Spanne, den Bremsanteil und ob der
Zeiger Pfad **und** Command nennt.

⛔ **Zahlen sind ausdrücklich KEINE Klasse.** Im echten Bestand trägt die Bremse ihre Messung
mit („834–941 MB/s" steht *in* der Fehlmessungs-Warnung). Ein Filter, der Zahlen meldet,
schneidet die Bremse weg.

⛔ **Eine Zeile mit ⛔/⚠/NIE/NUR wird nie Kandidat** — auch dann nicht, wenn eine Adresse
darin steht. `10.10.10.1 ZUERST, sonst ist das ein BEFUND` **ist** die Bremse.

⚠ **Kandidat ist kein Urteil.** Ob ein Satz Bremse oder Anleitung ist, ist eine
Bedeutungsfrage; mechanisch entscheidbar sind nur Formmerkmale. Die Liste sieht ein Mensch
durch — genau wie beim COMMAND-Vorschlag aus Step 3.

## Step 5: Umziehen — vier Gates, alle müssen halten

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_umzug.py" \
  --alt <snapshot/alt.md> --kurz <neue-kurz.md> --skill <skills/<name>/SKILL.md>
```

| Gate | prüft |
|---|---|
| **ERHALTUNG** | `Zeilen(Kurz) + Zeilen(Skill) ≥ Zeilen(Alt)` — Umziehen verschiebt, es kürzt nicht |
| **ERREICHBARKEIT** | die Kurz-Rule trägt **kein** `paths:`/`globs:` — eine Leitplanke mit Ladebedingung ist keine |
| ⭐ **PFAD** | die Kurz-Rule nennt den **Zielpfad wörtlich** |
| **BESCHREIBUNG** | ≥ 40 Zeichen, und Name+description unter der Kappung bei **1 536** `[DOKU]` |
| ⭐ **INHALT** (NEU v5.24.0) | jede **Marke** der alten Regel ist in Kurz **oder** Skill wiederzufinden |
| ~ *Hinweis* `COMMAND` | die Kurz-Rule nennt `/<name>`. **Kein Bruch** — der Pfad trägt |

### ⭐ Warum Gate 5 nötig war — gemessen am eigenen Lauf, 28.08.2026

`ERHALTUNG` zählt **Zeilen**. Beim Kürzen von `workstation-fernzugriff` (63 → 36) war der
Skill 705 Zeilen lang: `36 + 705 ≥ 63` hält mühelos — und der Punkt *„das `-i` ist meist
nötig, `gnome-session` hält einen block-Inhibitor"* wäre trotzdem verschwunden. Er stand
**nur** in der alten Rule. Gefunden hat ihn erst ein von Hand danebengelegtes
`coverage_gate.py`. Gate 5 macht diese Handarbeit zum Gate.

⚠ **Es schließt AUSLASSUNG aus, nicht VERTAUSCHUNG.** Eine Marke, die vom richtigen an den
falschen Ort wandert, sehen beide Gates nicht. Die menschliche Bestätigung bleibt Pflicht.

⛔ **Der Command ersetzt den Pfad NICHT.** Er ist ein Hinweis, kein Gate — die Messung unten
sagt Pfad **4/4** gegen Command-Auswahl **20–84 %**. Wer den Pfad später entfernt, „weil der
Command ja dasteht", macht den Umzug wieder unzuverlässig.

### ⭐ Warum das PFAD-Gate das wichtigste ist — gemessen 24.08.2026

| Zugriffsweg | Trefferquote |
|---|---|
| Kurz-Rule in `rules/` | **100 %** (Ladeprotokoll, 884× `session_start`) |
| Volltext über den **Pfad** | **4 von 4** (eigene Sonden, je 1 Werkzeugaufruf) |
| Volltext über **Command-Auswahl** | **20–84 %** (Vercel-Evals, 200+ Tests) |

Ein Zeiger auf einen Command-**Namen** verlässt sich auf die 20-%-Mechanik. Ein Zeiger auf
einen **Pfad** nicht. ⚠ Die aussagekräftigste Sonde nannte die Datei **beiläufig**
(*„Alles Weitere steht in …"*, ohne Verbotszeichen) — und wurde trotzdem gelesen.

⛔ **Die Gates schließen VERLUST aus, nicht VERTAUSCHUNG.** Ein Umzug, der die Leitplanke in
den Command schiebt und die Erklärung in der Rule lässt, besteht **alle vier**.

## Step 6: Die `description` schreiben

- sagt **worum** es geht, nennt die **Auslösewörter**, die ein Nutzer wirklich benutzt
- ⛔ **kein Änderungsprotokoll** — im Zustellplan lag eine mit **1 033** Zeichen, die
  `v13..v34` aufzählte
- ⚠ **Die 200-Zeichen-Grenze aus der Memory-Welt gilt hier NICHT.** Memory hat einen eigenen
  Auswähler mit Grenze 5; Skills haben **keinen** (am Binärprogramm 2.1.237 nachgesehen).
  Die Kappung liegt bei 1 536. Gemessen half **direktiver Stil**, nicht Kürze.

### ⛔ Step 5b: Stille Kappungen — PFLICHT vor jedem Umzug (NEU v5.17.0)

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_grenzen.py" --ziel <zieldatei> --dazu <inhalt>
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_grenzen.py" --bestand "$PROJ"
```

**Ein Werkzeug, das eine stille Grenze nicht kennt, verschiebt Inhalt an einen Ort, wo er
lautlos abgeschnitten wird.** Vorher war der Text zu lang, nachher ist er **weg** — ohne Meldung.

| Grenze | Wert | Verhalten |
|---|---|---|
| `MEMORY.md` | 200 Zeilen **oder** 25 KB | ⛔ **still** weg |
| ⭐ **`paths:`-Budget** | **1 000 Muster** | ⛔ Muster bleibt unexpandiert → **die Regel feuert nie mehr** |
| `@`-Import-Tiefe | 4 Hops | ⛔ still nicht aufgelöst |
| Skill-`description` | 1 536 Zeichen | ⛔ in der Liste gekappt |
| HTML-Kommentare | — | ⛔ **vor jeder Injektion entfernt** |
| Hook-Ausgabe | 10 000 Zeichen | Rest in Datei |
| Datei | 4 MiB | **laut** übersprungen |

⭐ **Das `paths:`-Budget ist die gefährlichste.** Alle anderen kappen Inhalt. Diese eine macht
eine **ganze Regel unwirksam**, ohne dass sich etwas Sichtbares ändert. ⚠ `{a,b,c}` zählt
**expandiert** — drei Muster, nicht eins.

⛔ **HTML-Kommentare sind keine Ablage.** Wer Inhalt dort „archiviert", hat ihn **gelöscht**,
nicht versteckt. Rückgabe **2 heißt NICHT MESSBAR** — kein bestandenes Gate.

## Step 7: Nachmessen und zurückrollen

```
1. Erhaltungs-Gate          nichts verloren?
2. bestandsaufnahme.py      um wie viel ist der Bestand gefallen?
3. NEUE Sitzung + Ladeprotokoll   ist die Datei WEG aus session_start?
4. erst dann die naechste
```

⛔ **Schritt 3 kann der Befehl NICHT selbst** — er braucht eine frische Sitzung. Bis das
Protokoll es belegt, heißt der Lauf **„verschoben, Wirkung unbestätigt"**.

### ⭐ Step 7a: Das Wirkungs-Gate — hat die Korrektur die Kennzahl bewegt?

**Nutzer-Befund 30.08.2026, wörtlich:** *„`cleaner_duplikate.py` hat mir 447
Duplikate gemeldet … Ich habe die Zahl gelesen und trotzdem nur umgeräumt. **Ein
Duplikat, das umzieht, ist immer noch ein Duplikat** — jetzt nur in zwei
Dateien, die beide immer laden."*

⛔ **Modularize ist NICHT Deduplizieren.** Modularize **verschiebt** — die Summe
bleibt gleich, und der Command sagt das selbst (*„Modularize spart KEINEN
Kontext"*). Deduplizieren macht eine Stelle zum **Zeiger**; erst dann fällt die
Summe. Beides sieht im Bericht gleich erfolgreich aus.

```bash
W="$CLAUDE_PLUGIN_ROOT/references/cleaner_wirkung.py"
python "$W" --vorher  "$PROJ"                       # VOR dem Anwenden
# … anwenden …
python "$W" --nachher "$PROJ" --erwartet duplikate,zeilen
```

⭐ **Der Fingerabdruck eines verschobenen statt behobenen Duplikats:**
`wurzelzeilen` fällt, **`zeilen` bleibt stehen**. Genau diese Schere meldet das
Gate mit Rückgabe 1.

⛔ **PFLICHT nach jedem `--umzug` und jedem `--rebuild --anwenden`.** Ein
Werkzeug ohne Aufrufer ist ein totes Werkzeug — dieselbe Kern-Invariante wie
„kein Tool ohne Companion-Rule", eine Ebene höher.

⚠ **Es misst die KENNZAHL, nicht die GÜTE.** Ein Umbau, der die Zahl senkt und
den Inhalt verstümmelt, kommt hier grün durch. Dafür sind die Gates aus Step 5.

### ⛔ Step 7c: Das Kontext-Tor rückwärts — über den GANZEN Bestand

`--audit` fährt es seit v5.26.0 als **Gruppe 6** mit; die Vorschrift steht in
[references/kontext-tor.md](../../references/kontext-tor.md). Die fünf
Context-Commands fragen **vor** dem `ADD`, `--audit` fragt über den **Bestand**.

⛔ **Nur vorwärts ließe den Altbestand stehen; nur rückwärts ist der Zustand von
heute, der nachweislich wächst.** Beide Richtungen oder keine.

### ⭐ Step 7b: Die Ratsche — damit aufgeräumt auch aufgeräumt BLEIBT (NEU v5.17.0)

```bash
# beim Archivieren — der Grund ist PFLICHT
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_ratsche.py" \
       --archiviere <datei> --grund "<warum es weggeht>" --projekt "$PROJ"

# bei jedem Lauf
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_ratsche.py" --pruefe --projekt "$PROJ"
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_ratsche.py" --verlauf --projekt "$PROJ"
```

⛔ **Sie misst WIEDERAUFERSTEHUNG, nicht Bytes.** Eine Größenbremse wäre falsch: ein Bestand
**darf** wachsen, neues Wissen ist kein Fehler. **Eine Bremse gegen legitimes Wachstum ist
eine Bremse gegen Lernen.**

Was nicht passieren darf, ist etwas anderes — dass etwas **bewusst Herausgenommenes**
unbemerkt zurückkommt:

> *„`MIND_NOTFALL_TOKENS` wurde am 22.08. archiviert (Grund: im Code entfallen) und steht
> seit dem 24.08. wieder in `CLAUDE.md`."*

⚠ **Eine Wiederauferstehung ist NICHT automatisch ein Fehler.** Vielleicht wurde damals zu
Unrecht archiviert. Die Ratsche meldet **mit Vorgeschichte**, sie urteilt nicht.

⛔ **Ohne `--grund` gibt es keinen Eintrag.** *„X ist zurück"* ohne *„warum es wegging"* hilft
beim nächsten Mal niemandem.

⚠ **`--verlauf` ist KEIN Gate.** Er schreibt eine Zeile je Lauf mit Dateizahl und Bytes je
Ablage — eine Kurve, die man ansehen kann. Nichts bricht daran ab.

## `--rebuild` — KÜRZEN, und zwar durch VERSCHIEBEN (NEU v5.21.0)

**Dein AUDIT/REBUILD-Auftrag vom 24.08.2026, wörtlich:** *„Behalte nur die Regeln, bei denen
du ohne sie tatsächlich Fehler machen würdest. Formuliere diese Regeln so kurz wie möglich
und verschiebe alles andere in einen archive-Ordner (**niemals dauerhaft löschen**)."*
Präzisiert am 25.08.2026: das Kriterium ist *„würdest du das **VERSTEHEN** ohne diese Rule"* —
nicht „würdest du es tun".

⛔ **Bis v5.20.2 stand hier „NIE kürzen".** Das war keine Nutzer-Entscheidung (Commit
`82efd0d` dokumentiert alle anderen namentlich, diese nicht) und setzte **kürzen** mit
**löschen** gleich. Hier wird nichts gelöscht: jeder Satz landet in der Kurzfassung oder im
Archiv, und der Weg zurück steht offen.

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_rebuild.py" --bereich "$PROJ" <regel.md>
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_rebuild.py" --bereich "$PROJ" <regel.md> --auto
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_rebuild.py" --bereich "$PROJ" <regel.md> --auto --anwenden
```

⛔ **`--anwenden` geht NUR zusammen mit `--auto`** (sonst rc=2). Ohne `--auto` ist der Lauf ein
Vorschlag, und die Auswahl der Sätze gehört dir.
⛔ **Eine Datei je Lauf** — im Code gezählt, nicht als Prosa behauptet. Ein Rebuild schneidet
die Wissensbasis; zwei auf einmal heißt zwei Schnitte, die niemand einzeln angesehen hat.

### Das Gate: SATZ-Identität, gefahren VOR dem Schreiben

| | |
|---|---|
| 1 VOLLSTÄNDIG | jeder Satz aus ALT steht in KURZ **oder** im ARCHIV |
| 2 VERSCHOBEN | kein Satz steht in **beiden** (sonst kopiert statt verschoben) |
| 3 NICHTS ERFUNDEN | kein Satz in KURZ/ARCHIV, der nicht in ALT stand |
| 4 ZEIGER | die Kurzfassung nennt den **Archivpfad wörtlich** |

⛔ **Das ERHALTUNGS-Gate aus Step 5 taugt hier NICHT.** Es zählt Zeilen, und ein Archiv mit
Kopf und Datum hat **immer** mehr Zeilen als das Entnommene — es ist trivial grün. Sein
eigener Docstring sagt es: *„Die Gates schliessen VERLUST aus, nicht VERTAUSCHUNG."*

⛔ **rc=2 heißt: die Datei wurde NICHT angefasst.** Geschrieben wird erst nach den Gates, und
dann atomar.

### Drei Sperren, die kein Gate ersetzen kann

Alle drei sind **Vertauschung, nicht Verlust** — kein Satz geht verloren, alle vier Gates
bleiben grün, und die Datei ist trotzdem schlechter. Gefunden wurden alle drei beim **Ansehen
eines Diffs**, nicht von einer Zusicherung:

- **Überschrift** — `## Was ein Snapshot enthaelt` wanderte mit seinem Absatz ins Archiv, die
  Tabelle darunter blieb überschriftenlos zurück (gemessen an `env-vars.md`, 26.08.2026).
- **Tabellenzeile** — `zerlege()` gibt jede Zeile als eigenen Satz zurück; eine mittendrin
  entnommene Zeile zerreißt die Tabelle.
- **Rückbezug** — entfernt wurde *„Teilentwarnung seit 17.08.2026: … lokales Git-Repo"*,
  stehen blieb *„Die Lücke bleibt **trotzdem** bestehen"*. Das „trotzdem" zeigt ins Leere.

⚠ Die Rückbezug-Sperre ist eine **Heuristik**: sie findet den sprachlichen Rückbezug, nicht
den gedanklichen. Ihr Fenster (50 Zeichen) steht zwischen einer Positiv- und einer
Negativkontrolle und kostet gemessen 1–2 von 16–20 Kandidaten. Sie fällt zur sicheren Seite:
**ein Fehlalarm heißt, der Satz bleibt.**

### Was `--auto` bewegen darf

**Nur BELEGE.** ⛔ **Prosa nie** (352 von 620 Aussagen im gemessenen Bestand), ⛔ **gemischt
nie** (da steckt ein Gebot drin), ⛔ **`autonom-arbeiten.md` gar nicht** — sie meldet
**0 Gebote bei 31 Kandidaten**, das dokumentierte Fehlurteil des Einordners. Eine Datei, deren
Einordnung nachweislich falsch ist, wird nicht automatisch zerschnitten.

### Der Rückweg

Das Archiv liegt unter `.claude/archiv/` — **außerhalb jedes Ladepfads**. Das ist der ganze
Punkt: `geladene_dateien()` ist rekursiv, ein Archiv unter `rules/` **lädt weiter mit**.
Zurück geht es mit `cleaner_ratsche.py --entarchiviere <n>`; die Archivdatei nennt den Befehl
in ihrer eigenen Kopfzeile.

## `--hook-bauen <datei>` — nur auf ausdrückliche Ansage

**Nutzer-Entscheidung 24.08.2026:** *„erstmal nur melden und wenn ich dann sage er soll es
bauen kann er es"*.

⛔ Ein Hook, der falsch blockt, **legt die nächste Sitzung lahm**. Deshalb: im Bericht steht
nur *„das wäre ein Hook-Kandidat, hier ist der Auslöser"*. Gebaut wird erst auf diesen
Aufruf — mit Prüffall, und ohne Eintrag in `hooks.json`, bis der Prüffall grün ist.

---

## Hard Constraints

- ⛔ **NIE ohne Snapshot.** Schlägt `mind_snapshot` fehl, bricht der Lauf ab.
- ⛔ **NIE mehr als eine Datei je Lauf.** Ein Lauf, der acht Dateien verschiebt, ist im
  Bericht nicht mehr prüfbar.
- ⛔ **NIE eine Leitplanke wegnehmen, ohne Ersatz an ihrer Stelle.**
- ⛔ **NIE behaupten, Kontext sei gespart.** Erst das Ladeprotokoll einer **neuen** Sitzung
  belegt das.
- ⛔ **NIE bei gebrochenem Gate trotzdem umziehen** — listen statt anwenden.
- ⛔ **NIE eine Datei anfassen, die nicht dem Nutzer gehört** (`upstream_datei()`).
- ⛔ **NIE LÖSCHEN.** Kein Satz verschwindet. **Kürzen heißt hier VERSCHIEBEN ins Archiv**
  (`.claude/archiv/`, liegt in keinem Ladepfad — gegen `geladene_dateien()` geprüft).
  Nutzer-Auftrag 24.08.2026, wörtlich: *„Formuliere diese Regeln so kurz wie möglich und
  verschiebe alles andere in einen archive-Ordner (**niemals dauerhaft löschen**)"*.
  ⛔ **Das Kürzen gilt NUR für `--rebuild`.** `--umzug`, `--plan` und `--hook-bauen`
  nehmen weiterhin keinen Satz aus einer lebenden Datei.
  ⚠ Bis v5.20.1 stand hier „NIE kürzen" — ohne Nutzer-Zuschreibung und im direkten
  Widerspruch zum Auftrag oben. **Kürzen war mit Löschen verwechselt worden.**

## Was der Befehl ausdrücklich NICHT tut

- **Entscheiden, was Leitplanke ist.** Er schlägt vor, der Nutzer bestätigt.
- **Den `paths:`/`globs:`-Widerspruch auflösen.** Er wird ausgewiesen, beide Seiten genannt.
- **Behaupten, der Umzug habe sich gelohnt.** ⚠ Dass ein großer Startkontext schadet, ist
  seit 24.08.2026 belegt (20 gestapelte Regeln: 96 % → 60,4 % Befolgung). **Ob 135 → 28 KB
  der richtige Betrag war, folgt aus keiner Quelle.** Belegt ist die Richtung, nicht der Betrag.


### ⛔ Step 8: Protokollieren — PFLICHT (NEU v5.21.0)

```bash
mind_debug_write "$PROJ" "mind-cleaner" "$ABSCHNITT" "$BEFUNDE"
```

**Bis v5.20.1 protokollierte KEIN einziges Cleaner-Werkzeug** — `grep -c "mind_log|logging"`
über alle neun ergab **0**, und `/mind-cleaner` meldete **nichts** an `MIND_DEBUG_DIR`,
während `/mind-all` es tut.

⛔ **Die Folge ist gemessen:** die zwei Werkzeugfehler vom 25.08.2026 (positionales Argument
still verworfen · Stamm `sicherung` gegen deutsche Prosa) sind **nur deshalb** bekannt, weil
sie zufällig auffielen. In der Wiederholungserkennung wären sie nie gelandet.

⚠ **Ein Lauf, der nichts findet, protokolliert das ebenfalls.** Ein Werkzeug, das schweigt
weil es soll, und eines, das schweigt weil es kaputt ist, sind sonst nicht zu unterscheiden
— dieselbe Lehre wie v5.3.1 (zwei Hooks mit 0 Log-Aufrufen) und v5.19.0 (die Quittung lag im
Ausfallpfad).

**Klassen für die Befundzeilen:** `instrument-misst-nichts` (das Werkzeug traf seinen
Gegenstand nicht) · `lauf-unvollstaendig` (ein Pflichtteil entfiel) · `doku-veraltet`.

## Self-Check — PFLICHT im Bericht

```
=== /mind-cleaner — Self-Check ===
[Bereich]        global | projekt | alles          Dateien: <n>
[Fremdklon]      <n> Dateien uebersprungen (nicht Eigentum des Nutzers)
[Step 1 Bestand] <bytes> in <n> Dateien (REKURSIV gezaehlt)
[Step 2 Laden]   <n> Ladevorgaenge / <n> Sitzungen — oder "kein Protokoll, KEINE Aussage"
[Step 3 Einordnung] Hook <n> · Skill <n> · Command <n> · bleibt <n> · unklar <n>
[Gates]          nur bei --umzug: <je Gate OK/BRUCH>
[Stufe]          BERICHT | PLAN | ANGEWENDET
[Wirkung]        unbestaetigt bis zum Ladeprotokoll einer NEUEN Sitzung
[Protokoll]      <n> Zeilen nach $MIND_LOG_FILE · <n> Befunde nach MIND_DEBUG_DIR
                 oder "still: nichts zu melden" — ein Lauf, der schweigt, sagt WARUM
```

⛔ Fehlt eine Zeile, ist der Bericht unvollständig und darf zurückgewiesen werden.
