#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Stille Kappungen — pruefen, BEVOR Inhalt an einen Ort verschoben wird.

⛔ WARUM ES DAS GIBT

Ein Aufraeum-Werkzeug, das eine stille Grenze nicht kennt, verschiebt Inhalt an
einen Ort, wo er **lautlos abgeschnitten** wird. Das ist schlimmer als gar nicht
aufraeumen: vorher war der Text zu lang, nachher ist er weg — und niemand merkt
es, weil keine Meldung erscheint.

## Die Grenzen, nach Gefaehrlichkeit sortiert

    STILL (Inhalt weg, keine Meldung)
      MEMORY.md            200 Zeilen ODER 25 KB       [ISSUE] #25006
      paths:-Glob-Budget   1000 Muster / 4 MiB         [DOKU]
                           -> Muster bleibt unexpandiert, die Regel feuert
                              danach NIE mehr, lautlos
      @-Import-Tiefe       4 Hops                      [DOKU]
      Skill-description    1536 Zeichen (mit when_to_use) [DOKU]
      HTML-Kommentare      werden VOR jeder Injektion entfernt [DOKU]
      Hook-Ausgabe         10 000 Zeichen              [ISSUE] #44086, #70460
      MCP-Instructions     ~4 KB gesamt                [ISSUE] #43474

    LAUT (erkennbar, kein stiller Verlust)
      CLAUDE.md / Rule     4 MiB je Datei -> Datei wird GANZ uebersprungen

⭐ **Die gefaehrlichste ist das paths:-Budget.** Alle anderen kappen Inhalt.
Diese eine macht eine ganze REGEL unwirksam, ohne etwas zu veraendern, das man
sehen koennte.

⚠ **HTML-Kommentare sind keine Ablage.** Wer Inhalt dort "archiviert", hat ihn
geloescht, nicht versteckt. Das Werkzeug meldet sie deshalb als Verlust, nicht
als Fundstelle.

Aufruf:
  python cleaner_grenzen.py --ziel <pfad> [--dazu <datei>]
  python cleaner_grenzen.py --bestand <projekt>
  python cleaner_grenzen.py --selbsttest

Rueckgabe: 0 = passt · 1 = Grenze gerissen oder nah dran · 2 = nicht messbar
"""
import io
import os
import re
import sys

# ⛔ `newline=""` ist PFLICHT auf Windows. Ohne diesen Zusatz uebersetzt
#    TextIOWrapper jeden Zeilenumbruch in die Windows-Fassung (CR + LF).
#    Jede zeilenverankerte Zusicherung (das Dollarzeichen in grep) bricht
#    dann — und zwar STILL, denn die Ausgabe sieht voellig richtig aus.
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", newline="")

MEMORY_ZEILEN = 200
MEMORY_BYTES = 25 * 1024
SKILL_DESC = 1536
PATHS_MUSTER = 1000
IMPORT_TIEFE = 4
HOOK_AUSGABE = 10000
DATEI_MAX = 4 * 1024 * 1024

# ⚠ Ab dieser Auslastung wird gewarnt, nicht erst beim Reissen. Eine Grenze,
#   die man erst bemerkt, wenn sie gerissen ist, hat ihren Zweck verfehlt.
NAH = 0.85


def _lies(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return None


def _art(pfad):
    n = os.path.basename(pfad)
    p = pfad.replace("\\", "/")
    if n == "MEMORY.md":
        return "memory"
    if n == "SKILL.md" or "/skills/" in p:
        return "skill"
    if "/rules/" in p or "/.claude/rules" in p:
        return "rule"
    if n == "CLAUDE.md":
        return "claudemd"
    if p.endswith((".sh", ".py")) and "/hooks/" in p:
        return "hook"
    return "sonstiges"


def _beschreibung(t):
    z = t.split("\n")
    if not z or z[0].strip() != "---":
        return None
    ende = next((i for i in range(1, len(z)) if z[i].strip() == "---"), None)
    if ende is None:
        return None
    kopf = z[1:ende]
    teile = []
    for i, zeile in enumerate(kopf):
        m = re.match(r"^(description|when_to_use):\s*(.*)$", zeile)
        if not m:
            continue
        rest = m.group(2).strip()
        if rest in ("|", ">", "|-", ">-"):
            for w in kopf[i + 1:]:
                if w.strip() and not w.startswith((" ", "\t")):
                    break
                teile.append(w.strip())
        else:
            teile.append(rest)
    return " ".join(x for x in teile if x) if teile else None


def _paths_muster(t):
    """Zahl der Muster im `paths:`/`globs:`-Feld — inklusive Klammer-Expansion.

    ⚠ `{a,b,c}` in einem Muster ist DREI Muster nach der Expansion. Wer nur
      Kommata auf oberster Ebene zaehlt, unterschaetzt das Budget dramatisch.
    """
    z = t.split("\n")
    if not z or z[0].strip() != "---":
        return 0
    ende = next((i for i in range(1, len(z)) if z[i].strip() == "---"), None)
    if ende is None:
        return 0
    roh = ""
    for zeile in z[1:ende]:
        m = re.match(r"^(paths|globs):\s*(.*)$", zeile)
        if m:
            roh = m.group(2)
            break
    if not roh:
        return 0
    stuecke = [s.strip().strip('"\'') for s in
               roh.strip("[]").split(",") if s.strip()]
    gesamt = 0
    for s in stuecke:
        n = 1
        for gruppe in re.findall(r"\{([^}]*)\}", s):
            n *= max(1, len(gruppe.split(",")))
        gesamt += n
    return gesamt


def _import_tiefe(pfad, gesehen=None, tiefe=0):
    """Wie tief geht die @-Import-Kette? ⚠ Zyklen brechen die Rekursion."""
    gesehen = gesehen or set()
    real = os.path.abspath(os.path.expanduser(pfad))
    if real in gesehen or tiefe > 12:
        return tiefe
    gesehen.add(real)
    t = _lies(real)
    if t is None:
        return tiefe
    tiefste = tiefe
    for m in re.findall(r"^@([^\s]+)", t, re.M):
        ziel = m if os.path.isabs(m) or m.startswith("~") else \
            os.path.join(os.path.dirname(real), m)
        tiefste = max(tiefste, _import_tiefe(ziel, gesehen, tiefe + 1))
    return tiefste


def pruefe(ziel, dazu_text=""):
    """(befunde, art) — je Befund (schwere, name, text). schwere: BRUCH|NAH|ok"""
    t = _lies(ziel)
    if t is None and not dazu_text:
        return None, None
    t = (t or "") + dazu_text
    art = _art(ziel)
    b = []

    def melde(name, ist, grenze, still, einheit=""):
        anteil = ist / float(grenze) if grenze else 0
        if ist > grenze:
            b.append(("BRUCH", name, "%d %s > %d — %s"
                      % (ist, einheit, grenze,
                         "STILL abgeschnitten" if still else "Datei wird uebersprungen")))
        elif anteil >= NAH:
            b.append(("NAH", name, "%d %s von %d (%.0f %%)"
                      % (ist, einheit, grenze, anteil * 100)))
        else:
            b.append(("ok", name, "%d %s von %d" % (ist, einheit, grenze)))

    if art == "memory":
        melde("MEMORY Zeilen", len(t.split("\n")), MEMORY_ZEILEN, True, "Zeilen")
        melde("MEMORY Bytes", len(t.encode("utf-8")), MEMORY_BYTES, True, "B")
    if art == "skill":
        d = _beschreibung(t)
        name = os.path.basename(os.path.dirname(ziel)) or os.path.basename(ziel)
        if d is None:
            b.append(("BRUCH", "Skill-description", "FEHLT — der Auswaehler "
                                                    "sieht nur Name und description"))
        else:
            melde("Skill-description", len(name) + len(d), SKILL_DESC, True, "Zeichen")
    if art in ("rule", "claudemd"):
        n = _paths_muster(t)
        if n:
            melde("paths:-Muster", n, PATHS_MUSTER, True, "Muster")
        melde("Dateigroesse", len(t.encode("utf-8")), DATEI_MAX, False, "B")
    if art == "hook":
        melde("Hook-Ausgabe (Datei)", len(t.encode("utf-8")), HOOK_AUSGABE, True, "B")

    tiefe = _import_tiefe(ziel) if os.path.isfile(ziel) else 0
    if tiefe:
        melde("@-Import-Tiefe", tiefe, IMPORT_TIEFE, True, "Hops")

    # ⛔ HTML-Kommentare sind KEINE Ablage. Wer dort etwas ablegt, loescht es.
    komm = re.findall(r"<!--.*?-->", t, re.S)
    zeilen = sum(len([z for z in k.split("\n") if z.strip()]) for k in komm)
    if zeilen:
        b.append(("BRUCH", "HTML-Kommentare",
                  "%d Zeile(n) in %d Kommentar(en) — werden VOR der Injektion "
                  "entfernt, erreichen das Modell NIE" % (zeilen, len(komm))))
    return b, art


def bericht(befunde, art, ziel):
    print("=" * 78)
    print("  Grenzen-Pruefung: %s" % os.path.basename(ziel))
    print("  erkannt als: %s" % art)
    print("=" * 78)
    for schwere, name, txt in befunde:
        marke = {"BRUCH": "⛔", "NAH": "⚠", "ok": "  "}[schwere]
        print("  %s %-22s %s" % (marke, name, txt))
    brueche = [x for x in befunde if x[0] == "BRUCH"]
    nah = [x for x in befunde if x[0] == "NAH"]
    print()
    if brueche:
        print("  ⛔ NICHT VERSCHIEBEN. %d Grenze(n) gerissen." % len(brueche))
        print("     Alle STILLEN Grenzen kappen ohne Meldung — was hier nicht")
        print("     passt, ist danach weg, nicht gekuerzt.")
    elif nah:
        print("  ⚠ Passt, aber knapp. Der naechste Umzug reisst die Grenze.")
    else:
        print("  Alle geprueften Grenzen halten.")
    return 1 if (brueche or nah) else 0


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

    def schreib(rel, text):
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        return p

    def schwere(befunde, name):
        return next((s for s, n, _ in befunde if n == name), "fehlt")

    print("=" * 78)
    print("  Selbsttest — jede Grenze muss BRECHEN und HALTEN koennen")
    print("=" * 78)

    # MEMORY.md — beide Richtungen
    klein = schreib("m1/MEMORY.md", "# M\n" + "Zeile\n" * 50)
    b, _ = pruefe(klein)
    pruef("MEMORY klein -> ok", schwere(b, "MEMORY Zeilen"), "ok")
    gross = schreib("m2/MEMORY.md", "# M\n" + "Zeile\n" * 300)
    b, _ = pruefe(gross)
    pruef("MEMORY 300 Zeilen -> BRUCH", schwere(b, "MEMORY Zeilen"), "BRUCH")
    # ⚠ Die Warnschwelle, ohne die man die Grenze erst beim Reissen bemerkt.
    knapp = schreib("m3/MEMORY.md", "# M\n" + "Zeile\n" * 180)
    b, _ = pruefe(knapp)
    pruef("MEMORY 181 Zeilen -> NAH", schwere(b, "MEMORY Zeilen"), "NAH")

    # Skill-description
    kurz = schreib("s1/skills/x/SKILL.md",
                   "---\nname: x\ndescription: Eine ausreichend lange Beschreibung "
                   "die sagt worum es geht\n---\n# X\n")
    b, _ = pruefe(kurz)
    pruef("Skill-description kurz -> ok", schwere(b, "Skill-description"), "ok")
    lang = schreib("s2/skills/y/SKILL.md",
                   "---\nname: y\ndescription: " + ("x" * 1600) + "\n---\n# Y\n")
    b, _ = pruefe(lang)
    pruef("Skill-description 1600 -> BRUCH", schwere(b, "Skill-description"), "BRUCH")
    ohne = schreib("s3/skills/z/SKILL.md", "---\nname: z\n---\n# Z\n")
    b, _ = pruefe(ohne)
    pruef("Skill ohne description -> BRUCH", schwere(b, "Skill-description"), "BRUCH")

    # ⭐ paths:-Budget — die gefaehrlichste Grenze, mit Klammer-Expansion
    pruef("Klammer zaehlt expandiert",
          _paths_muster('---\npaths: ["a/{x,y,z}/**", "b/**"]\n---\n'), 4)
    wenig = schreib("r1/.claude/rules/a.md", '---\npaths: ["src/**"]\n---\n# A\n')
    b, _ = pruefe(wenig)
    pruef("paths: 1 Muster -> ok", schwere(b, "paths:-Muster"), "ok")
    viel = schreib("r2/.claude/rules/b.md",
                   '---\npaths: ["%s"]\n---\n# B\n'
                   % ("{" + ",".join(str(i) for i in range(1100)) + "}"))
    b, _ = pruefe(viel)
    pruef("paths: 1100 Muster -> BRUCH", schwere(b, "paths:-Muster"), "BRUCH")

    # HTML-Kommentare
    ohne_k = schreib("h1/.claude/rules/c.md", "---\ndescription: x\n---\n# C\nText\n")
    b, _ = pruefe(ohne_k)
    pruef("ohne Kommentar -> kein Befund", schwere(b, "HTML-Kommentare"), "fehlt")
    mit_k = schreib("h2/.claude/rules/d.md",
                    "---\ndescription: x\n---\n# D\n<!--\nversteckt\nauch das\n-->\n")
    b, _ = pruefe(mit_k)
    pruef("mit Kommentar -> BRUCH", schwere(b, "HTML-Kommentare"), "BRUCH")

    # @-Import-Tiefe
    schreib("i1/e.md", "@f.md\n")
    schreib("i1/f.md", "@g.md\n")
    schreib("i1/g.md", "@h.md\n")
    schreib("i1/h.md", "@i.md\n")
    schreib("i1/i.md", "@j.md\n")
    schreib("i1/j.md", "Ende\n")
    b, _ = pruefe(os.path.join(d, "i1/e.md"))
    pruef("Import-Kette 5 tief -> BRUCH", schwere(b, "@-Import-Tiefe"), "BRUCH")
    # ⚠ Zyklus darf nicht in die Rekursion laufen.
    schreib("i2/k.md", "@l.md\n")
    schreib("i2/l.md", "@k.md\n")
    t = _import_tiefe(os.path.join(d, "i2/k.md"))
    pruef("Zyklus bricht ab statt zu haengen", t <= 12, True)

    # ⛔ `--dazu`: die eigentliche Frage vor einem Umzug.
    b, _ = pruefe(knapp, dazu_text="Zeile\n" * 40)
    pruef("knapp + 40 Zeilen -> BRUCH", schwere(b, "MEMORY Zeilen"), "BRUCH")

    # Nicht messbar
    b, art = pruefe(os.path.join(d, "gibtsnicht.md"))
    pruef("fehlende Datei -> nicht messbar", b, None)

    print("\n=== %d Abweichung(en) ===" % fehler)
    return 3 if fehler else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()

    def hol(f):
        return argv[argv.index(f) + 1] if f in argv and len(argv) > argv.index(f) + 1 else None

    if "--bestand" in argv:
        projekt = hol("--bestand") or os.getcwd()
        H = os.path.expanduser("~")
        kandidaten = []
        for d in (os.path.join(H, ".claude", "rules"),
                  os.path.join(projekt, ".claude", "rules")):
            if os.path.isdir(d):
                kandidaten += [os.path.join(d, f) for f in sorted(os.listdir(d))
                               if f.endswith(".md")]
        for f in (os.path.join(H, ".claude", "CLAUDE.md"),
                  os.path.join(projekt, "CLAUDE.md")):
            if os.path.isfile(f):
                kandidaten.append(f)
        if not kandidaten:
            print("⛔ Nichts gefunden unter %s — eher ein falscher Pfad." % projekt)
            return 2
        rc = 0
        print("=" * 78)
        print("  Grenzen im Bestand — %d Datei(en)" % len(kandidaten))
        print("=" * 78)
        for k in kandidaten:
            b, _ = pruefe(k)
            auff = [x for x in (b or []) if x[0] in ("BRUCH", "NAH")]
            if auff:
                rc = 1
                print("\n  %s" % os.path.relpath(k, os.path.dirname(k) + "/.."))
                for s, n, txt in auff:
                    print("     %s %-22s %s" % ("⛔" if s == "BRUCH" else "⚠", n, txt))
        if rc == 0:
            print("  Keine Grenze gerissen oder nah dran.")
        return rc

    ziel = hol("--ziel")
    if not ziel:
        print(__doc__.split("Aufruf:")[1])
        return 2
    dazu = ""
    dp = hol("--dazu")
    if dp:
        dazu = _lies(dp) or ""
    b, art = pruefe(ziel, dazu)
    if b is None:
        print("⛔ NICHT MESSBAR — %s ist nicht lesbar." % ziel)
        print("   Das ist KEIN bestandenes Gate.")
        return 2
    return bericht(b, art, ziel)


if __name__ == "__main__":
    sys.exit(main())
