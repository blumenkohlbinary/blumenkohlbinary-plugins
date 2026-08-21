#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Behobene Befunde aus dem Debug-Ordner entfernen (NEU v5.9.2).

⛔ DAS PROBLEM, DAS DAS HIER LOEST. `index.jsonl` wuchs nur. Ein Befund, der laengst
   behoben war, stand dort weiter und wanderte in jede neue `BEFUNDE.md`. Gemessen am
   21.08.2026: von 106 Zeilen waren mehrere die Fehlalarme "36 Skills ohne
   description" und "83 Skills ohne description" — beide durch den Check-Fix in v5.9.1
   erledigt, beide immer noch gelistet. Eine Liste, die nur waechst, wird unlesbar und
   dann ignoriert; genau so ist der Vorgaenger-Mechanismus gestorben.

DIE UNTERSCHEIDUNG, auf der alles beruht:

  Scanner-Befunde (`lauf == "mind-learnings"`) sind DETERMINISTISCH. Sie beschreiben
  den Zustand JETZT. Also werden sie bei jedem Lauf komplett ersetzt — was nicht mehr
  reproduziert, ist behoben und verschwindet. Das ist kein Datenverlust, sondern der
  einzig richtige Umgang mit einer wiederholbaren Messung.

  Laufberichte (`/mind-all` u.a.) sind HISTORISCH. Sie beschreiben, was in einem
  bestimmten Lauf passiert ist, und lassen sich nicht nachmessen. Die bleiben — es sei
  denn, jemand entfernt sie ausdruecklich.

⛔ Deshalb loescht `--scanner-neu` NUR Scanner-Zeilen. Historische Befunde anzufassen
   waere Geschichtsfaelschung: was einmal passiert ist, ist passiert.

Aufruf:
  debug_aufraeumen.py <debug-dir> --scanner-neu <neue.jsonl>   Scanner-Zeilen ersetzen
  debug_aufraeumen.py <debug-dir> --verwaiste                  Laufdateien ohne Befunde weg
  debug_aufraeumen.py <debug-dir> --entferne-lauf <name>       einen Laufbericht entfernen
Rueckgabe: 0 = erledigt · 1 = kein index.jsonl · 2 = Aufruffehler
"""
import io
import json
import os
import shutil
import sys
import time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

SCANNER = "mind-learnings"


def lies(idx):
    raus, kaputt = [], 0
    with open(idx, "rb") as f:
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
                raus.append(e)
            else:
                kaputt += 1
    return raus, kaputt


def schreib(idx, eintraege):
    """Zeilenenden der bestehenden Datei erhalten."""
    ende = "\n"
    if os.path.isfile(idx):
        roh = open(idx, "rb").read()
        crlf = roh.count(b"\r\n")
        if crlf > roh.count(b"\n") - crlf:
            ende = "\r\n"
    with open(idx, "wb") as f:
        for e in eintraege:
            f.write((json.dumps(e, ensure_ascii=True) + ende).encode("utf-8"))


def main():
    if len(sys.argv) < 3:
        print(__doc__.split("Aufruf:")[1], file=sys.stderr)
        return 2
    d = sys.argv[1]
    idx = os.path.join(d, "index.jsonl")
    if not os.path.isfile(idx):
        print("kein index.jsonl in %s" % d, file=sys.stderr)
        return 1

    alt, kaputt = lies(idx)

    # ⛔ Sicherung VOR jeder Loeschung — die globale Regel gilt auch hier.
    sich = os.path.join(d, "_verlauf")
    os.makedirs(sich, exist_ok=True)
    stempel = time.strftime("%Y%m%d_%H%M%S")
    shutil.copy2(idx, os.path.join(sich, "index-%s.jsonl" % stempel))

    if "--scanner-neu" in sys.argv:
        neu_datei = sys.argv[sys.argv.index("--scanner-neu") + 1]
        neu = []
        if os.path.isfile(neu_datei):
            neu, _ = lies(neu_datei)
        behalten = [e for e in alt if e.get("lauf") != SCANNER]
        entfernt = len(alt) - len(behalten)
        schreib(idx, behalten + neu)
        print("  Scanner-Zeilen ersetzt: %d entfernt, %d neu" % (entfernt, len(neu)))
        print("  historische Befunde unberuehrt: %d" % len(behalten))
        print("  index.jsonl: %d -> %d Zeilen" % (len(alt), len(behalten) + len(neu)))
        alt = behalten + neu

    if "--entferne-lauf" in sys.argv:
        name = sys.argv[sys.argv.index("--entferne-lauf") + 1]
        behalten = [e for e in alt if e.get("lauf") != name]
        print("  Lauf '%s': %d Befunde entfernt" % (name, len(alt) - len(behalten)))
        schreib(idx, behalten)
        alt = behalten

    if "--verwaiste" in sys.argv:
        # Eine Laufdatei ist verwaist, wenn KEIN Befund mehr auf ihren Zeitraum zeigt.
        # ⚠ Zuordnung ueber den Dateinamen <ts>_<slug>.md gegen ts+projekt der Befunde.
        ld = os.path.join(d, "laeufe")
        if os.path.isdir(ld):
            lebend = set()
            for e in alt:
                t = (e.get("ts") or "")[:13].replace("T", "_").replace(":", "")
                lebend.add(t)
            weg = []
            for f in sorted(os.listdir(ld)):
                if not f.endswith(".md"):
                    continue
                kopf = f[:13]        # 2026-08-21_15
                if kopf not in lebend:
                    weg.append(f)
            for f in weg:
                shutil.move(os.path.join(ld, f), os.path.join(sich, f))
            print("  verwaiste Laufberichte nach _verlauf/ verschoben: %d" % len(weg))
            if weg:
                print("    " + ", ".join(weg[:6]))

    # Auswertung neu erzeugen
    hier = os.path.dirname(os.path.abspath(__file__))
    aus = os.path.join(hier, "debug_auswertung.py")
    if os.path.isfile(aus):
        # ⛔ NICHT os.system: der Debug-Pfad enthaelt Leerzeichen
        #    ("Plugin - Entwicklung/Claude Mind Manager/Debug"), und os.system reicht
        #    die Zeile an cmd.exe weiter, das daran scheitert — gemessen:
        #    "Die Syntax fuer den Dateinamen ... ist falsch", und die Auswertung lief
        #    still gar nicht. subprocess mit LISTE hat das Problem nicht.
        import subprocess
        r = subprocess.run([sys.executable, aus, d], capture_output=True,
                           text=True, encoding="utf-8", errors="replace")
        if r.returncode == 0:
            for z in (r.stdout or "").strip().split("\n"):
                if z.strip():
                    print("  " + z.strip())
        else:
            print("  ⚠ debug_auswertung.py scheiterte (rc=%d): %s"
                  % (r.returncode, (r.stderr or "")[:200]))
    if kaputt:
        print("  ⚠ %d unlesbare Zeilen uebersprungen" % kaputt)
    print("  Sicherung: %s/index-%s.jsonl" % (sich, stempel))
    return 0


if __name__ == "__main__":
    sys.exit(main())
