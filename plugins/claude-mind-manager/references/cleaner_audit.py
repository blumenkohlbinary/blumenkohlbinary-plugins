#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Der Audit-Lauf — fuehrt alle Cleaner-Werkzeuge zu EINEM Bericht zusammen.

⛔ DIE REIHENFOLGE IM BERICHT IST ABSICHT

Gruppe 5 ("nicht entscheidbar") steht ZUERST, nicht zuletzt. Sie ist das
ehrliche Mass dafuer, wie viel dieses Audit wirklich wusste — ein Bericht, der
sie ans Ende schiebt, suggeriert eine Sicherheit, die er nicht hat.

## Und Gruppe 5 zerfaellt in ZWEI

    5a  kein Verstoss vorliegend                 -> vielleicht messbar, spaeter
    5b  diese Regelklasse ist NICHT LOGGBAR      -> grundsaetzlich unmessbar

⭐ **5b ist der Kern, nicht der Rest.** Urteils- und Prozessregeln
(`keine-annahmen`, `plan-mode`, `ursache-vor-reparatur`, `autonom-arbeiten`)
erzeugen kaum je einen maschinell erfassbaren Verstoss. Sie landen dort **nicht
weil sie unbeobachtet blieben, sondern weil sie unbeobachtBAR sind.**

Ein Leser, dem das nicht gesagt wird, haelt Gruppe 5 fuer eine Restmenge.

## ⛔ Dieser Lauf AENDERT NICHTS

Er ist Stufe 1 von drei: Bericht -> dein OK -> Plan -> dein OK -> anwenden.

Aufruf:
  python cleaner_audit.py [--bereich <projekt>] [--nur global|projekt|alles]
  python cleaner_audit.py --selbsttest

Rueckgabe: 0 = gelaufen · 1 = Befunde vorhanden · 2 = nicht messbar
"""
import os
import sys

_HIER = os.path.dirname(os.path.abspath(__file__))
if _HIER not in sys.path:
    sys.path.insert(0, _HIER)

# ⛔ NICHT nachbauen — jedes dieser Werkzeuge traegt seine eigene Gegenprobe.
#    Ein zweites Instrument daneben hiesse, dass sich ab jetzt zwei Messungen
#    widersprechen koennen.
import cleaner_duplikate as dup                                  # noqa: E402
import cleaner_einordnung as ein                                 # noqa: E402
import cleaner_belege as bel                                     # noqa: E402
import cleaner_aussagen as aus                                   # noqa: E402
import cleaner_grenzen as gre                                    # noqa: E402
import cleaner_urteile as urt                                    # noqa: E402

# ⛔ ERST importieren, DANN reconfigure — nie einen zweiten TextIOWrapper.
sys.stdout.reconfigure(encoding="utf-8", newline="")

# Regeln, deren Verstoesse strukturell nicht loggbar sind (Gruppe 5b).
# ⚠ Das ist eine ENTSCHEIDUNG, keine Messung. Sie steht hier sichtbar, damit
#   sie bestreitbar ist.
NICHT_LOGGBAR = ("keine-annahmen", "plan-mode", "ursache-vor-reparatur",
                 "autonom-arbeiten", "fertig-heisst-fertig", "messung-vor-glauben")


def dateien(projekt, nur="alles"):
    H = os.path.expanduser("~")
    out = []
    wurzeln = []
    if nur in ("alles", "global"):
        wurzeln.append(os.path.join(H, ".claude", "rules"))
    if nur in ("alles", "projekt"):
        wurzeln.append(os.path.join(projekt, ".claude", "rules"))
    for w in wurzeln:
        for wurzel, _, fs in os.walk(w):
            out += [os.path.join(wurzel, f) for f in sorted(fs) if f.endswith(".md")]
    return out


def lauf(projekt, nur="alles"):
    ds = dateien(projekt, nur)
    if not ds:
        print("⛔ Keine Regeldatei gefunden. Eher ein falscher Pfad als ein leerer Bestand.")
        return 2

    idx = bel.debug_pfad(projekt)
    gruppen = {"5a": [], "5b": [], "1": [], "2": [], "3": [], "4": []}
    grenzfaelle, blind = [], []

    for p in ds:
        name = os.path.splitext(os.path.basename(p))[0]
        u, grund, z = bel.urteile(p, idx)
        e = ein.mit_skill(p)
        vorschlag = (e or {}).get("vorschlag_zusammen") or (e or {}).get("vorschlag", "?")

        if u == "BELEGT NOETIG":
            gruppen["1"].append((p, grund))
        elif u == "VERALTUNGS-KANDIDAT":
            gruppen["4"].append((p, grund))
        elif u == "SCHWACHER KANDIDAT":
            gruppen["4"].append((p, grund + " (schwach)"))
        elif name in NICHT_LOGGBAR:
            gruppen["5b"].append((p, "Urteils-/Prozessregel — Verstoesse sind mit dem "
                                     "vorhandenen Instrumentarium NICHT loggbar"))
        else:
            gruppen["5a"].append((p, grund))

        # Falsch platziert?
        if vorschlag in ("HOOK-KANDIDAT", "SKILL") and e:
            gruppen["2"].append((p, "%s — %s" % (vorschlag,
                                                 e.get("grund_zusammen") or e.get("grund", ""))))
        # Lint Leakage
        verd, hook, wieso = ein.lint_leakage(p, projekt)
        if verd:
            gruppen["2"].append((p, "LINT LEAKAGE: %s" % wieso))

        # Grenzen
        b, _ = gre.pruefe(p)
        for schwere, gname, txt in (b or []):
            if schwere == "BRUCH":
                grenzfaelle.append((p, gname, txt))

        # Blinde Verweise
        a = aus.lauf(p)
        if a and a["blind"]:
            blind.append((p, len(a["blind"])))

    # Duplikate
    abl = dup.ablagen(projekt, "alles" if nur == "alles" else nur)
    text, wo = {}, {}
    import collections
    wo = collections.defaultdict(set)
    for nname, pfade in abl.items():
        for p in pfade:
            t = dup._inhalt(p)
            text[p] = t
            for m in dup.marken(t):
                wo[m].add((nname, p))
    for m, stellen in wo.items():
        st = sorted(stellen)
        if len({n for n, _ in st}) < 2:
            continue
        for i in range(len(st)):
            for j in range(i + 1, len(st)):
                (na, pa), (nb, pb) = st[i], st[j]
                if na == nb:
                    continue
                kat, g = dup.einordnen(m, pa, text[pa], pb, text[pb])
                zustand, eintrag = urt.pruefen(projekt, [pa, pb])
                if zustand == "gueltig" and eintrag.get("urteil") in urt.GESCHUETZT:
                    continue          # ⛔ Das Buch hat entschieden.
                if kat == "duplikat":
                    gruppen["3"].append((m, "%s + %s" % (na, nb)))
                elif kat == "zahlendrift":
                    gruppen["3"].append((m, "⛔ ZAHLENDRIFT: %s + %s — %s" % (na, nb, g)))

    # --- Bericht ----------------------------------------------------------
    print("=" * 88)
    print("  /mind-cleaner --audit   ·   %d Regeldatei(en)   ·   Bereich: %s"
          % (len(ds), nur))
    print("=" * 88)
    print("  ⛔ Dieser Lauf AENDERT NICHTS. Stufe 1 von drei.")
    print()

    # ⛔ Gruppe 5 ZUERST.
    print("  " + "=" * 84)
    print("  5 · NICHT ENTSCHEIDBAR — %d Datei(en)"
          % (len(gruppen["5a"]) + len(gruppen["5b"])))
    print("  " + "=" * 84)
    print("     Steht oben, weil es das ehrliche Mass dafuer ist, wie viel dieses")
    print("     Audit wirklich wusste. Eine nie gebrochene Regel kann ueberfluessig")
    print("     sein — oder GENAU DESHALB nie gebrochen worden sein, WEIL sie da ist.")
    print()
    print("  5a · kein Verstoss vorliegend (%d) — vielleicht spaeter messbar"
          % len(gruppen["5a"]))
    for p, g in gruppen["5a"]:
        print("       %-32s %s" % (os.path.basename(p)[:32], g[:44]))
    print()
    print("  5b · ⭐ GRUNDSAETZLICH NICHT LOGGBAR (%d) — der Kern, nicht der Rest"
          % len(gruppen["5b"]))
    for p, g in gruppen["5b"]:
        print("       %-32s %s" % (os.path.basename(p)[:32], g[:44]))
    if gruppen["5b"]:
        print()
        print("       Diese landen hier NICHT weil sie unbeobachtet blieben, sondern")
        print("       weil sie unbeobachtBAR sind. Wer 5b fuer eine Restmenge haelt,")
        print("       liest den Bericht falsch.")

    for nr, titel in (("1", "BELEGT NOETIG — bleibt, wo es ist"),
                      ("2", "FALSCH PLATZIERT — Ort A nach Ort B"),
                      ("3", "DOPPELT — eine Stelle wird Zeiger"),
                      ("4", "BELEGT VERALTET — ins Archiv, mit Beleg")):
        print()
        print("  %s · %s (%d)" % (nr, titel, len(gruppen[nr])))
        for a, b in gruppen[nr][:12]:
            print("       %-32s %s" % (os.path.basename(str(a))[:32], str(b)[:48]))

    if grenzfaelle:
        print()
        print("  ⛔ STILLE KAPPUNGEN — %d (hier verschwindet Inhalt OHNE Meldung)"
              % len(grenzfaelle))
        for p, gname, txt in grenzfaelle[:8]:
            print("       %-28s %-20s %s" % (os.path.basename(p)[:28], gname, txt[:34]))

    if blind:
        print()
        print("  ⚠ BLINDE VERWEISE — %d Datei(en) nennen eine Datei ohne zu sagen wozu"
              % len(blind))
        for p, n in blind[:8]:
            print("       %-32s %d Stelle(n)" % (os.path.basename(p)[:32], n))

    print()
    print("  " + "=" * 84)
    print("  NICHT GEPRUEFT — und das gehoert in jeden Bericht")
    print("  " + "=" * 84)
    print("     · ob eine nie verletzte Urteils-Regel ueberfluessig ist (dauerhaft offen)")
    print("     · welche Seite eines Widerspruchs recht hat")
    print("     · ob der Code dasselbe sagt wie die Regel (er sagt WAS, sie oft WARUM)")
    print("     · ob eine Regel FEHLT — ein Audit sieht nur, was da ist")
    if idx is None:
        print("     · ⛔ KEIN Verstoss-Protokoll erreichbar — alle Belege sind leer,")
        print("          und das ist KEIN 'nichts gefunden'")
    print()
    print("  Naechster Schritt: --plan (erst nach deinem OK).")
    befunde = sum(len(gruppen[k]) for k in ("2", "3", "4")) + len(grenzfaelle)
    return 1 if befunde else 0


def selbsttest():
    import tempfile
    d = tempfile.mkdtemp()
    fehler = 0

    def pruef(name, ist, soll):
        nonlocal fehler
        ok = ist == soll
        if not ok:
            fehler += 1
        print("    %-4s %-48s ist=%-9s soll=%s"
              % ("OK" if ok else "FEHL", name, ist, soll))

    print("=" * 78)
    print("  Selbsttest — der Audit-Lauf")
    print("=" * 78)

    proj = os.path.join(d, "leer")
    os.makedirs(proj)
    pruef("leerer Bestand -> Rueckgabe 2 (nicht messbar)",
          lauf(proj, "projekt"), 2)

    # ⛔ Die Gegenprobe: alle sechs Werkzeuge muessen erreichbar sein.
    #    Ein Audit, das eines nicht laden kann, meldet stillschweigend weniger.
    for m in (dup, ein, bel, aus, gre, urt):
        pruef("Werkzeug erreichbar: %s" % m.__name__.replace("cleaner_", ""),
              hasattr(m, "__file__"), True)

    print("\n=== %d Abweichung(en) ===" % fehler)
    return 3 if fehler else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()

    def hol(f):
        return argv[argv.index(f) + 1] if f in argv and len(argv) > argv.index(f) + 1 else None

    projekt = hol("--bereich") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    nur = hol("--nur") or "alles"
    if nur not in ("global", "projekt", "alles"):
        print("--nur braucht global|projekt|alles")
        return 2
    return lauf(projekt, nur)


if __name__ == "__main__":
    sys.exit(main())
