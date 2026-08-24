#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Bestandsaufnahme der globalen Regeln — Auftrag 6, Abschnitt 1.

Zaehlt MECHANISCH, was mechanisch zaehlbar ist: Belegsignale, datierte Vorfaelle,
Codebloecke, Alter der Datumsnennungen.

⛔ WAS DIESES WERKZEUG BEWUSST NICHT TUT: die Frage "gilt diese Datei ueberall
   oder nur fuer eine Maschine" beantworten. Das ist eine DATEI-Eigenschaft und
   braucht Urteil. Ein erster Anlauf versuchte es per Regex ueber Absaetze und
   fiel durch die eigene Kontrolle: `workstation-fernzugriff.md` handelt zu 100 %
   von EINER Maschine, aber nur 15 % seiner Absaetze nennen sie beim Namen -- die
   uebrigen sagen "die Maschine", "der Gast", "sie". Gemessen wurden also
   Namensnennungen, nicht Geltungsbereich.
   **Diese Einordnung steht deshalb im Bericht als Urteil ausgewiesen, nicht hier
   als Zahl.**

⚠ Auch die verbleibenden Zahlen zaehlen SIGNALE, nicht Bedeutung. Die Belegquote
   ist eine UNTERGRENZE: ein Absatz ohne Marker kann trotzdem Beleg sein.

KONTROLLE (muss bestehen, sonst Rueckgabe 3): ein SYNTHETISCHER Prueftext mit
   bekannter Antwort (4 Absaetze, 1 Beleg, 1 Vorfall, 1 Codeblock) plus eine
   Negativkontrolle mit unbeendetem Codezaun.
   ⛔ Eine fruehere Fassung kontrollierte an zwei benannten Dateien aus
      `~/.claude/rules` und verweigerte damit auf JEDEM anderen Ordner die
      Arbeit -- sie prueft den ORDNER statt das INSTRUMENT.

Aufruf: python Learnings/bestandsaufnahme.py [--ordner <pfad>]
"""
import os
import re
import sys
from datetime import date

sys.stdout.reconfigure(encoding="utf-8", newline="")

HEUTE = date(2026, 8, 21)

BELEG = re.compile(
    r"arXiv|DOI|ICSE|ICLR|NeurIPS|FSE 20|IFEval|SWE-bench|OWASP|"
    r"gemessen|Gemessen|belegt|Belegt|Beleg:|nachgewiesen|Messung|gegengeprueft|"
    r"gegengeprüft|Gegenprobe|Negativkontrolle|Positivkontrolle|reproduziert")

SCHADEN = re.compile(
    r"passiert|Schaden|gekostet|verloren|zerstoer|zerstör|kaputt|gescheitert|"
    r"Fehlalarm|Absturz|abgestuerzt|abgestürzt|Datenverlust|geloescht|gelöscht|"
    r"brach ab|scheiterte|Vorfall|teuerste|falsch war|Irrtum|widerlegt")

DATUM = re.compile(r"(\d{2})\.(\d{2})\.(20\d{2})")


def alter_tage(t):
    tage = []
    for tt, mm, jj in DATUM.findall(t):
        try:
            tage.append((HEUTE - date(int(jj), int(mm), int(tt))).days)
        except ValueError:
            pass
    return tage


def absaetze(t):
    """Bloecke zwischen Leerzeilen. Ein Codeblock bleibt EIN Block."""
    t = t.replace("\r\n", "\n")
    raus, puffer, im_code = [], [], False
    for z in t.split("\n"):
        if z.lstrip().startswith("```"):
            im_code = not im_code
            puffer.append(z)
            if not im_code:
                raus.append("\n".join(puffer))
                puffer = []
            continue
        if im_code:
            puffer.append(z)
            continue
        if z.strip() == "":
            if puffer:
                raus.append("\n".join(puffer))
                puffer = []
        else:
            puffer.append(z)
    if puffer:
        raus.append("\n".join(puffer))
    return [a for a in raus if a.strip()]


def messe(pfad):
    t = open(pfad, "rb").read().decode("utf-8", "replace")
    ab = absaetze(t)
    z = {"absaetze": len(ab), "bytes": len(t.encode("utf-8")),
         "beleg": 0, "vorfall": 0, "code": 0, "code_zeilen": 0, "rein": 0}
    for a in ab:
        if a.lstrip().startswith("```"):
            z["code"] += 1
            z["code_zeilen"] += len(a.split("\n"))
            continue
        b = bool(BELEG.search(a))
        v = bool(SCHADEN.search(a)) and bool(DATUM.search(a))
        if b:
            z["beleg"] += 1
        if v:
            z["vorfall"] += 1
        if not (b or v):
            z["rein"] += 1
    return z, alter_tage(t)


def _sammle(ordner):
    """Alle .md REKURSIV.

    ⛔ Bis v5.20.0 stand hier `os.listdir` — also FLACH, waehrend der Bericht
       "(REKURSIV gezaehlt)" behauptete und die Skill-Doku ausdruecklich sagt:
       *Wer den Umfang eines Regelbestands misst, misst rekursiv.*
       Der teuerste Einzelbefund dieses Werkzeugs hing genau daran: am
       23.08.2026 kamen **267 von 920** Ladevorgaengen aus einem `archive/`-
       Ordner, der angelegt worden war, UM den Bestand zu kuerzen. Eine flache
       Zaehlung haette ihn nie gesehen.
    """
    out = []
    for wurzel, _dirs, dateien in os.walk(ordner):
        for f in dateien:
            if f.endswith(".md"):
                out.append(os.path.join(wurzel, f))
    return out


def main():
    # ⛔ Bis v5.20.0 wurde ein POSITIONALES Argument STILL VERWORFEN.
    #    Die SKILL.md dokumentierte `bestandsaufnahme.py <verzeichnis>`; das
    #    Werkzeug las nur `--ordner`. Ein Projekt-Lauf meldete damit die
    #    GLOBALEN Zahlen — und das sah aus wie ein Befund ueber den Bestand.
    #    Aufgefallen im /mind-cleaner-Lauf vom 25.08.2026, und nur deshalb,
    #    weil Projekt- und Global-Zahlen byte-gleich waren.
    #    ⭐ Die Haertung ist nicht "positional geht jetzt auch", sondern:
    #       ein Argument, das nicht verstanden wird, BRICHT AB. Stilles
    #       Ignorieren laesst den naechsten Aufruf-Fehler wieder wie einen
    #       Befund ueber den Gegenstand aussehen.
    argv = sys.argv[1:]
    ordner = None
    if "--ordner" in argv:
        i = argv.index("--ordner")
        if i + 1 >= len(argv):
            print("--ordner braucht einen Pfad", file=sys.stderr)
            return 2
        ordner = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    unbekannt = [a for a in argv if a.startswith("-")]
    if unbekannt:
        print("Unbekanntes Argument: %s" % " ".join(unbekannt), file=sys.stderr)
        print("Aufruf: bestandsaufnahme.py [<verzeichnis> | --ordner <verzeichnis>]",
              file=sys.stderr)
        return 2
    rest = [a for a in argv if not a.startswith("-")]
    if len(rest) > 1:
        print("Mehr als ein Verzeichnis: %s" % " ".join(rest), file=sys.stderr)
        return 2
    if rest:
        if ordner is not None and os.path.abspath(rest[0]) != os.path.abspath(ordner):
            print("Widerspruch: --ordner %s gegen %s" % (ordner, rest[0]),
                  file=sys.stderr)
            return 2
        ordner = rest[0]
    if ordner is None:
        ordner = os.path.expanduser("~/.claude/rules")
    if not os.path.isdir(ordner):
        print("Kein Verzeichnis: %s" % ordner, file=sys.stderr)
        return 2

    pfade = sorted(_sammle(ordner), key=os.path.getsize, reverse=True)
    if not pfade:
        print("Keine .md-Dateien in %s" % ordner, file=sys.stderr)
        return 2

    # ⛔ Schluessel ist der RELATIVE Pfad, nicht der Dateiname. Seit die Suche
    #    rekursiv ist, koennen `archive/env-vars.md` und `env-vars.md`
    #    nebeneinander liegen — mit dem blossen Namen wuerde eine die andere
    #    ueberschreiben, und der Bestand saehe kleiner aus als er ist. Genau
    #    die Richtung des Fehlers, den die Rekursion beheben soll.
    werte, tage_je = {}, {}
    for p in pfade:
        k = os.path.relpath(p, ordner).replace("\\", "/")
        werte[k], tage_je[k] = messe(p)

    # ------------------------------------------------------------------
    # KONTROLLE am SYNTHETISCHEN Prueftext — unabhaengig vom Ordner.
    #
    # ⛔ Die erste Fassung kontrollierte an zwei benannten Dateien aus
    #    `~/.claude/rules`. Auf jeden anderen Ordner angewandt verweigerte das
    #    Werkzeug damit die Arbeit ("Datei fehlt") -- die Kontrolle pruefte den
    #    ORDNER statt das INSTRUMENT. Ein Prueftext mit bekannter Antwort prueft
    #    das Instrument und laeuft ueberall.
    # ------------------------------------------------------------------
    print("=" * 78)
    print("  KONTROLLE am Prueftext — ohne sie ist jede Zahl unten wertlos")
    print("=" * 78)
    fehler = 0

    PRUEFTEXT = (
        "Ein ganz normaler Absatz ohne jedes Signal.\n"
        "\n"
        "Hier steht das Wort gemessen, also ein Belegsignal.\n"
        "\n"
        "Am 01.01.2026 ist etwas kaputt gegangen — Datum plus Schadenswort.\n"
        "\n"
        "```bash\n"
        "echo eins\n"
        "echo zwei\n"
        "```\n")

    SOLL = {"absaetze": 4, "beleg": 1, "vorfall": 1, "code": 1,
            "code_zeilen": 4, "rein": 1}

    import tempfile
    with tempfile.NamedTemporaryFile("wb", suffix=".md", delete=False) as fh:
        fh.write(PRUEFTEXT.encode("utf-8"))
        pruefdatei = fh.name
    try:
        ist, _ = messe(pruefdatei)
    finally:
        os.unlink(pruefdatei)

    for schluessel, soll in SOLL.items():
        ok = ist[schluessel] == soll
        print("  %s %-14s erwartet %2d · gemessen %2d"
              % ("[ok ]" if ok else "[ROT]", schluessel, soll, ist[schluessel]))
        fehler += 0 if ok else 1

    # NEGATIVKONTROLLE: ein unbeendeter Codezaun darf keine zwei Bloecke ergeben
    # und nicht abstuerzen. Ohne diesen Fall waere ein kaputter Zerleger gruen.
    with tempfile.NamedTemporaryFile("wb", suffix=".md", delete=False) as fh:
        fh.write(b"Text davor.\n\n```bash\necho offen\n")
        kaputt = fh.name
    try:
        ist2, _ = messe(kaputt)
        ok = ist2["code"] <= 1
        print("  %s unbeendeter Codezaun ergibt hoechstens 1 Block (gemessen %d)"
              % ("[ok ]" if ok else "[ROT]", ist2["code"]))
        fehler += 0 if ok else 1
    except Exception as e:
        print("  [ROT] unbeendeter Codezaun stuerzt ab: %s" % e)
        fehler += 1
    finally:
        os.unlink(kaputt)

    if fehler:
        print("\n  ⛔ KONTROLLE GESCHEITERT — keine Zahl aus diesem Lauf verwenden.")
        return 3
    print("  alle Kontrollen bestanden\n")

    # ------------------------------------------------------------------
    print("=" * 78)
    print("  BESTANDSAUFNAHME  (%d Dateien in %s)" % (len(pfade), ordner))
    print("=" * 78)
    print("  %-32s %6s %5s | %5s %5s %5s %6s"
          % ("Datei", "kB", "Abs.", "Beleg", "Vorf.", "Code", "CodeZ."))
    print("  " + "-" * 74)

    g = dict.fromkeys(("absaetze", "beleg", "vorfall", "code", "code_zeilen", "rein", "bytes"), 0)
    for p in pfade:
        n = os.path.basename(p)
        z = werte[n]
        for s in g:
            g[s] += z[s]
        print("  %-32s %6.1f %5d | %5d %5d %5d %6d"
              % (n[:32], z["bytes"] / 1000, z["absaetze"], z["beleg"],
                 z["vorfall"], z["code"], z["code_zeilen"]))

    print("  " + "-" * 74)
    print("  %-32s %6.1f %5d | %5d %5d %5d %6d"
          % ("GESAMT", g["bytes"] / 1000, g["absaetze"], g["beleg"],
             g["vorfall"], g["code"], g["code_zeilen"]))

    a = max(1, g["absaetze"])
    print()
    print("  Anteile an %d Absaetzen:" % g["absaetze"])
    print("    mit Beleg-/Messsignal          %5.1f %%   (%d)" % (g["beleg"] / a * 100, g["beleg"]))
    print("    datierter Vorfall              %5.1f %%   (%d)" % (g["vorfall"] / a * 100, g["vorfall"]))
    print("    Codeblock                      %5.1f %%   (%d)" % (g["code"] / a * 100, g["code"]))
    print("    ohne beides (reine Anweisung)  %5.1f %%   (%d)" % (g["rein"] / a * 100, g["rein"]))

    alle = [t for ts in tage_je.values() for t in ts]
    if alle:
        print()
        print("  Datumsnennungen gesamt: %d" % len(alle))
        for grenze in (14, 30, 60, 90):
            n = sum(1 for t in alle if t > grenze)
            print("    aelter als %2d Tage             %5.1f %%   (%d)"
                  % (grenze, n / len(alle) * 100, n))
        print("    aeltestes                      %d Tage" % max(alle))

    print()
    print("  ⚠ Gezaehlt werden SIGNALE, nicht Bedeutung. Die Belegquote ist eine")
    print("    UNTERGRENZE. Der Geltungsbereich je Datei steht bewusst NICHT hier —")
    print("    er braucht Urteil und gehoert als solches in den Bericht.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
