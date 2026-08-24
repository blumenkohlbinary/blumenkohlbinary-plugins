#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prueffunktionen ohne Prueffall finden — die Sperre gegen `instrument-misst-nichts`.

⛔ WARUM ES DAS GIBT

`Debug/BEFUNDE.md` fuehrt `instrument-misst-nichts` mit **23 Vorkommen** als
groesste Klasse ueberhaupt. Die Datei sagt selbst dazu:

    "Eine Klasse mit 3 oder mehr Vorkommen ist kein Einzelfall, sondern ein
     Konstruktionsfehler. Aufschreiben hat sie nachweislich nicht verhindert —
     es braucht eine mechanische Sperre."

Am 23.08.2026 kam der Beweis: `mind_zeilenenden_gleich` war die Sperre gegen die
Klasse `zeilenenden` — und mass die falsche Groesse, an 1 von 68 Dateien, ein
Jahr lang. Sie hatte keinen Prueffall. Niemand konnte es sehen.

⭐ DIE EINZIGE FRAGE DIESES WERKZEUGS

    Gibt es zu jeder Pruef-Funktion einen Prueffall, der sie ROT werden laesst?

⛔ WAS ES NICHT KANN — und das gehoert in JEDE Ausgabe

Es prueft die EXISTENZ eines Prueffalls, nicht seine GUETE. Ein Prueffall, der am
falschen Gegenstand scheitert, ist genau der Fehler, den wir bekaempfen — und
dieses Werkzeug kann ihn nicht sehen. Es hebt die Untergrenze. Es garantiert
nichts. Wer aus einer Untergrenze eine Zusicherung macht, hat den Fehler wieder
gemacht, gegen den das Werkzeug gebaut ist.

DIE ZWEI ZAHLEN SIND VERSCHIEDEN VIEL WERT

  ungetestet         HARTE TATSACHE. Der Funktionsname kommt in keiner
                     Pruefdatei vor. Daran ist nichts zu deuteln.
  ohne_negativfall   HEURISTIK. Der Name kommt vor, aber in der Datei findet
                     sich keine Wendung, die auf eine Gegenprobe hindeutet.
                     Kann falsch liegen — deshalb nur Hinweis, nie Abbruch.

DIE SPERRE IST EINE RATSCHE, KEINE HUERDE

Ein Gate, das sofort rot ist, wird abgeschaltet. Deshalb: es faellt nur durch,
wenn die Zahl der UNGETESTETEN Funktionen STEIGT. Der Stand liegt in
`tests/.negativfall-stand`. Neue ungepruefte Funktion = rot. Bestand abbauen =
freiwillig, aber sichtbar.

Aufruf:
  python references/negativfall_gate.py                  # prueft, Ratsche greift
  python references/negativfall_gate.py --stand-setzen   # neuen Stand festschreiben
  python references/negativfall_gate.py --liste          # alle Funktionen zeigen

Rueckgabe: 0 = nicht schlechter geworden · 1 = neue ungetestete Funktion
           2 = Messung unmoeglich (keine lib.sh, kein tests/)
"""
import io
import os
import re
import sys

# ⛔ `newline=""` ist PFLICHT auf Windows. Ohne diesen Zusatz uebersetzt
#    TextIOWrapper jeden Zeilenumbruch in die Windows-Fassung (CR + LF).
#    Jede zeilenverankerte Zusicherung (das Dollarzeichen in grep) bricht
#    dann — und zwar STILL, denn die Ausgabe sieht voellig richtig aus.
#    Gemessen 24.08.2026 an `cleaner_duplikate.py`: zwei Prueffaelle meldeten
#    0 Treffer fuer Zeilen, die dastanden. Dieselbe Klasse wie der in der
#    globalen CLAUDE.md dokumentierte `write_text()`-Fall.
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", newline="")

WURZEL = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

LIB = os.path.join(WURZEL, "hooks", "lib.sh")
TESTS = os.path.join(WURZEL, "tests")
STAND = os.path.join(TESTS, ".negativfall-stand")

# Welche Funktionen ueberhaupt gemeint sind. Nicht jede Hilfsfunktion ist eine
# Pruefung — `mind_log` muss keinen Negativfall haben.
#
# ⚠ Die Auswahl ist eine ENTSCHEIDUNG, keine Messung. Sie steht hier sichtbar,
#   damit sie bestreitbar ist, statt in einer Regex zu verschwinden.
PRUEFT = (
    "check",       # mind_check_tools_have_rules
    "gleich",      # mind_zeilenenden_gleich
    "scan",        # mind_scan_poisoning
    "waechter",    # mind_zeilenenden_waechter
    "bilanz",      # mind_agent_bilanz
    "frisch",      # mind_sync_frisch
    "lebt",        # mind_pfad_lebt
    "seit",        # mind_commits_seit
    "schnappziel",
    "tokens",      # mind_kontext_tokens
    "health",      # mind_hook_health
)

# Wendungen, die auf eine Gegenprobe hindeuten. Bewusst grosszuegig — ein
# falscher Treffer hier kostet nichts (nur ein Hinweis entfaellt), ein
# verpasster erzeugt einen Fehlalarm, und Fehlalarme toeten Gates.
NEGATIV = re.compile(
    r"soll=(?:1|2)\b|Negativ|Gegenprobe|Gegenkontrolle|muss\s+(?:ROT|scheitern|rot)|"
    r"darf\s+NICHT|NICHT\s+gemeldet|scheitern\s+KOENNEN|sabotier",
    re.IGNORECASE)


def funktionen():
    if not os.path.isfile(LIB):
        return None
    t = open(LIB, encoding="utf-8", errors="replace").read()
    alle = re.findall(r"^([a-z_]+)\(\)", t, re.M)
    return [f for f in alle if any(k in f for k in PRUEFT)]


def pruefdateien():
    if not os.path.isdir(TESTS):
        return None
    return [os.path.join(TESTS, n) for n in sorted(os.listdir(TESTS))
            if n.startswith("test_") and n.endswith((".sh", ".py"))]


def main():
    fns = funktionen()
    dateien = pruefdateien()
    if fns is None or dateien is None:
        print("⛔ Messung unmoeglich: %s fehlt"
              % ("hooks/lib.sh" if fns is None else "tests/"))
        print("   Das ist NIE ein gutes Ergebnis — eher eine falsche Wurzel (%s)." % WURZEL)
        return 2
    if not fns:
        print("⛔ Keine Pruef-Funktion erkannt. Entweder ist die Auswahlliste PRUEFT")
        print("   zu eng, oder die Wurzel ist falsch. Beides ist ein Befund, kein OK.")
        return 2

    inhalt = {p: open(p, encoding="utf-8", errors="replace").read() for p in dateien}

    ungetestet, ohne_neg, gut = [], [], []
    for f in fns:
        treffer = [p for p, t in inhalt.items() if f in t]
        if not treffer:
            ungetestet.append(f)
        elif not any(NEGATIV.search(inhalt[p]) for p in treffer):
            ohne_neg.append((f, [os.path.basename(p) for p in treffer]))
        else:
            gut.append(f)

    if "--liste" in sys.argv:
        for f in fns:
            marke = ("UNGETESTET" if f in ungetestet
                     else "ohne Negativfall" if f in [a for a, _ in ohne_neg] else "ok")
            print("  %-16s %s" % (marke, f))
        return 0

    print("=" * 70)
    print("  Negativfall-Gate")
    print("  Wurzel: %s" % WURZEL)
    print("=" * 70)
    print("  %d Pruef-Funktionen · %d mit Gegenprobe · %d ohne · %d UNGETESTET"
          % (len(fns), len(gut), len(ohne_neg), len(ungetestet)))
    print()
    if ungetestet:
        print("  ⛔ UNGETESTET (harte Tatsache — der Name steht in keiner Pruefdatei):")
        for f in ungetestet:
            print("     - %s" % f)
        print()
    if ohne_neg:
        print("  ⚠ Ohne erkennbare Gegenprobe (HEURISTIK, kann falsch liegen):")
        for f, wo in ohne_neg:
            print("     - %-30s genannt in %s" % (f, ", ".join(wo)))
        print()

    print("  ⛔ Dieses Gate prueft die EXISTENZ eines Prueffalls, nicht seine GUETE.")
    print("     Ein Prueffall, der am falschen Gegenstand scheitert, ist unsichtbar")
    print("     — genau der Fehler, gegen den das Gate gebaut ist. Untergrenze,")
    print("     keine Zusicherung.")
    print()

    jetzt = len(ungetestet)
    if "--stand-setzen" in sys.argv:
        os.makedirs(TESTS, exist_ok=True)
        with open(STAND, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("%d\n" % jetzt)
        print("  Stand festgeschrieben: %d ungetestet" % jetzt)
        return 0

    vorher = None
    if os.path.isfile(STAND):
        roh = open(STAND, encoding="utf-8", errors="replace").read().strip()
        if roh.isdigit():
            vorher = int(roh)

    if vorher is None:
        print("  Kein Stand hinterlegt. Erste Messung setzt keinen Nullpunkt von")
        print("  selbst — das waere eine Ratsche, die sich selbst nachzieht.")
        print("  Absichtlich festschreiben mit --stand-setzen.")
        return 0

    if jetzt > vorher:
        print("  ⛔ ROT: %d ungetestet, vorher %d. Eine neue Pruef-Funktion ohne" % (jetzt, vorher))
        print("     Prueffall ist genau der Zustand, aus dem die 23 Vorkommen der")
        print("     Klasse `instrument-misst-nichts` entstanden sind.")
        return 1
    if jetzt < vorher:
        print("  ✅ %d ungetestet, vorher %d — Bestand abgebaut." % (jetzt, vorher))
        print("     Mit --stand-setzen festschreiben, sonst faellt es zurueck.")
        return 0
    print("  ✅ %d ungetestet, unveraendert." % jetzt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
