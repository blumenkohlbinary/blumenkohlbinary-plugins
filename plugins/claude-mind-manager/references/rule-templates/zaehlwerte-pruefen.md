---
globs: ["**/*"]
---

# Zahlen in der Doku messen, nicht glauben — `tools/zaehl_gate.py`

## Wann

Immer, wenn eine Context-Datei eine **Anzahl** behauptet: „7 Hooks", „12 Referenzen",
„84 Prüffälle", „5 Skills". Und **vor jedem Commit**, der eine solche Zahl anfasst.

## Wie

Schreib die Zahl **zusammen mit ihrem Zählbefehl** in eine Tabelle:

```markdown
| Skills **9**            | `ls -1d skills/*/ \| wc -l`              |
| Prueffaelle **84**      | `grep -rc '\[ok \]' tests/ \| paste -sd+ \| bc` |
```

Dann misst das Gate sie:

```bash
python tools/zaehl_gate.py .claude/rules/architecture.md
```

**Rückgabewert:** `0` = alle Zahlen stimmen · `1` = Abweichung · `2` = Tabelle nicht lesbar.
Damit hängt es sich in jede Kette (`&&`, Pre-Commit, CI).

`--cwd <verzeichnis>` setzt, von wo aus gemessen wird — Vorgabe ist der Ordner der
Doku-Datei.

## Die Regel

⛔ **Eine Zahl ohne danebenstehenden Zählbefehl ist eine Behauptung, keine Angabe.**
Entweder sie kommt in die Tabelle, oder sie wird durch eine qualitative Aussage ersetzt
(„mehrere", „alle unter `hooks/`"). Eine präzise Zahl, die niemand nachprüft, veraltet
lautlos und wird trotzdem geglaubt — gerade *weil* sie präzise aussieht.

## Warum es das gibt

Im Ursprungsprojekt stand die Tabelle mit Zählbefehlen seit Monaten da — und war
trotzdem **sechsmal** falsch:

| | behauptet | tatsächlich |
|---|---|---|
| `lib.sh`-Funktionen | 7 → 12 → 13 → 16 | 17 |
| ausgelieferte `.py` | 2, später 5 | 8 |
| Skills | 8 | 9 |
| Referenzen / Subdirs | 11 / 3 | 12 / 4 |

Die Datei notierte den Grund ab dem zweiten Mal selbst:

> *„Eine Lehre aufzuschreiben verhindert ihren Wiedereintritt nicht — nur ein Check tut
> das. Hier wäre er billig."*

Gebaut hatte ihn niemand. **Zwischen „wir wissen es" und „es kann nicht mehr passieren"
liegt ein ausführbares Skript, sonst nichts.**

## Zwei Fallen, beide gemessen

1. ⛔ **Die Pipe in einer Markdown-Tabellenzelle ist als `\|` maskiert.** Wer sie nicht
   zurücknimmt, gibt der Shell einen zerbrochenen Befehl, bekommt leere Ausgabe — und
   das Gate meldet *„alle Zahlen falsch"*, obwohl alle stimmen. Das Gate nimmt sie
   zurück; wer es nachbaut, muss daran denken.
2. ⛔ **`subprocess.run(["bash", …])` trifft auf Windows die WSL-Bash, nicht Git Bash.**
   `CreateProcess` durchsucht `System32` zuerst. Ergebnis: leere Ausgabe, Rückgabewert 1,
   und wieder „alle Zahlen falsch". Das Gate löst den Pfad über `shutil.which` auf und
   verwirft einen Treffer aus `System32`.

**Beides sieht von außen aus wie ein echter Befund über die Doku.** Erste Frage bei einem
roten Gate ist deshalb nicht „was ist an der Doku falsch", sondern **„hat das Instrument
seinen Gegenstand überhaupt erreicht?"** — findet es gar keine Zeilen, meldet es
Rückgabewert `2` statt eines Ergebnisses.

## Grenze, die dazugehört

Das Gate prüft **Zahlen**, nicht Aussagen. Ob „`stop.sh` sourct `lib.sh`" stimmt, sieht es
nicht. Dafür bleibt der Blick in den Code.
