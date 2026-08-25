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


# ---------------------------------------------------------------------------
# L1 — CODE-KANDIDATEN
#
# ⛔ DIESES WERKZEUG URTEILT NICHT. Es legt vor, wo der Quellbaum dieselben
#    benannten Dinge nennt wie eine Aussage. Die Frage "wuerdest du das auch
#    OHNE diese Regel verstehen?" beantwortet ein Mensch oder ein Modell mit
#    den Fundstellen vor Augen — nicht ein Zaehler.
#
# ⛔ WARUM KEIN AUTOMATISCHES URTEIL: `calculate_km`. Die km-Dynamik der
#    Zustellplan-App verschwand still bei einem Umbau, GENAU WEIL nur der Code
#    sie trug und keine Regel das Warum festhielt. Ein Werkzeug, das
#    "steht im Code -> Regel ueberfluessig" urteilt, haette genau diesen
#    Verlust empfohlen.
#
# ⚠ Der Code sagt WAS. Die Regel sagt oft WARUM.

CODE_ENDUNGEN = (".py", ".sh", ".bash", ".js", ".ts", ".tsx", ".jsx", ".mjs",
                 ".c", ".h", ".cpp", ".hpp", ".cs", ".java", ".go", ".rs",
                 ".rb", ".php", ".sql", ".ps1", ".bat", ".toml", ".ini",
                 ".yaml", ".yml", ".json")

# ⛔ Mindestens SO VIELE Marken einer Aussage muessen in DERSELBEN Datei stehen.
#    Mit 1 schlaegt jeder Allerweltsbezeichner ueberall an — dieselbe Lehre wie
#    beim Anteils-Filter in cleaner_duplikate: eine geteilte Marke ist Zufall,
#    mehrere sind ein Bezug.
_CODE_MIN_MARKEN = 2
_CODE_MAX_JE_AUSSAGE = 3


def _codedateien(wurzel):
    """Quelldateien unter `wurzel`, ohne fremden Code und ohne Kopien.

    ⛔ Die Ausschlussliste wird NICHT nachgebaut — sie steht in
       `learnings_quellen.AUS` und ist dort gegen den echten Bestand geeicht
       (blosse Rekursion fand 57 Projekte statt 23; 34 kamen aus Sicherungen).
    """
    try:
        from learnings_quellen import AUS
    except ImportError:                     # eigenstaendiger Aufruf
        AUS = ("node_modules", ".git", "__pycache__", ".venv", "venv",
               "dist", "build", ".claude-mind", "Beispiele", "cache")
    aus = []
    for w, ds, fs in os.walk(wurzel):
        ds[:] = [d for d in ds if d not in AUS and not d.startswith(".")]
        for f in fs:
            if f.endswith(CODE_ENDUNGEN):
                aus.append(os.path.join(w, f))
    return aus


def code_kandidaten(aussagen, quellbaum, regeldatei=None):
    """{aussage_nr: [(datei, zeile, ausschnitt, getroffene_marken)]}

    ⛔ Gibt KANDIDATEN zurueck, keine Urteile. Es gibt bewusst kein Feld
       "ueberfluessig", "redundant" oder "kann weg".
    """
    try:
        from cleaner_duplikate import marken as _marken
    except ImportError:
        return {}
    dateien = _codedateien(quellbaum)
    if regeldatei:
        rd = os.path.abspath(regeldatei)
        dateien = [d for d in dateien if os.path.abspath(d) != rd]

    # Einmal lesen, nicht je Aussage — sonst ist es bei 600 Aussagen unbenutzbar.
    inhalt = {}
    for d in dateien:
        try:
            with open(d, encoding="utf-8", errors="replace") as fh:
                inhalt[d] = fh.read()
        except OSError:
            continue

    out = {}
    for i, a in enumerate(aussagen):
        ms = _marken(a)
        if len(ms) < _CODE_MIN_MARKEN:
            continue
        treffer = []
        for d, txt in inhalt.items():
            drin = sorted(m for m in ms if m in txt)
            if len(drin) < _CODE_MIN_MARKEN:
                continue
            # erste Zeile, in der eine der Marken steht — als Beleg, nicht als Urteil
            zeile, schnipsel = 0, ""
            for nr, z in enumerate(txt.split(chr(10)), 1):
                if any(m in z for m in drin):
                    zeile, schnipsel = nr, z.strip()[:90]
                    break
            treffer.append((d, zeile, schnipsel, drin))
        if treffer:
            treffer.sort(key=lambda x: -len(x[3]))
            out[i] = treffer[:_CODE_MAX_JE_AUSSAGE]
    return out


def code_bericht(aussagen, kand, wurzel):
    """Legt die Fundstellen vor. ⛔ Kein Urteil, kein Vorschlag zum Loeschen."""
    print()
    print("  " + "=" * 84)
    print("  CODE-KANDIDATEN — %d von %d Aussagen haben eine Entsprechung im Code"
          % (len(kand), len(aussagen)))
    print("  " + "=" * 84)
    print("     Quellbaum: %s" % wurzel)
    print("     ⛔ DAS IST KEIN URTEIL. Der Code sagt WAS, die Regel sagt oft WARUM.")
    print("        Die Frage lautet: WUERDEST DU DAS AUCH OHNE DIESE REGEL VERSTEHEN?")
    print("        Sie wird mit den Fundstellen vor Augen beantwortet, nicht gezaehlt.")
    print("     ⛔ Gegenbeispiel, das hier immer mitgedacht wird: `calculate_km`.")
    print("        Die km-Dynamik verschwand still bei einem Umbau, GENAU WEIL nur")
    print("        der Code sie trug. 'Steht im Code' heisst nicht 'Regel ueberfluessig'.")
    print()
    for i in sorted(kand):
        kurz = re.sub(r"\s+", " ", aussagen[i])[:74]
        print("     [%d] %s" % (i, kurz))
        for d, z, s, ms in kand[i]:
            print("         %s:%d" % (os.path.relpath(d, wurzel).replace(chr(92), "/"), z))
            print("           %s" % s)
            print("           Marken: %s" % ", ".join(ms[:5]))
    if not kand:
        print("     (keine) — kein Quellcode nennt dieselben benannten Dinge.")
        print("     ⚠ Das heisst NICHT 'die Regeln sind alle noetig'. Es heisst,")
        print("       dass dieser Abgleich nichts beitragen kann.")


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
    # L1 — Code-Kandidaten. Ohne die Flagge aendert sich nichts.
    quellbaum = None
    if "--code" in argv:
        i = argv.index("--code") + 1
        if i >= len(argv) or argv[i].startswith("--"):
            print("--code braucht einen Quellbaum-Pfad")
            return 2
        quellbaum = argv[i]
        if not os.path.isdir(quellbaum):
            # ⛔ Abbruch statt still ins Leere messen. "0 Kandidaten" waere von
            #    "Pfad falsch" nicht zu unterscheiden — dieselbe Klasse wie der
            #    Bedienfehler bei --bereich in cleaner_duplikate (25.08.2026).
            print("Quellbaum existiert nicht: %s" % quellbaum)
            return 2
        dateien = [d for d in dateien if d != quellbaum]
    if not dateien:
        print("usage: cleaner_aussagen.py <datei.md> [--code <quellbaum>]")
        print("       cleaner_aussagen.py --verzeichnis <pfad> | --selbsttest")
        return 2
    rc = 0
    for p in dateien:
        e = lauf(p, zeige)
        if e is None:
            print("⛔ %s nicht lesbar — KEIN Ergebnis." % p)
            rc = max(rc, 2)
            continue
        rc = max(rc, bericht(e))
        if quellbaum:
            try:
                txt = open(p, encoding="utf-8", errors="replace").read()
            except OSError:
                txt = ""
            aussagen, _ = zerlege(txt)
            code_bericht(aussagen, code_kandidaten(aussagen, quellbaum, p), quellbaum)
        print()
    return rc


if __name__ == "__main__":
    sys.exit(main())
