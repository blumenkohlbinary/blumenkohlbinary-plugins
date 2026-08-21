#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Projektuebergreifender Strukturpruefer + Lehren-Sammler (v5.9.0).

Zwei Aufgaben, beide nur LESEND:

  1. Strukturbefunde  ->  in den zentralen Debug-Ordner (Wiederholungserkennung)
  2. Lehren           ->  in einen Bestand, der NIRGENDS geladen wird

⛔ Was sich gegenueber v5.8 geaendert hat, und warum:

   Die Projektfindung stieg genau ZWEI Ebenen ab und uebersprang alles mit '.' am
   Anfang. Gemessen: 3 Projekte uebersehen, `.claude/` nie betreten. Sie liegt jetzt
   in `learnings_quellen.py` und arbeitet voll rekursiv — mit einer sorgfaeltigen
   Ausschlussliste, weil blosse Rekursion 57 statt 23 Projekte fand (37 davon aus den
   Sicherungskopien des Plugins selbst).

   Und die Quellen waren zu eng: nur `memory`, `rules` (flach), `CLAUDE.md`, `tools`.
   Jetzt zusaetzlich Skills, Agents, Commands, Hooks — und `rules/` rekursiv.

Aufruf:  learnings_scan.py <wurzel> [--jsonl F] [--bericht F] [--bestand F] [--ts T]
Rueckgabe: 0 = gelaufen · 2 = Aufruffehler
"""
import io
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from learnings_quellen import (AUS, lehren, lies,  # noqa: E402
                               memory_pfad, projekte, quellen)

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# ⛔ ENTFERNT am 21.08.2026 — die Pruefung widersprach der Spezifikation.
#
#    Sie meldete "Memory-Dateien tragen ARBEITSMATERIAL statt Wissen" fuer alles mit
#    "Dauerauftrag", "Stand der", "Roadmap". Die Memory-Anweisung sagt zu `type: project`
#    aber woertlich:
#
#        "ongoing work, goals, or constraints not derivable from the code or git history"
#
#    LAUFENDE ARBEIT IST GENAU DAS, WOFUER `project` DA IST. Die Regel, an die ich
#    gedacht hatte ("was jemand AUSFUEHREN wuerde, ist Arbeitsmaterial"), gilt fuer
#    JOPLIN — nicht fuer das Memory.
#
#    Der Schaden waere gross gewesen: die Pruefung haette dazu verleitet, in DREI fremden
#    Projekten laufende Auftraege aus dem Memory zu nehmen — darunter zwei, die
#    ausdruecklich "LAUFENDER AUFTRAG (nicht stoppen)" heissen. Eine Sitzung haette
#    danach ihren Auftrag nicht mehr gefunden.
#
#    Das ist der VIERTE Fehlalarm dieser Bauart an einem Tag (settings-only `.claude/`,
#    AGENTS.md im Skillpaket, `~/.claude/` im Zeiger-Muster, und dieser). Muster:
#    ⭐ Der Check nimmt eine Regel an, die so nirgends steht — und meldet dann
#       Abweichungen von einer Erfindung.

# ⛔ Nur SELBSTBEZEICHNUNG als Verweis zaehlt — der blosse Pfad nicht.
#    Der erste Stand hatte `~/\.claude/` mit drin und meldete deshalb
#    `globale-rules-nicht-anfassen.md` als falsch getypt. Deren Beschreibung lautet
#    "der Nutzer hat abgelehnt, dass ich ~/.claude/rules/ bearbeite" — eine
#    NUTZER-ENTSCHEIDUNG, in der der Pfad der GEGENSTAND ist, nicht das Ziel eines
#    Verweises. Ein Muster, das den Unterschied nicht sieht, erzeugt Fehlalarme in
#    fremden Projekten.
ZEIGER = re.compile(r"^\s*[\"']?\s*(Pointer|Zeiger)\b|"
                    r"\b(Pointer|Zeiger) (auf|zu|nach)\b|"
                    r"\b(liegt|steht) (jetzt )?(als|in) (der )?globale[nr]? Rule\b", re.I)


def frontmatter_offen(t):
    """Erste Zeile `---`, aber keine zweite -> das ganze Dokument gilt als Kopf."""
    z = t.replace("\r\n", "\n").split("\n")
    if not z or z[0].strip() != "---":
        return False
    return "---" not in [x.strip() for x in z[1:40]]


def globs_treffer(regel, projekt):
    """Trifft das `globs:`-Muster ueberhaupt eine Datei im Projekt?"""
    m = re.search(r"^globs:\s*(.+)$", lies(regel), re.M)
    if not m:
        return None                      # kein globs -> laedt immer, kein Befund
    muster = [x.strip().strip('"\'') for x in
              m.group(1).strip().strip("[]").split(",") if x.strip()]
    if not muster:
        return None
    import fnmatch
    for wz, dirs, ds in os.walk(projekt):
        dirs[:] = [d for d in dirs if d not in AUS]
        for d in ds:
            rel = os.path.relpath(os.path.join(wz, d), projekt).replace("\\", "/")
            for mu in muster:
                if fnmatch.fnmatch(rel, mu) or fnmatch.fnmatch(rel, mu.lstrip("*/")):
                    return True
    return False


def pruefe(projekt, q):
    """Alle Strukturbefunde eines Projekts. Nur lesen."""
    b = []

    def f(klasse, kurz, datei=""):
        b.append({"klasse": klasse, "kurz": kurz, "datei": datei, "projekt": projekt})

    # --- Memory ----------------------------------------------------------
    topics = [p for p in q["memory"] if os.path.basename(p) != "MEMORY.md"]
    ohne_desc, offen, lang, zeiger = [], [], [], []
    for p in topics:
        x = os.path.basename(p)
        t = lies(p)
        kopf = "\n".join(t.replace("\r\n", "\n").split("\n")[:14])
        d = re.search(r"^description:[ \t]*(.*)$", kopf, re.M)
        besch = d.group(1).strip() if d else ""
        if not d:
            ohne_desc.append(x)
        elif len(besch) > 200:
            lang.append((x, len(besch)))
        if besch and not re.search(r"^[ \t]*type:[ \t]*reference\b", kopf, re.M) \
                and ZEIGER.search(besch):
            zeiger.append(x)
        if frontmatter_offen(t):
            offen.append(x)

    md = memory_pfad(projekt) or ""
    if ohne_desc:
        f("sichtbarkeit",
          "%d Memory-Topic-Dateien ohne `description` — der Auswaehler hat kein Signal, "
          "sie zaehlen aber voll gegen das Budget: %s"
          % (len(ohne_desc), ", ".join(ohne_desc[:5])), md)
    if offen:
        f("sichtbarkeit",
          "%d Memory-Dateien mit OFFENEM Frontmatter (erste Zeile `---`, keine zweite) — "
          "das ganze Dokument gilt als Kopf: %s" % (len(offen), ", ".join(offen[:5])), md)
    # ⭐ Am Binaerprogramm gelesen (2.1.237): der Auswaehler ist ein MODELL, das NUR
    #    Dateiname und `description` sieht — nie den Inhalt.
    if lang:
        f("sichtbarkeit",
          "%d Memory-Beschreibungen ueber 200 Zeichen (laengste %d) — der Auswaehler "
          "sieht NUR Name und description und ist auf Zurueckhaltung getrimmt: %s"
          % (len(lang), max(n for _, n in lang),
             ", ".join("%s (%d)" % (a, n) for a, n in sorted(lang, key=lambda z: -z[1])[:3])), md)
    if zeiger:
        f("sichtbarkeit",
          "%d Memory-Dateien beschreiben sich als Verweis, tragen aber nicht "
          "`type: reference`: %s" % (len(zeiger), ", ".join(zeiger[:5])), md)

    # --- Rules (REKURSIV, auch Unterordner) ------------------------------
    tot, r_offen = [], []
    for p in q["rules"]:
        rel = os.path.relpath(p, projekt)
        if frontmatter_offen(lies(p)):
            r_offen.append(rel)
        if globs_treffer(p, projekt) is False:
            tot.append(rel)
    if r_offen:
        f("sichtbarkeit", "%d Regeldateien mit OFFENEM Frontmatter: %s"
          % (len(r_offen), ", ".join(r_offen[:5])), projekt)
    if tot:
        f("sichtbarkeit",
          "%d Regeldateien, deren `globs:` KEINE Datei im Projekt trifft: %s "
          "(⚠ ein Muster ohne Treffer verhindert das Laden NICHT — Hinweis, kein Beweis)"
          % (len(tot), ", ".join(tot[:5])), projekt)

    # --- Skills / Agents / Commands --------------------------------------
    # ⛔ NUR echte Claude-Code-Einstiegsdateien pruefen: ein Skill ist `SKILL.md`,
    #    ein Agent bzw. Command eine `.md` DIREKT in `agents/` oder `commands/`.
    #    Alles andere darunter sind Inhaltsdateien.
    #
    #    Der erste Stand nahm JEDE `.md` unter `skills/`. Gemessen 21.08.2026: er
    #    meldete "36 Skills ohne description" in syncclipboard-mobile — alle 36 lagen
    #    in `vercel-react-native-skills/`, einem eingekauften Fremdpaket mit eigenem
    #    Frontmatter-Schema (`title`, `impact`, `impactDescription`, `tags`). Die sind
    #    sauber beschrieben, nur nicht in Claude Codes Schema. Sie zu "reparieren"
    #    haette 36 fremde Dateien veraendert, die beim naechsten Update ueberschrieben
    #    werden — und nichts behoben.
    def ist_einstieg(p):
        b = os.path.basename(p)
        if b.upper() == "SKILL.MD":
            return True
        eltern = os.path.basename(os.path.dirname(p)).lower()
        return eltern in ("agents", "commands") and b.endswith(".md")

    s_ohne, s_offen = [], []
    for p in [x for x in q["skills"] if ist_einstieg(x)]:
        t = lies(p)
        if frontmatter_offen(t):
            s_offen.append(os.path.relpath(p, projekt))
        kopf = "\n".join(t.replace("\r\n", "\n").split("\n")[:20])
        if kopf.lstrip().startswith("---") and not re.search(r"^description:", kopf, re.M):
            s_ohne.append(os.path.relpath(p, projekt))
    if s_offen:
        f("sichtbarkeit", "%d Skills/Agents mit OFFENEM Frontmatter: %s"
          % (len(s_offen), ", ".join(s_offen[:4])), projekt)
    if s_ohne:
        f("sichtbarkeit",
          "%d Skills/Agents mit Frontmatter, aber ohne `description` — ohne sie waehlt "
          "Claude Code den Skill nie aus: %s" % (len(s_ohne), ", ".join(s_ohne[:4])), projekt)

    # --- Hooks: Zeilenenden ----------------------------------------------
    # ⛔ Ein .sh mit CRLF scheitert unter bash mit "\r: command not found" — und der
    #    Hook schweigt dann, statt zu melden.
    crlf = []
    for p in q["hooks"]:
        if not p.endswith(".sh"):
            continue
        try:
            roh = open(p, "rb").read()
        except Exception:
            continue
        if roh.count(b"\r\n") > 0:
            crlf.append(os.path.relpath(p, projekt))
    if crlf:
        f("zeilenenden",
          "%d Hook-Skripte mit CRLF — unter bash scheitern sie mit \"\\r: command not "
          "found\" und schweigen dabei: %s" % (len(crlf), ", ".join(crlf[:4])), projekt)

    # --- CLAUDE.md -------------------------------------------------------
    if q["claudemd"]:
        for p in q["claudemd"]:
            n = len(lies(p).replace("\r\n", "\n").split("\n"))
            if n > 200:
                f("sonstiges",
                  "%s hat %d Zeilen (kritisch ueber 200) — laedt bei JEDEM Start; "
                  "Context Rot setzt ab ~25 %% Fensterfuellung ein"
                  % (os.path.relpath(p, projekt), n), p)
    elif os.path.isdir(os.path.join(projekt, ".claude")):
        f("sonstiges", "Projekt hat .claude/, aber KEINE CLAUDE.md", projekt)

    # --- Werkzeuge ohne Companion-Rule -----------------------------------
    td = os.path.join(projekt, "tools")
    if os.path.isdir(td) and q["rules"]:
        regeln = "".join(lies(p) for p in q["rules"])
        tote = [x for x in sorted(os.listdir(td))
                if x.endswith((".py", ".sh")) and ("tools/" + x) not in regeln]
        if tote:
            f("plugin-defekt",
              "%d Werkzeuge in tools/ ohne glob-getriggerte Companion-Rule (totes "
              "Werkzeug): %s" % (len(tote), ", ".join(tote[:5])), td)
    return b


def main():
    if len(sys.argv) < 2:
        print("Aufruf: learnings_scan.py <wurzel> [--jsonl F] [--bericht F] "
              "[--bestand F] [--ts T]", file=sys.stderr)
        return 2
    wurzel = sys.argv[1]
    if not os.path.isdir(wurzel):
        print("kein Verzeichnis: %s" % wurzel, file=sys.stderr)
        return 2

    def arg(n):
        return sys.argv[sys.argv.index(n) + 1] if n in sys.argv else None

    ps = projekte(wurzel)
    alle, ohne_befund = [], []
    lehr_bestand, quellzahl = [], {}

    print("=" * 74)
    print("  Strukturpruefung + Lehren-Sammlung ueber %d Projekte" % len(ps))
    print("=" * 74)
    for p in ps:
        q = quellen(p)
        for schl, fs in q.items():
            quellzahl[schl] = quellzahl.get(schl, 0) + len(fs)
        # Lehren einsammeln — aus ALLEN Quellen
        for schl, fs in q.items():
            for datei in fs:
                for text in lehren(datei):
                    lehr_bestand.append({
                        "projekt": os.path.basename(p), "quelle": schl,
                        "datei": os.path.relpath(datei, wurzel)
                                 if datei.startswith(os.path.abspath(wurzel)) else datei,
                        "text": text,
                    })
        b = pruefe(p, q)
        if not b:
            ohne_befund.append(os.path.basename(p))
            continue
        print()
        print("  %s  (%d)" % (os.path.relpath(p, wurzel), len(b)))
        for x in b:
            print("    [%s] %s" % (x["klasse"], x["kurz"][:150]))
        alle.extend(b)

    print()
    print("-" * 74)
    print("  Quellen: " + " · ".join("%s %d" % (k, v) for k, v in sorted(quellzahl.items())))
    print("  %d Befunde in %d von %d Projekten" % (len(alle), len(ps) - len(ohne_befund), len(ps)))
    print("  %d Lehr-Absaetze eingesammelt" % len(lehr_bestand))
    if ohne_befund:
        print("  ohne Befund: %s" % ", ".join(ohne_befund))

    jf = arg("--jsonl")
    if jf:
        ts = arg("--ts") or ""
        with open(jf, "w", encoding="utf-8", newline="\n") as fh:
            for x in alle:
                fh.write(json.dumps({
                    "ts": ts, "projekt": x["projekt"], "klasse": x["klasse"],
                    "kurz": x["kurz"], "datei": x["datei"], "lauf": "mind-learnings",
                }, ensure_ascii=True) + "\n")
        print("  JSONL -> %s (%d Zeilen)" % (jf, len(alle)))

    bf = arg("--bericht")
    if bf:
        z = ["# Strukturpruefung (`/mind-learnings`)", "",
             "Erzeugt von `references/learnings_scan.py`. **Nur gelesen, nichts geaendert.**",
             "", "| | |", "|---|---|",
             "| Projekte geprueft | %d |" % len(ps),
             "| Befunde | **%d** |" % len(alle),
             "| Lehr-Absaetze | %d |" % len(lehr_bestand), ""]
        nach = {}
        for x in alle:
            nach.setdefault(os.path.basename(x["projekt"]), []).append(x)
        for name in sorted(nach, key=lambda k: -len(nach[k])):
            z += ["## %s (%d)" % (name, len(nach[name])), ""]
            z += ["- **[%s]** %s" % (x["klasse"], x["kurz"]) for x in nach[name]]
            z.append("")
        if ohne_befund:
            z += ["## Ohne Befund", "", ", ".join(ohne_befund), ""]
        open(bf, "w", encoding="utf-8", newline="\n").write("\n".join(z))
        print("  Bericht -> %s" % bf)

    sf = arg("--bestand")
    if sf:
        # ⛔ Dieser Bestand laedt NIRGENDS: kein `globs:`, keine Rule, kein Hook.
        #    Er ist ein Lager, kein Kontext.
        #
        # ⭐ ENTDOPPELN und dabei die HERKUNFT zaehlen. Derselbe Absatz in zwei
        #    Projekten ist der interessante Fall — genau der Zaehler, den kein
        #    installierbares Werkzeug fuehrt (belegt 21.08.2026). Ohne ihn stuende
        #    eine zwischen Projekten kopierte Regel hier fuenfmal und saehe aus wie
        #    fuenf Belege, obwohl es einer ist.
        import hashlib
        gruppen = {}
        for x in lehr_bestand:
            schl = hashlib.sha256(" ".join(x["text"].split()).encode()).hexdigest()
            g = gruppen.setdefault(schl, {"text": x["text"], "projekte": set(),
                                          "quellen": set(), "dateien": []})
            g["projekte"].add(x["projekt"])
            g["quellen"].add(x["quelle"])
            g["dateien"].append(x["datei"])

        mehr = [g for g in gruppen.values() if len(g["projekte"]) >= 2]
        z = ["# Lehren-Bestand", "",
             "Erzeugt von `/mind-learnings`. **Wird von nichts automatisch geladen** — "
             "kein `globs:`, keine Rule, kein Hook. Ein Lager, kein Kontext.", "",
             "| | |", "|---|---|",
             "| Absaetze gefunden | %d |" % len(lehr_bestand),
             "| nach Entdopplung | **%d** |" % len(gruppen),
             "| davon in **mehreren Projekten** | **%d** |" % len(mehr), ""]
        if mehr:
            z += ["## ⭐ In mehreren Projekten belegt", "",
                  "Diese Absaetze stehen wortgleich in mehr als einem Projekt. Das ist "
                  "der Evidenzzaehler, den kein installierbares Werkzeug fuehrt — und "
                  "zugleich ein Hinweis auf **Kopien**, die besser einmal global "
                  "staenden.", ""]
            for g in sorted(mehr, key=lambda x: -len(x["projekte"]))[:40]:
                z += ["### %d Projekte: %s" % (len(g["projekte"]),
                                               ", ".join(sorted(g["projekte"]))), "",
                      "*%s*" % ", ".join(sorted(set(g["dateien"])))[:200], "",
                      g["text"], ""]
        nachq = {}
        for g in gruppen.values():
            nachq.setdefault(sorted(g["quellen"])[0], []).append(g)
        z += ["## Nach Quelle", ""]
        for k, v in sorted(nachq.items(), key=lambda z2: -len(z2[1])):
            z += ["### %s (%d)" % (k, len(v)), ""]
            for g in v:
                z += ["**%s** — `%s`" % (", ".join(sorted(g["projekte"])),
                                         sorted(set(g["dateien"]))[0]), "", g["text"], ""]
        open(sf, "w", encoding="utf-8", newline="\n").write("\n".join(z))
        print("  Bestand -> %s (%d Absaetze, %d nach Entdopplung, %d mehrfach belegt)"
              % (sf, len(lehr_bestand), len(gruppen), len(mehr)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
