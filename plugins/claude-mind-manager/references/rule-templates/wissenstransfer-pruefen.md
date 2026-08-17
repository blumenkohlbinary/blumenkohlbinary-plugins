---
description: Vollstaendigkeit eines Wissenstransfers messen statt behaupten (tools/coverage_gate.py)
globs: ["**/*"]
---

# Wissenstransfer prüfen — `tools/coverage_gate.py`

## Wann

Immer, wenn Inhalte aus Quelldateien in ein Zieldokument übertragen wurden (Referenzen →
Leitfaden, Recherche → Notiz, Rohmaterial → Dokumentation, mehrere Dateien → eine) und die
Frage lautet: **„Ist wirklich alles drin?"**

Nicht schätzen. Nicht durchlesen und nicken. Messen.

## Wie

```bash
python tools/coverage_gate.py <ziel.md> <quelle1.md> [quelle2.md ...]
```

Das Zieldokument muss als **Datei** vorliegen. Liegt es in einem externen System (Notiz-App,
Wiki, Ticket), erst herunterladen und ablegen, dann prüfen.

**Rückgabewert:** `0` = alle Prüfpunkte belegt · `1` = offene Punkte (einzeln gelistet) ·
`2` = falscher Aufruf · `3` = **Messung ungültig**, Negativkontrolle hat angeschlagen.

## ⛔ Die absolute Prozentzahl ist wertlos — nur der Zuwachs zählt

Gemessen 2026-08-16: gegen einen Stand, in dem das Material nachweislich **fehlte**, meldete
das Gate trotzdem **43 %** — teils echte thematische Überlappung, teils Zufallstreffer.

```bash
# Vorher-Stand sichern, uebertragen, dann BEIDE messen
python tools/coverage_gate.py ziel-VORHER.md  quelle.md   # Grundrate
python tools/coverage_gate.py ziel-AKTUELL.md quelle.md   # danach
```

**Bleibt die Zahl gleich, ist nichts angekommen** — unabhängig davon, wie hoch sie ist.

## Zwei Grenzen, die dazugesagt werden müssen

1. **Gemessen wird ERWÄHNUNG, nicht inhaltliche Treue.** Ein Marker kann vorkommen, während
   der Punkt verstümmelt übertragen wurde. Das Gate schließt **Auslassungen** aus, nicht
   **Verfälschungen**.
2. **Offene Punkte werden einzeln gelistet und einzeln angesehen** — nicht pauschal
   nachgetragen. Ein Punkt kann als „offen" erscheinen, obwohl er sinngemäß übertragen wurde.

## ⛔ Warum die Marker sprachunabhängig sind — das Gate war zweimal blind

Der teuerste Konstruktionsfehler dieses Werkzeugs, beide Fassungen am 2026-08-16 gemessen:

| Fassung | Marker | Symptom |
|---|---|---|
| 1 | **ein** Stichwort je Prüfpunkt | 58,6 % Grundrate für Material, das nachweislich fehlte |
| 2 | mehrere Stichwörter, aber **aus dem Quelltext** | Quelle englisch, Ziel deutsch → **vorher und nachher identisch**, obwohl 1 000 Zeilen dazukamen |

Fassung 2 ist die tückischere: Die Zahl bewegte sich nicht, *weil das Instrument die Sprache
wechselte*, nicht weil der Transfer scheiterte. Beide Male sah das Ergebnis plausibel aus.

**Deshalb zählt `checkpoints()` nur, was eine Übersetzung überlebt:** Inline-Code-Spans
(`` `globs:` ``), Zahlen mit Einheit (`200 Zeilen`, `4,5:1`), CamelCase- und ALLCAPS-Namen
(`InstructionsLoaded`, `CWE-79`). Fließtext-Substantive **nicht** — die sind genau das, was
beim Übersetzen verschwindet.

## Die Gegenprobe läuft MIT, nicht daneben

Vor jeder Messung prüft das Gate einen Kontrollbegriff, der nachweislich nicht im Ziel steht.
Schlägt er an, bricht der Lauf mit Rückgabewert `3` ab und **alle** Ergebnisse des Laufs sind
ungültig.

> **Die Lehre über dieses Werkzeug hinaus:** Ein Messinstrument, das den Gegenstand knapp
> verfehlt, liefert weiter Zahlen — und die sehen aus wie ein Befund. Bevor eine Messung ein
> Urteil trägt, muss sie an einem bekannt LEEREN und einem bekannt VOLLEN Stand gefahren
> werden. Beim Einbau ins Plugin (v5.3.0) belegt: voll → 44/44 (RC 0), leer → 0/44 (RC 1),
> sabotiert → Abbruch (RC 3).
