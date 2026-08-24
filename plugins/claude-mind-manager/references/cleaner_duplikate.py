#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dieselbe Information an mehreren Orten — vier Kategorien, nicht zwei.

⛔ DER FEHLER, DEN DIE ERSTE PLANFASSUNG GEMACHT HAETTE

Sie kannte nur **Duplikat** (beide behaupten es -> eine wird Zeiger) und
**Zeiger** (eine nennt die andere -> nichts tun).

**Der reale Bestand ist ueberwiegend BEIDES GLEICHZEITIG.** Die globale
`CLAUDE.md` fasst eine Regel zusammen UND nennt ihren Pfad. Wer das binaer als
Duplikat einordnet, entfernt genau den Inhalt aus der IMMER LADENDEN Datei,
dessen 100-%-Trefferquote der ganze Zweck war.

    Kurz-Regel in rules/         laedt zu 100 %
    Volltext ueber den Pfad      4 von 4 (gemessen)
    Volltext ueber Skill-Auswahl 20-84 %

## Die vier Kategorien

    duplikat     zwei etwa gleich lange Fassungen, kein Zeiger  -> eine wird Zeiger
    zielform     kuerzere Fassung PLUS Pfad                     -> ✅ NICHTS TUN
    zeiger       nennt die andere, wiederholt fast nichts       -> ✅ nichts tun
    zahlendrift  gleicher Bezeichner, ABWEICHENDE Zahl/Status   -> melden

## ⭐ ZAHLENDRIFT ist der Fall, den Textaehnlichkeit NIE findet

Marken-Ueberlappung sieht "derselbe Begriff kommt zweimal vor". Sie kann nicht
unterscheiden, ob die zweite Stelle dasselbe oder das GEGENTEIL sagt.

**Verifiziert am 24.08.2026 im eigenen Bestand:**

    Hook-Code            MIND_NOTFALL_TOKENS wird NIRGENDS gelesen
    env-vars.md:178      "entfallen v5.9.3"                        ✅
    env-vars.md:191      zeigt 940 000 -> NOTFALL als aktiv        ⛔
    globale CLAUDE.md    fuehrt ihn als geltenden Schwellwert      ⛔

Zwei von drei Stellen falsch, eine widerspricht sich INNERHALB derselben Datei.

⛔ **Das Werkzeug entscheidet NICHT, welche Stelle recht hat.** Es legt sie
nebeneinander. Und es sagt dazu: eine dritte Quelle — der CODE — schlaegt beide
Textstellen.

## ⚠ Der Rauschfilter ist tragend, nicht kosmetisch

Gemessen ueber fuenf Ablagen: 103 von 696 Marken standen in mehr als einer.
**44 davon waren Allerweltswoerter** ("nicht", "claude", "keine") — fast die
Haelfte. Echt sind 59, also 8 %.

Eine Liste, die zur Haelfte Muell ist, wird nicht gelesen.

Aufruf:
  python cleaner_duplikate.py --bereich <projektpfad>
  python cleaner_duplikate.py --selbsttest

Rueckgabe: 0 = gelaufen · 1 = keine Ablage lesbar · 3 = Selbsttest gescheitert
"""
import os
import re
import sys
import collections

# ⛔ `newline=""` ist PFLICHT auf Windows. Ohne diesen Zusatz uebersetzt
#    TextIOWrapper jeden Zeilenumbruch in die Windows-Fassung (CR + LF).
#    Jede zeilenverankerte Zusicherung (das Dollarzeichen in grep) bricht
#    dann — und zwar STILL, denn die Ausgabe sieht voellig richtig aus.
#    Gemessen 24.08.2026 an `cleaner_duplikate.py`: zwei Prueffaelle meldeten
#    0 Treffer fuer Zeilen, die dastanden. Dieselbe Klasse wie der in der
#    globalen CLAUDE.md dokumentierte `write_text()`-Fall.
sys.stdout.reconfigure(encoding="utf-8", newline="")

# Marken, die eine Uebersetzung ueberleben und spezifisch genug sind.
# ⚠ Bewusst ENG. Lieber ein Duplikat uebersehen als eine Liste voller Rauschen.
_MARKE = re.compile(
    r"`([^`\n]{3,60})`"                       # Inline-Code
    r"|\b([A-Z][A-Z0-9_]{4,})\b"              # ALLCAPS_BEZEICHNER
    r"|\b(\d[\d\s.,]{2,}\s?(?:%|B|KB|MB|Zeichen|Zeilen|Tokens?|s|ms))\b")

_STOPP = {"claude", "nicht", "keine", "kein", "memory", "skill", "rules", "hook",
          "hooks", "datei", "dateien", "immer", "code", "projekt", "kohlektiv"}


def _spezifisch(m):
    """⛔ Ohne diesen Filter ist fast die Haelfte der Meldungen Rauschen."""
    m = m.strip()
    if len(m) < 4 or m.lower() in _STOPP:
        return False
    return bool(re.search(r"[/\\.\d_-]", m)) or m.isupper()


def marken(text):
    out = set()
    for t in _MARKE.findall(text):
        for g in t:
            if g and _spezifisch(g):
                out.add(g.strip())
    return out


def _inhalt(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def _zeilen_mit(text, marke):
    return [z.strip() for z in text.split("\n") if marke in z and z.strip()]


# ⛔ Die erste Fassung war VIEL zu locker und hat sich selbst begraben.
#
#    Sie nahm als Statuswoerter unter anderem `aus` und `an` — im Deutschen
#    Allerweltswoerter — und zaehlte JEDE Zahl als Wert, auch Datumsangaben und
#    Versionsnummern. Gemessen am echten Bestand: **12 Treffer, davon 11
#    Fehlalarme**. `/mind-all` stand in zwei Dateien mit verschiedenen DATEN
#    daneben und galt als Drift.
#
#    Der eine echte Treffer (`MIND_NOTFALL_TOKENS`: 940 000 gegen "entfallen")
#    war da, aber im Rauschen nicht auffindbar. Genau der Zustand, vor dem der
#    Rauschfilter-Abschnitt oben warnt.
#
# ⭐ Scharfe Fassung: Drift heisst, eine Stelle erklaert etwas fuer TOT, waehrend
#    die andere es als LEBEND oder mit einem konkreten Wert fuehrt.
_TOT = re.compile(r"\b(entfallen|gestrichen|veraltet|abgeschaltet|ersetzt|"
                  r"entfernt|aufgehoben|wird nicht mehr)\b", re.IGNORECASE)
_LEBT = re.compile(r"\b(aktiv|scharf|gilt|eingeschaltet|wieder an)\b", re.IGNORECASE)

# Werte, KEINE Datumsangaben und KEINE Versionsnummern.
_DATUM = re.compile(r"\b\d{1,2}\.\d{1,2}\.\d{4}\b|\b20\d\d\b")
_VERSION = re.compile(r"\bv?\d+\.\d+(\.\d+)?\b")
_WERT = re.compile(r"\b\d[\d\s.]{2,}\b")


def einordnen(marke, a_pfad, a_text, b_pfad, b_text):
    """Vier Kategorien. Gibt (kategorie, begruendung) zurueck."""
    a_zeilen = _zeilen_mit(a_text, marke)
    b_zeilen = _zeilen_mit(b_text, marke)

    # --- Zahlendrift zuerst: er ist der einzige, der GEFAHR bedeutet ---------
    def merkmale(zeilen):
        tot = lebt = False
        werte = set()
        for x in zeilen:
            tot = tot or bool(_TOT.search(x))
            lebt = lebt or bool(_LEBT.search(x))
            # Datum und Version herausschneiden, BEVOR Werte gelesen werden.
            rest = _VERSION.sub(" ", _DATUM.sub(" ", x))
            werte.update(w.strip() for w in _WERT.findall(rest) if len(w.strip()) >= 3)
        return tot, lebt, werte
    a_tot, a_lebt, a_w = merkmale(a_zeilen)
    b_tot, b_lebt, b_w = merkmale(b_zeilen)

    # ⛔ NUR wenn eine Seite etwas fuer TOT erklaert und die andere es als
    #    lebend oder mit konkretem Wert fuehrt. Alles Weichere erzeugt
    #    Fehlalarme, die den einen echten Treffer begraben.
    if (a_tot and (b_lebt or b_w)) or (b_tot and (a_lebt or a_w)):
        links = "tot" if a_tot else (sorted(a_w)[:2] or "lebend")
        rechts = "tot" if b_tot else (sorted(b_w)[:2] or "lebend")
        return "zahlendrift", ("eine Stelle fuehrt es als entfallen, die andere "
                               "als geltend: %s gegen %s" % (links, rechts))

    # --- Zeigt eine Stelle auf die andere? ----------------------------------
    def zeigt_auf(text, ziel):
        n = os.path.basename(ziel)
        stamm = os.path.basename(os.path.dirname(ziel))
        return n in text or ("%s/%s" % (stamm, n)) in text.replace("\\", "/")
    a_zeigt = zeigt_auf(a_text, b_pfad)
    b_zeigt = zeigt_auf(b_text, a_pfad)

    la, lb = len(a_zeilen), len(b_zeilen)
    if not (a_zeigt or b_zeigt):
        return "duplikat", "beide behaupten es, keine nennt die andere"

    # ⭐ DIE KATEGORIE, DIE GEFEHLT HAT.
    #    Kuerzere Fassung PLUS Zeiger = Zielform. Nicht anfassen.
    kurz, lang = (la, lb) if a_zeigt else (lb, la)
    if lang and kurz < 0.6 * lang:
        return "zielform", ("kuerzere Fassung (%d gegen %d Zeilen) nennt den Pfad "
                            "— das ist die Zielform" % (kurz, lang))
    if kurz <= 1:
        return "zeiger", "nennt die andere, wiederholt fast nichts"
    return "duplikat", ("etwa gleich lang (%d gegen %d Zeilen), trotz Zeiger"
                        % (la, lb))


def ablagen(projekt, bereich="alles"):
    """Welche Ablagen verglichen werden.

    ⛔ `bereich` ist nicht Bequemlichkeit, sondern eine Messvoraussetzung.
       Ohne ihn liest JEDER Lauf auch den globalen Bestand mit. Gemessen
       24.08.2026: ein Prueffall mit zwei kuenstlichen Dateien bekam dadurch
       199 Marken und 2 Zahlendrift-Treffer aus dem ECHTEN Bestand des
       Rechners — die Zusicherung mass etwas anderes als das, was sie
       aufgebaut hatte.
    """
    H = os.path.expanduser("~")

    def md(d):
        return ([os.path.join(d, f) for f in sorted(os.listdir(d))
                 if f.endswith(".md")] if os.path.isdir(d) else [])
    a = {}
    if bereich in ("alles", "global"):
        a["g:CLAUDE.md"] = [os.path.join(H, ".claude", "CLAUDE.md")]
        a["g:rules"] = md(os.path.join(H, ".claude", "rules"))
    if bereich in ("alles", "projekt"):
        a["p:CLAUDE.md"] = [os.path.join(projekt, "CLAUDE.md")]
        a["p:rules"] = md(os.path.join(projekt, ".claude", "rules"))
    return {k: [p for p in v if os.path.isfile(p)] for k, v in a.items()}


def lauf(projekt, bereich="alles"):
    abl = ablagen(projekt, bereich)
    if not any(abl.values()):
        print("⛔ Keine Ablage lesbar unter %s" % projekt)
        print("   Das ist NIE ein gutes Ergebnis — eher ein falscher Pfad.")
        return 1

    text = {}
    wo = collections.defaultdict(set)
    for name, pfade in abl.items():
        for p in pfade:
            t = _inhalt(p)
            text[p] = t
            for m in marken(t):
                wo[m].add((name, p))

    print("=" * 86)
    print("  Duplikat-Pruefung ueber %d Ablagen" % len([k for k, v in abl.items() if v]))
    print("=" * 86)
    for name, pfade in abl.items():
        print("  %-14s %2d Datei(en)" % (name, len(pfade)))

    mehrfach = {m: s for m, s in wo.items() if len({n for n, _ in s}) >= 2}
    print("\n  %d Marken gesamt · %d in mehr als einer Ablage" % (len(wo), len(mehrfach)))

    treffer = collections.Counter()
    zeilen = []
    for m, stellen in sorted(mehrfach.items()):
        st = sorted(stellen)
        for i in range(len(st)):
            for j in range(i + 1, len(st)):
                (na, pa), (nb, pb) = st[i], st[j]
                if na == nb:
                    continue
                kat, grund = einordnen(m, pa, text[pa], pb, text[pb])
                treffer[kat] += 1
                zeilen.append((kat, m, na, nb, grund, pa, pb))

    print()
    for kat in ("zahlendrift", "duplikat", "zielform", "zeiger"):
        n = treffer[kat]
        marke = "⛔" if kat == "zahlendrift" else ("⚠" if kat == "duplikat" else "✅")
        print("  %s %-12s %3d" % (marke, kat, n))

    # ⛔ Zahlendrift zuerst und im Volltext — es ist die einzige Kategorie,
    #    bei der eine Stelle FALSCH ist statt nur redundant.
    drift = [z for z in zeilen if z[0] == "zahlendrift"]
    if drift:
        print("\n  " + "=" * 82)
        print("  ⛔ ZAHLENDRIFT — hier ist eine Stelle FALSCH, nicht nur doppelt")
        print("  " + "=" * 82)
        for _, m, na, nb, grund, pa, pb in drift[:12]:
            print("\n  %s" % m)
            print("     %-14s %s" % (na, os.path.basename(pa)))
            print("     %-14s %s" % (nb, os.path.basename(pb)))
            print("     %s" % grund)
        print("\n  ⛔ Welche Stelle recht hat, entscheidet dieses Werkzeug NICHT.")
        print("     ⭐ Und eine dritte Quelle schlaegt beide: der CODE.")

    dup = [z for z in zeilen if z[0] == "duplikat"]
    if dup:
        print("\n  ⚠ DUPLIKAT — eine Stelle koennte zum Zeiger werden")
        for _, m, na, nb, grund, _, _ in dup[:10]:
            print("     %-30s %s + %s  (%s)" % (m[:30], na, nb, grund))

    ziel = [z for z in zeilen if z[0] == "zielform"]
    if ziel:
        print("\n  ✅ ZIELFORM — bewusst so, NICHT anfassen (%d)" % len(ziel))
        for _, m, na, nb, grund, _, _ in ziel[:6]:
            print("     %-30s %s + %s" % (m[:30], na, nb))

    print()
    print("  ⛔ Vor jeder Aenderung das Urteilsbuch fragen:")
    print("     cleaner_urteile.py <projekt> --orte <a> <b>")
    print("  ⚠ Gemessen wird ERWAEHNUNG derselben Marke, nicht Bedeutungsgleichheit.")
    print("     Zwei Stellen, die dasselbe ANDERS formulieren, findet das hier NICHT.")
    return 0


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
        print("    %-4s %-46s ist=%-12s soll=%s"
              % ("OK" if ok else "FEHL", name, ist, soll))

    def schreib(n, t):
        p = os.path.join(d, n)
        open(p, "w", encoding="utf-8", newline="\n").write(t)
        return p

    print("=" * 78)
    print("  Selbsttest — vier Kategorien muessen UNTERSCHIEDEN werden")
    print("=" * 78)

    # 1) Zielform: kurze Fassung + Zeiger auf die lange
    lang = schreib("lang.md", "# L\n\n" + "\n\n".join(
        "Zeile %d ueber `MIND_SYNC_AT_TOKENS`." % i for i in range(10)))
    kurz = schreib("kurz.md", "# K\n\n`MIND_SYNC_AT_TOKENS` steuert die Mahnung.\n"
                              "Volltext: `lang.md`\n")
    k, _ = einordnen("MIND_SYNC_AT_TOKENS", kurz, _inhalt(kurz), lang, _inhalt(lang))
    pruef("kurz + Zeiger -> zielform", k, "zielform")

    # 2) Duplikat: zwei etwa gleich lange, keiner zeigt
    d1 = schreib("d1.md", "# A\n\n" + "\n\n".join(
        "Etwas ueber `MIND_BACKUP_KEEP_COUNT` Nummer %d." % i for i in range(6)))
    d2 = schreib("d2.md", "# B\n\n" + "\n\n".join(
        "Etwas ueber `MIND_BACKUP_KEEP_COUNT` Nummer %d." % i for i in range(6)))
    k, _ = einordnen("MIND_BACKUP_KEEP_COUNT", d1, _inhalt(d1), d2, _inhalt(d2))
    pruef("gleich lang, kein Zeiger -> duplikat", k, "duplikat")

    # 3) ⭐ Zahlendrift — der Fall, den Textaehnlichkeit nie findet
    z1 = schreib("z1.md", "# A\n\n`MIND_NOTFALL_TOKENS` ist entfallen in v5.9.3.\n")
    z2 = schreib("z2.md", "# B\n\n`MIND_NOTFALL_TOKENS` steht auf 940000 und ist aktiv.\n")
    k, grund = einordnen("MIND_NOTFALL_TOKENS", z1, _inhalt(z1), z2, _inhalt(z2))
    pruef("gleicher Name, anderer Status -> zahlendrift", k, "zahlendrift")

    # 4) Reiner Zeiger
    r1 = schreib("r1.md", "# A\n\nSiehe `r2.md` fuer `MIND_LOG_MAX_LINES`.\n")
    r2 = schreib("r2.md", "# B\n\n" + "\n\n".join(
        "`MIND_LOG_MAX_LINES` Absatz %d." % i for i in range(8)))
    k, _ = einordnen("MIND_LOG_MAX_LINES", r1, _inhalt(r1), r2, _inhalt(r2))
    pruef("eine Zeile + Zeiger -> zeiger oder zielform", k in ("zeiger", "zielform"), True)

    # ⛔ Die Gegenprobe: vier Faelle, mindestens drei VERSCHIEDENE Urteile.
    #    Ein Einordner, der immer dasselbe sagt, bestuende jeden Einzelfall.
    ergebnisse = {
        einordnen("MIND_SYNC_AT_TOKENS", kurz, _inhalt(kurz), lang, _inhalt(lang))[0],
        einordnen("MIND_BACKUP_KEEP_COUNT", d1, _inhalt(d1), d2, _inhalt(d2))[0],
        einordnen("MIND_NOTFALL_TOKENS", z1, _inhalt(z1), z2, _inhalt(z2))[0],
    }
    pruef("drei verschiedene Urteile", len(ergebnisse), 3)

    # Rauschfilter
    pruef("Allerweltswort gefiltert", _spezifisch("claude"), False)
    pruef("kurzes Wort gefiltert", _spezifisch("abc"), False)
    pruef("Pfad ist spezifisch", _spezifisch("tools/rollback.py"), True)
    pruef("ALLCAPS ist spezifisch", _spezifisch("MIND_SYNC_AT_TOKENS"), True)
    m = marken("Text mit `tools/x.py` und MIND_ABC_DEF und claude und 200 Zeilen.")
    pruef("claude nicht in den Marken", "claude" in m, False)
    pruef("Pfad in den Marken", "tools/x.py" in m, True)

    print("\n=== %d Abweichung(en) ===" % fehler)
    return 3 if fehler else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()
    projekt = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    if "--bereich" in argv:
        i = argv.index("--bereich") + 1
        if i < len(argv):
            projekt = argv[i]
    # ⚠ --nur global|projekt|alles schraenkt die Ablagen ein. Vorgabe: alles.
    bereich = "alles"
    if "--nur" in argv:
        i = argv.index("--nur") + 1
        if i < len(argv) and argv[i] in ("global", "projekt", "alles"):
            bereich = argv[i]
        else:
            print("--nur braucht global|projekt|alles")
            return 2
    return lauf(projekt, bereich)


if __name__ == "__main__":
    sys.exit(main())
