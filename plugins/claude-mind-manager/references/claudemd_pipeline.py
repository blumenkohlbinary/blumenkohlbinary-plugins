#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Die deterministische Pruef-Pipeline aus mind-claudemd Step 4c — AUSFUEHRBAR (NEU v5.7.0).

⛔ WARUM ES DIESE DATEI GIBT — der teuerste wiederkehrende Fehler dieses Projekts.

Step 4c beschreibt seit v5.4.0 eine Pipeline aus 24 Checks. Sie stand dort als PROSA, ohne
ausfuehrbares Skript. Jeder Lauf baute sie neu — und baute die schon behobenen Fehler mit.
Erhebung ueber 16 Laufabschnitte in zwei listeverbesserungen.md: "instrument-nachgebaut" ist
mit ~25 Vorkommen die mit Abstand haeufigste Ursachenklasse, DREIMAL IN FOLGE derselbe Fall:

  20.08.2026  Nachbau meldete 11 Slash-Commands als tote Pfade
  20.08.2026  zweiter Anlauf: Nachbar-Repo-Pfad blieb faelschlich DEAD
  21.08.2026  Nachbau meldete 9 tote Pfade — echte tote Pfade: 0

Alle drei Fehler waren im Plugin laengst behoben: `classify_path()` in mind-update Step 3b
kennt das Auslassungszeichen, die Markdown-Link-Syntax und Slash-Commands seit v5.3.1.
Der Nachbau kannte sie nie. Deshalb wird die Funktion hier PORTIERT, nicht neu erfunden —
Zeile fuer Zeile, samt der Begruendungen, warum jede SKIP-Regel existiert.

Vorbild: references/session_sampler.py (v5.0.0) und arbeitsstand_render.py (v5.6.0) — beide
liegen aus demselben Grund als Datei bei und nicht als Heredoc im Skill.

AUFRUF
    python claudemd_pipeline.py <ziel.md> --projekt <verzeichnis> [--json]
    python claudemd_pipeline.py --selbsttest        # Instrument gegen sich selbst

RUECKGABE
    0 = gemessen, keine Befunde   1 = Befunde   2 = Aufrufasfehler
    3 = MESSUNG UNGUELTIG (Instrumentenkontrolle durchgefallen)
"""
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", newline="")


def _md_rekursiv(d):
    """Alle .md unter d, REKURSIV, sortiert.

    ⛔ Bis v5.20.1 stand hier ueberall `os.listdir` — flach. Ein Unterordner
       (etwa ein `archive/`) war damit unsichtbar. Genau daran hing der
       teuerste Einzelbefund dieses Bestands: am 23.08.2026 kamen **267 von
       920** Ladevorgaengen aus einem `archive/`-Ordner, der angelegt worden
       war, UM den Bestand zu kuerzen.

    ⭐ Nicht nachgebaut: dieselbe Schleife steht seit v5.17.0 in
       cleaner_ratsche.py:90 (`geladene_dateien`).
    """
    aus = []
    if not os.path.isdir(d):
        return aus
    for wurzel, _dirs, dateien in os.walk(d):
        for f in dateien:
            if f.endswith(".md"):
                aus.append(os.path.join(wurzel, f))
    return sorted(aus)

# ---------------------------------------------------------------------------
# Check 3 — Emoji. NIE nach Unicode-Kategorie.
# ---------------------------------------------------------------------------
# ⛔ Der Fehlgriff, den diese Zeilen verhindern: ein Zaehler nach Kategorie `So`/`Sk` uebersieht
#    `→` (Kategorie Sm) und schlaegt gleichzeitig bei `—` an. Deshalb feste Bereiche.
# ⚠ Bewusste Entscheidung: die SEMANTISCHEN Marker dieses Projekts sind KEIN Befund.
#    ⛔ ⚠ ✅ ❌ ⏭ tragen hier Bedeutung (Verbot, Warnung, erledigt, offen, Fortsetzung) und
#    stehen in jeder Regeldatei. Wer sie als Emoji meldet, erzeugt Rauschen statt Messung.
PIKTOGRAMME = [(0x1F300, 0x1FAFF)]
DEKORATIV = {0x2728, 0x26A1, 0x2600, 0x2601, 0x2604, 0x2615, 0x263A, 0x2665, 0x2764,
             0x270C, 0x270A, 0x261D, 0x1F44D}
MARKER_ERLAUBT = {0x26D4, 0x26A0, 0x2705, 0x274C, 0x23ED, 0x2192, 0x2014, 0x2026,
                  0x00B7, 0x2B50}   # ⭐ = „besonders wichtig“, gemessen am Regelwerk 21.08.2026


def ist_emoji(zeichen):
    o = ord(zeichen)
    if o in MARKER_ERLAUBT:
        return False
    if o in DEKORATIV:
        return True
    return any(a <= o <= b for a, b in PIKTOGRAMME)


# ---------------------------------------------------------------------------
# classify_path — PORTIERT aus skills/mind-update/SKILL.md Step 3b, v5.3.1
# ---------------------------------------------------------------------------
TLD = r"(com|de|org|net|io|dev|ai|co|eu|info)"
_WEB = re.compile(r"(^|/)([a-z0-9-]+\.)+" + TLD + r"(/|$)", re.I)
_PROTO = re.compile(r"^(https?|ftp|mailto|file)://", re.I)


def _ohne_zeilennummer(p):
    """`hooks/lib.sh:104-106` -> `hooks/lib.sh`. Sonst unveraendert.

    ⛔ EINE Quelle fuer Einordner UND Aufrufer. Die erste Fassung (26.08.2026)
       hatte die Regel nur im Einordner: der klassifizierte dann korrekt CHECK,
       und der Aufrufer prueste danach den ungekuerzten String auf Existenz —
       der Pfad blieb "tot", nur ueber einen anderen Weg. Halb repariert ist
       hier nicht besser als gar nicht: die Zahl bewegt sich nicht, und der
       naechste Lauf haelt den Fall fuer ungeloest.
    """
    m = re.fullmatch(r"(.+\.[A-Za-z0-9]{1,8}):\d+(?:-\d+)?", p)
    return m.group(1) if m else p


def classify_path(p):
    """SKIP | UNSURE | CHECK — Wortlaut und Reihenfolge wie in mind-update Step 3b."""
    # 0) NORMALISIEREN: Zitat mit Zeilennummer (NEU 26.08.2026).
    #    `hooks/lib.sh:104-106` ist ein ECHTER Pfad mit einer Fundstellenangabe.
    #    SKIP waere hier falsch — der Pfad davor soll sehr wohl geprueft werden.
    #    Deshalb abschneiden und mit dem Rest weitermachen, nicht ueberspringen.
    p = _ohne_zeilennummer(p)
    # 0a) SKIP: Leerzeichen UNMITTELBAR VOR dem Schraegstrich (NEU 26.08.2026).
    #     Ein Pfadtrenner hat NIE ein Leerzeichen davor — auch nicht auf Windows.
    #     Gefangen werden damit die Ausgabezeile `gefunden / gefahren / gruen`
    #     (tests/alle.sh) und Befehlsschalter wie `rmdir /s /q`.
    #     ⚠ ENG gefasst mit Absicht: der Selbsttest fuehrt
    #       ("APP - Zustellplan/dist", "CHECK") — einen echten Pfad MIT
    #       Leerzeichen. Dort steht vor dem Schraegstrich keines.
    if re.search(r"\s/", p):
        return "SKIP"
    # 0b) SKIP: Shell-Umleitung (NEU 26.08.2026). `2>/dev/null`, `>/dev/null`.
    #     Der Schraegstrich gehoert zum Ziel der Umleitung, der Span ist ein
    #     Befehlsfragment — Check 14 ist dafuer zustaendig, nicht Check 13.
    if re.search(r"\d*>\s*/", p):
        return "SKIP"
    # 1) SKIP: Web-Adresse ohne Protokoll
    if _WEB.search(p):
        return "SKIP"
    # 2) SKIP: Protokoll explizit
    if _PROTO.search(p):
        return "SKIP"
    # 3) SKIP: abgekuerztes Beispiel oder Platzhalter.
    #    '…' (U+2026) steht hier SEIT v5.3.1 und wurde von jedem Nachbau verloren.
    #    '[' + '](' ebenfalls: `[name](../../references/file.md)` enthaelt keines der anderen
    #    Zeichen, wurde also CHECK -> nicht gefunden -> DEAD -> und bei <=5 Findings AUTONOM
    #    GELOESCHT. Genau diese Zeile steht in der CLAUDE.md dieses Projekts.
    if ("…" in p or "..." in p or ("<" in p and ">" in p)
            or ("{" in p and "}" in p) or "$" in p or "*" in p
            or ("[" in p and "](" in p)):
        return "SKIP"
    # 3y) SKIP: Interpreter-AUFRUF, kein zu pruefender Pfad (aus dem Zustellplan-Lauf,
    #     21.08.2026). `.venv/Scripts/python` und `/usr/bin/python` sind Befehle und
    #     gehoeren an Check 14, nicht an 13. Dort meldete Check 13 elf tote Pfade,
    #     echte tote Pfade: null — dieselbe Fehlerklasse zum vierten Mal.
    if re.search(r'/(Scripts|\.?bin)/(python|python3|node|bash|sh)[0-9.]*$', p):
        return 'SKIP'
    # 3z) SKIP: Escape-Sequenz, Code-Fragment, Endungspaar (NEU 21.08.2026).
    #     Aufgedeckt am Lauf gegen die globale CLAUDE.md: dort galten \n, \r, \v,
    #     \udc90, `"hooks": "hooks/hooks.json"` und `.tsx/.jsx` als tote Pfade. Alle tragen
    #     einen Schraegstrich oder Backslash und kamen deshalb bis hierher durch.
    if re.fullmatch(r'(\\+[a-zA-Z0-9]{1,8})+', p):
        return 'SKIP'                      # reine Escape-Sequenz
    if re.search(r'\\x[0-9a-fA-F]{2}|\\u[0-9a-fA-F]{4}', p):
        return 'SKIP'                      # Hex-/Unicode-Escape im Span
    if '"' in p or "'" in p:
        return 'SKIP'                      # Code- oder JSON-Fragment, kein Pfad
    if all(t.startswith('.') for t in p.split('/') if t):
        return 'SKIP'                      # Endungspaar wie .tsx/.jsx
    # 3x) SKIP: Fortschrittsanzeige oder Verhaeltnis (`◐ 2/8`, `3/10`).
    #     Ein Span, dessen Segmente rein numerisch sind, ist nie ein Dateipfad.
    _teile = [t for t in re.split(r'[/\\]', p) if t]
    if _teile and all(re.fullmatch(r'\d+', t.strip()) for t in _teile):
        return 'SKIP'
    if re.match(r'^[^a-zA-Z0-9\s]\s', p):    # fuehrendes Symbol wie ◐
        return 'SKIP'
    # 3a) SKIP: FORMEL, kein Pfad (NEU nach dem ersten echten Lauf, 21.08.2026).
    #     `min(Fenster-12 %, Fenster x Prozent/100, Fenster-13000)` hat einen
    #     Schraegstrich und keines der Zeichen aus 3). Ein Span mit Leerzeichen UND
    #     Klammern ist nie ein Dateipfad — Pfade mit Leerzeichen haben keine Klammerpaare.
    if ' ' in p and (('(' in p and ')' in p) or ',' in p or '=' in p):
        return 'SKIP'
    # 3b) SKIP: Slash-Command — fuehrender /, GENAU ein Segment, MIT Bindestrich.
    #     ⛔ Kriterium bewusst ENG: NICHT "ein Segment ohne Punkt" — das verschluckte
    #     /etc, /tmp, /usr, /var, /opt. Der Bindestrich trennt Befehlsnamen sauber ab.
    #     EHRLICHER PREIS: ein wirklich toter Pfad der Form /foo-bar wird nicht gelistet.
    if p.count("/") == 1 and p.startswith("/") and "-" in p[1:]:
        return "SKIP"
    # 3w) UNSURE: schlichte Woerter ohne Punkt, mit Schraegstrich getrennt
    #     (`actual/expected`, `ja/nein`, `a/b/c`, `UPDATE/ENRICH/ADD`).
    #     Ein echter Dateipfad traegt fast immer eine Endung. Ohne Punkt und ohne
    #     Verzeichnis-Anmutung ist DEAD zu scharf — UNSURE meldet, ohne zu behaupten.
    #
    # ⛔ v5.13.0 — die Bedingung lautete `p.count('/') == 1` und griff damit NUR
    #    bei genau ZWEI Segmenten. Eine Aufzaehlung mit drei Gliedern rutschte
    #    durch und wurde als toter Pfad gemeldet:
    #        a/b/c · UPDATE/ENRICH/ADD · Nutzer/Tester/Betreiber
    #    GEMESSEN im Zustellplan-Lauf vom 21.08.2026: 10 bis 21 Fehltreffer JE
    #    REGELDATEI. Sie ertraenken die echten Befunde — eine Pruefung, deren
    #    Ausgabe zu 95 % aus Rauschen besteht, wird nicht mehr gelesen.
    #    Aus `== 1` wird `>= 1`: eine Aufzaehlung wird nicht dadurch zum Pfad,
    #    dass sie ein Glied mehr hat.
    #
    # ⚠ Umlaute gehoeren in die Zeichenklasse. `Groesse/Anzahl` faellt sonst
    #   durch, sobald es jemand mit ö schreibt — und genau solche Woerter stehen
    #   in deutschen Regeldateien.
    #
    # ⚠ NICHT abgedeckt und bewusst so: `dist/unstable/_build_counter`. Der
    #   Unterstrich macht das Segment zu keinem schlichten Wort, der Pfad bleibt
    #   CHECK. Das ist ein anderer Befund (die Datei existiert wirklich nicht,
    #   weil sie beim Release geloescht wird) und braucht eine andere Loesung —
    #   hier wird er nicht miterschlagen, nur weil es bequem waere.
    if '.' not in p and p.count('/') >= 1 and not p.startswith('/'):
        if all(re.fullmatch(r'[a-zA-ZäöüÄÖÜß]+', t) for t in p.split('/') if t):
            return 'UNSURE'
    # 4) UNSURE: fuehrender / ohne Laufwerk/MSYS-Wurzel
    if p.startswith("/"):
        if re.match(r"^/[a-z]/", p) or p == "/":
            pass
        else:
            return "UNSURE"
    return "CHECK"


# ---------------------------------------------------------------------------
# Schritt 0 — Vorverarbeitung (PFLICHT vor jedem Check)
# ---------------------------------------------------------------------------
def vorverarbeiten(text):
    """(zeilen, ohne_fences, bullet_einheiten) — alle drei Schritte aus Step 4c Schritt 0.

    Alle drei sind real passiert, am 2026-08-18 beim Bau genau dieser Pruefungen.
    """
    zeilen = text.split("\n")
    ohne, drin = [], False
    for z in zeilen:
        if z.lstrip().startswith("```"):
            drin = not drin
            ohne.append(None)
            continue
        ohne.append(None if drin else z)

    # 0.2 mehrzeilige Bullets zu EINER Einheit — sonst meldet Check 7 falsch:
    #     das NEVER steht auf Zeile 1, die Alternative auf Zeile 2.
    einheiten, akt, nr = [], None, 0
    for i, z in enumerate(ohne, 1):
        if z is None:
            continue
        if re.match(r"^\s*([-*+]\s|\d+\.\s)", z):
            if akt is not None:
                einheiten.append((nr, akt))
            akt, nr = z, i
        elif akt is not None and z.startswith("  ") and z.strip():
            akt += " " + z.strip()
        else:
            if akt is not None:
                einheiten.append((nr, akt))
            akt = None
    if akt is not None:
        einheiten.append((nr, akt))
    return zeilen, ohne, einheiten


SEKTIONEN = [
    ("Uebersicht", True, ("übersicht", "ubersicht", "overview", "projekt", "project",
                          "zweck", "purpose", "about")),
    ("Commands", True, ("command", "befehl", "build", "test", "script", "entwicklung",
                        "development")),
    ("Architektur", True, ("architekt", "architecture", "struktur", "structure", "aufbau",
                           "layout")),
    ("Konventionen", True, ("konvention", "convention", "stil", "style", "regel", "rule",
                            "pattern")),
    ("Gotchas", True, ("gotcha", "falle", "pitfall", "warnung", "warning", "bekannte fehler",
                       "known issue")),
    ("Workflow", False, ("workflow", "ablauf", "prozess", "process", "beitrag", "contributing")),
]

CODE_MARKER = ("package.json", "pyproject.toml", "Cargo.toml", "go.mod", "Makefile",
               "CMakeLists.txt", "build.gradle", "pom.xml")


def spans(text_ohne_fences):
    return sorted(set(m.strip() for m in re.findall(r"`([^`\n]+)`", text_ohne_fences)))


def wurzeln_finden(ohne_text, projekt):
    """Alle Verzeichnisse, gegen die ein Pfad geprueft werden darf — die Reihenfolge zaehlt.

    [0]  = das Projekt selbst      -> Treffer bedeutet: gar kein Finding
    [1:] = Nachbarn und selbst genannte Wurzeln -> Treffer bedeutet: EXTERN, nur Hinweis

    ⛔ DIESE FUNKTION IST DIE ZWEITE HAELFTE DES 20.08.-FEHLERS. Der erste Anlauf hielt
       Slash-Commands fuer Pfade; der zweite meldete `hooks/hooks.json` als tot, obwohl die
       Datei unter `hackj-plugins/plugins/claude-mind-manager/` liegt — einer Wurzel, die die
       CLAUDE.md SELBST nennt. Der damalige Erkenner sah nur absolute C:-Spans und keine
       RELATIVEN Verzeichnis-Spans. Am 21.08.2026 ist derselbe Fehler im Nachbau erneut
       aufgetreten — deshalb steht er jetzt hier, mit eigenem Selbsttest.
    """
    eltern = os.path.dirname(projekt.rstrip('/' + chr(92)))
    # Das Memory-Verzeichnis liegt AUSSERHALB des Projekts (~/.claude/projects/<slug>/).
    # Ohne es meldet jeder Verweis wie `memory/lessons.md` faelschlich DEAD.
    _heim = os.path.expanduser('~/.claude/projects')
    if os.path.isdir(_heim):
        _slug = re.sub(r'^-*', '', re.sub(r'[^A-Za-z0-9]', '-', projekt.replace('/', chr(92))))
        _m = os.path.join(_heim, _slug)
        if os.path.isdir(_m):
            wurzeln_extra = [_m]
        else:
            wurzeln_extra = []
    else:
        wurzeln_extra = []
    wurzeln = [projekt, eltern] + wurzeln_extra
    for s in set(re.findall(r'`([^`\n]+)`', ohne_text)):
        s = s.strip().replace(chr(92), '/').rstrip('/')
        if not s or '/' not in s or classify_path(s) != 'CHECK':
            continue
        for basis in (projekt, eltern):
            kandidat = os.path.join(basis, s)
            if os.path.isdir(kandidat) and kandidat not in wurzeln:
                wurzeln.append(kandidat)
    return wurzeln


def pruefe(pfad, projekt):
    text = open(pfad, encoding="utf-8").read()
    zeilen, ohne, bullets = vorverarbeiten(text)
    ohne_text = "\n".join(z for z in ohne if z is not None)
    B, H = [], []

    def befund(nr, zeile, was):
        B.append({"check": nr, "zeile": zeile, "text": was})

    def hinweis(nr, zeile, was):
        H.append({"check": nr, "zeile": zeile, "text": was})

    ueberschriften = [(i, len(m.group(1)), z) for i, z in enumerate(zeilen, 1)
                      if (m := re.match(r"^(#+)\s", z)) and ohne[i - 1] is not None]

    # --- 2 · H1 oder direkter H2-Start, beides zulaessig --------------------
    if not ueberschriften or ueberschriften[0][1] > 2:
        befund(2, 1, "weder H1 noch H2 am Anfang")

    # --- 3 · Emojis ---------------------------------------------------------
    for i, z in enumerate(ohne, 1):
        if not z:
            continue
        tr = [c for c in z if ist_emoji(c)]
        if tr:
            befund(3, i, "Emoji: %s" % " ".join(tr[:4]))

    # --- 4 · Bullets hoechstens 3 Ebenen ------------------------------------
    for i, z in enumerate(ohne, 1):
        if z and (m := re.match(r"^(\s*)([-*+]\s|\d+\.\s)", z)):
            if len(m.group(1)) // 2 >= 3:
                befund(4, i, "Bullet-Ebene %d" % (len(m.group(1)) // 2 + 1))

    # --- 5 · keine Leerzeile ZWISCHEN Bullets (beide Nachbarn pruefen) ------
    for i in range(1, len(ohne) - 1):
        a, b, c = ohne[i - 1], ohne[i], ohne[i + 1]
        if b == "" and a and c and re.match(r"^\s*[-*+]\s", a) and re.match(r"^\s*[-*+]\s", c):
            befund(5, i + 1, "Leerzeile zwischen zwei Bullets")

    # --- 6 · Zeilenlaenge, ZWEI Schwellen -----------------------------------
    #     ⛔ Eine Schwelle war falsch: 100 traf Regelzeilen mit Grund — genau das Format,
    #        das Check 7 verlangt. Die echten Prosa-Waende lagen bei 518 und 643 Zeichen.
    for i, z in enumerate(ohne, 1):
        if not z:
            continue
        # ⛔ Eine eingerueckte FORTSETZUNG eines Bullets ist strukturiert, nicht Prosa.
        #    Ohne das meldete der Lauf gegen die globale CLAUDE.md acht Fehltreffer in
        #    Folge — alle im selben Aufzaehlungsabsatz. Schritt 0.2 fasst Fortsetzungen
        #    fuer Check 7 laengst zusammen; Check 6 mass weiter Zeile fuer Zeile.
        _vorher = next((x for x in reversed(ohne[:i - 1]) if x and x.strip()), '')
        _fortsetzung = (z.startswith('  ') and z.strip()
                        and bool(re.match(r'^\s*([-*+]\s|\d+\.\s)', _vorher)
                                 or (_vorher.startswith('  ') and _vorher.strip())))
        strukt = bool(re.match(r"^\s*([-*+]\s|\d+\.\s|\||>)", z) or z.startswith("#"))
        grenze = 250 if (strukt or _fortsetzung) else 100
        if len(z) > grenze:
            befund(6, i, "%d Zeichen > %d (%s)" % (len(z), grenze,
                                                   "strukturiert" if strukt else "Prosa"))

    # --- 7 · jedes NEVER nennt eine Alternative ------------------------------
    for nr, e in bullets:
        low = e.lower()
        if "never" in low and not any(w in low for w in
                                      ("stattdessen", "instead", "->", "→", "sondern",
                                       "always", "nutze", "nimm", "use ")):
            befund(7, nr, "NEVER ohne Alternative: %s" % e.strip()[:70])

    # --- 11 · Zeilenzahl, ZWEI Skalen ---------------------------------------
    n = len(zeilen)
    stufe = ("optimal" if n < 60 else "akzeptabel" if n < 150
             else "WARNUNG" if n <= 200 else "KRITISCH")
    if n > 200:
        befund(11, 0, "%d Zeilen (kritisch, >200)" % n)

    # --- 12 · Tokens/Zeile, DREI Schaetzer ----------------------------------
    nl = max(1, len([z for z in zeilen if z.strip()]))
    schaetzer = (len(text) / 4 / nl, len(text.encode("utf-8")) / 4 / nl,
                 len(text.split()) * 1.4 / nl)
    if min(schaetzer) > 15:
        befund(12, 0, "Tokens/Zeile %.1f / %.1f / %.1f — ALLE drei ueber 15" % schaetzer)
    elif max(schaetzer) > 15:
        hinweis(12, 0, "Tokens/Zeile %.1f / %.1f / %.1f (Schwelle 15, uneinig)" % schaetzer)

    # --- 13/14 · Pfade und Befehle ------------------------------------------
    dead, extern, skip, unsure, befehle = [], [], 0, 0, 0
    wurzeln = wurzeln_finden(ohne_text, projekt)
    for s in spans(ohne_text):
        # Befehl? Auch mit Interpreter-PFAD davor und Argumenten dahinter.
        # `.venv/Scripts/python -m pytest tests/ -v` ist ein Befehl, kein Pfad —
        # gemessen am Zustellplan, wo genau das 5 Fehltreffer erzeugte.
        if (re.match(r'^(python|python3|node|bash|sh|npm|git|pip|timeout|cd)\s|^\./', s)
                or re.search(r'(Scripts|\.?bin)/(python|python3|node|bash|sh)[0-9.]*(\s|$)', s)):
            befehle += 1
            continue
        if "/" not in s and "\\" not in s:
            skip += 1
            continue
        k = classify_path(s)
        if k == "SKIP":
            skip += 1
            continue
        if k == "UNSURE":
            unsure += 1
            continue
        # ⛔ '~' EXPANDIEREN. Ohne das galt jeder `~/.claude/...`-Pfad als tot — auch
        #    solche, die nachweislich existieren. 8 von 13 Fehlbefunden im ersten Lauf.
        roh = s.replace(chr(92), '/').rstrip('/')
        if roh.startswith('~'):
            voll = os.path.expanduser(roh)
            if os.path.exists(voll):
                continue
            dead.append(s)
            continue
        # pytest-Notation `datei.py::test_name` — der Teil hinter :: ist kein Pfad.
        rel = roh.split('::')[0] if '::' in roh else roh
        # Fundstellenangabe `datei.sh:104-106` — dito, und aus derselben Quelle
        # wie im Einordner. Ohne diese Zeile klassifiziert classify_path zwar
        # richtig, die Existenzpruefung laeuft aber weiter gegen den langen
        # String und meldet denselben toten Pfad (gemessen 26.08.2026).
        rel = _ohne_zeilennummer(rel)
        # Windows: ein genanntes Werkzeug liegt oft als .exe/.bat/.cmd vor.
        varianten = [rel] + ([rel + e for e in ('.exe', '.bat', '.cmd')]
                             if os.name == 'nt' and '.' not in os.path.basename(rel)
                             else [])
        if any(os.path.exists(os.path.join(wurzeln[0], v)) or os.path.exists(v)
               for v in varianten):
            continue
        # EXTERN: existiert unter einer der erkannten Wurzeln. Nur Hinweis, nie Befund.
        if any(os.path.exists(os.path.join(w, rel)) for w in wurzeln[1:]):
            extern.append(s)
            continue
        dead.append(s)
    for d in dead:
        befund(13, 0, "toter Pfad: %s" % d)
    for e in extern:
        hinweis(13, 0, "EXTERN (Nachbar-Repo o.ae.): %s" % e)

    # --- 15 · Versions-Tags in Ueberschriften MUESSEN 0 sein ----------------
    for i, z in enumerate(zeilen, 1):
        if re.match(r"^#+ .*\(v[0-9]", z):
            befund(15, i, "Versions-Tag in Ueberschrift: %s" % z.strip()[:60])

    # --- 17 · Secrets --------------------------------------------------------
    for i, z in enumerate(zeilen, 1):
        if re.search(r"sk-ant-|AKIA|BEGIN .*PRIVATE KEY|password=", z):
            befund(17, i, "Secret-Muster")

    # --- 18 · Modularity messbar --------------------------------------------
    rules = len(_md_rekursiv(os.path.join(projekt, ".claude", "rules")))
    imports = len(re.findall(r"@import", text))

    # --- 19 · Ueberschriften-Hierarchie, keine Spruenge ----------------------
    for (_, a, _t1), (i2, b, _t2) in zip(ueberschriften, ueberschriften[1:]):
        if b - a > 1:
            befund(19, i2, "Sprung H%d -> H%d" % (a, b))

    # --- 20 · Architektur 3-7 Eintraege --------------------------------------
    arch_i = next((i for i, _, z in ueberschriften
                   if any(w in z.lower() for w in ("architekt", "architecture", "struktur"))),
                  None)
    if arch_i:
        naechste = next((i for i, _, _ in ueberschriften if i > arch_i), len(zeilen) + 1)
        block = [z for z in zeilen[arch_i:naechste - 1]
                 if re.match(r"^\s*([-*+]\s|\|)", z) and "---" not in z]
        eintraege = max(0, len(block) - 1) if any("|" in z for z in block) else len(block)
        if eintraege > 7:
            hinweis(20, arch_i, "%d Architektur-Eintraege (>7 = Verzeichnisliste)" % eintraege)

    # --- 21 · Commands-Inhalt, NUR bei Code-Projekten ------------------------
    #     ⛔ Ein Workspace ohne Build hat kein build/test/lint. Ein Check, der auf einer
    #        ganzen Projektklasse IMMER anschlaegt, misst dort nichts.
    ist_code = any(os.path.exists(os.path.join(projekt, m)) for m in CODE_MARKER)
    if ist_code:
        low = text.lower()
        fehlend = [w for w in ("build", "test", "lint") if w not in low]
        if fehlend:
            befund(21, 0, "Code-Projekt ohne %s im Text" % "/".join(fehlend))

    # --- Heuristiken (NIE Punktabzug) ---------------------------------------
    low = text.lower()
    for name, pflicht, syn in SEKTIONEN:
        if not any(s in low for s in syn):
            hinweis(1, 0, "Sektion '%s' %s— ungeprueft, Agent bestaetigen"
                    % (name, "(Pflicht) " if pflicht else "(optional) "))
    harte = len(re.findall(r"\b(MUST|NEVER|ALWAYS)\b", text))
    weiche = len(re.findall(r"\b(PREFER|SHOULD|CONSIDER)\b", text))
    if harte and not weiche:
        hinweis(8, 0, "%d harte Regeln, 0 weiche — bei guten Dateien normal" % harte)
    elif weiche and not harte:
        hinweis(8, 0, "%d weiche Regeln, 0 harte" % weiche)
    fett = len(re.findall(r"\*\*[^*]+\*\*", text))
    if harte and fett > harte * 10:
        hinweis(9, 0, "Betonung %d Fett gegen %d Marker (>10:1)" % (fett, harte))
    for phrase in ("write clean code", "sauberen code", "best practice", "keep it simple"):
        if phrase in low:
            hinweis(10, 0, "moeglicherweise generisch: '%s'" % phrase)
    nicht_bullet = len([z for z in ohne if z and not re.match(r"^\s*([-*+#>|]|\d+\.)", z)])
    gesamt = max(1, len([z for z in ohne if z]))
    if nicht_bullet / gesamt > 0.6:
        hinweis(22, 0, "Prosa-Anteil %.0f %%" % (100 * nicht_bullet / gesamt))
    for w in ("prettier", "eslint", "black", "ruff", "semicolon", "einrueckung"):
        if w in low:
            hinweis(23, 0, "moeglicherweise Linter-Aufgabe: '%s'" % w)

    return {
        "datei": pfad, "zeilen": n, "stufe": stufe, "tokens_pro_zeile": schaetzer,
        "pfade": {"dead": dead, "extern": extern, "skip": skip, "unsure": unsure,
                  "befehle": befehle},
        "modularity": {"rules": rules, "imports": imports},
        "befunde": B, "hinweise": H,
    }


# ---------------------------------------------------------------------------
# Instrumentenkontrolle — die Kontrolldatei wird ERZEUGT, nicht gesucht
# ---------------------------------------------------------------------------
# ⛔ Bewusst eingebaut statt danebengelegt: eine Kontrolldatei, die man vergessen oder
#    verlieren kann, ist keine Kontrolle. So kann der Lauf sie nicht ueberspringen.
KONTROLLE = """# Projekt

Dieses Projekt ist ein Projekt und es ist wichtig dass man beim Arbeiten an diesem Projekt immer sauberen Code schreibt und auf gute Lesbarkeit achtet sowie darauf dass alles ordentlich dokumentiert ist und Tests hat und dass man best practice einhaelt \U0001F680

#### Direkt H4 nach H1

- NEVER commit secrets
- NEVER push broken code

- NEVER delete files

Man sollte generell immer daran denken dass es sehr sinnvoll ist wenn man beim Programmieren ordentlich vorgeht und die Dinge so macht wie sie gemacht werden sollten damit am Ende ein gutes Ergebnis dabei herauskommt und alle zufrieden sind mit dem was dabei entstanden ist \U0001F389

Siehe `tools/gibtesnicht.py` und `docs/fehlt.md` und `src/weg.ts`
"""


def selbsttest():
    """Drei gezielte Check-13-Gegenproben — genau die, die den Fehler dreimal verhindert haetten."""
    faelle = [
        ("tools/gibtesnicht.py", "CHECK", "toter Pfad MUSS geprueft werden"),
        ("/mind-all", "SKIP", "Slash-Command darf NICHT als Pfad gelten"),
        ("/deep-review", "SKIP", "Slash-Command mit Bindestrich"),
        ("/tmp", "UNSURE", "Unix-Wurzel darf NICHT als Befehl verschluckt werden"),
        ("/etc", "UNSURE", "dito"),
        ("/tmp/mind-manager.log", "UNSURE", "mehrsegmentig, kein Befehlsname"),
        ("[name](../../references/file.md)", "SKIP", "Markdown-Link-Syntax (v5.3.1)"),
        ("references/…/datei.md", "SKIP", "Auslassungszeichen U+2026"),
        ("docs/...", "SKIP", "drei Punkte"),
        ("example.com/pfad", "SKIP", "Web-Adresse ohne Protokoll"),
        ("https://a.b/c", "SKIP", "Protokoll explizit"),
        ("src/{name}.ts", "SKIP", "Platzhalter"),
        ("min(Fenster-12 %, Fenster x Prozent/100, Fenster-13000)", "SKIP",
         "FORMEL, kein Pfad — vom ersten echten Lauf aufgedeckt"),
        ("a b/c (d)", "SKIP", "Leerzeichen + Klammern = nie ein Pfad"),
        ("APP - Zustellplan/dist", "CHECK",
         "Leerzeichen ALLEIN macht keinen Formel-Treffer"),
        (chr(92) + "n", "SKIP", "Escape-Sequenz, kein Pfad"),
        (chr(92) + "r" + chr(92) + "n", "SKIP", "zwei Escapes hintereinander"),
        (chr(92) + "udc90", "SKIP", "Unicode-Escape"),
        ("C:" + chr(92) + "x0bdd_settings.xml", "SKIP", "zerstoerter Beispielpfad"),
        ('"hooks": "hooks/hooks.json"', "SKIP", "JSON-Fragment"),
        # ⛔ Die drei Fehlalarme aus dem /mind-all-Lauf vom 25.08.2026. Sie
        #    standen dort als Verbesserungsvorschlag und waren beim naechsten
        #    Lauf immer noch da. Jeder Fall EINZELN — ein Prueffall mit zwei
        #    Signalen belegt nur, dass EINES lebt (werkzeuge-zuerst.md).
        ("gefunden / gefahren / gr\u00fcn", "SKIP",
         "Ausgabezeile von tests/alle.sh, Leerzeichen vor dem Schraegstrich"),
        ("rmdir /s /q", "SKIP", "Befehlsschalter, kein Pfad"),
        ("2>/dev/null", "SKIP", "Shell-Umleitung"),
        (">/dev/null", "SKIP", "Umleitung ohne Deskriptor"),
        ("hooks/lib.sh:104-106", "CHECK",
         "Zitat MIT Zeilennummer -> der Pfad davor WIRD geprueft, nicht uebersprungen"),
        ("tests/alle.sh:12", "CHECK", "einzelne Zeilennummer"),
        # ⭐ NEGATIVKONTROLLEN zu genau diesen Regeln. Ohne sie waere die
        #    Verschaerfung nur Stille — und der teuerste Fehler dieses Werkzeugs
        #    war immer ein zu breiter Filter.
        ("APP - Zustellplan/dist", "CHECK",
         "echter Pfad MIT Leerzeichen — vor dem Schraegstrich steht keines"),
        ("Plugin - Entwicklung/Claude Mind Manager", "CHECK",
         "zwei Leerzeichen im Namen, keines vor dem Trenner"),
        ("knowledge/README.md", "CHECK", "gewoehnlicher Pfad bleibt CHECK"),
        (".tsx/.jsx", "SKIP", "Endungspaar"),
        (".claude/rules/x.md", "CHECK", "fuehrender Punkt ALLEIN ist ein echter Pfad"),
        (".venv/Scripts/python", "SKIP", "Interpreter-Aufruf, gehoert an Check 14"),
        ("/usr/bin/python3", "SKIP", "Interpreter mit Versionsziffer"),
        ("node_modules/.bin/bash", "SKIP", "Interpreter in einem Werkzeugverzeichnis"),
        ("tools/python_helper.py", "CHECK", "python im DATEInamen ist kein Interpreter"),
        ("2/8", "SKIP", "Verhaeltnis, kein Pfad"),
        ("10/100", "SKIP", "rein numerisch"),
        ("actual/expected", "UNSURE", "Prosa-Paar ohne Punkt — melden, nicht behaupten"),
        ("src/main.py", "CHECK", "mit Endung bleibt es ein Pfad"),
        ("hooks/lib.sh", "CHECK", "normaler relativer Pfad"),
        ("/c/Users/x/y.md", "CHECK", "MSYS-Laufwerk ist pruefbar"),
    ]
    rot = 0
    print("=== Selbsttest classify_path (die drei Fehlerklassen von 20./21.08.) ===")
    for p, soll, warum in faelle:
        ist = classify_path(p)
        gut = ist == soll
        rot += 0 if gut else 1
        print("  %s %-34s %-7s %s" % ("[ok ]" if gut else "[ROT]", p, ist, warum))
        if not gut:
            print("        erwartet %s" % soll)

    # --- Der Fixture-Test, der den 20.08.-Fehler festnagelt ----------------
    #     Ein Pfad, der NUR unter einem relativ genannten Nachbarverzeichnis existiert,
    #     MUSS EXTERN werden — nicht DEAD. Zweimal ist genau das schiefgegangen.
    import shutil, tempfile
    t = tempfile.mkdtemp(prefix='pipeline_fixture_')
    try:
        proj = os.path.join(t, 'projekt')
        wurzel = os.path.join(t, 'nachbar', 'paket')
        os.makedirs(proj); os.makedirs(os.path.join(wurzel, 'hooks'))
        open(os.path.join(wurzel, 'hooks', 'ziel.json'), 'w').close()
        md = os.path.join(proj, 'CLAUDE.md')
        with open(md, 'w', encoding='utf-8') as f:
            f.write('# P\n\n## Uebersicht\n\nDer Code liegt in `nachbar/paket/`.\n'
                    'Die Konfiguration heisst `hooks/ziel.json`.\n'
                    'Diese hier gibt es nicht: `voellig/erfunden.json`.\n')
        r = pruefe(md, proj)
        p = r['pfade']
        for name, ist, soll in (('Pfad unter selbst genannter Wurzel -> EXTERN',
                                 'hooks/ziel.json' in p['extern'], True),
                                ('erfundener Pfad bleibt DEAD',
                                 'voellig/erfunden.json' in p['dead'], True),
                                ('und steht NICHT in DEAD',
                                 'hooks/ziel.json' in p['dead'], False)):
            rot += 0 if gut else 1
            print('  %s %-46s %s' % ('[ok ]' if gut else '[ROT]', name, ist))
    finally:
        shutil.rmtree(t, ignore_errors=True)

    print()
    print("=== Emoji-Abgrenzung ===")
    for z, soll, warum in ((chr(0x1F680), True, "Rakete = Emoji"),
                           ("⭐", False, "Stern = Wichtig-Marker, kein Schmuck"),
                           ("⛔", False, "Verbotsmarker = KEIN Befund"),
                           ("⚠", False, "Warnmarker = KEIN Befund"),
                           ("→", False, "Pfeil ist erlaubt"),
                           ("—", False, "Gedankenstrich ist erlaubt")):
        ist = ist_emoji(z)
        gut = ist == soll
        rot += 0 if gut else 1
        print("  %s %-4s %-6s %s" % ("[ok ]" if gut else "[ROT]", z, str(ist), warum))
    return rot


def main():
    if "--selbsttest" in sys.argv:
        rot = selbsttest()
        print()
        print("  %s" % ("alle Selbsttests bestanden" if not rot else "%d ROT" % rot))
        return 1 if rot else 0

    if len(sys.argv) < 2 or "--projekt" not in sys.argv:
        hilfe = (__doc__ or "").split("AUFRUF")
        print(hilfe[1].split("RUECKGABE")[0].strip() if len(hilfe) > 1
              else "Aufruf: claudemd_pipeline.py <ziel.md> --projekt <dir>", file=sys.stderr)
        return 2
    ziel = sys.argv[1]
    projekt = sys.argv[sys.argv.index("--projekt") + 1]
    if not os.path.isfile(ziel):
        print("ABBRUCH: %s existiert nicht" % ziel, file=sys.stderr)
        return 2

    r = pruefe(ziel, projekt)

    # Instrumentenkontrolle — EINZIGER Abbruchgrund
    import tempfile
    tmp = tempfile.mkdtemp(prefix="claudemd_kontrolle_")
    kpfad = os.path.join(tmp, "kontrolle.md")
    with open(kpfad, "w", encoding="utf-8") as f:
        f.write(KONTROLLE)
    k = pruefe(kpfad, projekt)
    # ⛔ NACH DICHTE vergleichen, nicht nach Anzahl (korrigiert 21.08.2026).
    #    Die Kontrolldatei hat 17 Zeilen, eine echte CLAUDE.md hat 85-200. Absolut
    #    gerechnet gewinnt die kurze Datei IMMER, und jede lange Datei galt als
    #    'Messung ungueltig'. Gemessen: Kontrolle 0,76 Befunde/Zeile gegen 0,19 beim Ziel.
    #    Dieselbe Fehlerklasse stand schon im Debug-Ordner — sie ist mir trotzdem
    #    ein zweites Mal passiert.
    d_k = len(k['befunde']) / max(1, k['zeilen'])
    d_r = len(r['befunde']) / max(1, r['zeilen'])
    gueltig = d_k >= d_r * 2.0

    if "--json" in sys.argv:
        r["instrumentenkontrolle"] = {"dichte_kontrolle": round(d_k, 3),
                                      "dichte_ziel": round(d_r, 3), "gueltig": gueltig}
        print(json.dumps(r, ensure_ascii=False, indent=2))
        return 3 if not gueltig else (1 if r["befunde"] else 0)

    print("=== %s ===" % os.path.basename(ziel))
    print("  Zeilen %d (%s) · Tokens/Zeile %.1f / %.1f / %.1f (Schwelle 15)"
          % (r["zeilen"], r["stufe"], *r["tokens_pro_zeile"]))
    p = r["pfade"]
    print("  Pfade: %d DEAD · %d EXTERN · %d SKIP · %d UNSURE · %d Befehle"
          % (len(p["dead"]), len(p["extern"]), p["skip"], p["unsure"], p["befehle"]))
    print("  Modularity: %d rules, %d @import" % (r["modularity"]["rules"],
                                                  r["modularity"]["imports"]))
    print()
    print("  --- BEFUNDE (%d) ---" % len(r["befunde"]))
    for b in r["befunde"]:
        print("    [Check %-2d] Z%-4d %s" % (b["check"], b["zeile"], b["text"]))
    print("  --- HINWEISE (%d, nie Punktabzug) ---" % len(r["hinweise"]))
    for h in r["hinweise"]:
        print("    [Check %-2d] Z%-4d %s" % (h["check"], h["zeile"], h["text"]))
    print()
    print("  Instrumentenkontrolle: Kontrolle %.2f Befunde/Zeile gegen Ziel %.2f -> %s"
          % (d_k, d_r, "GUELTIG" if gueltig else "UNGUELTIG"))
    if not gueltig:
        print()
        print("  ABBRUCH: die Kontrolldatei schneidet nicht deutlich schlechter ab.")
        print("  Kontrolle: %d Befunde auf %d Zeilen (%.2f/Zeile)"
              % (len(k["befunde"]), k["zeilen"], d_k))
        print("  Ziel:      %d Befunde auf %d Zeilen (%.2f/Zeile)"
              % (len(r["befunde"]), r["zeilen"], d_r))
        print()
        print("  Wahrscheinliche Ursachen, in dieser Reihenfolge pruefen:")
        print("    1. Ist <ziel.md> versehentlich eine KONTROLL- oder Beispieldatei?")
        print("       Ziel war: %s" % os.path.realpath(ziel))
        print("    2. Stimmt --projekt? Eine falsche Wurzel erzeugt Schein-Befunde")
        print("       bei Check 13. Projekt war: %s" % os.path.realpath(projekt))
        print("    3. Ist das Ziel wirklich so schlecht? Dann sind die Befunde echt —")
        print("       aber die Messung traegt sie nicht, weil die Kontrolle nicht trennt.")
        print()
        print("  Alle Zahlen oben sind ungueltig, bis das geklaert ist.")
        return 3
    return 1 if r["befunde"] else 0


if __name__ == "__main__":
    sys.exit(main())
