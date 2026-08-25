#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Schritt 8 von /mind-cleaner — KUERZEN. Und zwar durch VERSCHIEBEN.

Dein AUDIT/REBUILD-Auftrag vom 24.08.2026, woertlich:

  "Ueberpruefe jede Anweisung ... REBUILD — Behalte nur die Regeln, bei denen
   du ohne sie tatsaechlich Fehler machen wuerdest. Formuliere diese Regeln so
   kurz wie moeglich und verschiebe alles andere in einen archive-Ordner
   (NIEMALS DAUERHAFT LOESCHEN)."

Praezisierung vom 25.08.2026: das Kriterium ist
  "wuerdest du das VERSTEHEN ohne diese rule" — nicht "wuerdest du es TUN".

⛔ DIE SKILL.md SAGTE BIS v5.20.2 "NIE kuerzen". Das war MEINE Zeile, nicht
   deine (Commit 82efd0d dokumentiert alle anderen Entscheidungen namentlich,
   diese nicht) — und sie hat KUERZEN mit LOESCHEN gleichgesetzt. Hier wird
   nichts geloescht: jeder Satz landet entweder in der Kurzfassung oder im
   Archiv, und der Weg zurueck steht offen.

## Warum das ein eigenes Modul ist und kein Anbau an cleaner_umzug

`cleaner_umzug.py` prueft den UMZUG (Regel -> Skill) und schreibt NICHTS. Der
Rebuild schreibt. Zwei Operationen, zwei Gates:

    Umzug     Regel + Kurz + Skill   ->  4 Gates, davon 1x Zeilenzahl
    Rebuild   Alt -> Kurz + Archiv   ->  SATZ-IDENTITAET

## ⛔ WARUM DAS ERHALTUNGS-GATE AUS cleaner_umzug HIER NICHT TAUGT

  trivial gruen   `inhaltszeilen()` zaehlt Zeilen. Ein Archiv mit Kopf, Datum
                  und Grund je Satz hat IMMER mehr Zeilen als das Entnommene.
  nicht auswertbar  `pruefe()` braucht `--alt`; nach dem Schreiben in-place gibt
                  es das nicht mehr. Fehlt eine Datei -> rc=2, und wer nur auf
                  rc==1 prueft, haelt das fuer bestanden.
  Gate 4 bricht   BESCHREIBUNG verlangt `description:` >= 40 Zeichen. Ein
                  Archiv hat keins.
  es sagt es selbst  Docstring dort: "Die Gates schliessen VERLUST aus, nicht
                  VERTAUSCHUNG."

## ⛔ KORREKTUR AM EIGENEN PLAN (26.08.2026)

Der Plan formulierte das Ersatz-Gate ueber MARKEN:

    Marken(alt) ⊆ Marken(kurz) ∪ Marken(archiv)  und
    Marken(kurz) ∩ Marken(archiv) = ∅

Die zweite Zeile ist FALSCH und haette jeden vernuenftigen Rebuild blockiert.
Eine Kurzfassung, die das Gebot behaelt ("NIE `git add -A`"), und ein Archiv,
das den Beleg dazu traegt ("...weil dort 7 fremde Aenderungen liegen, `git
add -A` ..."), teilen die Marke ZWANGSLAEUFIG. Genau diese Ueberlappung macht
den Zeiger ueberhaupt sinnvoll.

Gebaut ist deshalb, was die Ueberschrift des Plans schon sagte — SATZ-Identitaet:

    1 VOLLSTAENDIG  jeder Satz aus ALT steht in KURZ oder im ARCHIV
    2 VERSCHOBEN    kein Satz steht in BEIDEN (sonst kopiert statt verschoben)
    3 NICHTS ERFUNDEN  kein Satz in KURZ/ARCHIV, der nicht in ALT stand
                    (Ausnahme: der Zeiger und der Archivkopf, beide benannt)
    4 ZEIGER        die Kurzfassung nennt den ARCHIVPFAD WOERTLICH
                    — die Lehre aus cleaner_umzug Gate 3: ein Zeiger auf einen
                      NAMEN verlaesst sich auf die 20-%-Mechanik der
                      Skill-Auswahl, ein Zeiger auf einen PFAD nicht.

⛔ ALLE VIER laufen VOR dem Schreiben, gegen Zeichenketten im Speicher.
   Erst wenn sie halten, wird geschrieben — und dann atomar.
   rc=2 heisst: NICHT angefasst.

## Freigabe

    ohne Flagge   Bericht -> dein OK -> Plan -> dein OK -> anwenden
    --auto        BELEGE wandern automatisch. Sonst nichts.

⛔ PROSA WANDERT NIE AUTOMATISCH (352 von 620 Aussagen im gemessenen Bestand).
⛔ GEMISCHT auch nicht — da steckt ein Gebot drin.
⛔ `autonom-arbeiten.md` ist AUSGENOMMEN: sie meldet 0 Gebote bei 31
   Kandidaten. Das ist das dokumentierte Fehlurteil des Einordners, und eine
   Datei, deren Einordnung nachweislich falsch ist, wird nicht automatisch
   zerschnitten.
⛔ EINE DATEI JE LAUF — im Code gezaehlt, nicht als Prosa behauptet.

Aufruf:
    python cleaner_rebuild.py --bereich <projekt> <regel.md>            # Vorschlag
    python cleaner_rebuild.py --bereich <projekt> <regel.md> --auto     # Belege
    python cleaner_rebuild.py --bereich <projekt> <regel.md> --auto --anwenden
    python cleaner_rebuild.py --selbsttest
"""
import io
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import cleaner_aussagen as aus                                   # noqa: E402
import cleaner_ratsche as rat                                    # noqa: E402

# ⛔ Dateien, deren Einordnung nachweislich falsch ist. Sie werden nie
#    automatisch zerschnitten. Die Liste ist kurz und BEGRUENDET — sie ist
#    keine Bequemlichkeit.
AUSGENOMMEN = {
    # 0 Gebote bei 31 Kandidaten. Der Einordner sieht die Gebote dort nicht,
    # weil sie als Tabellenzeilen und Fragen formuliert sind.
    "autonom-arbeiten.md": "Einordner meldet 0 Gebote bei 31 Kandidaten",
}

# Was `--auto` bewegen darf. NUR das.
AUTO_KLASSEN = ("beleg",)


def _norm(s):
    """Ein Satz, vergleichbar gemacht. Nur Leerraum, sonst NICHTS."""
    return re.sub(r"\s+", " ", s).strip()


def _lies(p):
    try:
        # ⛔ newline="" ist PFLICHT. Ohne das uebersetzt Python CRLF still nach
        #    LF, und `_zeilenende()` misst dann IMMER LF — ein Rebuild haette
        #    jede CRLF-Datei gekippt, genau der Schaden, gegen den der
        #    Zeilenenden-Waechter in /mind-all gebaut wurde.
        with io.open(p, encoding="utf-8", errors="replace", newline="") as fh:
            return fh.read()
    except OSError:
        return None


def _zeilenende(text):
    """⚠ Das Zeilenende der Zieldatei wird UEBERNOMMEN, nicht gesetzt.

    Ein Rebuild, der LF nach CRLF kippt, macht den Diff unlesbar und reisst
    Ersetzungsanker — genau der Schaden, gegen den der Zeilenenden-Waechter
    in /mind-all gebaut wurde.
    """
    crlf = text.count("\r\n")
    lf = text.count("\n") - crlf
    return "\r\n" if crlf > lf else "\n"


def einteilen(pfad, auto=False):
    """(bleibt, wandert, uebersprungen) — Saetze nach Klasse.

    ⛔ Urteilt NICHT ueber den Inhalt. Es wendet `cleaner_aussagen.einordnen`
       an, und das ist ein Regex-Einordner, kein Richter.
    """
    text = _lies(pfad)
    if text is None:
        return None, None, "nicht lesbar"
    name = os.path.basename(pfad)
    if name in AUSGENOMMEN:
        return None, None, "ausgenommen: %s" % AUSGENOMMEN[name]

    # ⛔ OHNE Frontmatter. Sonst steht es zweimal in der Kurzfassung — einmal
    #    als vorangestellter Kopf, einmal als "Satz" — und Gate 1 wie Gate 3
    #    brechen. Gemessen beim ersten Selbsttestlauf (26.08.2026).
    saetze, _ = aus.zerlege(_koerper(text))
    bleibt, wandert = [], []
    for i, s in enumerate(saetze):
        k = aus.einordnen(s)
        darf = auto and k in AUTO_KLASSEN and not _bleibt_immer(s)
        # ⛔ RUECKBEZUG-SPERRE: zeigt der FOLGESATZ auf diesen hier, bleibt er.
        if darf and i + 1 < len(saetze) and _zeigt_zurueck(saetze[i + 1]):
            darf = False
        if darf:
            wandert.append((s, k))
        else:
            bleibt.append((s, k))
    return bleibt, wandert, None


# ⚠ HEURISTIK, und sie wird als solche ausgewiesen: gefunden wird der
#   SPRACHLICHE Rueckbezug, nicht der gedankliche. Ein Folgesatz, der ohne
#   Signalwort auf den entfernten Bezug nimmt, bleibt unsichtbar.
_RUECKBEZUG = re.compile(
    r"\b(trotzdem|dennoch|deshalb|darum|daher|stattdessen|genau das|beides|"
    r"beide|danach|dabei|dazu|davon|dieser|diese|dies|derselbe|dasselbe)\b",
    re.IGNORECASE)

# ⛔ Nur der ANFANG des Folgesatzes zaehlt — und die Zahl ist GEMESSEN, nicht
#    gewaehlt. Sie steht zwischen genau einer Positiv- und einer
#    Negativkontrolle (werkzeuge-zuerst.md: "Jede Schwelle steht zwischen einer
#    Positiv- UND einer Negativkontrolle"):
#
#      Fenster | gesperrt | "bleibt TROTZDEM bestehen" | "…test_x.sh, DAVON 4 rot"
#         30   |    6     |   verfehlt                 |  richtig ignoriert
#         40   |    6     |   verfehlt                 |  richtig ignoriert
#      >> 50   |    8     |   GEFANGEN                 |  richtig ignoriert
#         60   |    8     |   gefangen                 |  FEHLALARM
#         90   |    8     |   gefangen                 |  FEHLALARM
#
#    Der Fehlalarm bei 60+: "davon" bezieht sich dort auf "8 Pruefungen" im
#    SELBEN Satz, nicht auf den vorigen.
# ⚠ Zwei Ankerfaelle sind eine duenne Grundlage. Sie sind das Minimum, nicht
#   der Beweis — und die Sperre faellt bewusst zur sicheren Seite: ein
#   Fehlalarm heisst, der Satz BLEIBT.
_RUECKBEZUG_FENSTER = 50


def _zeigt_zurueck(folgesatz):
    """Beginnt der Folgesatz mit einem Rueckbezug?

    ⛔ Gefunden beim Ansehen eines Diffs, nicht von einem Gate (26.08.2026):
         entfernt  "**Teilentwarnung seit 17.08.2026:** ... lokales Git-Repo"
         bleibt    "⚠ Die Luecke bleibt TROTZDEM bestehen."
       Nach dem Schnitt zeigt das "trotzdem" ins Leere. Kein Satz verloren,
       keine Struktur zerbrochen, alle vier Satz-Identitaets-Gates gruen.
       Das ist VERTAUSCHUNG statt VERLUST — die Klasse, die cleaner_umzug in
       seinem eigenen Docstring als ungedeckt benennt.

    Gemessen ueber sechs echte Regeln, BEVOR daraus eine Sperre wurde:
    sie kostet 1-2 von 16-20 Kandidaten (6-20 %, ein Ausreisser bei 67 % in
    einer Datei mit nur drei Kandidaten). Eine Sperre, die alles blockiert,
    waere keine.
    """
    return bool(_RUECKBEZUG.search(
        re.sub(r"\s+", " ", folgesatz)[:_RUECKBEZUG_FENSTER]))


def _bleibt_immer(s):
    """⛔ Was NIE automatisch wandert — auch wenn es als Beleg eingeordnet ist.

    Beides sind Faelle von VERTAUSCHUNG, nicht von VERLUST. Kein Gate kann sie
    sehen, weil kein Satz verlorengeht:

      Tabellenzeile   `zerlege()` gibt jede Zeile als eigenen Satz zurueck.
                      Eine mittendrin herausgeschnittene Zeile zerreisst die
                      Tabelle.
      Ueberschrift    Gemessen am ersten sauberen Trockenlauf (env-vars.md,
                      26.08.2026): "## Was ein Snapshot enthaelt" wanderte mit
                      seinem Absatz ins Archiv — und die Tabelle darunter blieb
                      ueberschriftenlos in der Kurzfassung zurueck.

    Wer eine Tabelle oder einen Abschnitt kuerzen will, macht das von Hand.
    """
    kopf = s.lstrip()
    return kopf.startswith("|") or kopf.startswith("#")


def _kopfzeilen(text):
    """Frontmatter + alles bis zur ersten Aussage bleibt unangetastet."""
    if not text.startswith("---"):
        return ""
    m = re.match(r"^---\r?\n.*?\r?\n---\r?\n", text, re.S)
    return m.group(0) if m else ""


def _koerper(text):
    """Der Text ohne Frontmatter."""
    return text[len(_kopfzeilen(text)):]


def baue(pfad, projekt, auto=False):
    """(kurz_text, archiv_text, archiv_pfad, grund) — NUR im Speicher.

    ⛔ Schreibt NICHTS. Das Schreiben passiert erst nach den Gates.
    """
    bleibt, wandert, grund = einteilen(pfad, auto)
    if grund:
        return None, None, None, grund
    if not wandert:
        return None, None, None, "nichts zu verschieben"

    text = _lies(pfad)
    ze = _zeilenende(text)
    ziel = rat.archiv_datei(projekt, pfad)
    rel = os.path.relpath(ziel, projekt).replace(chr(92), "/")

    # ⭐ DER ZEIGER NENNT DEN PFAD, NICHT DEN NAMEN. Lehre aus cleaner_umzug
    #    Gate 3: Pfad 4 von 4 gelesen, Skill-NAME 20-84 %.
    zeiger = ("> Belege, Zahlen und Herleitung: `%s` — dorthin verschoben "
              "am %s durch /mind-cleaner --rebuild." % (rel, _heute()))

    # ⛔ AUSSCHNEIDEN, NICHT NEU ZUSAMMENSETZEN.
    #    Die erste Fassung baute `kurz` aus den Rueckgaben von `zerlege()` neu
    #    auf. `zerlege()` ist aber ein SATZ-Trenner, kein Dokumentmodell: die
    #    Leerzeilen fehlen danach, Ueberschrift und Folgeabsatz verschmelzen
    #    beim Wiedereinlesen, und die Gates melden Saetze, die es nie gab.
    #    Gemessen am ersten Trockenlauf (env-vars.md, 26.08.2026): 38 fehlend,
    #    11 erfunden — ohne dass ein einziger Satz verlorengegangen waere.
    #    Was bleibt, bleibt jetzt BYTE-GLEICH: Tabellen, Codebloecke,
    #    Einrueckungen, Leerzeilen.
    kurz = text
    for s, _k in wandert:
        i = kurz.find(s)
        if i < 0:
            return None, None, None, ("Satz nicht wiederfindbar (Umbau "
                                      "abgebrochen): %s" % _norm(s)[:60])
        j = i + len(s)
        # Die Leerzeile hinter dem Satz mitnehmen, sonst sammeln sich Luecken.
        weg = 0
        while weg < 2 and kurz[j:j + len(ze)] == ze:
            j += len(ze)
            weg += 1
        kurz = kurz[:i] + kurz[j:]
    kurz = kurz.rstrip() + ze + ze + zeiger + ze
    archiv = (("# Archiv zu `%s`" % os.path.basename(pfad)) + ze + ze
              + ("Verschoben am %s. NICHTS ist geloescht — `cleaner_ratsche.py "
                 "--entarchiviere <n>` holt es zurueck." % _heute()) + ze + ze
              + (ze + ze).join([s for s, _k in wandert]) + ze)
    return kurz, archiv, ziel, None


def _heute():
    # ⚠ Kein datetime-Import noetig und kein Zeitzonen-Raten: das Datum kommt
    #   aus derselben Quelle wie in der Ratsche.
    import time
    return time.strftime("%d.%m.%Y")


def gate(alt_text, kurz_text, archiv_text, archiv_rel):
    """Vier Gates ueber SATZ-Identitaet. -> (ok, [meldungen])

    ⛔ Laeuft VOR dem Schreiben, gegen Zeichenketten. Ein gebrochenes Gate
       heisst: die Datei wurde NICHT angefasst.
    """
    m = []
    # ⛔ Frontmatter zaehlt NICHT als Satz — es wird uebernommen, nicht bewegt.
    a = set(_norm(s) for s in aus.zerlege(_koerper(alt_text))[0])
    k = set(_norm(s) for s in aus.zerlege(_koerper(kurz_text))[0])
    r = set(_norm(s) for s in aus.zerlege(_koerper(archiv_text))[0])

    # Was der Rebuild selbst hinzufuegt — namentlich, nicht pauschal.
    erlaubt = set()
    for s in (k | r):
        if archiv_rel in s or s.startswith("# Archiv zu") or "Verschoben am" in s:
            erlaubt.add(s)

    fehlt = a - k - r
    if fehlt:
        m.append("1 VOLLSTAENDIG gebrochen: %d Satz/Saetze weder in der "
                 "Kurzfassung noch im Archiv" % len(fehlt))
        for s in sorted(fehlt)[:3]:
            m.append("     %s" % s[:76])

    doppelt = (k & r) - erlaubt
    if doppelt:
        m.append("2 VERSCHOBEN gebrochen: %d Satz/Saetze stehen in BEIDEN "
                 "(kopiert statt verschoben)" % len(doppelt))
        for s in sorted(doppelt)[:3]:
            m.append("     %s" % s[:76])

    erfunden = (k | r) - a - erlaubt
    if erfunden:
        m.append("3 NICHTS ERFUNDEN gebrochen: %d Satz/Saetze standen nicht "
                 "in der Vorlage" % len(erfunden))
        for s in sorted(erfunden)[:3]:
            m.append("     %s" % s[:76])

    if archiv_rel not in kurz_text:
        m.append("4 ZEIGER gebrochen: die Kurzfassung nennt den Archivpfad "
                 "`%s` nicht woertlich" % archiv_rel)

    return (not m), m


def rebuild(projekt, pfad, auto=False, anwenden=False):
    """0 = angewendet oder Vorschlag · 1 = nichts zu tun · 2 = Gate gebrochen."""
    kurz, archiv, ziel, grund = baue(pfad, projekt, auto)
    if grund:
        print("  --  %s: %s" % (os.path.basename(pfad), grund))
        return 1

    alt = _lies(pfad)
    rel = os.path.relpath(ziel, projekt).replace("\\", "/")
    ok, meldungen = gate(alt, kurz, archiv, rel)

    print("  " + "=" * 84)
    print("  REBUILD  %s" % os.path.basename(pfad))
    print("  " + "=" * 84)
    bleibt, wandert, _ = einteilen(pfad, auto)
    print("     bleibt   %3d Satz/Saetze" % len(bleibt))
    print("     wandert  %3d Satz/Saetze  ->  %s" % (len(wandert), rel))
    if not ok:
        print()
        print("  ⛔ GATE GEBROCHEN — die Datei wurde NICHT angefasst.")
        for x in meldungen:
            print("     %s" % x)
        return 2
    print("     ✅ alle vier Gates halten (Satz-Identitaet, vor dem Schreiben)")
    if not anwenden:
        print()
        print("  Vorschlag. Nichts geschrieben. Mit --anwenden ausfuehren.")
        return 0

    # --- ab hier wird geschrieben: erst das Archiv, dann atomar tauschen ----
    rat.archiviere_saetze(projekt, pfad, [s for s, _k in wandert],
                          "rebuild --auto" if auto else "rebuild",
                          rest="\n".join(s for s, _k in bleibt))
    os.makedirs(os.path.dirname(ziel), exist_ok=True)
    with io.open(ziel, "w", encoding="utf-8", newline="") as fh:
        fh.write(archiv)
    tmp = pfad + ".rebuild.tmp"
    with io.open(tmp, "w", encoding="utf-8", newline="") as fh:
        fh.write(kurz)
    os.replace(tmp, pfad)
    print("     ✅ geschrieben. Zurueck: cleaner_ratsche.py --entarchiviere <n>")
    return 0


# ---------------------------------------------------------------- Selbsttest
def selbsttest():
    import tempfile
    d = tempfile.mkdtemp()
    fehler = 0

    def pruef(name, ist, soll):
        nonlocal fehler
        if ist != soll:
            fehler += 1
        print("    %-4s %-52s ist=%-9s soll=%s"
              % ("OK" if ist == soll else "FEHL", name, ist, soll))

    proj = os.path.join(d, "p")
    rules = os.path.join(proj, ".claude", "rules")
    os.makedirs(rules)

    def schreib(n, t):
        p = os.path.join(rules, n)
        with io.open(p, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(t)
        return p

    print("=" * 78)
    print("  Selbsttest — kuerzen heisst verschieben, und die Gates halten")
    print("=" * 78)

    r = schreib("t.md", "\n".join([
        "---", "description: Testregel", "---", "# T", "",
        "- ALWAYS `tools/x.py` vor dem Loeschen aufrufen.", "",
        "- Gemessen 2026-08-01: 12 von 14 Laeufen scheiterten an `xargs`.", "",
        "- Belegt mit 8 Pruefungen in `tests/test_x.sh`, davon 4 rot.", "",
        "- NEVER `git add -A` im Plugin-Repo.", ""]))

    b, w, g = einteilen(r, auto=True)
    pruef("Belege wandern", len(w) > 0, True)
    pruef("Gebote bleiben", all(k != "beleg" for _s, k in b), True)
    pruef("kein Prosa-Satz wandert", all(k != "prosa" for _s, k in w), True)

    kurz, arch, ziel, grund = baue(r, proj, auto=True)
    pruef("baue() liefert etwas", grund, None)
    rel = os.path.relpath(ziel, proj).replace("\\", "/")
    pruef("Zeiger nennt den PFAD", rel in kurz, True)
    ok, m = gate(_lies(r), kurz, arch, rel)
    pruef("alle vier Gates halten", ok, True)

    # --- ⛔ NEGATIVKONTROLLEN: jedes Gate muss BRECHEN koennen -------------
    ok1, m1 = gate(_lies(r), kurz.replace(
        "- Gemessen 2026-08-01: 12 von 14 Laeufen scheiterten an `xargs`.", ""),
        arch.replace(
        "- Gemessen 2026-08-01: 12 von 14 Laeufen scheiterten an `xargs`.", ""), rel)
    pruef("Gate 1 bricht, wenn ein Satz verschwindet", ok1, False)
    pruef("und nennt VOLLSTAENDIG", any("VOLLSTAENDIG" in x for x in m1), True)

    ok2, m2 = gate(_lies(r), kurz + "\n\n- NEVER `git add -A` im Plugin-Repo.\n",
                   arch + "\n\n- NEVER `git add -A` im Plugin-Repo.\n", rel)
    pruef("Gate 2 bricht bei einem Satz in BEIDEN", ok2, False)
    pruef("und nennt VERSCHOBEN", any("VERSCHOBEN" in x for x in m2), True)

    ok3, m3 = gate(_lies(r), kurz + "\n\n- Ein Satz, der nirgends stand.\n",
                   arch, rel)
    pruef("Gate 3 bricht bei einem erfundenen Satz", ok3, False)
    pruef("und nennt ERFUNDEN", any("ERFUNDEN" in x for x in m3), True)

    ok4, m4 = gate(_lies(r), kurz.replace(rel, "irgendein-name"), arch, rel)
    pruef("Gate 4 bricht ohne Pfad-Zeiger", ok4, False)
    pruef("und nennt ZEIGER", any("ZEIGER" in x for x in m4), True)

    # --- ⛔ Die drei Sperren gegen VERTAUSCHUNG ---------------------------
    #     Keine davon kann ein Satz-Identitaets-Gate sehen: kein Satz geht
    #     verloren, und die Gates bleiben gruen.

    # (a) Ueberschrift — gemessen an env-vars.md (26.08.2026): 
    #     '## Was ein Snapshot enthaelt' wanderte mit seinem Absatz ins
    #     Archiv, und die Tabelle darunter blieb ueberschriftenlos zurueck.
    u = schreib("u.md", "# U\n\n## Gemessen 2026-08-01: 12 von 14 Laeufen scheiterten.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n")
    _b, wu, _g = einteilen(u, auto=True)
    pruef("Ueberschrift wandert nie", len(wu), 0)

    # (b) Tabellenzeile — eine mittendrin entnommene Zeile zerreisst die
    #     Tabelle, ohne dass ein Satz fehlt.
    tb = schreib("tb.md", "# T\n\n| Fall | Beleg |\n|---|---|\n| x | Gemessen 2026-08-01: 12 von 14 |\n")
    _b, wt, _g = einteilen(tb, auto=True)
    pruef("Tabellenzeile wandert nie", len(wt), 0)

    # (c) Rueckbezug — POSITIVKONTROLLE mit dem ECHTEN Wortlaut aus
    #     env-vars.md, an dem der Fall aufgefallen ist.
    rb = schreib("rb.md", "# R\n\n**Teilentwarnung seit 17.08.2026:** Gemessen 2026-08-17 liegt das Repo lokal.\n\nDie Luecke im Snapshot bleibt trotzdem bestehen.\n")
    _b, wr, _g = einteilen(rb, auto=True)
    pruef("Satz bleibt, wenn der Folgesatz zurueckzeigt", len(wr), 0)

    # (d) ⛔ NEGATIVKONTROLLE zur selben Schwelle. Ohne sie waere (c) nur
    #     Stille — eine Sperre, die alles sperrt, ist keine.
    #     'davon' bezieht sich hier auf '8 Pruefungen' im SELBEN Satz.
    rn = schreib("rn.md", "# N\n\n- Gemessen 2026-08-01: 12 von 14 Laeufen scheiterten an `xargs`.\n\n- Belegt mit 8 Pruefungen in `tests/test_x.sh`, davon 4 rot.\n")
    _b, wn, _g = einteilen(rn, auto=True)
    pruef("Rueckbezug im SELBEN Satz sperrt nicht", len(wn) > 0, True)

    # --- ⛔ Ausnahmen ------------------------------------------------------
    a = schreib("autonom-arbeiten.md", "# A\n\n- Gemessen: 3 von 4.\n")
    _b, _w, g2 = einteilen(a, auto=True)
    pruef("autonom-arbeiten.md wird uebersprungen", "ausgenommen" in (g2 or ""), True)

    p = schreib("prosa.md", "# P\n\nEin ganz normaler erklaerender Satz ohne alles.\n")
    _b, w2, _g = einteilen(p, auto=True)
    pruef("reine Prosa wandert im auto-Modus nicht", len(w2), 0)

    # --- Zeilenenden -------------------------------------------------------
    c = schreib("crlf.md", "# C\r\n\r\n- Gemessen 2026-08-01: 12 von 14.\r\n"
                           "\r\n- ALWAYS pruefen.\r\n")
    k3, _a3, _z3, _g3 = baue(c, proj, auto=True)
    pruef("CRLF-Datei bleibt CRLF", (k3 or "").count("\r\n") > 0, True)

    print()
    print("=== %d Abweichung(en) ===" % fehler)
    return 1 if fehler else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()
    projekt = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    if "--bereich" in argv:
        i = argv.index("--bereich") + 1
        if i < len(argv):
            projekt = argv[i]
    if not os.path.isdir(projekt):
        print("Projektpfad existiert nicht: %s" % projekt)
        return 2
    auto = "--auto" in argv
    anwenden = "--anwenden" in argv
    dateien = [a for a in argv if not a.startswith("--") and a != projekt]
    if not dateien:
        print("usage: cleaner_rebuild.py --bereich <projekt> <regel.md> "
              "[--auto] [--anwenden]")
        return 2

    # ⛔ EINE DATEI JE LAUF — hier gezaehlt, nicht als Prosa behauptet.
    #    Ein Rebuild schneidet die Wissensbasis. Zwei auf einmal heisst: zwei
    #    Schnitte, die niemand einzeln angesehen hat.
    if len(dateien) > 1:
        print("⛔ EINE Datei je Lauf. Bekommen: %d (%s)"
              % (len(dateien), ", ".join(os.path.basename(x) for x in dateien)))
        return 2

    if anwenden and not auto:
        print("⛔ --anwenden nur zusammen mit --auto. Ohne --auto ist dieser")
        print("   Lauf ein VORSCHLAG — die Auswahl der Saetze gehoert dann dir.")
        return 2
    return rebuild(projekt, dateien[0], auto, anwenden)


if __name__ == "__main__":
    sys.exit(main())
