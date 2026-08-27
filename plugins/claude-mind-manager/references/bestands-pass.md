# Der Bestands-Pass — jeder Skill sieht sich seinen eigenen Bestand an

> Gemeinsame Vorschrift für `mind-claudemd`, `mind-memory`, `mind-rules`, `mind-files`
> und `mind-update`. Jeder Skill nennt in seinem eigenen Block nur noch **seinen Bereich**
> und zeigt hierher. **NEU v5.22.0.**

## ⛔ Wozu

**Nutzer-Auftrag 27.08.2026:** *„die anderen skills sollen von vorne rein sauber arbeiten,
ähnlich wie der mind cleaner — nicht immer mehr und mehr. Auch gucken: braucht man das,
kann das weg, steht das schon woanders."*

Der Anlass ist gemessen: `/mind-all` ist eine **Anhänge-Maschine**. Fünf Skills tragen nach,
keiner sieht je zurück. An **einem Tag** wuchs der immer geladene Kontext eines Projekts um
**+19 460 B (+21 %)** auf 2 601 Zeilen und 138 Anweisungen. `references/budget-thresholds.md`
nennt **>400 Zeilen** als die Schwelle, ab der die Befolgung auf 71 % fällt, und **~100–150**
als die Zahl der Anweisungen, die ein Modell verlässlich hält.

⭐ **Bei ausgeschöpftem Budget ist Anhängen kein Zuwachs mehr, sondern ein TAUSCH** — jede
neue Anweisung verdrängt eine alte. Der Tausch wurde bisher nirgends benannt.

Das Gegengewicht `/mind-cleaner` steht **bewusst außerhalb der Kette** und ist **nicht
autonom** (Nutzer-Entscheidung 24.08.2026). Es kann also nicht der Weg sein, auf dem der
Bestand routinemäßig geprüft wird. Deshalb prüft ihn jeder Skill selbst — klein, regelmäßig,
und **ohne zu handeln**.

## ⛔ Die Grenze, und sie ist die wichtigste Zeile hier

> **Der Pass MELDET. Er schneidet nicht, verschiebt nicht, löscht nicht.**

Handeln bleibt `/mind-cleaner`. Dessen Nicht-Autonomie wird hiervon **nicht** berührt.
Wer diese Grenze aufweicht, macht aus fünf meldenden Skills fünf schneidende — und genau
das hat der Nutzer bei `/mind-cleaner` ausdrücklich abgelehnt.

⭐ **Warum ein bloßes Melden trotzdem wirkt:** dieselbe Mechanik wie bei der Agent-Quittung.
Die zwingt keinen Agenten zu arbeiten — sie macht sein **Fehlen sichtbar**. Das hat gereicht.

---

## 1 · Die Dauerkontext-Bilanz — Pflichtzeile im Bericht

```bash
[ -n "$CLAUDE_PLUGIN_ROOT" ] || { echo "ERROR: \$CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 1; }
source "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
mind_kontext_bilanz "$PROJ" --vergleichen
```

Ergibt zwei Zeilen, die **wörtlich in den Bericht** gehören:

```
ZEILEN=2601 ANWEISUNGEN=138 DATEIEN=21 BYTES=165508
Dauerkontext: 2586 -> 2601 Zeilen (+15) · Anweisungen 137 -> 138 (+1)
```

⚠ **Topic-Dateien zählen NICHT mit.** Sie laden höchstens 5 pro Anfrage, über einen
Auswähler, der nur Name und `description` sieht. Ihr Wuchs kostet **Auffindbarkeit**, kaum
Tokens — eine ganz andere Größe. `MEMORY.md` selbst zählt sehr wohl mit.

⚠ **Die Anweisungszahl ist eine Heuristik** (Zeilen mit `MUST`/`NEVER`/`ALWAYS`/⛔). Als
Trend brauchbar, als Absolutwert nicht. **So auch berichten**, nicht als harte Zahl.

## 2 · Die Stichprobe — 3 Einträge, die am längsten ungeprüft sind

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_stichprobe.py" "$PROJ" \
       --skill <dein-skill-name> --verzeichnis "<dein-bereich>"
```

⭐ **Das ist die Antwort auf „nicht so invasiv".** Kein Skill kämmt seinen ganzen Bestand
durch; jeder sieht sich jedes Mal einen **anderen** kleinen Ausschnitt an. Über viele Läufe
ist der Bestand vollständig abgedeckt, ohne dass ein einzelner Lauf teuer wird.

| Grenze | Wert |
|---|---|
| je Skill | **3** Einträge |
| je `/mind-all`-Lauf | **15** insgesamt, über alle fünf |
| Reihenfolge | am längsten ungeprüft zuerst, bei Gleichstand alphabetisch |

⛔ **Der Rotationszustand ist PROJEKTWEIT, nicht je Skill.** Sonst legen sich fünf Skills
fünfmal denselben Eintrag vor, und der Rest des Bestands wird nie gesehen. Ein Eintrag, den
ein anderer Skill in **diesem** Lauf schon vorgelegt bekam, wird übersprungen.

⚠ **`(nichts)` ist eine gültige Antwort** — leerer Bestand, neues Projekt oder Laufbudget
erschöpft. Ein **fehlender Block** ist es nicht, siehe Abschnitt 5.

## 3 · Die drei Fragen — für JEDEN Eintrag der Stichprobe, EINE Zeile je Eintrag

| # | Frage | Werkzeug | urteilt es? |
|---|---|---|---|
| 1 | **Steht es schon woanders?** | `cleaner_duplikate.py --bereich "$PROJ"` | mechanisch, ja |
| 2 | **Steht es im Code besser?** | `cleaner_aussagen.py <datei> --code <quellbaum>` | ⛔ **nein — legt Kandidaten vor** |
| 3 | **Wird es noch gebraucht?** | `cleaner_belege.py --datei <datei>` | Belege statt Selbsteinschätzung |

⛔ **Frage 2 urteilt bewusst nicht.** *„Der Code sagt WAS, die Regel oft WARUM."* Das
Gegenbeispiel steht in diesem Projekt: `calculate_km` **stand im Code** und verschwand beim
Umbau trotzdem still — die Regel, die das WARUM trug, hätte es verhindert.
**Kandidaten vorlegen, nie streichen.**

⛔ **Frage 1 läuft EINMAL für den ganzen Bereich**, nicht dreimal. `cleaner_duplikate`
arbeitet über eine Ablage, nicht über eine Datei.

**Die Ausgabe je Eintrag ist EINE Zeile:**

```
BESTAND  .claude/rules/env-vars.md   dupl 2 (hooks.md:88, architecture.md:221) · code 0 · beleg: 14 d
```

## 4 · Schon einmal entschieden? — vor jedem Vorschlag

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_urteile.py" "$PROJ" \
       --pruefen --orte "<stelle-a>" "<stelle-b>"
```

| Rückgabe | was du tust |
|---|---|
| `unbekannt` | melden |
| `gueltig` + `duplikat` | melden |
| `gueltig` + `zielform`/`zeiger` | ⛔ **nicht erneut vorlegen** — bewusst so gelassen |
| `veraltet` | melden, mit dem Hinweis dass der Inhalt sich geändert hat |

⚠ **Widerspricht dein Befund dem Buch, überstimme es nicht — melde den Widerspruch:**
*„Buch sagt `zielform` (mensch, 24.08.), ich sehe ein Duplikat."*

## 5 · Die Quittung — sonst ist Schweigen nicht von Sauberkeit zu unterscheiden

```bash
python "$CLAUDE_PLUGIN_ROOT/references/cleaner_stichprobe.py" "$PROJ" \
       --quittung --skill <dein-skill-name> --geprueft <n> --stichprobe <n>
```

Schreibt `bestand=<skill>:<geprueft>/<stichprobe>` in `analyzed-scopes`.

⛔ **Ein FEHLENDER Block macht den Lauf zum Teilsync.** `(nichts)` ist erlaubt, Schweigen
nicht. Ein Skill, der schweigt weil sein Bestand sauber ist, und einer, der schweigt weil
der Pass ausgefallen ist, sehen von außen **identisch** aus — genau diese Ununterscheidbarkeit
hat v5.3.1 bei zwei Hooks und v5.19.0 bei der Agent-Quittung gekostet. Beide Male war die
Lösung dieselbe: **das Fehlen messbar machen, nicht das Vorhandensein.**

⚠ Außerhalb einer `/mind-all`-Kette gibt es keine `analyzed-scopes`; die Quittung entfällt
dann **still** und ist kein Fehler.

---

## Fehlerszenarien — der Pass darf NIE einen Skill töten

| Fall | Verhalten |
|---|---|
| Werkzeug fehlt oder stürzt ab | **fail-open**: `UNGEPRUEFT: <werkzeug>` melden, Skill läuft weiter |
| Urteilsbuch fehlt oder ist unparsbar | wie `unbekannt` behandeln — **nie** als „schon entschieden" |
| Bestand leer / neues Projekt | Stichprobe 0, Meldung `(nichts)` — kein Fehler |
| Kein Quellbaum vorhanden | Frage 2 entfällt, wird als `n/a` **ausgewiesen**, nicht verschwiegen |
| Zwei Skills gleichzeitig | Rotationsstand wird **nach** dem Lesen geschrieben; doppelte Prüfung ist harmlos, doppeltes Auslassen nicht |
| Stichprobe > Bestand | `min(3, Bestand)` |
| Laufbudget erschöpft | `(nichts)` mit Begründung — **nicht** stillschweigend nichts tun |

⛔ **Fail-open ist hier Pflicht, nicht Bequemlichkeit.** Ein Bestands-Pass ist eine
Zusatzleistung; er darf den Sync, für den der Skill eigentlich läuft, unter keinen Umständen
verhindern.

## ⛔ Risiko: fremde Memory-Bestände im gemeinsamen Debug-Ordner

Der Pass liest auch **fremde** Memory-Bestände. In `APP - Zustellplan` stehen dort
**Abonnenten-, Routen- und Geschäftsdaten**. `mind_debug_write` schickt Befundtexte in den
**gemeinsamen** Debug-Ordner aller Projekte.

> **Verbindlich: Ort und Klasse melden, nie Inhalt.**
> `env-vars.md:112 doppelt zu hooks.md:88` — **niemals die Zeile selbst.**

Das ist bereits Regel in `mind-memory` (*„Keine Inhalte fremder Memory-Bestände in Berichte,
Logs oder Commits"*) und hier **mechanisch** gehalten: `cleaner_stichprobe.py` kennt
ausschließlich **Pfade** und hat auf Inhalte gar keinen Zugriff.

## Was der Pass auch danach NICHT kann

- ⛔ *„Braucht man das?"* bleibt ein **Urteil**. Der Pass erzwingt eine **Antwort**, nicht
  die richtige.
- ⛔ **„Steht im Code" heißt nicht „überflüssig".** Siehe Frage 2.
- ⛔ **Ob eine Regel FEHLT**, sieht kein Audit — es sieht nur, was da ist.
- ⚠ **Ob der Umbau die Befolgung hebt, ist nicht belegt.** Die Richtung ist es, der Betrag
  nicht. Die SFEIR-Zahlen sind fremde Messungen, nicht an dieser Maschine erhoben.
