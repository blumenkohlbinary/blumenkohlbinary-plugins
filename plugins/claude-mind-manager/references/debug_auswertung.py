#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Erzeugt BEFUNDE.md aus Debug/index.jsonl (NEU v5.7.0).

WOZU. Jeder /mind-all-Lauf protokolliert Probleme und Vorschlaege projektlokal in
listeverbesserungen.md. Gemessen am 21.08.2026: 6 Projekte, 28 Laeufe — verstreut. Dass
DERSELBE Fehler zum dritten Mal auftritt, sah niemand. Genau das ist passiert: der
classify_path()-Nachbau meldete dreimal in Folge Slash-Commands als tote Pfade.

Diese Auswertung beantwortet genau eine Frage, und zwar mechanisch:
    Was ist das hier schon einmal gewesen?

Ab dem ZWEITEN Vorkommen einer Ursachenklasse steht WIEDERHOLT daneben. Das ist der ganze
Zweck — eine Liste, die nur zaehlt, haette den dritten Nachbau ebenso wenig verhindert wie
die zwei Lehren, die schon dazu aufgeschrieben waren.

Aufruf:  python debug_auswertung.py <debug-verzeichnis>
Rueckgabe: 0 = geschrieben · 1 = kein index.jsonl · 2 = Aufruffehler
"""
import io
import json
import os
import sys
from collections import defaultdict

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# Feste Liste. Ein freies Textfeld waere nach drei Laeufen unbrauchbar — dann heisst
# derselbe Fehler dreimal anders und wird nie als Wiederholung erkannt.
KLASSEN = {
    "instrument-nachgebaut": "Ein vorhandenes Pruefwerkzeug wurde nachgebaut statt benutzt",
    "instrument-misst-nichts": "Eine Pruefung lief, konnte ihren Gegenstand aber nicht treffen",
    "windows-pfad": "MSYS-/Windows-Pfad, cygpath, Heredoc-Zerstoerung",
    "zeilenenden": "CRLF/LF gemischt oder unbeabsichtigt umgestellt",
    "agent-fehlbericht": "Ein Subagent gab etwas Falsches zurueck",
    "agent-gestorben": "Ein Subagent lieferte kein Ergebnis (= UNGEPRUEFT, nicht unauffaellig)",
    "plugin-defekt": "Fehler im Plugin selbst",
    "doku-veraltet": "Dokumentation widerspricht dem gemessenen Stand",
    "sichtbarkeit": "Inhalt existiert, wird aber nicht geladen/ausgewaehlt",
    "ungeklaerter-widerspruch": "Zwei Quellen widersprechen sich, keine ist belegt",
    "sonstiges": "passt in keine der obigen Klassen",
}

# ⛔ WEM GEHOERT DER BEFUND? (NEU v5.7.3)
#    Der Debug-Ordner ist fuer PLUGIN-Fehler da — das war die ausdrueckliche Absicht.
#    Die Laufberichte mischen aber drei Sorten: Fehler im Plugin, Fehler im Projekt und
#    eigene Methodenfehler. In einem Topf sieht der Plugin-Betreiber nicht, was IHN
#    angeht. Deshalb trennt BEFUNDE.md sie ab jetzt.
PLUGIN_KLASSEN = {
    "instrument-nachgebaut", "instrument-misst-nichts", "plugin-defekt",
    "agent-fehlbericht", "agent-gestorben", "sichtbarkeit",
}


def lies(pfad):
    eintraege, kaputt = [], 0
    with open(pfad, "rb") as f:
        for roh in f:
            roh = roh.strip()
            if not roh:
                continue
            try:
                e = json.loads(roh.decode("utf-8", "replace"))
            except Exception:
                kaputt += 1
                continue
            if isinstance(e, dict) and e.get("klasse"):
                eintraege.append(e)
            else:
                kaputt += 1
    return eintraege, kaputt


def main():
    if len(sys.argv) < 2:
        print("Aufruf: debug_auswertung.py <debug-verzeichnis>", file=sys.stderr)
        return 2
    d = sys.argv[1]
    idx = os.path.join(d, "index.jsonl")
    if not os.path.isfile(idx):
        print("kein index.jsonl in %s" % d, file=sys.stderr)
        return 1

    eintraege, kaputt = lies(idx)
    nach_klasse = defaultdict(list)
    for e in eintraege:
        nach_klasse[e["klasse"]].append(e)

    projekte = {e.get("projekt", "?") for e in eintraege}
    laeufe = {e.get("lauf", "?") for e in eintraege}

    z = []
    z.append("# Befunde aller /mind-all-Laeufe")
    z.append("")
    z.append("Erzeugt von `references/debug_auswertung.py` aus `index.jsonl`.")
    z.append("**Nicht von Hand bearbeiten** — jeder Lauf schreibt die Datei neu.")
    z.append("")
    z.append("| | |")
    z.append("|---|---|")
    z.append("| Befunde gesamt | **%d** |" % len(eintraege))
    z.append("| Laeufe | %d |" % len(laeufe))
    z.append("| Projekte | %d |" % len(projekte))
    if kaputt:
        z.append("| unlesbare Zeilen | %d |" % kaputt)
    z.append("")

    wiederholt = [(k, v) for k, v in nach_klasse.items() if len(v) >= 2]
    z.append("## Wiederholungen — hier zuerst hinsehen")
    z.append("")
    if not wiederholt:
        z.append("(keine — jede Ursachenklasse bisher genau einmal)")
    else:
        z.append("| Klasse | Anzahl | zuerst | zuletzt | Projekte |")
        z.append("|---|---|---|---|---|")
        for k, v in sorted(wiederholt, key=lambda x: -len(x[1])):
            ts = sorted(e.get("ts", "") for e in v)
            pj = sorted({os.path.basename(e.get("projekt", "?")) for e in v})
            z.append("| **%s** | **%d×** | %s | %s | %s |"
                     % (k, len(v), ts[0][:10] or "?", ts[-1][:10] or "?",
                        ", ".join(pj)[:60]))
        z.append("")
        z.append("⛔ **Eine Klasse mit 3 oder mehr Vorkommen ist kein Einzelfall, sondern "
                 "ein Konstruktionsfehler.** Aufschreiben hat sie nachweislich nicht "
                 "verhindert — es braucht eine mechanische Sperre.")
    z.append("")

    plugin = {a: b for a, b in nach_klasse.items() if a in PLUGIN_KLASSEN}
    projekt = {a: b for a, b in nach_klasse.items() if a not in PLUGIN_KLASSEN}
    z.append("## Zustaendigkeit")
    z.append("")
    z.append("| | Befunde | Klassen |")
    z.append("|---|---|---|")
    z.append("| **Plugin** — hier ist der Mind Manager selbst zu reparieren | **%d** | %d |"
             % (sum(len(v) for v in plugin.values()), len(plugin)))
    z.append("| Projekt / Methode — gehoert in das jeweilige Projekt | %d | %d |"
             % (sum(len(v) for v in projekt.values()), len(projekt)))
    z.append("")
    z.append("## Alle Klassen")
    z.append("")
    for k, v in sorted(nach_klasse.items(), key=lambda x: -len(x[1])):
        marke = "  — **WIEDERHOLT**" if len(v) >= 2 else ""
        wem = "PLUGIN" if k in PLUGIN_KLASSEN else "Projekt"
        z.append("### [%s] %s (%d×)%s" % (wem, k, len(v), marke))
        beschreibung = KLASSEN.get(k)
        if beschreibung:
            z.append("")
            z.append("*%s*" % beschreibung)
        elif k not in KLASSEN:
            z.append("")
            z.append("⚠ unbekannte Klasse — nicht in der festen Liste von "
                     "`debug_auswertung.py`")
        z.append("")
        for e in sorted(v, key=lambda x: x.get("ts", ""), reverse=True)[:8]:
            z.append("- `%s` %s · %s"
                     % (e.get("ts", "?")[:16], os.path.basename(e.get("projekt", "?")),
                        e.get("kurz", "").replace("\n", " ")[:150]))
        if len(v) > 8:
            z.append("- … %d weitere" % (len(v) - 8))
        z.append("")

    ziel = os.path.join(d, "BEFUNDE.md")
    # Zeilenenden der bestehenden Datei erhalten (Windows-Arbeitsbaum kann CRLF fuehren)
    ende = "\n"
    if os.path.isfile(ziel):
        roh = open(ziel, "rb").read()
        crlf = roh.count(b"\r\n")
        if crlf > roh.count(b"\n") - crlf:
            ende = "\r\n"
    with open(ziel, "wb") as f:
        f.write(ende.join(z).encode("utf-8") + ende.encode("utf-8"))

    print("BEFUNDE.md: %d Befunde, %d Klassen, %d wiederholt"
          % (len(eintraege), len(nach_klasse), len(wiederholt)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
