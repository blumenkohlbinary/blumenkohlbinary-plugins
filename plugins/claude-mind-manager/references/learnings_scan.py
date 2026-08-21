#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Projektuebergreifender Strukturpruefer — meldet nach Debug (NEU v5.8.0).

WOZU. Die Phase-0-Messung am 21.08.2026 hat gezeigt, dass ein Uebertrag von
LEHREN zwischen Projekten wenig bringt: von 207 Bulletpoints blieben nach beiden
Toren ~3 echte uebrig, und die staerksten standen bereits woertlich in der globalen
CLAUDE.md. Der Kanal existiert und ist gefuellt.

Was NICHT gefuellt ist: strukturelle Befunde ueber Projekte hinweg. Die entstehen
heute nur, wenn in einem Projekt zufaellig `/mind-all` laeuft. Ein Projekt, das
monatelang keinen Lauf hat, meldet nichts — und niemand sieht, dass dort 7
Memory-Dateien ohne `description` liegen und damit fuer die Auswahl unsichtbar sind.

Dieser Pruefer sieht ALLE Projekte an und schreibt in denselben Debug-Ordner, der
schon die Wiederholungserkennung traegt. Am 21.08.2026 hat dieser Kanal vier echte
Plugin-Fehler aus FREMDEN Projekten geliefert — er funktioniert, er war nur zu
schmal gespeist.

⛔ Er AENDERT NICHTS. Nur lesen und melden. Wer Befunde behebt, entscheidet der Mensch.

Aufruf:  python learnings_scan.py <wurzel> [--jsonl <datei>] [--bericht <datei>]
Rueckgabe: 0 = gelaufen (auch mit Befunden) · 2 = Aufruffehler
"""
import io
import json
import os
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

UEBERSPRINGEN = ("node_modules", ".git", "_claude_backups", "Beispiele",
                 "dist", "build", ".venv", "__pycache__")

# Wortstaemme, an denen ein Memory-Eintrag als ARBEITSMATERIAL erkennbar ist.
# Der Nutzer trennt das ausdruecklich: was jemand AUSFUEHREN wuerde, ist kein Wissen.
ARBEIT = re.compile(r"laufender auftrag|dauerauftrag|wortlaut gesichert|"
                    r"stand der|offene punkte|roadmap|fahrplan|nacharbeiten|"
                    r"was noch offen|todo|batch", re.I)


def lies(p):
    try:
        return open(p, "rb").read().decode("utf-8", "replace")
    except Exception:
        return ""


def frontmatter_offen(t):
    """Erste Zeile `---`, aber keine zweite -> das ganze Dokument gilt als Kopf."""
    z = t.replace("\r\n", "\n").split("\n")
    if not z or z[0].strip() != "---":
        return False
    return "---" not in [x.strip() for x in z[1:40]]


def globs_treffer(regel, projekt):
    """Trifft das `globs:`-Muster ueberhaupt eine Datei im Projekt?"""
    t = lies(regel)
    m = re.search(r"^globs:\s*(.+)$", t, re.M)
    if not m:
        return None                      # kein globs -> laedt immer, kein Befund
    roh = m.group(1).strip().strip("[]")
    muster = [x.strip().strip('"\'') for x in roh.split(",") if x.strip()]
    if not muster:
        return None
    import fnmatch
    for wz, dirs, ds in os.walk(projekt):
        dirs[:] = [d for d in dirs if d not in UEBERSPRINGEN]
        for d in ds:
            rel = os.path.relpath(os.path.join(wz, d), projekt).replace("\\", "/")
            for mu in muster:
                if fnmatch.fnmatch(rel, mu) or fnmatch.fnmatch(rel, mu.lstrip("*/")):
                    return True
    return False


def ist_projekt(p):
    return os.path.isfile(os.path.join(p, "CLAUDE.md")) \
        or os.path.isdir(os.path.join(p, ".claude"))


def projekte(wurzel):
    """Ein Projekt ist ein Verzeichnis mit CLAUDE.md oder .claude/.

    ⛔ Es wird IMMER eine Ebene tiefer weitergesucht, auch wenn das Elternverzeichnis
       selbst schon ein Projekt ist. Der erste Stand stieg nur ab, wenn der Vater
       KEIN Projekt war — dadurch fehlten `Plugin - Entwicklung/Claude Mind Manager`
       und `.../hackj-plugins` vollstaendig in der Pruefung: der Vater hat ein
       `.claude/`, also galt er als das Projekt und die Kinder wurden nie besucht.
       Aufgefallen nur, weil ein bekanntes Projekt weder unter den Befunden noch
       unter "ohne Befund" auftauchte — eine Liste, die etwas AUSLAESST, sieht
       genauso aus wie eine, in der nichts zu melden war."""
    raus = []
    for e in sorted(os.listdir(wurzel)):
        p = os.path.join(wurzel, e)
        if not os.path.isdir(p) or e.startswith(("_", ".")):
            continue
        if ist_projekt(p):
            raus.append(p)
        try:
            kinder = sorted(os.listdir(p))
        except OSError:
            continue
        for e2 in kinder:
            p2 = os.path.join(p, e2)
            if not os.path.isdir(p2) or e2.startswith(("_", ".")) or e2 in UEBERSPRINGEN:
                continue
            if ist_projekt(p2):
                raus.append(p2)
    return raus


def memory_dir(projekt):
    """Slug-Regel von Claude Code: JEDES Nicht-Alphanumerische wird zu '-'."""
    slug = re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(projekt))
    d = os.path.join(os.path.expanduser("~"), ".claude", "projects", slug, "memory")
    return d if os.path.isdir(d) else None


def pruefe(projekt):
    """Alle Befunde eines Projekts. Nur lesen."""
    b = []
    name = os.path.basename(projekt)

    def f(klasse, kurz, datei=""):
        b.append({"klasse": klasse, "kurz": kurz, "datei": datei, "projekt": projekt})

    # --- 1 · Memory ------------------------------------------------------
    md = memory_dir(projekt)
    if md:
        topics = [x for x in sorted(os.listdir(md))
                  if x.endswith(".md") and x != "MEMORY.md"]
        ohne_desc, offen, arbeit, lang, zeiger = [], [], [], [], []
        for x in topics:
            t = lies(os.path.join(md, x))
            kopf = "\n".join(t.replace("\r\n", "\n").split("\n")[:14])
            d = re.search(r"^description:[ \t]*(.*)$", kopf, re.M)
            besch = d.group(1).strip() if d else ""
            if not d:
                ohne_desc.append(x)
            elif len(besch) > 200:
                lang.append((x, len(besch)))
            # Zeiger-Fall: bezeichnet sich selbst als Verweis, ist aber nicht `reference`
            if besch and not re.search(r"^[ \t]*type:[ \t]*reference\b", kopf, re.M):
                if re.search(r"\bPointer\b|\bZeiger\b|globale Rule|~/\.claude/", besch):
                    zeiger.append(x)
            if frontmatter_offen(t):
                offen.append(x)
            if ARBEIT.search(kopf):
                arbeit.append(x)

        # ⭐ Am Binaerprogramm gelesen (2.1.237, 21.08.2026): der Auswaehler ist ein
        #    MODELL, das NUR Dateiname und `description` sieht — nie den Inhalt. Woertlich:
        #    "Only include memories that you are certain will be helpful based on their
        #    name and description." Eine ueberlange Beschreibung ist damit kein Detail,
        #    sondern der ganze Zugang zur Datei.
        if lang:
            f("sichtbarkeit",
              "%d Memory-Beschreibungen ueber 200 Zeichen (laengste %d) — der Auswaehler "
              "sieht NUR Name und description und ist auf Zurueckhaltung getrimmt "
              "(\"if you are unsure … do not include it\"): %s"
              % (len(lang), max(n for _, n in lang),
                 ", ".join("%s (%d)" % (a, b) for a, b in
                           sorted(lang, key=lambda z: -z[1])[:3])), md)
        # ⛔ `[user]` und `[project]` behandelt der Auswaehler AUSDRUECKLICH zurueckhaltender:
        #    "These describe the user's ongoing focus, not what every question is about."
        #
        # ⚠ Ein frueherer Stand meldete hier "ueber 60 % tragen type: project". Das war
        #   falsch gedacht: eine PROJEKT-Memory SOLL ueberwiegend `project` sein. Nicht der
        #   Anteil ist der Fehler, sondern eine EINZELNE Datei, die in den zurueckhaltenden
        #   Topf gehoert und dort nicht hingehoert. Gemessen an Zustellplan: von 25
        #   `project`-Dateien waren DREI falsch getypt, nicht 25.
        #
        # Mechanisch erkennbar ist davon nur der Zeiger-Fall — eine Datei, die sich selbst
        # als Verweis bezeichnet oder auf einen Pfad ausserhalb des Projekts zeigt, ist
        # `reference`. Der feedback-Fall ("sagt, WIE gearbeitet werden soll") laesst sich
        # aus einer Beschreibung nicht zuverlaessig ableiten und wird deshalb NICHT geraten.
        if zeiger:
            f("sichtbarkeit",
              "%d Memory-Dateien beschreiben sich als Verweis (Pointer / globale Rule / "
              "Pfad ausserhalb des Projekts), tragen aber nicht `type: reference`: %s"
              % (len(zeiger), ", ".join(zeiger[:5])), md)
        if ohne_desc:
            f("sichtbarkeit",
              "%d Memory-Topic-Dateien ohne `description` — der Auswaehler hat kein "
              "Signal, sie zaehlen aber voll gegen das Budget: %s"
              % (len(ohne_desc), ", ".join(ohne_desc[:5])), md)
        if offen:
            f("sichtbarkeit",
              "%d Memory-Dateien mit OFFENEM Frontmatter (erste Zeile `---`, keine "
              "zweite) — das ganze Dokument gilt als Kopf: %s"
              % (len(offen), ", ".join(offen[:5])), md)
        if arbeit:
            f("sonstiges",
              "%d Memory-Dateien tragen ARBEITSMATERIAL statt Wissen (Auftraege, "
              "Staende, Roadmaps): %s — Wissen gehoert ins Memory, Auszufuehrendes "
              "in eine Projektdatei" % (len(arbeit), ", ".join(arbeit[:5])), md)

    # --- 2 · Rules -------------------------------------------------------
    rd = os.path.join(projekt, ".claude", "rules")
    if os.path.isdir(rd):
        tot, offen = [], []
        for x in sorted(os.listdir(rd)):
            if not x.endswith(".md"):
                continue
            p = os.path.join(rd, x)
            if frontmatter_offen(lies(p)):
                offen.append(x)
            if globs_treffer(p, projekt) is False:
                tot.append(x)
        if offen:
            f("sichtbarkeit",
              "%d Regeldateien mit OFFENEM Frontmatter: %s"
              % (len(offen), ", ".join(offen[:5])), rd)
        if tot:
            f("sichtbarkeit",
              "%d Regeldateien, deren `globs:` KEINE Datei im Projekt trifft: %s "
              "(⚠ gemessen 2026-08: ein Muster ohne Treffer verhindert das Laden "
              "NICHT — der Befund ist ein Hinweis, kein Beweis)"
              % (len(tot), ", ".join(tot[:5])), rd)

    # --- 3 · CLAUDE.md ---------------------------------------------------
    cm = os.path.join(projekt, "CLAUDE.md")
    if os.path.isfile(cm):
        n = len(lies(cm).replace("\r\n", "\n").split("\n"))
        if n > 200:
            f("sonstiges",
              "CLAUDE.md hat %d Zeilen (kritisch ueber 200) — sie laedt bei JEDEM "
              "Start; Context Rot setzt ab ~25 %% Fensterfuellung ein" % n, cm)
    elif os.path.isdir(os.path.join(projekt, ".claude")):
        f("sonstiges", "Projekt hat .claude/, aber KEINE CLAUDE.md", projekt)

    # --- 4 · Werkzeuge ohne Companion-Rule -------------------------------
    td = os.path.join(projekt, "tools")
    if os.path.isdir(td) and os.path.isdir(rd):
        regeln = "".join(lies(os.path.join(rd, x))
                         for x in os.listdir(rd) if x.endswith(".md"))
        tot = [x for x in sorted(os.listdir(td))
               if x.endswith((".py", ".sh")) and ("tools/" + x) not in regeln]
        if tot:
            f("plugin-defekt",
              "%d Werkzeuge in tools/ ohne glob-getriggerte Companion-Rule (totes "
              "Werkzeug): %s" % (len(tot), ", ".join(tot[:5])), td)

    return b, name


def main():
    if len(sys.argv) < 2:
        print("Aufruf: learnings_scan.py <wurzel> [--jsonl <datei>] [--bericht <datei>]",
              file=sys.stderr)
        return 2
    wurzel = sys.argv[1]
    if not os.path.isdir(wurzel):
        print("kein Verzeichnis: %s" % wurzel, file=sys.stderr)
        return 2

    def arg(name):
        return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else None

    ps = projekte(wurzel)
    alle, ohne_befund = [], []
    print("=" * 72)
    print("  Strukturpruefung ueber %d Projekte" % len(ps))
    print("=" * 72)
    for p in ps:
        b, name = pruefe(p)
        if not b:
            ohne_befund.append(name)
            continue
        print()
        print("  %s  (%d)" % (name, len(b)))
        for x in b:
            print("    [%s] %s" % (x["klasse"], x["kurz"][:150]))
        alle.extend(b)

    print()
    print("-" * 72)
    print("  %d Befunde in %d von %d Projekten" % (len(alle), len(ps) - len(ohne_befund), len(ps)))
    if ohne_befund:
        print("  ohne Befund: %s" % ", ".join(ohne_befund))

    jf = arg("--jsonl")
    if jf:
        ts = arg("--ts") or ""
        with open(jf, "w", encoding="utf-8", newline="\n") as f:
            for x in alle:
                f.write(json.dumps({
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
             "| Befunde | **%d** |" % len(alle), ""]
        nach_proj = {}
        for x in alle:
            nach_proj.setdefault(os.path.basename(x["projekt"]), []).append(x)
        for name in sorted(nach_proj, key=lambda k: -len(nach_proj[k])):
            z.append("## %s (%d)" % (name, len(nach_proj[name])))
            z.append("")
            for x in nach_proj[name]:
                z.append("- **[%s]** %s" % (x["klasse"], x["kurz"]))
            z.append("")
        if ohne_befund:
            z += ["## Ohne Befund", "", ", ".join(ohne_befund), ""]
        open(bf, "w", encoding="utf-8", newline="\n").write("\n".join(z))
        print("  Bericht -> %s" % bf)
    return 0


if __name__ == "__main__":
    sys.exit(main())
