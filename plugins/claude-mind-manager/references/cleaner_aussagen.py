#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Die Einheit ist die AUSSAGE, nicht die Datei.

⛔ WARUM DIE DATEI DIE FALSCHE EINHEIT IST

Eine Regeldatei enthaelt fast immer BEIDES: das Gebot und seine Herleitung.
Wer die Datei als Ganzes bewertet, verwirft mit der Herleitung das Gebot — oder
behaelt mit dem Gebot 30 kB Belege.

    `messung-vor-glauben.md`  6243 B  = vier Gates (Gebot)
                                       + Messreihen, Vorfaelle, Zahlen (Beleg)

Der Umzug will das eine behalten und das andere verschieben. Dafuer muss man
sie erst trennen koennen.

⚠ **Das liefert KANDIDATEN, kein Urteil.** Ob drei Saetze eine Aussage sind oder
drei, ist Auslegung. Das Werkzeug legt die Zerlegung SICHTBAR vor, damit sie
bestreitbar ist — nicht damit sie geglaubt wird.

## Blind References

`[STUDIE, unbestaetigt]` arXiv 2606.15828, 87 % Erkennungspraezision: ein Verweis
auf eine andere Datei OHNE zu sagen, WOZU und WANN man ihm folgen soll.

⭐ Das trifft direkt eine eigene Messung: einem Zeiger wurde **4 von 4** mal
gefolgt — aber in allen vier Sonden war die Aufgabe OHNE den Wert unloesbar.
Ein Zeiger ohne Anlass ist ungemessen.

Aufruf:
  python cleaner_aussagen.py <datei.md> [--zeige]
  python cleaner_aussagen.py --verzeichnis <pfad>
  python cleaner_aussagen.py --selbsttest

Rueckgabe: 0 = zerlegt · 1 = Blind References gefunden · 2 = nicht lesbar
"""
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", newline="")

# Ein Gebot erkennt man am Imperativ oder am Verbotszeichen.
GEBOT = re.compile(
    r"\bMUST\b|\bNEVER\b|\bALWAYS\b|\bniemals\b|\bnie\b|\bimmer\b|\bmuss\b|"
    r"\bdarf nicht\b|\bkeinesfalls\b|\bPflicht\b|⛔", re.IGNORECASE)

# Ein Beleg nennt Zahlen, Daten, Messungen.
BELEG = re.compile(
    r"\bgemessen\b|\bbelegt\b|\bnachgewiesen\b|\bgepr[uü]ft\b|"
    r"\b\d{1,2}\.\d{1,2}\.\d{4}\b|\b\d{3,}\b|\bv\d+\.\d+", re.IGNORECASE)

# Ein Verweis auf eine andere Datei.
VERWEIS = re.compile(
    r"`([^`\n]*?[\w.-]+\.(?:md|py|sh|json|exe|bat))`"
    r"|(?<![\w`])((?:~|\.{0,2})?/[\w./-]+\.(?:md|py|sh|json))")

# ⚠ Wozu-Woerter. Steht eines davon in der Naehe, ist der Verweis nicht blind.
#   Bewusst GROSSZUEGIG: ein Fehlalarm hier kostet Vertrauen, ein verpasster
#   Treffer nur einen Hinweis.
WOZU = re.compile(
    r"\bDetails?\b|\bVolltext\b|\bBelege?\b|\bfalls\b|\bwenn\b|\bsiehe\b|"
    r"\bHerleitung\b|\bBegr[uü]ndung\b|\bnachlesen\b|\bLangfassung\b|"
    r"\bAnleitung\b|\bVorfall\b|\bMessung\b|\bwer\b|\bzum\b|\bfuer\b|\bfür\b|"
    r"\bsteht\b|\berkl[aä]rt\b|\bbeschreibt\b|\bdazu\b", re.IGNORECASE)

CODEZAUN = re.compile(r"^\s*```")


def zerlege(text):
    """Kandidaten fuer einzelne Aussagen. (liste, code_uebersprungen)

    Geschnitten wird an: Aufzaehlungspunkten, Tabellenzeilen, Ueberschriften,
    Leerzeilen. Codebloecke bleiben als EIN Stueck beim vorigen Kandidaten —
    ein Befehl gehoert zu der Aussage, die ihn erklaert.
    """
    aussagen = []
    akt = []
    drin = False
    code = 0
    for z in text.split("\n"):
        if CODEZAUN.match(z):
            drin = not drin
            code += 1
            akt.append(z)
            continue
        if drin:
            code += 1
            akt.append(z)
            continue
        neu = bool(re.match(r"^\s*(?:[-*+]\s|\d+\.\s|#{1,6}\s|\|)", z))
        if (neu or not z.strip()) and akt:
            s = "\n".join(akt).strip()
            if s:
                aussagen.append(s)
            akt = []
        if z.strip():
            akt.append(z)
    if akt:
        s = "\n".join(akt).strip()
        if s:
            aussagen.append(s)
    return aussagen, code


def einordnen(a):
    """gebot | beleg | gemischt | prosa"""
    g = bool(GEBOT.search(a))
    b = bool(BELEG.search(a))
    if g and b:
        return "gemischt"
    if g:
        return "gebot"
    if b:
        return "beleg"
    return "prosa"


def blinde_verweise(aussagen):
    """Verweise ohne Wozu. (liste je (aussage_nr, ziel, ausschnitt))"""
    out = []
    for i, a in enumerate(aussagen):
        for m in VERWEIS.finditer(a):
            ziel = m.group(1) or m.group(2)
            if not ziel:
                continue
            # ⚠ Der Kontext ist die ganze Aussage, nicht nur die Zeile —
            #   ein Wozu steht oft im Satz davor.
            if WOZU.search(a):
                continue
            out.append((i, ziel, re.sub(r"\s+", " ", a)[:70]))
    return out


def lauf(pfad, zeige=False):
    try:
        with open(pfad, encoding="utf-8", errors="replace") as fh:
            t = fh.read()
    except OSError:
        return None
    aussagen, code = zerlege(t)
    arten = {}
    for a in aussagen:
        arten[einordnen(a)] = arten.get(einordnen(a), 0) + 1
    blind = blinde_verweise(aussagen)
    return {"pfad": pfad, "aussagen": len(aussagen), "arten": arten,
            "blind": blind, "code": code, "liste": aussagen if zeige else []}


def bericht(e):
    print("=" * 84)
    print("  %s — %d Aussage-Kandidaten" % (os.path.basename(e["pfad"]), e["aussagen"]))
    print("=" * 84)
    for k in ("gebot", "gemischt", "beleg", "prosa"):
        print("  %-10s %3d" % (k, e["arten"].get(k, 0)))
    print()
    g = e["arten"].get("gebot", 0) + e["arten"].get("gemischt", 0)
    b = e["arten"].get("beleg", 0)
    if g and b:
        print("  ⭐ %d Gebot(e) und %d Beleg(e) in EINER Datei — genau der Fall, fuer" % (g, b))
        print("     den es den Umzug gibt: das Gebot bleibt, die Belege gehen.")
    if e["blind"]:
        print()
        print("  ⚠ %d BLINDER VERWEIS(E) — nennt eine Datei, sagt aber nicht wozu:"
              % len(e["blind"]))
        for _, ziel, aus in e["blind"][:8]:
            print("     %-34s in: %s" % (ziel[:34], aus))
        print()
        print("     Gemessen: einem Zeiger wird 4 von 4 mal gefolgt — aber in allen")
        print("     Sonden war die Aufgabe ohne den Wert unloesbar. Ein Zeiger ohne")
        print("     Anlass ist ungemessen.")
    if e["liste"]:
        print()
        for i, a in enumerate(e["liste"]):
            print("  [%2d] %-8s %s" % (i, einordnen(a), re.sub(r"\s+", " ", a)[:66]))
    print()
    print("  ⚠ KANDIDATEN, kein Urteil. Ob drei Saetze eine Aussage sind oder drei,")
    print("    ist Auslegung — die Zerlegung steht hier, damit sie bestreitbar ist.")
    return 1 if e["blind"] else 0


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

    print("=" * 78)
    print("  Selbsttest — Zerlegung und Blind References")
    print("=" * 78)

    # Gebot gegen Beleg unterscheiden
    pruef("Imperativ -> gebot", einordnen("⛔ NIEMALS die dist/ loeschen."), "gebot")
    pruef("Zahl+gemessen -> beleg",
          einordnen("Gemessen am 21.08.2026: 267 von 920 Ladevorgaengen."), "beleg")
    pruef("beides -> gemischt",
          einordnen("⛔ NIE loeschen. Gemessen 21.08.2026: 267 Faelle."), "gemischt")
    pruef("weder noch -> prosa", einordnen("Der Ablauf hat drei Stufen."), "prosa")

    # Zerlegung
    t = ("# Titel\n\n- Erster Punkt\n- Zweiter Punkt\n\nEin Absatz.\n\n"
         "| a | b |\n|---|---|\n")
    a, _ = zerlege(t)
    pruef("zerlegt in mehrere Kandidaten", len(a) >= 5, True)

    # ⚠ Ein Codeblock bleibt EIN Stueck.
    t2 = "- Punkt\n\n```bash\necho eins\necho zwei\n```\n"
    a2, code = zerlege(t2)
    pruef("Codeblock zaehlt als Codezeilen", code >= 4, True)

    # ⭐ Blind References — beide Richtungen
    a3, _ = zerlege("- Der Volltext steht in `skills/x/SKILL.md`.\n")
    pruef("Verweis MIT Wozu -> nicht blind", len(blinde_verweise(a3)), 0)
    a4, _ = zerlege("- Vergleiche `skills/x/SKILL.md`.\n")
    pruef("Verweis OHNE Wozu -> blind", len(blinde_verweise(a4)), 1)
    a5, _ = zerlege("- Ein Absatz ganz ohne Verweis.\n")
    pruef("kein Verweis -> nichts gemeldet", len(blinde_verweise(a5)), 0)

    # Nicht lesbar ist kein Ergebnis
    pruef("fehlende Datei -> None", lauf(os.path.join(d, "x.md")), None)

    print("\n=== %d Abweichung(en) ===" % fehler)
    return 3 if fehler else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()
    zeige = "--zeige" in argv
    if "--verzeichnis" in argv:
        i = argv.index("--verzeichnis") + 1
        w = argv[i] if i < len(argv) else "."
        dateien = []
        for wurzel, _, fs in os.walk(w):
            dateien += [os.path.join(wurzel, f) for f in sorted(fs) if f.endswith(".md")]
    else:
        dateien = [a for a in argv if not a.startswith("--")]
    if not dateien:
        print("usage: cleaner_aussagen.py <datei.md> | --verzeichnis <pfad> | --selbsttest")
        return 2
    rc = 0
    for p in dateien:
        e = lauf(p, zeige)
        if e is None:
            print("⛔ %s nicht lesbar — KEIN Ergebnis." % p)
            rc = max(rc, 2)
            continue
        rc = max(rc, bericht(e))
        print()
    return rc


if __name__ == "__main__":
    sys.exit(main())
