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

## ⛔ Der Ablauf ist dreistufig, und jede Stufe braucht ein OK

```
1. BERICHT     /mind-cleaner [--bereich global|projekt|alles]     aendert NICHTS
      ↓  Nutzer sagt ok
2. PLAN        /mind-cleaner --plan [--bereich …]                  schreibt einen Plan
      ↓  Nutzer gibt den Plan frei
3. ANWENDEN    /mind-cleaner --umzug <datei>                       GENAU EINE Datei
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
| `Debug/index.jsonl` | datierte Verstöße — **hören sie an einem Modellwechsel auf?** |
| Git-Historie | **Ein-Commit** = seit Anlage nie überarbeitet („Init Fossilization") |

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
python "$CLAUDE_PLUGIN_ROOT/references/bestandsaufnahme.py" <verzeichnis>
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
| an der **Aufgabe** | **Skill** |
| der Nutzer ruft es **beim Namen** | **Slash-Command** |
| **gar nicht**, gilt vor jedem Eingriff | **bleibt Rule** |

⛔ **Die harte Kante: was ERZWUNGEN werden muss, wird NIE ein Skill.** Das ist keine
Vorsicht, sondern Herstelleraussage — die Skills-Doku sagt bei nachlassender Wirkung
*„…or use hooks to enforce behavior deterministically"*.

⛔ **Das Werkzeug nennt seine eigenen Fehlurteile.** Zwei sind gemessen und stehen dauerhaft
in seiner Ausgabe:

- `autonom-arbeiten.md` → Vorschlag **SKILL**, Imperativdichte **0,00** — die Datei enthält
  **null** Imperativ-Wörter und ist trotzdem eine der direktivsten des Bestands.
  **Deutsche Prosa befiehlt ohne Schlüsselwort.**
- `keine-annahmen.md` → Vorschlag **HOOK-KANDIDAT**, weil sie **andere Regeldateien
  zitiert**. Eine Zitierung ist kein Aufruf-Anker.

**Daraus folgt und ist nicht verhandelbar:** ein SKILL-Vorschlag wird **nie ohne menschliche
Bestätigung** angewendet.

## Step 4: Die Leitplanke herausschneiden — der schwierigste Teil

**Hier gibt es kein Werkzeug.** Was bleibt, muss allein tragen; was geht, muss vollständig sein.

**Was in der Kurz-Rule bleibt:** das Verbot · die Entscheidung in einem Satz · die Zahl, die
man vor dem Anfangen wissen muss · **der Pfad zum Volltext**.
**Was in den Skill geht:** Herleitung · Belege · Messreihen · Fallen · Beispiele.

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

### ⭐ Warum das PFAD-Gate das wichtigste ist — gemessen 24.08.2026

| Zugriffsweg | Trefferquote |
|---|---|
| Kurz-Rule in `rules/` | **100 %** (Ladeprotokoll, 884× `session_start`) |
| Volltext über den **Pfad** | **4 von 4** (eigene Sonden, je 1 Werkzeugaufruf) |
| Volltext über **Skill-Auswahl** | **20–84 %** (Vercel-Evals, 200+ Tests) |

Ein Zeiger auf einen Skill-**Namen** verlässt sich auf die 20-%-Mechanik. Ein Zeiger auf
einen **Pfad** nicht. ⚠ Die aussagekräftigste Sonde nannte die Datei **beiläufig**
(*„Alles Weitere steht in …"*, ohne Verbotszeichen) — und wurde trotzdem gelesen.

⛔ **Die Gates schließen VERLUST aus, nicht VERTAUSCHUNG.** Ein Umzug, der die Leitplanke in
den Skill schiebt und die Erklärung in der Rule lässt, besteht **alle vier**.

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
- ⛔ **NIE kürzen.** Kein Satz wird gestrichen. Wer kürzen will, tut das getrennt und sichtbar.

## Was der Befehl ausdrücklich NICHT tut

- **Entscheiden, was Leitplanke ist.** Er schlägt vor, der Nutzer bestätigt.
- **Den `paths:`/`globs:`-Widerspruch auflösen.** Er wird ausgewiesen, beide Seiten genannt.
- **Behaupten, der Umzug habe sich gelohnt.** ⚠ Dass ein großer Startkontext schadet, ist
  seit 24.08.2026 belegt (20 gestapelte Regeln: 96 % → 60,4 % Befolgung). **Ob 135 → 28 KB
  der richtige Betrag war, folgt aus keiner Quelle.** Belegt ist die Richtung, nicht der Betrag.

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
```

⛔ Fehlt eine Zeile, ist der Bericht unvollständig und darf zurückgewiesen werden.
