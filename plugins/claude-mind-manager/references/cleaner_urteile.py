#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Das Urteilsbuch — was einmal entschieden wurde, bleibt entschieden.

⛔ WARUM ES DAS GIBT

Nutzer-Entscheidung 24.08.2026: **beide** Werkzeuge duerfen aufraeumen —
`/mind-cleaner` (dreistufig, mit Rueckfrage) UND `/mind-claudemd` (autonom bei
jedem `/mind-all`). Damit ist ein gemeinsamer Zustand keine Kuer mehr, sondern
die Bedingung dafuer, dass die Entscheidung ueberhaupt traegt.

⭐ **Der Fall, der ohne das Buch passiert — und zwar zwangslaeufig:**

    1. `/mind-cleaner` sieht: globale CLAUDE.md fasst eine Regel zusammen UND
       nennt ihren Pfad. Das ist die ZIELFORM (kuerzere Fassung + Zeiger).
       Urteil: nichts tun.
    2. Beim naechsten `/mind-all` sieht `/mind-claudemd` zwei Stellen mit
       demselben Inhalt, haelt es fuer ein Duplikat und entfernt eine —
       AUTONOM, ohne Rueckfrage.
    3. Beim uebernaechsten Lauf fehlt der Kurz-Regel ihr Inhalt, und niemand
       weiss, warum.

Das Buch bricht diesen Kreis: ein Paar mit Urteil `zielform` wird nicht erneut
gemeldet, und ein autonomes Werkzeug darf ein `zielform` NIE aufheben.

## Die fuenf Urteile

    duplikat      zwei Stellen behaupten dasselbe vollstaendig  -> eine wird Zeiger
    zielform      kuerzere Fassung PLUS Pfad                    -> nichts tun
    zeiger        nennt die andere, wiederholt nichts           -> nichts tun
    zahlendrift   eine Kopie aktualisiert, andere vergessen     -> melden
    widerspruch   beide sagen Verschiedenes                     -> melden, nie selbst loesen

## ⚠ Ein Urteil ist eine ENTSCHEIDUNG, kein Messwert

Aendert sich der Inhalt an einer der beiden Stellen wesentlich, ist das alte
Urteil hinfaellig. Deshalb speichert jeder Eintrag einen **Hash beider Stellen**.
Weicht er ab, gilt das Paar als NEU ZU BEURTEILEN.

⛔ Ohne diesen Hash wuerde ein einmal gefaelltes Urteil eine Datei **einfrieren** —
und das Buch waere kein Gedaechtnis, sondern eine Fessel.

Aufruf:
  python cleaner_urteile.py --lesen   <projekt>
  python cleaner_urteile.py --pruefen <projekt> --orte A B
  python cleaner_urteile.py --schreiben <projekt> --orte A B --urteil zielform \
                            --werkzeug mind-cleaner --von mensch --grund "..."
  python cleaner_urteile.py --selbsttest

Rueckgabe beim Pruefen: 0 = bekannt und gueltig · 1 = unbekannt oder veraltet
"""
import hashlib
import json
import os
import sys
import time

# ⛔ `newline=""` ist PFLICHT auf Windows. Ohne diesen Zusatz uebersetzt
#    TextIOWrapper jeden Zeilenumbruch in die Windows-Fassung (CR + LF).
#    Jede zeilenverankerte Zusicherung (das Dollarzeichen in grep) bricht
#    dann — und zwar STILL, denn die Ausgabe sieht voellig richtig aus.
#    Gemessen 24.08.2026 an `cleaner_duplikate.py`: zwei Prueffaelle meldeten
#    0 Treffer fuer Zeilen, die dastanden. Dieselbe Klasse wie der in der
#    globalen CLAUDE.md dokumentierte `write_text()`-Fall.
sys.stdout.reconfigure(encoding="utf-8", newline="")

URTEILE = ("duplikat", "zielform", "zeiger", "zahlendrift", "widerspruch")

# ⛔ Ein autonomes Werkzeug darf diese Urteile NICHT aufheben. `duplikat` darf es
#    anwenden — das ist eine Aufraeumung. `zielform`/`zeiger` sind dagegen
#    ENTSCHEIDUNGEN gegen eine Aufraeumung, und die aufzuheben hiesse, die
#    Entscheidung eines Menschen ohne Rueckfrage umzukehren.
GESCHUETZT = ("zielform", "zeiger")


def buchpfad(projekt):
    return os.path.join(projekt, ".claude-mind", "urteile.jsonl")


def _hash_ort(ort):
    """Hash des INHALTS an einem Ort. Ort ist ein Pfad, optional mit #Abschnitt.

    ⚠ Fehlt die Datei, ist der Hash `None` — NICHT der Hash des leeren Strings.
      Sonst waeren zwei geloeschte Dateien 'unveraendert gleich'.
    """
    pfad = ort.split("#", 1)[0]
    pfad = os.path.expanduser(pfad)
    if not os.path.isfile(pfad):
        return None
    with open(pfad, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()[:16]


def _schluessel(orte):
    """Reihenfolgeunabhaengig — A|B und B|A sind dasselbe Paar."""
    return "|".join(sorted(o.replace("\\", "/") for o in orte))


def lesen(projekt):
    p = buchpfad(projekt)
    if not os.path.isfile(p):
        return []
    eintraege = []
    with open(p, encoding="utf-8", errors="replace") as fh:
        for z in fh:
            z = z.strip()
            if not z:
                continue
            try:
                eintraege.append(json.loads(z))
            except ValueError:
                # ⛔ Eine kaputte Zeile darf das ganze Buch nicht unlesbar machen —
                #    sonst faellt bei einem einzigen Schreibfehler der gesamte
                #    Schutz aus, und zwar STILL.
                eintraege.append({"__kaputt__": z[:120]})
    return eintraege


def schreiben(projekt, orte, urteil, werkzeug, von="mensch", grund=""):
    if urteil not in URTEILE:
        raise ValueError("unbekanntes Urteil: %s (erlaubt: %s)"
                         % (urteil, ", ".join(URTEILE)))
    p = buchpfad(projekt)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    e = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "werkzeug": werkzeug,
        "orte": list(orte),
        "schluessel": _schluessel(orte),
        "urteil": urteil,
        "entschieden_von": von,
        "grund": grund,
        "hashes": {o: _hash_ort(o) for o in orte},
    }
    with open(p, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(e, ensure_ascii=True) + "\n")
    return e


def pruefen(projekt, orte):
    """Was sagt das Buch zu diesem Paar?

    Rueckgabe: (zustand, eintrag)
      "unbekannt"   noch nie beurteilt          -> beurteilen
      "gueltig"     beurteilt, Inhalt unveraendert -> Urteil gilt
      "veraltet"    beurteilt, Inhalt geaendert -> NEU beurteilen
    """
    s = _schluessel(orte)
    treffer = [e for e in lesen(projekt)
               if not e.get("__kaputt__") and e.get("schluessel") == s]
    if not treffer:
        return "unbekannt", None
    letzter = treffer[-1]          # das juengste Urteil gilt
    jetzt = {o: _hash_ort(o) for o in orte}
    damals = letzter.get("hashes") or {}
    for o in orte:
        if damals.get(o) != jetzt.get(o):
            return "veraltet", letzter
    return "gueltig", letzter


def darf_anwenden(zustand, eintrag, autonom):
    """⛔ DER VERTRAG. Darf ein Werkzeug hier jetzt etwas aendern?

    Ein autonomes Werkzeug darf `duplikat` anwenden — das ist Aufraeumen.
    Es darf `zielform`/`zeiger` NICHT aufheben — das waere die Umkehrung einer
    menschlichen Entscheidung ohne Rueckfrage.
    """
    if zustand != "gueltig" or not eintrag:
        return True, "kein gueltiges Urteil im Buch"
    u = eintrag.get("urteil")
    if autonom and u in GESCHUETZT:
        return False, ("Buch sagt '%s' (%s, %s) — ein autonomes Werkzeug hebt das "
                       "nicht auf" % (u, eintrag.get("entschieden_von", "?"),
                                      eintrag.get("ts", "?")[:10]))
    if u in GESCHUETZT:
        return False, "Buch sagt '%s' — nichts zu tun" % u
    return True, "Buch sagt '%s'" % u


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
        print("    %-4s %-48s ist=%-11s soll=%s"
              % ("OK" if ok else "FEHL", name, ist, soll))

    a = os.path.join(d, "a.md")
    b = os.path.join(d, "b.md")
    open(a, "w", encoding="utf-8", newline="\n").write("# A\nEins\n")
    open(b, "w", encoding="utf-8", newline="\n").write("# B\nZwei\n")

    print("=" * 78)
    print("  Selbsttest — das Buch muss UNTERSCHEIDEN und BREMSEN koennen")
    print("=" * 78)

    z, e = pruefen(d, [a, b])
    pruef("unbeurteiltes Paar", z, "unbekannt")

    schreiben(d, [a, b], "zielform", "mind-cleaner", "mensch", "Verdichtung + Zeiger")
    z, e = pruefen(d, [a, b])
    pruef("nach dem Eintrag", z, "gueltig")
    pruef("Urteil kommt zurueck", e["urteil"], "zielform")

    # ⭐ DER FALL, WEGEN DEM ES DAS BUCH GIBT
    darf, grund = darf_anwenden(z, e, autonom=True)
    pruef("autonom darf zielform NICHT aufheben", darf, False)
    darf2, _ = darf_anwenden(z, e, autonom=False)
    pruef("auch nicht-autonom: nichts zu tun", darf2, False)

    # Gegenrichtung: `duplikat` DARF ein autonomes Werkzeug anwenden.
    c = os.path.join(d, "c.md")
    open(c, "w", encoding="utf-8", newline="\n").write("# C\n")
    schreiben(d, [a, c], "duplikat", "mind-claudemd", "autonom", "gleiche Aussage")
    z2, e2 = pruefen(d, [a, c])
    darf3, _ = darf_anwenden(z2, e2, autonom=True)
    pruef("autonom DARF duplikat anwenden", darf3, True)

    # ⛔ Ohne diesen Fall waere das Buch eine Fessel: geaenderter Inhalt
    #    muss das alte Urteil hinfaellig machen.
    open(b, "a", encoding="utf-8", newline="\n").write("Drei\nVier\n")
    z3, _ = pruefen(d, [a, b])
    pruef("Inhalt geaendert -> Urteil veraltet", z3, "veraltet")

    # Reihenfolge darf keine Rolle spielen.
    pruef("A|B und B|A sind dasselbe Paar",
          _schluessel([a, b]) == _schluessel([b, a]), True)

    # Fehlende Datei: Hash None, nicht Hash von "".
    fehlt = os.path.join(d, "gibtsnicht.md")
    pruef("fehlende Datei -> Hash None", _hash_ort(fehlt), None)

    # ⛔ Eine kaputte Zeile darf nicht das ganze Buch stilllegen.
    with open(buchpfad(d), "a", encoding="utf-8", newline="\n") as fh:
        fh.write("{kein json\n")
    z4, _ = pruefen(d, [a, c])
    pruef("kaputte Zeile: Buch bleibt lesbar", z4, "gueltig")

    # Unbekanntes Urteil muss abgelehnt werden.
    try:
        schreiben(d, [a, b], "irgendwas", "test")
        pruef("unbekanntes Urteil abgelehnt", False, True)
    except ValueError:
        pruef("unbekanntes Urteil abgelehnt", True, True)

    print("\n=== %d Abweichung(en) ===" % fehler)
    return 3 if fehler else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()

    def hol(flag, n=1):
        if flag not in argv:
            return None
        i = argv.index(flag) + 1
        werte = []
        while i < len(argv) and not argv[i].startswith("--"):
            werte.append(argv[i])
            i += 1
        return werte if n > 1 else (werte[0] if werte else None)

    projekt = next((a for a in argv if not a.startswith("--")), None)
    if not projekt:
        print(__doc__.split("Aufruf:")[1])
        return 2

    if "--lesen" in argv:
        for e in lesen(projekt):
            if e.get("__kaputt__"):
                print("  ⛔ KAPUTTE ZEILE: %s" % e["__kaputt__"])
                continue
            print("  %s  %-12s %-11s %s"
                  % (e.get("ts", "?")[:16], e.get("urteil", "?"),
                     e.get("entschieden_von", "?"), e.get("schluessel", "?")[:60]))
        return 0

    orte = hol("--orte", 2) or []
    if len(orte) < 2:
        print("--orte braucht zwei Pfade")
        return 2

    if "--schreiben" in argv:
        e = schreiben(projekt, orte, hol("--urteil"), hol("--werkzeug") or "?",
                      hol("--von") or "mensch", hol("--grund") or "")
        print("  eingetragen: %s" % e["urteil"])
        return 0

    zustand, e = pruefen(projekt, orte)
    print("  Zustand: %s" % zustand)
    if e:
        print("  Urteil:  %s (%s, %s)" % (e.get("urteil"), e.get("entschieden_von"),
                                          e.get("ts", "")[:16]))
        print("  Grund:   %s" % e.get("grund", ""))
        for autonom in (True, False):
            darf, grund = darf_anwenden(zustand, e, autonom)
            print("  %-14s %s — %s" % ("autonom:" if autonom else "mit Rueckfrage:",
                                       "DARF" if darf else "DARF NICHT", grund))
    return 0 if zustand == "gueltig" else 1


if __name__ == "__main__":
    sys.exit(main())
