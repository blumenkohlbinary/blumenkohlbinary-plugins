---
description: Vorhandene Pruefwerkzeuge benutzen statt nachbauen — mit der Bilanz der bisherigen Nachbauten
globs: ["**/*.py", "**/tools/*", "**/references/*"]
---

# Erst das vorhandene Werkzeug

⛔ **Bevor du einen Pfad-Klassifikator, einen Frontmatter-Parser, einen Zeilenenden-Zähler
oder irgendeine andere Prüf-Logik schreibst: sieh nach, ob es sie schon gibt.**

## Die Bilanz — sie ist eindeutig

Der Debug-Ordner führt die Klasse `instrument-nachgebaut` mit **7 Vorkommen**. Was die
Nachbauten geliefert haben:

| Nachbau | Ergebnis |
|---|---|
| `classify_path` von Hand | **~250 Fehltreffer**, verworfen |
| Check 13 nachgebaut | 11 Slash-Commands als tote Pfade |
| Pipeline ERNEUT nachgebaut | 9 tote Pfade gemeldet, **echte: 0** |
| eigene Pfad-Pipeline | 7 Fehltreffer bei 7 Treffern |
| eigener Frontmatter-Zähler als Zeilen-Regex | falsches Zwischenbild |
| Wurzel-Erkenner, zweiter Anlauf | Nachbar-Repo blieb DEAD |
| Pipeline-Skript, dritter Anlauf | derselbe Wurzel-Fehler, vom Fixture gefangen |

**Kein einziger Nachbau war besser als das Original.** Nicht einer.

⚠ **Warum der Impuls trotzdem kommt:** Das Original wirkt groß, der eigene Fall wirkt
einfach, und ein Dreizeiler ist in dreißig Sekunden geschrieben. Die Fehltreffer tauchen
erst danach auf — und sehen dann aus wie Befunde über das Projekt, nicht wie Fehler im
Instrument.

## Was es gibt

```bash
# Ist ein Pfad in einer Context-Datei tot? -> NICHT selbst regexen
python "$CLAUDE_PLUGIN_ROOT/references/claudemd_pipeline.py" --selbsttest
python "$CLAUDE_PLUGIN_ROOT/references/claudemd_pipeline.py" <datei.md>

# Prueft eine Pruef-Funktion ueberhaupt etwas? -> Negativfall-Gate
python "$CLAUDE_PLUGIN_ROOT/references/negativfall_gate.py"

# Stimmen die Zahlen in der Doku noch? -> Zaehl-Gate
python Learnings/zaehl_gate.py

# Zeilenenden byte-genau  ⛔ NIE `grep -c $'\r'` — das zaehlt in Git Bash JEDE Zeile
mind_zeilenenden <datei>            # aus hooks/lib.sh
```

⭐ **`--selbsttest` ist der billigste Weg, den Nachbau-Impuls zu entkräften.** Er zeigt in
zwei Sekunden, dass das Vorhandene funktioniert — und macht damit die Frage „ist es
kaputt?" beantwortbar, statt sie zur Annahme werden zu lassen.

## Die Regel in einem Satz

> **Ein nachgebautes Instrument ist so lange verdächtig, bis es gegen dieselben Fälle
> gefahren wurde wie das Original.** Wer nachbaut, baut zuerst den Fixture-Satz nach —
> und merkt dabei meistens, dass er das Original hätte nehmen sollen.

## ⚠ Wenn das Original wirklich nicht passt

Dann ist das ein **Befund über das Original**, kein Anlass für einen Zweitbau:

1. Den Fall benennen, an dem es scheitert.
2. Ihn als Prüffall **zum Original** hinzufügen (neue Datei, bestehende bleiben unberührt).
3. Das Original erweitern.

Ein zweites Werkzeug neben dem ersten heißt: ab jetzt widersprechen sich zwei Messungen,
und niemand weiß, welche gilt.
