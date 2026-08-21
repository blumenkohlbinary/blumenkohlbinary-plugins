# Prüfsammlungen

**Am gebauten Paket fahren, nicht am Quellbaum** (`~/.claude/rules/fertig-heisst-fertig.md` §1):

> ⛔ **Bis v5.7.5 tat das keine dieser Sammlungen.** Drei von fünf setzten `CLAUDE_PLUGIN_ROOT`
> per `export` hart auf den Quellbaum und **überschrieben damit, was der Aufrufer mitgab** —
> die Anweisung darunter war also wirkungslos, und „am gebauten Paket geprüft" war eine
> unbelegte Behauptung. Heute steht dort `${CLAUDE_PLUGIN_ROOT:-…}`.
>
> **Die Gegenprobe, die das belegt** — mit unerreichbarer Wurzel *müssen* sie scheitern:
>
> ```bash
> CLAUDE_PLUGIN_ROOT=/gibt/es/nicht bash tests/test_precompact.sh && echo "ROT: Wurzel wird ignoriert"
> ```

```bash
export CLAUDE_PLUGIN_ROOT=~/.claude/plugins/cache/kohlosseum/claude-mind-manager/<version>
bash "$CLAUDE_PLUGIN_ROOT/tests/test_teil1.sh"
bash "$CLAUDE_PLUGIN_ROOT/tests/test_debug.sh"
bash "$CLAUDE_PLUGIN_ROOT/tests/test_precompact.sh"
python "$CLAUDE_PLUGIN_ROOT/references/claudemd_pipeline.py" --selbsttest
python "$CLAUDE_PLUGIN_ROOT/references/slug_regression.py" --live
```

| Datei | Prüffälle | Gegenstand |
|---|---|---|
| `test_teil1.sh` | 15 | Token-Schwellen, Mahnung, Zwang, `lib.sh`-Ausfall |
| `test_debug.sh` | 12 | Debug-Ordner, Wiederholungserkennung, Zeilenenden |
| `test_precompact.sh` | 11 | Chat-Rettung, Arbeitsstand, `sync-stand`, Fail-open |
| `test_toolrule.sh` | 7 | Tool→Rule-Nachweis, auch für Werkzeuge im Wurzelverzeichnis |
| `test_compact_faellig.sh` | 23 | `COMPACT-FAELLIG`: Zwang, Zähler, Notausgang, Fail-open |
| `test_precompact.py` | — | Hilfsteil für `test_precompact.sh` |

## ⛔ Jede Sammlung enthält eine Gegenprobe, die scheitern KANN

Das ist keine Zierde. Eine Messung ohne Negativkontrolle liefert weiter Zahlen und greift am
Fehler vorbei — siehe `~/.claude/rules/messung-vor-glauben.md` §1. Konkret hier:

- **`test_teil1.sh`** sabotiert `lib.sh` und verlangt, dass der Schuld-Zwang **trotzdem** blockt.
- **`test_precompact.sh`** sabotiert **nur** die Übergabe-Marke und verlangt, dass Chat-Rettung,
  Auftrag und `OPEN` trotzdem entstehen.
- **`test_toolrule.sh`** fährt einen blinden Stub gegen denselben Fall und verlangt, dass er
  **durchfällt**. Ohne diesen Lauf wäre nicht belegt, dass die übrigen Zusicherungen überhaupt
  etwas messen — und genau das war der Defekt, den diese Sammlung fängt: der Wurzel-Fix von
  v5.7.1 stand nur im **Kommentar**, die Variable wurde gesammelt und nie benutzt.
- **`test_debug.sh`** prüft, dass zwei **verschiedene** Klassen **kein** `WIEDERHOLT` erzeugen —
  ohne diesen Fall wäre die Wiederholungserkennung nicht von „meldet immer WIEDERHOLT" zu
  unterscheiden.

## ⛔ Was hier NICHT hineingehört

**Nichts, was `~/.claude/settings.json` oder Umgebungsvariablen schreibt.** Ein Plugin, das
seine eigenen Regler setzt, macht genau den Fehler von `claude-mem` (#2836): dort wurden so
75 Erinnerungen unsichtbar. Die Schwellen setzt der Mensch von Hand.

Der Beleg der Schwellen-Kalibrierung vom 21.08.2026 liegt deshalb im Workspace unter
`Debug/messungen/`, nicht im ausgelieferten Paket.
