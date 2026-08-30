# Das Kontext-Tor — die gemeinsame Vorschrift für alle Commands

> **Rules, Dokus, CLAUDE.md und Memory existieren AUSSCHLIESSLICH für das, was
> Claude nicht ohnehin weiß.** Alles andere ist Kosten ohne Gegenwert — und
> verdrängt eine Regel, die trägt.

⛔ **Diese Datei steht EINMAL und wird von allen Commands nur GENANNT.** Sie in
jeden Command zu kopieren wäre genau das Duplikat, gegen das sie gebaut ist.
Dieselbe Bauform wie [bestands-pass.md](bestands-pass.md).

**Nutzer-Auftrag 30.08.2026, wörtlich:**

> *„überall es wird immer mehr, es darf nicht sein — führe was ein wo der
> Context durch läuft: ist es irgendwo schon, ist es selbsterklärend, ist es im
> Code schon erklärt. … in den Context-Dateien soll kein unwichtiger Müll
> stehen, er ist begrenzt, wertvoll und kostet Geld."*

Bis v5.25.0 arbeitete das Plugin nur **rückwärts** — es prüfte Bestände, die
schon da sind. Es gab **kein Tor beim Hineinschreiben.** Deshalb wächst alles.

---

## Die neun Fragen

### Gruppe A — braucht es die AUSSAGE überhaupt?

| # | Frage | wer beantwortet sie | mechanisch? |
|---|---|---|---|
| **A1** | Weiß das Modell es ohnehin? | `cleaner_tor` (Extremfall) | ⚠ teilweise |
| **A2** | Ist es noch wahr? | `cleaner_tor`, `cleaner_belege` | ⚠ teilweise |
| **A3** | Handlungsleitend — oder Historie? | `cleaner_tor` | ⚠ teilweise |

### Gruppe B — braucht es sie an DIESEM ORT?

| # | Frage | wer beantwortet sie | mechanisch? |
|---|---|---|---|
| **B1** | Steht es schon woanders? Ist es doppelt? | `cleaner_duplikate` | ✅ **ja** |
| **B2** | Steht es im Code? | `cleaner_aussagen --code` | ⚠ teilweise |
| **B3** | Wirkt es an diesem Ort? | `cleaner_grenzen` | ✅ ja |

### Gruppe C — trägt die FORM?

| # | Frage | wer beantwortet sie | mechanisch? |
|---|---|---|---|
| **C1** | Ist es hart formuliert? | `cleaner_tor` | ✅ ja |
| **C2** | Ist es befolgbar? | `cleaner_tor` | ⚠ schwächste |

⛔ **B1/B2/B3 werden von `cleaner_tor` NICHT beantwortet, sondern GENANNT.** Die
Klasse `instrument-nachgebaut` steht mit **7** Vorkommen im Debug-Ordner, Bilanz
~250 · 11 · 9 · 7 Fehltreffer — **kein einziger Nachbau war besser als das
Original** (`werkzeuge-zuerst.md`).

---

## Zwei Richtungen — beide oder keine

| Richtung | wann | Wirkung |
|---|---|---|
| **VORWÄRTS** | vor jedem `ADD` / `NEW_FILE` | ohne Quittung ist der Lauf ein **Teilsync** |
| **RÜCKWÄRTS** | `/mind-cleaner --audit`, ganzer Bestand | Kandidatenliste für den Bericht |

⛔ **Nur vorwärts ließe den Altbestand stehen; nur rückwärts ist der Zustand von
heute, der nachweislich wächst.**

```bash
# VORWAERTS — vor der Ergaenzung
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_tor.py" --text "<die neue Zeile>"

# RUECKWAERTS — ueber eine bestehende Context-Datei
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_tor.py" --datei "<datei.md>"
```

## Die Quittung

```
tor=<datei>:A1/A2/A3:B1/B2/B3:C1/C2
z.B.  tor=CLAUDE.md:neu/wahr/regel:neu/n-a/wirkt:hart/spez
```

⛔ **Ein `ADD` ohne Tor-Quittung macht den Lauf zum Teilsync** — dieselbe
Kopplung wie Bestands-Pass (v5.22.0) und Schritt-Quittung (v5.25.0). Ohne sie
wäre das Verfahren wieder das, was `PFLICHT` **67 mal** war: Prosa im
Ausfallpfad.

---

## ⭐ Warum C1 die ⚠-Vorbehalte NICHT frisst

Der Auftrag lautete *„alle Regeln hart formuliert, keine Ausnahmen"*. **Ich habe
dem widersprochen, und der Widerspruch steht im Code.**

**Hart formuliert und ehrlich formuliert sind nicht dasselbe.** Dieser Bestand
ist voll von Sätzen wie *„⚠ Beide Schwellen sind GERATEN, nicht gemessen"* —
das sind **keine weichen Regeln**, sondern **harte Aussagen über schwache
Belege**. Sie sind der Grund, warum der Bestand etwas taugt.

| ⛔ weich — wird gemeldet | ✅ hart über Unsicherheit — NIE gemeldet |
|---|---|
| *„man sollte vorher sichern"* | *„sichern. ⚠ Ob es reicht, ist ungemessen."* |
| *„möglichst nicht löschen"* | *„NIE löschen."* |

**Der Test ist die HANDLUNG, nicht der Ton:** Weiß ich nach dem Satz, was ich
**tun** soll? Dann ist er hart, auch mit Vorbehalt.

⛔ **Das Zeichen ⛔ befreit ABSICHTLICH NICHT.** *„⛔ möglichst nicht löschen"*
ist der gemischte Fall und gehört gehärtet.

⭐ **Und der NEBENSATZ ist keine Regel.** Im deutschen Hauptsatz steht das
Modalverb an zweiter Stelle (*„man sollte VORHER sichern"*), im Nebensatz am
Ende (*„den Befund, den der Agent finden sollte"*). **Gemessen:** ohne diese
Unterscheidung waren **beide** C1-Treffer im ganzen Skill-Bestand Fehlalarme —
zweimal derselbe Satz.

---

## ⛔ Was das Tor NICHT kann

- **A1 und C2 bleiben Urteile.** Ob ein Modell etwas weiß, steht in keiner
  Datei. Das Tor erzwingt eine **Antwort**, nicht die richtige — dieselbe
  Mechanik wie die Agent-Quittung (v5.19.0): sie zwingt keinen Agenten zu
  arbeiten, sie macht sein **Fehlen** sichtbar. Das hat gereicht.
- **Es verhindert kein Wachstum.** Es macht jedes `ADD` begründungspflichtig.
- **Es misst Form, nicht Bedeutung.** Jeder Treffer ist ein **Kandidat**; die
  Liste sieht ein Mensch durch — wie beim SKILL-Vorschlag aus `mind-cleaner`
  Step 3.
- ⚠ **Ob weniger Kontext besser befolgt wird, ist für DIESEN Bestand nicht
  belegt.** Die Richtung ist es (SFEIR, 20 gestapelte Regeln: 96 % → 60,4 %),
  der Betrag nicht.

---

## Der Memory-Deckel — nur für `/mind-memory`

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_tor.py" --memory "<memory-dir>"
```

**Nutzer-Auftrag:** *„keine Memory-Dateien so viele, dass diese nicht mehr
geladen werden, keine Ausnahmen."*

⛔ **„Wird nicht mehr geladen" ist NICHT messbar — gemessen 30.08.2026.**
139 Topic-Dateien über 14 Projekte, **0** auffindbare Abrufe in den Transkripten
— aber die **Positivkontrolle fällt durch**: `claudeMd`, `auto-memory` und
`Contents of` kommen dort **ebenfalls null mal** vor, obwohl sie nachweislich
eingespielt werden. Der eingespielte Kontext steht gar nicht im Transkript.

**Ein Deckel auf beobachteten Ladungen wäre ein Instrument, das nichts misst** —
die häufigste Fehlerklasse dieses Projekts (**71** Vorkommen im Debug-Ordner).

**Er stützt sich stattdessen auf die belegte Grenze** (wörtlich in
`claude.exe` 2.1.237): *„Return a list of filenames … **(up to 5)**. Only
include memories … **based on their name and description**."*

| Dateien | Ampel | Folge |
|---|---|---|
| bis 15 | grün | in ~3 Anfragen ist alles einmal erreichbar |
| 16–25 | gelb | Meldung mit den schwächsten `description` |
| über 25 | **ROT** | ⛔ `ADD` nur gegen Zusammenführung — eine rein, eine raus |

⛔ **Die drei Zahlen sind GESETZT, nicht gemessen**, und deshalb Regler
(`MIND_MEMORY_MAX_GRUEN` / `_MAX_GELB` / `_DESC_MIN` / `_DESC_MAX`) — dieselbe
Begründung wie bei den drei v5.5.0-Reglern: *eine hartkodierte Zahl aus einer
unbestätigten Quelle ist eine Behauptung.* ⛔ **Das Plugin setzt sie nie selbst**
(claude-mem #2836).

⭐ **Der wirksamere Hebel ist NICHT die Dateizahl, sondern die `description`** —
sie ist der **einzige** Zugang des Auswählers, er sieht nie den Inhalt. Deshalb
prüft der Deckel sie zuerst.

⛔ **Vor einer Zusammenführung sichern**, danach `Learnings/memory_gates.py` —
Zusammenführen **löscht eine Datei** (`backup-usage.md`).

---

## ⚠ Die Falle beim Bauen: zwei Module, ein stdout-Puffer

`sys.stdout = io.TextIOWrapper(sys.stdout.buffer, …)` am Modulkopf war in drei
Werkzeugen **bedingungslos**. Wer stdout selbst einhüllt und dann importiert,
hängt **zwei** Wrapper an denselben Puffer; wird einer eingesammelt, schließt er
den Puffer des anderen, und jedes weitere `print()` bricht mit
`I/O operation on closed file` — **nach** der letzten erfolgreichen Ausgabe,
also an der falschen Stelle. Zweimal am 30.08.2026 gemessen, seither idempotent
(`cleaner_leitplanke`, `cleaner_stichprobe`, `cleaner_wirkung`).
Prüffall: `tests/test_kontext_tor.sh`, Fall 8.
