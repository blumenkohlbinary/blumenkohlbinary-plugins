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
import cleaner_urteile as urt                                 # noqa: E402
import cleaner_tor as tor
# L6 (v5.21.0): die Referenz-Existenzpruefung. ⛔ NICHT nachbauen — diese Kette
# traegt die Narben von DREI gescheiterten Nachbauten (20.08.2026: 11
# Slash-Commands als tote Pfade · 21.08.: 9 gemeldet, echte 0 · ein dritter
# Anlauf mit demselben Wurzel-Fehler).
import claudemd_pipeline as pipe                                 # noqa: E402

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
    gruppen = {"5a": [], "5b": [], "1": [], "2": [], "3": [], "4": [],
               "6": []}
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

        # ⛔ KONTEXT-TOR (v5.26.0) — die RUECKWAERTS-Richtung.
        #    Die fuenf Commands fragen VOR dem ADD; hier wird der ganze
        #    Bestand gefragt. Nur vorwaerts liesse den Altbestand stehen.
        try:
            _txt = open(p, encoding="utf-8", errors="replace").read()
            _tr = tor.pruefe_text(_txt)
        except OSError:
            _tr = {}
        for _k in ("A1", "A2", "A3", "C1"):
            if _tr.get(_k):
                gruppen["6"].append(
                    (p, "%s x%d — %s" % (_k, len(_tr[_k]),
                                         _tr[_k][0][1][:40])))

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
                      ("4", "BELEGT VERALTET — ins Archiv, mit Beleg"),
                      ("6", "KONTEXT-TOR — kostet Kontext ohne Gegenwert")):
        print()
        print("  %s · %s (%d)" % (nr, titel, len(gruppen[nr])))
        for a, b in gruppen[nr][:12]:
            print("       %-32s %s" % (os.path.basename(str(a))[:32], str(b)[:48]))

    if gruppen["6"]:
        print()
        print("       ⚠ A1 (weiss das Modell es?) und C2 (befolgbar?) sind")
        print("         URTEILE, keine Messungen — Kandidaten, kein Befund.")
        print("         Vorschrift: references/kontext-tor.md")

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

    # ======================================================================
    # L6 · TOTE VERWEISE (NEU v5.21.0)
    # ======================================================================
    # ⭐ Die EINZIGE Stelle, an der ohne Verstossdaten "veraltet" geurteilt
    #    werden darf: der genannte Gegenstand existiert nicht mehr. Das ist
    #    eine Existenzpruefung, keine Verhaltensfrage.
    # ⚠ `pfade` mischt Listen und Zaehler — am Code nachgesehen, nicht geraten:
    #   dead/extern sind LISTEN, skip/unsure/befehle sind ZAHLEN. Die erste
    #   Fassung dieses Blocks iterierte ueber `unsure` und brach mit
    #   "'int' object is not iterable" ab.
    tot, extern, unlesbar = [], [], []
    unsure = 0
    for p in ds:
        try:
            erg = pipe.pruefe(p, projekt)
        except Exception as e:                       # noqa: BLE001
            unlesbar.append((p, str(e)[:60]))
            continue
        pf = erg.get("pfade") or {}
        # ⛔ EIN GLOBALER PFAD IST VON HIER AUS NICHT ENTSCHEIDBAR.
        #    Eine Regel in `~/.claude/rules/` nennt Pfade relativ zur
        #    ARBEITSWURZEL des Nutzers, nicht relativ zu diesem Projekt.
        #    GEMESSEN 25.08.2026: der erste Lauf meldete 22 tote Pfade — und
        #    `_claude_backups/_auto`, `_claude_tools/hooks/sicherung.py` und
        #    `_claude_vm/sichtpruef.py` existieren alle, nur eben unter
        #    `C:\CD\KOHLEKTIV`. **Alle 22 stammten aus globalen Regeln.**
        #    Sie als tot zu melden hiesse, gueltige Verweise zum Loeschen
        #    vorzuschlagen — genau der Fehler, den `classify_path` dreimal
        #    gemacht hat, bevor er portiert wurde.
        global_regel = os.path.abspath(p).startswith(
            os.path.abspath(os.path.join(os.path.expanduser("~"), ".claude")))
        if global_regel:
            unsure += len(pf.get("dead") or []) + len(pf.get("extern") or [])
        else:
            tot += [(p, x) for x in (pf.get("dead") or [])]
            extern += [(p, x) for x in (pf.get("extern") or [])]
        # ⛔ UNSURE ist die DRITTE Klasse und wird NIE geurteilt, nur gezaehlt.
        #    Ein Pfad, den das Instrument nicht einordnen kann, ist nicht tot —
        #    er ist UNGEMESSEN. Wer beides gleichsetzt, loescht gueltige Verweise.
        unsure += int(pf.get("unsure") or 0)

    print()
    print("  ⚠ REFERENZ-EXISTENZ [EXPERIMENTELL] — %d fraglich · %d extern · %d ungemessen"
          % (len(tot), len(extern), unsure))
    print("     ⛔ NICHT ALS BEFUNDLISTE AUSGEGEBEN, und das ist Absicht.")
    print("        Gemessen 25.08.2026 am eigenen Bestand: von 11 Meldungen war")
    print("        KEINE EINZIGE ein echter toter Pfad. Darunter `\\|` (maskierte")
    print("        Tabellen-Pipe), `hooks/lib.sh:104-106` (Zitat mit Zeilennummer),")
    print("        `rmdir /s /q` und `2>/dev/null` (Shell-Fragmente).")
    print("        `classify_path` ist fuer CLAUDE.md gebaut, nicht fuer Regeldateien")
    print("        voller Code-Zitate. Eine Liste, die zu 100 Prozent Fehlalarm ist, waere")
    print("        schaedlicher als keine — sie schluege vor, gueltige Verweise zu")
    print("        loeschen. Der Weg steht in werkzeuge-zuerst.md: den Fall als")
    print("        Prueffall ZUM ORIGINAL geben und das Original erweitern.")
    for p, was in unlesbar:
        # ⛔ Ein unlesbarer Lauf ist NICHT MESSBAR, nicht "sauber" — der wird gemeldet.
        print("       %-30s ⛔ NICHT MESSBAR: %s" % (os.path.basename(p)[:30], was))

    # ---------------------------------------------------------------- L5
    # ⛔ Diese Pruefung sieht KEINE andere: `ablagen()` vergleicht Ablagen
    #    GEGENEINANDER. Eine Datei, die dieselbe Sache viermal sagt, ist dort
    #    unauffaellig — sie ist ja nur EINE Ablage.
    # ⚠ Steht bewusst ganz am ENDE. tests/test_audit.sh haengt an der
    #    Reihenfolge (Gruppe 5 vor Gruppe 1) und an einem sed-Bereich von
    #    "5b ·" bis "1 ·"; ein Abschnitt dazwischen braeche beides.
    wdh = []
    for p in ds:
        try:
            wdh.extend(dup.wiederholung_in_datei(p))
        except (OSError, ValueError):
            continue
    if wdh:
        print()
        print("  " + "=" * 84)
        print("  WIEDERHOLUNG INNERHALB EINER DATEI — Vorschlag: SCHNITT (%d)" % len(wdh))
        print("  " + "=" * 84)
        print("     ⚠ KEIN Fehler und NICHT in der Befundzahl. Eine Datei mit")
        print("       Versionsabschnitten SOLL dieselbe Sache mehrfach nennen —")
        print("       jede Nennung gehoert zu ihrer Version. Was fehlt, ist die")
        print("       Trennung zwischen 'gilt heute' und 'galt damals'.")
        print("       ⛔ Wer hier dedupliziert, loescht Historie.")
        for b in wdh[:10]:
            print("     %-28s %dx, Zeilen %s"
                  % (os.path.basename(b["datei"])[:28], b["anzahl"],
                     ", ".join(str(z) for z in b["zeilen"])))
            print("       Kern: %s" % ", ".join(b["geteilt"][:6]))
            if b["nimmt_zurueck"]:
                print("       ⭐ eine der Stellen nimmt eine andere ausdruecklich")
                print("          zurueck — genau das verdient einen Schnitt")
        if len(wdh) > 10:
            print("     ... und %d weitere (nicht gelistet)" % (len(wdh) - 10))
        print("     ⚠ GRENZE: gefunden werden Wiederholungen BENANNTER Dinge")
        print("       (Dateien, Variablen, Pfade). Eine wiederholte Zahlen- oder")
        print("       Prosakaskade findet das NICHT — die Marken dafuer gibt es nicht.")

    print()
    print("  " + "=" * 84)
    print("  NICHT GEPRUEFT — und das gehoert in jeden Bericht")
    print("  " + "=" * 84)
    print("     · ob eine nie verletzte Urteils-Regel ueberfluessig ist (dauerhaft offen)")
    print("     · welche Seite eines Widerspruchs recht hat")
    print("     · ob der Code dasselbe sagt wie die Regel (er sagt WAS, sie oft WARUM)")
    print("     · ob eine Regel FEHLT — ein Audit sieht nur, was da ist")
    print("     · ob eine Regel nur eine Schwaeche AELTERER Modelle behebt —")
    print("       ableitbar, aber die Debug-Daten liegen alle NACH dem letzten")
    print("       Modellwechsel (142 von 142). Trennschaerfe heute: null.")
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
