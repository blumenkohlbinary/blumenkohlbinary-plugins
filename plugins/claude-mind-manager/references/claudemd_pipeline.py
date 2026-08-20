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
import io
import json
import os
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

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
             0x270C, 0x270A, 0x261D, 0x2B50, 0x1F44D}
MARKER_ERLAUBT = {0x26D4, 0x26A0, 0x2705, 0x274C, 0x23ED, 0x2192, 0x2014, 0x2026, 0x00B7}


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


def classify_path(p):
    """SKIP | UNSURE | CHECK — Wortlaut und Reihenfolge wie in mind-update Step 3b."""
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
    # 3b) SKIP: Slash-Command — fuehrender /, GENAU ein Segment, MIT Bindestrich.
    #     ⛔ Kriterium bewusst ENG: NICHT "ein Segment ohne Punkt" — das verschluckte
    #     /etc, /tmp, /usr, /var, /opt. Der Bindestrich trennt Befehlsnamen sauber ab.
    #     EHRLICHER PREIS: ein wirklich toter Pfad der Form /foo-bar wird nicht gelistet.
    if p.count("/") == 1 and p.startswith("/") and "-" in p[1:]:
        return "SKIP"
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
    wurzeln = [projekt, eltern]
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
        strukt = bool(re.match(r"^\s*([-*+]\s|\d+\.\s|\||>)", z) or z.startswith("#"))
        grenze = 250 if strukt else 100
        if len(z) > grenze:
            befund(6, i, "%d Zeichen > %d (%s)" % (len(z), grenze,
                                                   "strukturiert" if strukt else "Prosa"))

    # --- 7 · jedes NEVER nennt eine Alternative ------------------------------
    for nr, e in bullets:
        low = e.lower()
        if "never" in low and not any(w in low for w in
                                      ("stattdessen", "instead", "->", "→", "sondern")):
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
        if re.match(r"^(python|python3|node|bash|sh|npm|git|pip)\s|^\./", s):
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
        rel = s.replace("\\", "/").rstrip("/")
        if any(os.path.exists(os.path.join(w, rel)) for w in wurzeln[:1]) or os.path.exists(rel):
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
    rules = len([f for f in os.listdir(os.path.join(projekt, ".claude", "rules"))
                 if f.endswith(".md")]) if os.path.isdir(
        os.path.join(projekt, ".claude", "rules")) else 0
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
    gueltig = len(k["befunde"]) > len(r["befunde"])

    if "--json" in sys.argv:
        r["instrumentenkontrolle"] = {"kontrolle": len(k["befunde"]),
                                      "ziel": len(r["befunde"]), "gueltig": gueltig}
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
    print("  Instrumentenkontrolle: Kontrolldatei %d Befunde gegen Ziel %d -> %s"
          % (len(k["befunde"]), len(r["befunde"]), "GUELTIG" if gueltig else "UNGUELTIG"))
    if not gueltig:
        print()
        print("  ABBRUCH: die bekannt schlechte Kontrolldatei schneidet nicht schlechter ab.")
        print("  Das Instrument misst nichts — alle Zahlen oben sind ungueltig.")
        return 3
    return 1 if r["befunde"] else 0


if __name__ == "__main__":
    sys.exit(main())
