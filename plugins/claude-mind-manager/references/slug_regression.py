#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Gegenprobe fuer hash_project_dir() aus hooks/lib.sh (NEU v5.7.0).

WOZU. Bis v5.6.0 ersetzte die Funktion nur `[\\: ()]` durch Bindestriche. Claude Code
ersetzt aber JEDES Nicht-Alphanumerische. Die Folge war kein Absturz, sondern etwas
Schlimmeres: `get_memory_dir` fiel still in den Fallback, und der Skill arbeitete an einem
anderen Ort als dem, an dem die Erinnerungen liegen. Aufgefallen ist es nur, weil in
`Entwicklung&Forschung` bei JEDEM Lauf eine Warnung erschien.

DIE PRUEFUNG MUSS SCHEITERN KOENNEN. Deshalb faehrt sie am Ende die ALTE Regel gegen
dieselben Faelle. Besteht die alte Regel, misst dieser Prueftand nichts und alle
Ergebnisse sind ungueltig (Rueckgabewert 3).

Aufruf:
    python slug_regression.py                 # nur die festen Pruefvektoren
    python slug_regression.py --live <wurzel>  # zusaetzlich gegen ~/.claude/projects

Rueckgabe: 0 = alles gruen  |  1 = Faelle rot  |  3 = Pruefstand ungueltig
"""
import io
import os
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

BS = chr(92)


def neu(win_path):
    """Die Regel ab v5.7.0 — Spiegelbild von: sed 's|[^A-Za-z0-9]|-|g' | sed 's|^-*||'"""
    return re.sub(r"^-*", "", re.sub(r"[^A-Za-z0-9]", "-", win_path))


def alt(win_path):
    """Die Regel bis v5.6.0 — sed 's|[" + BS + BS + ": ()]|-|g'. Nur fuer die Gegenprobe."""
    return re.sub(r"^-*", "", re.sub(r"[" + BS + BS + r":\s()]", "-", win_path))


# (Eingabe, erwarteter Slug, warum dieser Fall drin ist)
VEKTOREN = [
    (r"C:\CD\KOHLEKTIV", "C--CD-KOHLEKTIV",
     "Grundfall: Doppelpunkt und Backslash"),
    (r"C:\CD\KOHLEKTIV\Entwicklung&Forschung", "C--CD-KOHLEKTIV-Entwicklung-Forschung",
     "DER Ausloeser: '&' schickte Memory in den Fallback"),
    (r"C:\CD\KOHLEKTIV\_claude_vm", "C--CD-KOHLEKTIV--claude-vm",
     "'_' wird ebenfalls ersetzt — von der alten Regel uebersehen"),
    (r"C:\CD\KOHLEKTIV\APP - Zustellplan", "C--CD-KOHLEKTIV-APP---Zustellplan",
     "Leerzeichen-Strich-Leerzeichen ergibt DREI Bindestriche"),
    (r"C:\CD\KOHLEKTIV\Plugin - Entwicklung\Claude Mind Manager",
     "C--CD-KOHLEKTIV-Plugin---Entwicklung-Claude-Mind-Manager",
     "dieses Projekt"),
    (r"C:\CD\KOHLEKTIV\Joplin\plugin-design", "C--CD-KOHLEKTIV-Joplin-plugin-design",
     "vorhandene Bindestriche bleiben Bindestriche"),
    (r"C:\CD\KOHLEKTIV\Entwicklung&Forschung\Pc Forschung",
     "C--CD-KOHLEKTIV-Entwicklung-Forschung-Pc-Forschung",
     "'&' und Leerzeichen zusammen"),
    (r"C:\CD\KOHLEKTIV\Tobis Tools\Namens ersteller",
     "C--CD-KOHLEKTIV-Tobis-Tools-Namens-ersteller",
     "mehrere Leerzeichen ueber zwei Ebenen"),
    (r"C:\a.b\c", "C--a-b-c", "Punkt wird ersetzt (.claude-worktrees)"),
    (r"C:\x(y)z", "C--x-y-z", "Klammern — die alte Regel konnte das schon"),
    (r"C:\a+b,c", "C--a-b-c", "Plus und Komma"),
    (r"\\server\freigabe", "server-freigabe", "UNC-Pfad: fuehrende Bindestriche fallen weg"),
]


def main():
    rot = []
    print("=== Pruefvektoren (NEUE Regel) ===")
    for eingabe, soll, warum in VEKTOREN:
        ist = neu(eingabe)
        gut = ist == soll
        if not gut:
            rot.append((eingabe, soll, ist))
        print("  %s %-52s -> %s" % ("[ok ]" if gut else "[ROT]", warum, ist))
        if not gut:
            print("        erwartet: %s" % soll)

    # --- Negativkontrolle: die ALTE Regel MUSS durchfallen -------------------
    print()
    print("=== NEGATIVKONTROLLE: alte Regel muss scheitern ===")
    alt_rot = [e for e, s, _ in VEKTOREN if alt(e) != s]
    print("  alte Regel faellt bei %d von %d Faellen durch" % (len(alt_rot), len(VEKTOREN)))
    if not alt_rot:
        print()
        print("  ABBRUCH: die alte Regel besteht alle Faelle.")
        print("  Dieser Pruefstand misst nichts — alle Ergebnisse oben sind ungueltig.")
        return 3
    for e in alt_rot[:4]:
        print("     %s -> %s" % (e, alt(e)))

    # --- Optional: gegen die real vorhandenen Claude-Code-Ordner -------------
    if "--live" in sys.argv:
        i = sys.argv.index("--live")
        wurzel = sys.argv[i + 1] if len(sys.argv) > i + 1 else None
        pd = os.path.expanduser("~/.claude/projects")
        if wurzel and os.path.isdir(wurzel) and os.path.isdir(pd):
            echte = {d for d in os.listdir(pd) if os.path.isdir(os.path.join(pd, d))}
            gefunden = verloren = 0
            for d, unter, _ in os.walk(wurzel):
                if d.count(os.sep) - wurzel.count(os.sep) > 2:
                    unter[:] = []
                    continue
                unter[:] = [u for u in unter if not u.startswith((".", "_"))]
                win = d.replace("/", BS)
                if neu(win) in echte:
                    gefunden += 1
                if alt(win) in echte and neu(win) not in echte:
                    verloren += 1
            print()
            print("=== Live gegen ~/.claude/projects ===")
            print("  neue Regel trifft %d vorhandene Ordner, verliert %d" % (gefunden, verloren))
            if verloren:
                rot.append(("live", "0 Verluste", "%d Verluste" % verloren))

    print()
    print("=" * 60)
    if rot:
        print("  ERGEBNIS: %d von %d ROT" % (len(rot), len(VEKTOREN)))
        return 1
    print("  ERGEBNIS: alle %d Faelle bestanden, Negativkontrolle greift" % len(VEKTOREN))
    return 0


if __name__ == "__main__":
    sys.exit(main())
