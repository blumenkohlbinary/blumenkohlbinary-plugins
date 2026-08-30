# -*- coding: utf-8 -*-
"""Das Kontext-Tor — neun Fragen, bevor eine Zeile Dauerkontext kostet.

    Rules, Dokus, CLAUDE.md und Memory existieren AUSSCHLIESSLICH fuer das,
    was Claude nicht ohnehin weiss.

Bis v5.25.0 arbeitete das Plugin nur RUECKWAERTS: es prueft Bestaende, die
schon da sind. Es gab kein Tor beim HINEINschreiben — deshalb waechst alles.

## Die neun Fragen

  A  braucht es die AUSSAGE?      A1 weiss das Modell es ohnehin?
                                  A2 ist es noch wahr?
                                  A3 handlungsleitend — oder Historie?
  B  braucht es sie HIER?         B1 steht es schon woanders?
                                  B2 steht es im Code?
                                  B3 wirkt es an diesem Ort?
  C  traegt die FORM?             C1 ist es hart formuliert?
                                  C2 ist es befolgbar?

⛔ B1/B2/B3 werden hier NICHT nachgebaut. Dafuer gibt es `cleaner_duplikate`,
   `cleaner_aussagen --code` und `cleaner_grenzen`. Die Klasse
   `instrument-nachgebaut` steht mit 7 Vorkommen im Debug-Ordner, Bilanz
   ~250 / 11 / 9 / 7 Fehltreffer — kein einziger Nachbau war besser als das
   Original. Dieses Werkzeug NENNT sie und beantwortet sie nicht selbst.

⚠ A1 und C2 sind URTEILE, keine Messungen. Das Tor kann die Antwort
  ERZWINGEN, nicht sie geben — dieselbe Mechanik wie die Agent-Quittung
  (v5.19.0): sie zwingt keinen Agenten zu arbeiten, sie macht sein Fehlen
  sichtbar. Das hat gereicht.

⛔ Es schreibt NICHTS. Kein Pfad wird angefasst (Gate `v0_schreibt_nichts.py`).

Aufruf:
  python cleaner_tor.py --datei <kontextdatei.md>      rueckwaerts, Bestand
  python cleaner_tor.py --text "<neue zeile>"          vorwaerts, vor dem ADD
  python cleaner_tor.py --memory <projektpfad>         der Memory-Deckel
  python cleaner_tor.py --selbsttest

Rueckgabe: 0 = keine Kandidaten · 1 = Kandidaten vorgelegt · 2 = Aufruffehler
"""
import io
import os
import re
import sys

_HIER = os.path.dirname(os.path.abspath(__file__))
if _HIER not in sys.path:
    sys.path.insert(0, _HIER)

# ⛔ werkzeuge-zuerst.md: die Helfer gibt es schon. `fence_bereiche` und
#    `inhaltszeilen` stammen aus cleaner_leitplanke.py / cleaner_umzug.py.
#
# ⛔ DIESER IMPORT STEHT VOR DEM STDOUT-WAECHTER, UND DAS IST DER GANZE PUNKT.
#    Zwei Module, die BEIDE `sys.stdout` neu umhuellen, teilen sich denselben
#    Puffer — wird eines der Wrapper-Objekte eingesammelt, schliesst es den
#    Puffer des anderen, und jedes weitere print() bricht mit
#    "I/O operation on closed file". `cleaner_leitplanke` huellt
#    BEDINGUNGSLOS ein; ein Waechter auf DIESER Seite hilft deshalb nicht,
#    wenn er vorher laeuft — nur die Reihenfolge hilft.
#    Gemessen 30.08.2026: der Selbsttest starb NACH dem letzten Pruefpunkt
#    und sah dadurch aus wie ein Fehler in der Bilanz statt wie einer im
#    Kopf der Datei. Vier Werkzeuge in `references/` huellen stdout ein.
try:
    from cleaner_leitplanke import fence_bereiche, inhaltszeilen
except ImportError:                                     # pragma: no cover
    def fence_bereiche(zs):
        drin, offen = set(), False
        for i, z in enumerate(zs):
            if z.strip().startswith("```"):
                offen = not offen
                continue
            if offen:
                drin.add(i)
        return drin

    def inhaltszeilen(text):
        t = re.sub(r"^---\n.*?\n---\n", "", text, count=1, flags=re.S)
        return [z for z in t.split("\n") if z.strip()]

# Erst JETZT — und nur, falls der Import es nicht schon getan hat.
_ENC = (getattr(sys.stdout, "encoding", "") or "").lower().replace("-", "")
if _ENC != "utf8":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


# ---------------------------------------------------------------- Marker ---

# Eine PROJEKTMARKE macht eine Zeile spezifisch. Sie ueberlebt eine
# Uebersetzung — dieselbe Auswahl wie in coverage_gate.py, und aus demselben
# Grund: Fliesstext-Substantive sind genau das, was beim Uebersetzen (und beim
# Umformulieren) verschwindet.
_CODE = re.compile(r"`[^`]+`")
# ⛔ Der Laufwerksbuchstabe MUSS mit hinein. Erste Fassung kannte nur
#    `~/…`, `./…` und `/…`; `Z:/daten` galt damit als pfadlos, und C2
#    meldete "NIE mit Edit auf Z:/daten schreiben" als unspezifisch —
#    ausgerechnet eine der konkretesten Regeln des Bestands. Gefunden von
#    der Negativkontrolle, nicht vom Lesen.
_PFAD = re.compile(
    r"[~./][\w./-]*[/\\][\w./-]+"
    r"|\b[A-Za-z]:[/\\][\w./\\-]*"
    r"|\b\w+\.(py|sh|md|json|exe|jsonl)\b")
_ZAHL = re.compile(r"\d")
_CAMEL = re.compile(r"\b\w*[a-z][A-Z]\w*\b")
_ALLCAPS = re.compile(r"\b[A-Z][A-Z0-9_]{2,}\b")
_ZEICHEN = re.compile(r"[⛔⚠⭐✅]")

# Ein GEBOT. Bewusst breit — eine Zeile mit Gebot ist nie Allgemeinwissen.
_GEBOT = re.compile(
    r"\b(NIE|NIEMALS|IMMER|MUSS|MUESSEN|NUR|PFLICHT|KEIN|KEINE|"
    r"NEVER|ALWAYS|MUST|ONLY|"
    r"nie|niemals|immer|muss|muessen|darf|duerfen|verboten)\b")

# ⚠ EVIDENZ-VORBEHALT — hart formulierte Aussagen ueber SCHWACHE BELEGE.
#   Sie sind das Wertvollste in diesem Bestand und werden NIE als weich
#   gemeldet. Der Auftrag lautete "alle Regeln hart, keine Ausnahmen" —
#   aber hart formuliert und ehrlich formuliert sind nicht dasselbe.
#   ⛔ Das Verbotszeichen ⛔ befreit ABSICHTLICH NICHT: "⛔ moeglichst nicht
#      loeschen" ist genau der gemischte Fall, der gehaertet gehoert.
_VORBEHALT = re.compile(
    r"⚠|nicht gemessen|nicht belegt|ungeprueft|ungeklaert|geraten|"
    r"Kandidat|kein Urteil|nicht entscheidbar|unbestaetigt|"
    r"NICHT MESSBAR|heuristisch|Heuristik|vermutlich|offen\b")


def _hat_projektmarke(s):
    """Traegt die Zeile irgendetwas Projektspezifisches?"""
    return bool(_CODE.search(s) or _PFAD.search(s) or _ZAHL.search(s)
                or _CAMEL.search(s) or _ALLCAPS.search(s)
                or _ZEICHEN.search(s))


# ------------------------------------------------------------------- A1 ---

# "<X> ist ein/eine <Y>"  —  die Definitionsform.
_DEFINITION = re.compile(
    r"^\s*(?:[-*]\s*)?[A-ZÄÖÜ][\wÄÖÜäöüß -]{1,40}?\s+"
    r"(?:ist|sind|heisst|bedeutet)\s+"
    r"(?:ein|eine|einer|eines|der|die|das)\b")


def allgemeinwissen(s):
    """A1 — Kandidat fuer 'weiss das Modell ohnehin'.

    Drei Merkmale muessen ALLE zutreffen. Der Nutzer nannte den Massstab:
    *Python ist eine Programmiersprache* · *die Banane ist gelb*.

    ⚠ KANDIDAT, kein Urteil. Ob ein Modell etwas weiss, steht in keiner Datei.
      Das hier ist der EXTREMFALL, nicht die Frage.
    """
    s = s.strip()
    if not _DEFINITION.match(s):
        return False
    if _hat_projektmarke(s):
        return False
    if _GEBOT.search(s):
        return False
    return True


# ------------------------------------------------------------------- A2 ---

# Eine BESTANDSZAHL ohne Zaehlbefehl daneben. Genau die Fehlerklasse, die
# dieses Projekt SECHSMAL getroffen hat (lib.sh-Funktionen 7->12->13->16->37,
# ausgelieferte .py 2 statt 5, Referenzen 11 statt 12).
_BESTANDSZAHL = re.compile(
    r"\b\d+\s+(Skills?|Agents?|Hooks?|Dateien|Funktionen|Referenzen|"
    r"Sammlungen|Regeln|Commands?|Zusicherungen|Prueffaelle|Subdirs?)\b")
_ZAEHLBELEG = re.compile(
    r"wc -l|grep -c|find |ls -1|zaehl_gate|nachgezaehlt|nachgemessen|"
    r"gemessen|gezaehlt|\|\s*wc")


def unbelegte_zahl(s):
    """A2 — eine Bestandszahl, die kein Zaehlbefehl absichert.

    ⚠ Deckt NUR den mechanisch fassbaren Teil von 'ist es noch wahr'.
      Ob eine Aussage inhaltlich ueberholt ist, sieht kein Regex.
      Fuer tote Pfade: `claudemd_pipeline.py`. Fuer nie ueberarbeitete
      Dateien: `cleaner_belege.py` (Ein-Commit-Erkennung).
    """
    s = s.strip()
    if not _BESTANDSZAHL.search(s):
        return False
    return not _ZAEHLBELEG.search(s)


# ------------------------------------------------------------------- A3 ---

# RUECKBLICK auf einen frueheren Zustand. Nicht zu verwechseln mit einem
# BELEG ("gemessen am 21.08.") — der stuetzt eine geltende Aussage.
_HISTORIE = re.compile(
    r"stand (hier|bis|dort)|hiess (bis|es)|lautete|war bis|"
    r"[Bb]is v\d+\.\d+|frueher stand|vorher stand|"
    r"in der ersten Fassung|die erste Fassung|bis zum \d|"
    r"ist ENTFALLEN|wurde ersetzt|ist widerlegt|war falsch")


def historie(s):
    """A3 — Rueckblick statt Anweisung.

    ⚠ Das ist KEIN Muell — es ist am falschen ORT. Die Herleitung verhindert,
      dass ein behobener Fehler wiederkommt. Aber sie gehoert in
      `design-history.md` / ins Archiv, das BEI BEDARF gelesen wird, nicht in
      den DAUERKONTEXT, der bei jeder Anfrage zaehlt.

    Ein Rueckblick MIT Gebot bleibt: "Bis v5.20.2 stand hier NIE kuerzen —
    das gilt nicht mehr" traegt die geltende Anweisung mit.
    """
    s = s.strip()
    if not _HISTORIE.search(s):
        return False
    return not _GEBOT.search(s)


# ------------------------------------------------------------------- C1 ---

# ⛔ re.I ist PFLICHT, nicht Bequemlichkeit. Ohne sie blieb
#    "Moeglichst nicht loeschen" (Satzanfang, grosses M) unerkannt, waehrend
#    "man sollte …" mitten im Satz ansprang — der Detektor haette also genau
#    die Zeilen verfehlt, die als eigener Satz dastehen, und das sind die
#    Regeln. Gefunden von der Positivkontrolle.
_WEICH = re.compile(
    r"\b(sollte|solltest|sollten|moeglichst|möglichst|"
    r"nach Moeglichkeit|nach Möglichkeit|im Idealfall|"
    r"es empfiehlt sich|empfiehlt sich|waere gut|wäre gut|"
    r"waere sinnvoll|wäre sinnvoll|man kann|kann man|"
    r"eventuell|gegebenenfalls|ruhig mal|am besten)\b", re.I)


def weich(s):
    """C1 — ein Gebot in weicher Form.

    Nutzer-Auftrag 30.08.2026: *alle Regeln sollen hart formuliert sein,
    keine Ausnahmen*.

    ⛔ MIT EINER EINSCHRAENKUNG, die ich ihm ausdruecklich widersprochen habe:
       ein EVIDENZ-VORBEHALT ist keine weiche Regel. `⚠ Beide Schwellen sind
       GERATEN, nicht gemessen` ist eine HARTE Aussage ueber einen SCHWACHEN
       Beleg — und genau das unterscheidet diesen Bestand von einer Sammlung
       Behauptungen. Ein Detektor, der sie frisst, macht ihn schlechter.

    Der Test ist die HANDLUNG, nicht der Ton: weiss ich nach dem Satz, was
    ich TUN soll? Dann ist er hart, auch mit Vorbehalt.
    """
    s = s.strip()
    m = _WEICH.search(s)
    if not m:
        return False
    if _VORBEHALT.search(s):
        return False
    # ⛔ NEBENSATZ ist keine Regel. Im deutschen HAUPTsatz steht das
    #    Modalverb an zweiter Stelle ("man sollte VORHER sichern"), im
    #    NEBENsatz am Ende ("den Befund, den der Agent finden sollte.").
    #    Nur der Hauptsatz spricht den Leser an; der Nebensatz beschreibt.
    #    ⚠ GEMESSEN, nicht ausgedacht: ohne diese Regel waren BEIDE C1-Treffer
    #      im ganzen Skill-Bestand Fehlalarme (mind-all Z316, mind-update Z990
    #      — zweimal derselbe Satz "den Befund, den der Agent finden sollte").
    #      Ein Detektor mit 2 Treffern und 2 Fehlalarmen ist keiner.
    if re.match(r"[\s]*[.!?,;:)\]]|[\s]*$", s[m.end():]):
        return False
    return True


# ------------------------------------------------------------------- C2 ---

_BEDINGUNG = re.compile(
    r"\b(wenn|bevor|ab |sobald|falls|solange|nachdem|vor jedem|vor jeder|"
    r"bei |ohne )")


def unspezifisch(s):
    """C2 — ein Gebot ohne pruefbare Handlung.

    *Sei vorsichtig bei Dateioperationen* ist hart formuliert und trotzdem
    wertlos: es nennt keine Handlung, kein Werkzeug, keine Bedingung. Eine
    Regel ohne benanntes Verhalten ist Dekoration und kostet dasselbe wie
    eine, die traegt.

    ⚠ SCHWAECHSTE der neun Fragen — hohe Fehlalarmquote. Sie wird deshalb
      GETRENNT ausgewiesen und steht im Bericht hinter allen anderen.
    """
    s = s.strip()
    if not _GEBOT.search(s):
        return False
    if _CODE.search(s) or _PFAD.search(s):
        return False
    if _BEDINGUNG.search(s):
        return False
    return True


# ---------------------------------------------------------------- Pruefer ---

_FRAGEN = [
    ("A1", "allgemeinwissen", allgemeinwissen,
     "weiss das Modell ohnehin?"),
    ("A2", "unbelegte-zahl", unbelegte_zahl,
     "Bestandszahl ohne Zaehlbefehl — ist sie noch wahr?"),
    ("A3", "historie", historie,
     "Rueckblick statt Anweisung — gehoert ins Archiv"),
    ("C1", "weich", weich,
     "Gebot in weicher Form"),
]
_NACHRANGIG = [
    ("C2", "unspezifisch", unspezifisch,
     "Gebot ohne pruefbare Handlung (hohe Fehlalarmquote)"),
]


def pruefe_text(text):
    """-> {kuerzel: [(zeilennr, ausschnitt)]}  ueber einen ganzen Dateitext."""
    zs = text.split("\n")
    im_fence = fence_bereiche(zs)
    aus = {}
    for i, z in enumerate(zs):
        s = z.strip()
        if not s or s.startswith("```") or i in im_fence:
            continue
        if s.startswith("|") or s.startswith("---") or s.startswith(">"):
            # Tabellenzeilen, Trenner und Zitate: die Form traegt hier
            # andere Bedeutung. Fail-safe Richtung BEHALTEN.
            continue
        for kuerzel, _n, fn, _b in _FRAGEN + _NACHRANGIG:
            if fn(s):
                aus.setdefault(kuerzel, []).append((i + 1, s[:88]))
    return aus


def _verweise():
    print()
    print("  B1  steht es schon woanders / ist es doppelt?")
    print("      python cleaner_duplikate.py --bereich <projekt>")
    print("  B2  steht es im Code?")
    print("      python cleaner_aussagen.py --code <quellbaum>")
    print("  B3  wirkt es an diesem Ort?")
    print("      python cleaner_grenzen.py --bestand <projekt>")
    print("  ⛔ Diese drei werden hier NICHT nachgebaut — es gibt sie.")


def lauf_datei(pfad):
    if not os.path.isfile(pfad):
        print("⛔ keine Datei: %s" % pfad)
        return 2
    text = open(pfad, encoding="utf-8", errors="replace").read()
    treffer = pruefe_text(text)
    n_inhalt = len(inhaltszeilen(text))

    print("=" * 72)
    print("KONTEXT-TOR  —  %s" % os.path.basename(pfad))
    print("=" * 72)
    print("  %d Inhaltszeilen" % n_inhalt)
    print()

    gesamt = 0
    for kuerzel, _n, _fn, bedeutung in _FRAGEN:
        tr = treffer.get(kuerzel, [])
        gesamt += len(tr)
        print("  %-3s %-3d  %s" % (kuerzel, len(tr), bedeutung))
        for nr, s in tr[:6]:
            print("         Z%-5d %s" % (nr, s))
        if len(tr) > 6:
            print("         … %d weitere" % (len(tr) - 6))

    print()
    print("  ── nachrangig, hohe Fehlalarmquote ─────────────────────────")
    for kuerzel, _n, _fn, bedeutung in _NACHRANGIG:
        tr = treffer.get(kuerzel, [])
        print("  %-3s %-3d  %s" % (kuerzel, len(tr), bedeutung))
        for nr, s in tr[:3]:
            print("         Z%-5d %s" % (nr, s))

    _verweise()
    print()
    print("  ⚠ KANDIDATEN, keine Urteile. A1 und C2 sind Bedeutungsfragen;")
    print("    mechanisch entscheidbar sind nur Formmerkmale.")
    return 1 if gesamt else 0


def lauf_text(s):
    """Vorwaerts: eine geplante Ergaenzung, VOR dem ADD."""
    print("=" * 72)
    print("KONTEXT-TOR  —  geplante Ergaenzung")
    print("=" * 72)
    print("  %s" % s[:120])
    print()
    offen = 0
    for kuerzel, _n, fn, bedeutung in _FRAGEN + _NACHRANGIG:
        t = fn(s)
        print("  %-3s %-9s %s" % (kuerzel, "KANDIDAT" if t else "frei",
                                  bedeutung))
        offen += 1 if t else 0
    _verweise()
    print()
    print("  Quittung fuer den Lauf (in den Bericht, sonst Teilsync):")
    print("    tor=<datei>:A1/A2/A3:B1/B2/B3:C1/C2")
    return 1 if offen else 0


# ------------------------------------------------------- der Memory-Deckel ---

# ⛔ GESETZT, nicht gemessen — und deshalb Regler. Herkunft steht daneben,
#    wie bei den drei v5.5.0-Reglern: eine hartkodierte Zahl aus einer
#    unbestaetigten Quelle ist eine Behauptung.
MAX_GRUEN = int(os.environ.get("MIND_MEMORY_MAX_GRUEN", "15"))
MAX_GELB = int(os.environ.get("MIND_MEMORY_MAX_GELB", "25"))
DESC_MIN = int(os.environ.get("MIND_MEMORY_DESC_MIN", "40"))
DESC_MAX = int(os.environ.get("MIND_MEMORY_DESC_MAX", "200"))


def _desc(pfad):
    try:
        t = open(pfad, encoding="utf-8", errors="replace").read(4000)
    except OSError:
        return ""
    m = re.search(r"^description:\s*(.+?)\s*$", t, re.M)
    return (m.group(1).strip().strip('"') if m else "")


def lauf_memory(mdir):
    """T2 — der Deckel. Er stuetzt sich auf die GRENZE 5, nicht auf Ladungen.

    ⛔ 'wird nicht mehr geladen' ist NICHT messbar. Gemessen 30.08.2026:
       139 Topic-Dateien ueber 14 Projekte, 0 auffindbare Abrufe — aber die
       POSITIVKONTROLLE faellt durch (`claudeMd`, `auto-memory` ebenfalls 0).
       Der eingespielte Kontext steht gar nicht im Transkript. Ein Deckel auf
       beobachteten Ladungen waere ein Instrument, das nichts misst.

    Belegt ist stattdessen (woertlich in claude.exe 2.1.237):
       "Return a list of filenames ... (up to 5). Only include memories that
        you are certain will be helpful based on their name and description."
    """
    if not os.path.isdir(mdir):
        print("⛔ kein Verzeichnis: %s" % mdir)
        return 2
    topics = sorted(f for f in os.listdir(mdir)
                    if f.endswith(".md") and f != "MEMORY.md")
    n = len(topics)

    print("=" * 72)
    print("MEMORY-DECKEL  —  %s" % mdir)
    print("=" * 72)
    if n <= MAX_GRUEN:
        ampel, rc = "gruen", 0
    elif n <= MAX_GELB:
        ampel, rc = "gelb", 1
    else:
        ampel, rc = "ROT", 1
    print("  %d Topic-Dateien   ->   %s   (gruen<=%d, gelb<=%d)"
          % (n, ampel, MAX_GRUEN, MAX_GELB))
    print("  Auswaehler nimmt hoechstens 5 je ANFRAGE und wiederholt nicht;")
    print("  ueber eine Sitzung sammelt sich die Abdeckung also an.")

    schwach = []
    for f in topics:
        d = _desc(os.path.join(mdir, f))
        if len(d) < DESC_MIN:
            schwach.append((len(d), f, "zu kurz"))
        elif len(d) > DESC_MAX:
            schwach.append((len(d), f, "zu lang"))
    if schwach:
        print()
        print("  ⭐ Der wirksamere Hebel ist die `description`, nicht die Zahl —")
        print("     sie ist der EINZIGE Zugang des Auswaehlers (er sieht nie")
        print("     den Inhalt). %d von %d sind ausserhalb %d-%d Zeichen:"
              % (len(schwach), n, DESC_MIN, DESC_MAX))
        for laenge, f, warum in sorted(schwach, reverse=True)[:8]:
            print("       %4d  %-11s %s" % (laenge, warum, f))
        rc = 1
    if ampel == "ROT":
        print()
        print("  ⛔ ROT: ein ADD nur noch gegen Zusammenfuehrung — eine rein,")
        print("     eine raus. Vorher sichern, danach `memory_gates.py`.")
    print()
    print("  ⛔ Die drei Zahlen sind GESETZT, nicht gemessen. Regler:")
    print("     MIND_MEMORY_MAX_GRUEN / _MAX_GELB / _DESC_MIN / _DESC_MAX")
    print("  ⚠ Der Deckel belegt NICHT, dass eine Datei nie ausgewaehlt wurde.")
    return rc


# ------------------------------------------------------------ Selbsttest ---

def _ja(name, ist, soll):
    ok = (ist == soll)
    print("  %s  %s" % ("OK  " if ok else "FEHL", name))
    if not ok:
        print("        erwartet %s, war %s" % (soll, ist))
    return ok


def selbsttest():
    """⛔ JE FRAGE ein eigener Fall, mit EINEM Signal.

    Die v5.20.0-Lehre, teuer bezahlt: ein Prueffall mit zwei Signalen belegt
    nur, dass EINES lebt. Damals waren drei Fassungen nacheinander gruen und
    trotzdem blind.

    Und je Frage eine NEGATIVKONTROLLE — ein Detektor, der nichts findet,
    besteht jede Negativprobe. Ohne Positivfall waere er unsichtbar kaputt.
    """
    print("=" * 72)
    print("SELBSTTEST  cleaner_tor.py")
    print("=" * 72)
    ok = []

    print("\n A1 — weiss das Modell es ohnehin?")
    ok.append(_ja("positiv: 'Python ist eine Programmiersprache'",
                  allgemeinwissen("Python ist eine Programmiersprache."), True))
    ok.append(_ja("positiv: 'Die Banane ist eine Frucht'",
                  allgemeinwissen("Die Banane ist eine Frucht."), True))
    ok.append(_ja("negativ: Definition MIT Code-Marke bleibt",
                  allgemeinwissen("`jq` ist ein Werkzeug fuer JSON."), False))
    ok.append(_ja("negativ: Definition MIT Gebot bleibt",
                  allgemeinwissen("Z: ist ein Mount und darf nie beschrieben "
                                  "werden."), False))
    ok.append(_ja("negativ: Anweisung ist keine Definition",
                  allgemeinwissen("Sichere vor jedem Loeschen."), False))
    ok.append(_ja("negativ: Definition MIT Zahl bleibt",
                  allgemeinwissen("Ein Snapshot ist eine Kopie von 3 Staenden."),
                  False))

    print("\n A2 — Bestandszahl ohne Zaehlbefehl")
    ok.append(_ja("positiv: '5 Hooks' ohne Beleg",
                  unbelegte_zahl("Das Plugin hat 5 Hooks."), True))
    ok.append(_ja("negativ: dieselbe Zahl MIT Zaehlbefehl",
                  unbelegte_zahl("5 Hooks — nachzaehlen mit ls hooks/ | wc -l"),
                  False))
    ok.append(_ja("negativ: dieselbe Zahl MIT 'gemessen'",
                  unbelegte_zahl("5 Hooks, gemessen 27.08.2026."), False))
    ok.append(_ja("negativ: Zahl ohne Bestandswort",
                  unbelegte_zahl("Die Schwelle liegt bei 5 Minuten."), False))

    print("\n A3 — Rueckblick statt Anweisung")
    ok.append(_ja("positiv: 'Hier stand bis gestern X'",
                  historie("Hier stand bis 27.08. eine andere Zahl."), True))
    ok.append(_ja("positiv: 'Bis v5.20.2 lautete es anders'",
                  historie("Bis v5.20.2 lautete der Satz anders."), True))
    ok.append(_ja("negativ: Rueckblick MIT geltendem Gebot bleibt",
                  historie("Bis v5.20.2 stand hier NIE kuerzen — das gilt "
                           "nicht mehr."), False))
    ok.append(_ja("negativ: ein BELEG ist kein Rueckblick",
                  historie("Gemessen am 21.08.2026 an vier Projekten."), False))

    print("\n C1 — Gebot in weicher Form")
    ok.append(_ja("positiv: 'man sollte vorher sichern'",
                  weich("Man sollte vorher sichern."), True))
    ok.append(_ja("positiv: 'moeglichst nicht loeschen'",
                  weich("Moeglichst nicht loeschen."), True))
    ok.append(_ja("⛔ positiv: ⛔ befreit NICHT — der gemischte Fall",
                  weich("⛔ Moeglichst nicht loeschen."), True))
    ok.append(_ja("⭐ negativ: EVIDENZ-VORBEHALT ist NICHT weich",
                  weich("⚠ Beide Schwellen sind geraten, man kann sie "
                        "korrigieren."), False))
    ok.append(_ja("⭐ negativ: 'nicht gemessen' ist NICHT weich",
                  weich("Der Betrag ist nicht gemessen, man kann ihn nur "
                        "schaetzen."), False))
    ok.append(_ja("negativ: hartes Gebot",
                  weich("NIE mit Edit auf Z: schreiben."), False))
    ok.append(_ja("⭐ negativ: NEBENSATZ (Modalverb am Ende) ist keine Regel",
                  weich("den Befund geliefert, den der Agent finden sollte."),
                  False))
    ok.append(_ja("positiv: HAUPTSATZ mit demselben Wort bleibt Kandidat",
                  weich("Der Agent sollte den Befund liefern."), True))

    print("\n C2 — Gebot ohne pruefbare Handlung")
    ok.append(_ja("positiv: 'NIE unvorsichtig sein'",
                  unspezifisch("NIE unvorsichtig sein."), True))
    ok.append(_ja("negativ: Gebot MIT Pfad",
                  unspezifisch("NIE mit Edit auf Z:/daten schreiben."), False))
    ok.append(_ja("negativ: Gebot MIT Bedingung",
                  unspezifisch("NIE loeschen, bevor gesichert wurde."), False))
    ok.append(_ja("negativ: Gebot MIT Code-Marke",
                  unspezifisch("NIE `git add -A` benutzen."), False))

    print("\n Textlauf — Fences und Tabellen werden uebersprungen")
    t = ("Python ist eine Programmiersprache.\n"
         "```\nBash ist eine Shell.\n```\n"
         "| Ruby ist eine Sprache | x |\n")
    tr = pruefe_text(t)
    ok.append(_ja("nur die freie Zeile zaehlt (1 Treffer A1)",
                  len(tr.get("A1", [])), 1))

    n_ok = sum(1 for x in ok if x)
    print()
    print("=" * 72)
    print("  %d/%d gruen" % (n_ok, len(ok)))
    print("=" * 72)
    return 0 if n_ok == len(ok) else 1


def main(argv=None):
    a = list(sys.argv[1:] if argv is None else argv)
    if "--selbsttest" in a:
        return selbsttest()
    for flag, fn in (("--datei", lauf_datei), ("--text", lauf_text),
                     ("--memory", lauf_memory)):
        if flag in a:
            i = a.index(flag)
            if i + 1 >= len(a):
                print("⛔ %s braucht ein Argument" % flag)
                return 2
            return fn(a[i + 1])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
