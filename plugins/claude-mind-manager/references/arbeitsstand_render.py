#!/usr/bin/env python3
"""Rendert <ts>_ARBEITSSTAND.json lesbar — fuer /mind-all Step 0.

NEU v5.6.0. Ausgelieferte DATEI, kein Heredoc nach /tmp — siehe "Befund 9" in
session_sampler.py: der Heredoc-Weg ist auf Windows/Git-Bash unzuverlaessig
(Pfade mit '&', Leerzeichen, Umlauten).

⛔ OHNE Kappung. Die Erinnerungs-Hooks kappen RESUME.md bei 30 Zeilen, und das ist
   dort richtig — eine Erinnerung soll kurz sein. HIER ist der Ort, an dem der
   ausfuehrliche Stand vollstaendig gelesen wird.

Aufruf:  python arbeitsstand_render.py <arbeitsstand.json>
Rueckgabe: 0 = gerendert · 1 = Datei fehlt/unlesbar (Aufrufer laeuft weiter)
"""
import io
import json
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

KATEGORIEN = [
    ("decisions", "Architektonische Entscheidungen"),
    ("bugs", "Aktive Bugs"),
    ("constraints", "Aktive Constraints"),
]


def main(argv):
    if len(argv) < 2:
        print("usage: arbeitsstand_render.py <arbeitsstand.json>", file=sys.stderr)
        return 1
    try:
        d = json.load(open(argv[1], encoding="utf-8"))
    except Exception as e:
        print("  (Arbeitsstand nicht lesbar: %s)" % e, file=sys.stderr)
        return 1

    ereignisse = d.get("total_events", 0)
    print("  Quelle: %d Events%s"
          % (ereignisse, " (lange Sitzung, Top-N reduziert)" if d.get("long_session") else ""))

    for schluessel, titel in KATEGORIEN:
        eintraege = d.get(schluessel) or []
        gesamt = d.get(schluessel + "_total", len(eintraege))
        print("  %s (%d):" % (titel, gesamt))
        if not eintraege:
            # ⛔ Leer ist ein Ergebnis, kein Fehler. Ein Extraktor, der immer etwas
            #    findet, misst nichts.
            print("    (keine)")
            continue
        for e in eintraege:
            quelle = (" [%s]" % e["src"]) if e.get("src") else ""
            print("    - [%s]%s %s" % (e.get("line", "?"), quelle, (e.get("text") or "").strip()))
        if gesamt > len(eintraege):
            print("    ... %d weitere ausgeblendet" % (gesamt - len(eintraege)))

    dateien = d.get("files") or []
    gesamt = d.get("files_total", len(dateien))
    print("  Geaenderte Dateien (%d):" % gesamt)
    if not dateien:
        print("    (keine)")
    for f in dateien[:15]:
        print("    - %s" % f)
    if gesamt > min(len(dateien), 15):
        print("    ... %d weitere ausgeblendet" % (gesamt - min(len(dateien), 15)))

    print("  ⚠ Heuristik-basiert — vor dem Verwenden pruefen.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
