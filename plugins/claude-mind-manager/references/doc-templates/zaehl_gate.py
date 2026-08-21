#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prueft Zahlen in einer Doku-Datei gegen die Realitaet.

⛔ WARUM ES DAS GIBT. Eine Doku-Tabelle, die neben jede Zahl den Befehl schreibt,
   mit dem man sie nachzaehlt, verhindert das Veralten NICHT. Im Ursprungsprojekt
   war genau so eine Tabelle **sechsmal** falsch (`lib.sh`-Funktionen 7 -> 12 -> 13
   -> 16 -> 17; ausgelieferte `.py` 2 statt 5, spaeter 5 statt 8; Skills 8 statt 9),
   obwohl sie seit dem zweiten Mal selbst notierte:

       "Eine Lehre aufzuschreiben verhindert ihren Wiedereintritt nicht --
        nur ein Check tut das. Hier waere er billig."

   Gebaut hatte ihn niemand. Das ist er.

ERWARTETES FORMAT -- eine Markdown-Tabelle, deren Zeilen so aussehen:

    | Skills **9**                | `ls -1d skills/*/ \\| wc -l`            |
    | Prueffaelle **84**          | `grep -rc '\\[ok \\]' tests/ \\| ...`   |

Die Zeilen duerfen in einem Blockzitat stehen (`>` am Zeilenanfang).

Aufruf:   python tools/zaehl_gate.py <doku.md> [--cwd <verzeichnis>]
Rueckgabe: 0 = alle Zahlen stimmen · 1 = Abweichung · 2 = Tabelle nicht lesbar
"""
import io
import os
import re
import shutil
import subprocess
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


def zeilen_der_tabelle(t):
    """Zeilen der Form:  | <Name> **<Zahl>** | `<befehl>` |

    ⚠ Steht die Tabelle in einem Blockzitat (`>` am Zeilenanfang) und man
       vergisst das beim Parsen, findet man nichts und meldet "Tabelle leer"
       statt "Zahlen stimmen nicht" -- ein Instrument, das schweigt, wo es
       messen soll.
    """
    raus = []
    for z in t.replace("\r\n", "\n").split("\n"):
        z = z.lstrip().lstrip(">").strip()
        m = re.match(r"^\|\s*(.+?)\s*\*\*(\d+)\*\*\s*\|\s*`(.+?)`\s*\|$", z)
        if m:
            # ⛔ In einer Markdown-Tabelle ist die Pipe als `\|` maskiert, sonst
            #    zerlegt sie die Zelle. Ohne das Zuruecknehmen bekommt bash
            #    `ls -1d skills/*/ \| wc -l` -- der Backslash zerbricht den Befehl,
            #    die Ausgabe ist leer, und das Gate meldet "alle Zahlen falsch".
            #    Ein Instrument, das an seiner EIGENEN Eingabe scheitert, sieht
            #    von aussen aus wie ein echter Befund ueber den Gegenstand.
            raus.append((m.group(1).strip(), int(m.group(2)),
                         m.group(3).strip().replace("\\|", "|")))
    return raus


def finde_bash():
    """⛔ `bash` NIE ueber den blossen Namen aufrufen.

    Gemessen 21.08.2026: Windows' CreateProcess durchsucht System32 zuerst, und
    dort liegt WSLs `bash.exe`. Der Aufruf scheitert mit
    "WSL ... execvpe /bin/bash failed 2", die Ausgabe ist LEER, der Rueckgabewert 1
    -- und das Gate meldete "7 von 7 Zahlen stimmen NICHT", obwohl alle sieben
    stimmten. `shutil.which` findet Git Bash dagegen korrekt.
    """
    b = shutil.which("bash")
    if b and "System32" not in b:
        return b
    for k in (r"C:\Program Files\Git\bin\bash.exe",
              r"C:\Program Files\Git\usr\bin\bash.exe",
              "/bin/bash", "/usr/bin/bash"):
        if os.path.isfile(k):
            return k
    return None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print((__doc__ or "").split("Aufruf:")[-1].strip(), file=sys.stderr)
        return 2
    doku = args[0]
    cwd = os.path.dirname(os.path.abspath(doku)) or "."
    if "--cwd" in sys.argv:
        cwd = sys.argv[sys.argv.index("--cwd") + 1]

    if not os.path.isfile(doku):
        print("Doku-Datei nicht gefunden: %s" % doku, file=sys.stderr)
        return 2
    if not os.path.isdir(cwd):
        print("Arbeitsverzeichnis nicht gefunden: %s" % cwd, file=sys.stderr)
        return 2

    eintraege = zeilen_der_tabelle(open(doku, "rb").read().decode("utf-8", "replace"))
    if not eintraege:
        print("\u26d4 Keine Zaehl-Zeilen gefunden. Erwartet wird "
              "`| Name **Zahl** | \\`befehl\\` |` -- Format geaendert?", file=sys.stderr)
        return 2

    bash = finde_bash()
    if not bash:
        print("\u26d4 Keine brauchbare bash gefunden -- das Gate kann nicht messen. "
              "Es meldet AUSDRUECKLICH kein Ergebnis, statt eines zu erfinden.",
              file=sys.stderr)
        return 2

    print("=" * 66)
    print("  Zaehl-Gate: %s" % os.path.basename(doku))
    print("  gemessen in: %s" % cwd)
    print("=" * 66)

    rot = 0
    for name, soll, befehl in eintraege:
        r = subprocess.run([bash, "-c", befehl], cwd=cwd, capture_output=True,
                           text=True, encoding="utf-8", errors="replace")
        roh = (r.stdout or "").strip()
        try:
            ist = int(roh.split()[0])
        except (ValueError, IndexError):
            # ⚠ Kein Ergebnis ist KEINE Null. Ein Befehl, der nichts liefert,
            #    wird als unmessbar gemeldet, nicht als 0 verglichen.
            print("  [??] %-34s Befehl lieferte '%s'" % (name[:34], roh[:30]))
            rot += 1
            continue
        gut = ist == soll
        print("  %s %-34s Doku %4d \u00b7 gemessen %4d"
              % ("[ok ]" if gut else "[ROT]", name[:34], soll, ist))
        if not gut:
            rot += 1

    print()
    if rot:
        print("  \u26d4 %d von %d Zahlen stimmen NICHT. Zuerst die DOKU verdaechtigen, "
              "nicht den Gegenstand." % (rot, len(eintraege)))
    else:
        print("  %d Zahlen geprueft, alle stimmen." % len(eintraege))
    return 1 if rot else 0


if __name__ == "__main__":
    sys.exit(main())
