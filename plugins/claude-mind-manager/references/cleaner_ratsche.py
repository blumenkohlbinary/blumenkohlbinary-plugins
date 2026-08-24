#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Die Ratsche — misst WIEDERAUFERSTEHUNG, nicht Bytes.

⛔ WARUM KEINE GROESSENBREMSE

Die naheliegende Bremse waere ein Byte-Budget: "der Bestand darf nicht ueber
X wachsen". Das waere falsch. **Ein Bestand DARF wachsen — neues Wissen ist kein
Fehler.** Eine Bremse gegen legitimes Wachstum ist eine Bremse gegen Lernen.

Was nicht passieren darf, ist etwas anderes: dass etwas, das **bewusst
herausgenommen** wurde, unbemerkt **zurueckkommt**.

    Beim Archivieren:  die Marken des archivierten Inhalts festhalten,
                       samt Datum und Grund.
    Bei jedem Lauf:    kommt eine dieser Marken wieder in einer GELADENEN
                       Datei vor?
    Wenn ja:           melden — mit Vorgeschichte.

⭐ Das beantwortet die Frage, die eine Groessenzahl nie beantwortet: nicht
"ist es groesser geworden?", sondern **"ist genau das zurueck, was wir
weggenommen haben?"**

⚠ **Eine Wiederauferstehung ist NICHT automatisch ein Fehler.** Vielleicht wurde
zu Unrecht archiviert. Das Werkzeug meldet mit Vorgeschichte, es urteilt nicht:

    `MIND_NOTFALL_TOKENS` wurde am 22.08. archiviert (Grund: im Code entfallen)
    und steht seit dem 24.08. wieder in CLAUDE.md.

Zusaetzlich, billig und ehrlich: je Lauf eine Zeile mit Dateizahl und Bytes je
Ablage. **Kein Gate, kein Abbruch** — nur eine Kurve, die man ansehen kann.

Ablage: `.claude-mind/archiviert-marken.json` · `.claude-mind/bestandsverlauf.jsonl`

Aufruf:
  python cleaner_ratsche.py --archiviere <datei> --grund "..." [--projekt P]
  python cleaner_ratsche.py --pruefe [--projekt P]
  python cleaner_ratsche.py --verlauf [--projekt P]
  python cleaner_ratsche.py --selbsttest

Rueckgabe beim Pruefen: 0 = nichts auferstanden · 1 = Wiederauferstehung · 2 = nicht messbar
"""

import json
import os
import sys
import time

_HIER = os.path.dirname(os.path.abspath(__file__))
if _HIER not in sys.path:
    sys.path.insert(0, _HIER)
# ⛔ NICHT nachbauen: die Markenerkennung samt Rauschfilter steht schon in
#    cleaner_duplikate. Ein zweites Instrument daneben hiesse, dass sich ab
#    jetzt zwei Messungen widersprechen koennen.
from cleaner_duplikate import marken                            # noqa: E402

# ⛔ ERST importieren, DANN `reconfigure` — und NIE einen zweiten TextIOWrapper.
#
#    `cleaner_duplikate` setzt beim Import selbst einen Wrapper auf
#    `sys.stdout.buffer`. Wer davor einen eigenen anlegt, laesst ihn ohne
#    Referenz zurueck — und ein TextIOWrapper SCHLIESST beim Wegraeumen seinen
#    Puffer. Der naechste `print` bricht dann mit
#    `ValueError: I/O operation on closed file`.
#
#    ⚠ Das ist an einem Tag FUENFMAL passiert. `reconfigure` tauscht kein
#    Objekt aus und hat das Problem nicht.
#
#    `newline=""` bleibt Pflicht: sonst uebersetzt Windows jeden Zeilenumbruch
#    in CR + LF, und jede zeilenverankerte Zusicherung bricht daran — STILL,
#    denn die Ausgabe sieht voellig richtig aus.
sys.stdout.reconfigure(encoding="utf-8", newline="")


def _mp(projekt):
    return os.path.join(projekt, ".claude-mind", "archiviert-marken.json")


def _vp(projekt):
    return os.path.join(projekt, ".claude-mind", "bestandsverlauf.jsonl")


def _lies(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return None


def geladene_dateien(projekt, nur_projekt=False):
    """Was bei einer Sitzung wirklich mitgeladen wird.

    ⛔ REKURSIV. Ein Unterordner in `rules/` laedt MIT — gemessen 23.08.2026:
       267 von 920 Ladevorgaengen kamen aus einem `archive/`-Ordner, der
       angelegt worden war, UM den Bestand zu kuerzen.

    ⛔ `nur_projekt` ist eine MESSVORAUSSETZUNG, keine Bequemlichkeit.
       Ohne diesen Schalter durchsucht jeder Lauf auch den echten globalen
       Bestand des Rechners. Der eigene Selbsttest schlug dadurch an, weil
       `MIND_NOTFALL_TOKENS` in der ECHTEN globalen CLAUDE.md steht — der
       Prueffall mass die Maschine statt seiner eigenen Fixture.
       Dritter Fall dieser Bauart an einem Tag.
    """
    H = os.path.expanduser("~")
    out = []
    wurzeln = [os.path.join(projekt, ".claude", "rules")]
    if not nur_projekt:
        wurzeln.insert(0, os.path.join(H, ".claude", "rules"))
    for wurzel in wurzeln:
        for w, _, fs in os.walk(wurzel):
            out += [os.path.join(w, f) for f in sorted(fs) if f.endswith(".md")]
    kandidaten = [os.path.join(projekt, "CLAUDE.md")]
    if not nur_projekt:
        kandidaten.insert(0, os.path.join(H, ".claude", "CLAUDE.md"))
    for f in kandidaten:
        if os.path.isfile(f):
            out.append(f)
    return out


def archiviere(projekt, datei, grund):
    t = _lies(datei)
    if t is None:
        return None
    p = _mp(projekt)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    bestand = json.loads(_lies(p) or "[]") if os.path.isfile(p) else []
    e = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "datei": datei.replace("\\", "/"),
        "grund": grund,
        "marken": sorted(marken(t)),
    }
    bestand.append(e)
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(bestand, fh, ensure_ascii=True, indent=1)
    return e


def pruefe(projekt, nur_projekt=False):
    """(auferstanden, geprueft) — auferstanden je (marke, eintrag, fundorte)"""
    p = _mp(projekt)
    if not os.path.isfile(p):
        return None, 0
    try:
        bestand = json.loads(_lies(p) or "[]")
    except ValueError:
        return None, 0

    dateien = geladene_dateien(projekt, nur_projekt)
    inhalt = {d: (_lies(d) or "") for d in dateien}
    auferstanden = []
    for e in bestand:
        # ⚠ Die Quelldatei selbst zaehlt nicht — sie liegt im Archiv und laedt
        #   ohnehin nicht mit. Gesucht wird nur in dem, was WIRKLICH laedt.
        quelle = e.get("datei", "").replace("\\", "/")
        for m in e.get("marken", []):
            wo = [d for d, t in inhalt.items()
                  if m in t and d.replace("\\", "/") != quelle]
            if wo:
                auferstanden.append((m, e, wo))
    return auferstanden, len(dateien)


def verlauf_schreiben(projekt):
    """⚠ Kein Gate. Nur eine Kurve, die man ansehen kann."""
    H = os.path.expanduser("~")
    zeile = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "ablagen": {}}
    for name, wurzel in (("g:rules", os.path.join(H, ".claude", "rules")),
                         ("p:rules", os.path.join(projekt, ".claude", "rules"))):
        n = b = 0
        for w, _, fs in os.walk(wurzel):
            for f in fs:
                if f.endswith(".md"):
                    n += 1
                    b += os.path.getsize(os.path.join(w, f))
        zeile["ablagen"][name] = {"dateien": n, "bytes": b}
    for name, f in (("g:CLAUDE.md", os.path.join(H, ".claude", "CLAUDE.md")),
                    ("p:CLAUDE.md", os.path.join(projekt, "CLAUDE.md"))):
        zeile["ablagen"][name] = {"dateien": 1 if os.path.isfile(f) else 0,
                                  "bytes": os.path.getsize(f) if os.path.isfile(f) else 0}
    p = _vp(projekt)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(zeile, ensure_ascii=True) + "\n")
    return zeile


# --------------------------------------------------------------------------
def selbsttest():
    import tempfile
    d = tempfile.mkdtemp()
    fehler = 0

    def pruef(name, ist, soll):
        nonlocal fehler
        ok = ist == soll
        if not ok:
            fehler += 1
        print("    %-4s %-50s ist=%-9s soll=%s"
              % ("OK" if ok else "FEHL", name, ist, soll))

    proj = os.path.join(d, "proj")
    os.makedirs(os.path.join(proj, ".claude", "rules"))

    def schreib(rel, t):
        p = os.path.join(proj, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(t)
        return p

    print("=" * 78)
    print("  Selbsttest — die Ratsche muss ANSCHLAGEN und SCHWEIGEN koennen")
    print("=" * 78)

    # Ohne Archiv gibt es kein Urteil, nicht "alles gut".
    a, n = pruefe(proj, nur_projekt=True)
    pruef("ohne Archiv -> kein Urteil", a, None)

    # Etwas archivieren.
    alt = schreib("archiv/alt.md",
                  "# Alt\n\n`MIND_NOTFALL_TOKENS` steht auf 940 000.\n")
    e = archiviere(proj, alt, "im Code entfallen")
    pruef("Marke erfasst", "MIND_NOTFALL_TOKENS" in (e or {}).get("marken", []), True)

    # ⛔ SCHWEIGEN: die Marke steht nur im Archiv, nicht im geladenen Bestand.
    schreib("CLAUDE.md", "# P\n\nNichts Besonderes hier.\n")
    a, n = pruefe(proj, nur_projekt=True)
    pruef("nur im Archiv -> still", len(a), 0)
    pruef("und es hat wirklich gesucht", n > 0, True)

    # ⭐ ANSCHLAGEN: die Marke kommt in einer GELADENEN Datei zurueck.
    schreib("CLAUDE.md", "# P\n\n`MIND_NOTFALL_TOKENS` steht auf 940 000.\n")
    a, _ = pruefe(proj, nur_projekt=True)
    pruef("Marke zurueck -> Wiederauferstehung", len(a) >= 1, True)
    if a:
        m, eintrag, wo = a[0]
        pruef("nennt die Marke", m, "MIND_NOTFALL_TOKENS")
        pruef("nennt den Grund von damals", eintrag.get("grund"), "im Code entfallen")
        pruef("nennt den Fundort", any("CLAUDE.md" in x for x in wo), True)

    # ⛔ Die Quelldatei selbst darf NICHT als Wiederauferstehung zaehlen —
    #    sonst schlaegt die Ratsche unmittelbar nach dem Archivieren an.
    schreib("CLAUDE.md", "# P\n\nNichts Besonderes.\n")
    a, _ = pruefe(proj, nur_projekt=True)
    pruef("Archivdatei selbst zaehlt nicht", len(a), 0)

    # Verlauf: eine Zeile je Lauf, kein Gate.
    z = verlauf_schreiben(proj)
    pruef("Verlauf hat Ablagen", "p:rules" in z["ablagen"], True)
    verlauf_schreiben(proj)
    with open(_vp(proj), encoding="utf-8") as fh:
        pruef("zwei Laeufe -> zwei Zeilen",
              len([x for x in fh if x.strip()]), 2)

    print("\n=== %d Abweichung(en) ===" % fehler)
    return 3 if fehler else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()

    def hol(f):
        return argv[argv.index(f) + 1] if f in argv and len(argv) > argv.index(f) + 1 else None

    projekt = hol("--projekt") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    if "--archiviere" in argv:
        datei = hol("--archiviere")
        grund = hol("--grund")
        if not datei or not grund:
            print("--archiviere braucht eine Datei UND --grund")
            print("⛔ Ohne Grund ist der spaetere Befund nicht lesbar: "
                  "'X ist zurueck' ohne 'warum es wegging' hilft niemandem.")
            return 2
        e = archiviere(projekt, datei, grund)
        if e is None:
            print("⛔ %s nicht lesbar." % datei)
            return 2
        print("  archiviert: %s — %d Marke(n) festgehalten"
              % (os.path.basename(datei), len(e["marken"])))
        return 0

    if "--verlauf" in argv:
        z = verlauf_schreiben(projekt)
        print("  %s" % z["ts"])
        for k, v in sorted(z["ablagen"].items()):
            print("    %-14s %3d Datei(en) %8d B" % (k, v["dateien"], v["bytes"]))
        print("\n  ⚠ Kein Gate. Ein Bestand DARF wachsen — neues Wissen ist kein Fehler.")
        return 0

    a, n = pruefe(projekt, nur_projekt=("--nur-projekt" in argv))
    if a is None:
        print("⛔ NICHT MESSBAR — kein Archiv unter %s" % _mp(projekt))
        print("   Das ist KEIN 'nichts auferstanden'. Es wurde nie etwas archiviert.")
        return 2
    print("=" * 78)
    print("  Ratsche — %d geladene Datei(en) durchsucht" % n)
    print("=" * 78)
    if not a:
        print("  Nichts auferstanden.")
        return 0
    print("  ⛔ %d WIEDERAUFERSTEHUNG(EN)\n" % len(a))
    for m, e, wo in a[:15]:
        print("  `%s`" % m)
        print("     archiviert am %s aus %s"
              % (e.get("ts", "?")[:10], os.path.basename(e.get("datei", "?"))))
        print("     Grund damals: %s" % e.get("grund", "?"))
        print("     steht wieder in: %s" % ", ".join(os.path.basename(x) for x in wo))
        print()
    print("  ⚠ Das ist NICHT automatisch ein Fehler. Vielleicht wurde damals zu")
    print("    Unrecht archiviert. Hier steht die Vorgeschichte, nicht das Urteil.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
