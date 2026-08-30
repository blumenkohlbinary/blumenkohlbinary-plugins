# -*- coding: utf-8 -*-
"""Ist die zurueckgebliebene Kurz-Rule noch eine LEITPLANKE — oder schon wieder Mechanik?

⛔ WOZU. `cleaner_umzug.py` sagt im eigenen Kopf: **„EIN UMZUG VERSCHIEBT. ER KUERZT
   NICHT."** Damit endet ein Umzug bei einer Kurz-Rule beliebiger Groesse, und niemand
   merkt, wenn sie zu gross geblieben ist. Gemessen 28.08.2026 an fuenf umgezogenen
   Regeln: vier lagen bei 19-33 Zeilen, `workstation-fernzugriff` bei **63** — mit
   MAC-Adressen, Durchsatztabellen und `sudoers`-Dateinamen darin. Kein Gate hat das
   je gemeldet, weil keines danach fragt.

⭐ DER UNTERSCHIED, DEN DIESES WERKZEUG SUCHT — Bremse gegen Anleitung:

     Bremse      haelt dich vom Falschen ab, BEVOR du merkst, dass du nachschlagen
                 solltest. Muss in der Rule stehen, sonst kommt sie zu spaet.
     Anleitung   brauchst du erst, WAEHREND du arbeitest. Dann hast du den Command
                 ohnehin geladen. Gehoert dorthin.

   Beispiel aus dem echten Bestand: *„suspend NUR auf ausdrueckliche Ansage"* ist eine
   Bremse — wer aufraeumen will, laedt keinen Skill dafuer. *„834-941 MB/s, wer weniger
   misst, hat seinen Aufbau gemessen"* ist Anleitung — beim Messen ist der Command da.

⛔ ES URTEILT NICHT, ES LEGT KANDIDATEN VOR. Ob ein Satz Bremse oder Anleitung ist, ist
   eine Bedeutungsfrage; mechanisch entscheidbar sind nur **Formmerkmale**. Deshalb drei
   eng gefasste Klassen, und Zahlen sind AUSDRUECKLICH keine davon — im echten Bestand
   traegt die Bremse die Zahl mit („834-941 MB/s" steht IN der Fehlmessungs-Warnung).

⚠ DIE KORPUS-SPANNE WIRD GEMESSEN, NICHT VERDRAHTET. Eine einmal erhobene Zahl fest
  einzutragen ist in diesem Projekt sechsmal schiefgegangen. Der Vergleichswert kommt
  aus den Geschwister-Leitplanken des Laufs, und die Fallzahl steht dabei
  (`messung-vor-glauben.md` §3: keine Kennzahl ohne Fallzahl).

Aufruf:
  python cleaner_leitplanke.py --rule <kurz.md> --skill <skill.md>
  python cleaner_leitplanke.py --verzeichnis <rules-dir> --skills <skills-dir>
  python cleaner_leitplanke.py --selbsttest

Rueckgabe: 0 = keine Kandidaten · 1 = Kandidaten gefunden · 2 = Aufruffehler
           3 = Selbsttest gescheitert
"""
import io
import os
import re
import shutil
import sys
import tempfile

# ⛔ IDEMPOTENT — nicht bedingungslos. Huellt ein aufrufendes
#    Skript stdout schon ein und importiert dann dieses Modul, haengen
#    sonst ZWEI Wrapper am selben Puffer; wird einer eingesammelt,
#    schliesst er den Puffer des anderen und jedes weitere print()
#    bricht mit "I/O operation on closed file" — und zwar NACH der
#    letzten erfolgreichen Ausgabe, also an der falschen Stelle.
#    Zweimal gemessen am 30.08.2026 beim Bau von cleaner_tor.py.
_ENC = (getattr(sys.stdout, "encoding", "") or "").lower().replace("-", "")
if _ENC != "utf8":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# ── Die drei Formklassen ─────────────────────────────────────────────────────
# ⛔ Bewusst ENG. Ein breiter Filter faengt die Bremsen mit, und dann wird die
#    Leitplanke kleingeschnitten statt der Mechanik. Lieber ein Kandidat zu
#    wenig — Uebersehen kostet Zeilen, Falschmelden kostet die Bremse.
ADRESSE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b|\b(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\b")
SYSPFAD = re.compile(r"(?<![\w/])/(?:etc|usr|var|proc|sys)/[\w./-]+")
PLATZHALTER = re.compile(r"<[^>]{1,40}>|\$\{?[A-Z_]{2,}")

# Zeilen, die eine BREMSE tragen — die zaehlen nie als Kandidat.
BREMSE = re.compile(r"⛔|⚠|\bNEVER\b|\bMUST\b|\bALWAYS\b|\bNIE\b|\bNUR\b|\bKEIN")


def zeilen(text):
    return [z for z in text.split("\n")]


def inhaltszeilen(text):
    """Ohne Frontmatter und ohne Leerzeilen — wie in cleaner_umzug.py."""
    t = re.sub(r"^---\n.*?\n---\n", "", text, count=1, flags=re.S)
    return [z for z in t.split("\n") if z.strip()]


def fence_bereiche(zs):
    """-> Menge der Zeilenindizes INNERHALB von ```-Bloecken."""
    drin, offen = set(), False
    for i, z in enumerate(zs):
        if z.strip().startswith("```"):
            offen = not offen
            continue
        if offen:
            drin.add(i)
    return drin


def kandidaten(text):
    """-> [(zeilennr, klasse, ausschnitt)]  — Formmerkmale, kein Urteil."""
    zs = zeilen(text)
    im_fence = fence_bereiche(zs)
    aus = []
    for i, z in enumerate(zs):
        s = z.strip()
        if not s or s.startswith("```"):
            continue
        # ⛔ Eine Zeile mit Bremse wird NIE Kandidat — auch wenn eine Adresse
        #    darin vorkommt. "10.10.10.1 ZUERST, sonst ist das ein BEFUND" ist
        #    die Bremse selbst.
        if BREMSE.search(z):
            continue

        if ADRESSE.search(s):
            aus.append((i + 1, "adresse", s[:72]))
        elif SYSPFAD.search(s):
            aus.append((i + 1, "syspfad", s[:72]))
        elif i in im_fence and not PLATZHALTER.search(s) and len(s.split()) >= 3:
            # Ein Befehl MIT konkreten Argumenten. Mit `<platzhalter>` oder
            # `$VARIABLE` ist es eine Form, keine Anleitung — die darf bleiben.
            aus.append((i + 1, "befehl", s[:72]))
    return aus


def bremsanteil(text):
    ih = inhaltszeilen(text)
    if not ih:
        return 0.0
    return sum(1 for z in ih if BREMSE.search(z)) / len(ih)


def zeiger(text):
    """-> (nennt_pfad, nennt_command)

    ⛔ BEIDE, und der PFAD ist der wichtigere. Gemessen (cleaner_umzug.py Gate 3):
       Volltext ueber den PFAD 4 von 4 · ueber die Skill-AUSWAHL 20-84 %.
       Der Command ist die bequeme Route, der Pfad die verlaessliche.
    """
    pfad = bool(re.search(r"\.claude/skills/[\w-]+/SKILL\.md", text))
    cmd = bool(re.search(r"(?<![\w/])/[a-z][\w-]{3,}", text))
    return pfad, cmd


# ── Bericht ──────────────────────────────────────────────────────────────────

def pruefe(rule_pfad, skill_pfad, spanne=None, n_korpus=0):
    try:
        rt = open(rule_pfad, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print("  ⛔ Rule nicht lesbar: %s" % e)
        return None
    st = ""
    if skill_pfad and os.path.isfile(skill_pfad):
        st = open(skill_pfad, encoding="utf-8", errors="replace").read()

    n_r = len(inhaltszeilen(rt))
    n_s = len(inhaltszeilen(st)) if st else 0
    kand = kandidaten(rt)
    br = bremsanteil(rt)
    pfad, cmd = zeiger(rt)

    name = os.path.basename(rule_pfad)
    lage = ""
    if spanne and n_korpus >= 3:
        lo, hi = spanne
        if n_r > hi:
            lage = "  ⚠ ueber der Korpus-Spanne %d-%d (n=%d)" % (lo, hi, n_korpus)
        else:
            lage = "  (Korpus %d-%d, n=%d)" % (lo, hi, n_korpus)

    print("  %-32s %3d Z. Rule · %4d Z. Command · Bremsanteil %2d %%%s"
          % (name, n_r, n_s, round(br * 100), lage))
    if not pfad:
        print("       ⛔ ZEIGER OHNE PFAD — faellt auf die 20-%-Skill-Auswahl zurueck")
    if not cmd:
        print("       ⚠ nennt den Command nicht (nur den Pfad) — Bequemlichkeit fehlt")
    for nr, klasse, txt in kand:
        print("       KANDIDAT Z%-4d [%-7s] %s" % (nr, klasse, txt))
    return kand


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()

    def hol(f):
        return argv[argv.index(f) + 1] if f in argv and argv.index(f) + 1 < len(argv) else None

    verz, skills = hol("--verzeichnis"), hol("--skills")
    if verz:
        if not os.path.isdir(verz):
            print("  ⛔ kein Verzeichnis: %s" % verz)
            return 2
        paare = []
        for f in sorted(os.listdir(verz)):
            if not f.endswith(".md"):
                continue
            sp = os.path.join(skills or "", f[:-3], "SKILL.md")
            if skills and os.path.isfile(sp):
                paare.append((os.path.join(verz, f), sp))
        if not paare:
            print("  (nichts) — keine Rule mit gleichnamigem Command gefunden")
            return 0
        # ⚠ Spanne AUS DEM LAUF, nicht verdrahtet.
        laengen = sorted(len(inhaltszeilen(open(r, encoding="utf-8", errors="replace").read()))
                         for r, _ in paare)
        spanne = (laengen[0], laengen[len(laengen) // 2])
        print("  %d Rule(s) mit gleichnamigem Command · Korpus-Median %d Zeilen"
              % (len(paare), laengen[len(laengen) // 2]))
        print()
        alle = 0
        for r, s in paare:
            k = pruefe(r, s, spanne, len(paare))
            alle += len(k or [])
        print()
        print("  %d Kandidat(en) gesamt. ⛔ Kandidaten sind KEIN Urteil — sie sind die"
              % alle)
        print("     Liste, die ein Mensch durchsieht. Schneiden bleibt /mind-cleaner.")
        return 1 if alle else 0

    r, s = hol("--rule"), hol("--skill")
    if not r:
        print(__doc__.split("Aufruf:")[1])
        return 2
    k = pruefe(r, s)
    return 1 if k else 0


# ── Selbsttest ───────────────────────────────────────────────────────────────

def selbsttest():
    ok = rot = 0

    def janein(name, erwartet, ist):
        nonlocal ok, rot
        if erwartet == ist:
            print("  [ok ] %s" % name)
            ok += 1
        else:
            print("  [ROT] %s — erwartet %r, bekommen %r" % (name, erwartet, ist))
            rot += 1

    # ⭐ POSITIVKONTROLLE: eine Rule, die nachweislich Mechanik traegt.
    #    Nachgebaut nach der echten workstation-Fassung vom 28.08.2026 (63 Zeilen).
    DICK = """# Maschine — Leitplanke

Erreichbar per SSH.

```bash
ssh -o BatchMode=yes workiii@10.10.10.1 'uptime'
sudo -n systemctl poweroff -i
```

Die MAC `30:c5:99:aa:56:b4` traegt das LAN.
Die Freigabe steht in /etc/sudoers.d/ki-befehle.

⛔ **Nur auf ausdrueckliche Ansage herunterfahren.**

> Volltext: `~/.claude/skills/maschine/SKILL.md`
"""
    # ⭐ NEGATIVKONTROLLE: eine echte Leitplanke — muss STILL bleiben.
    #    Ohne sie waere ein Filter, der alles meldet, ebenso "erfolgreich".
    DUENN = """# Ablage — Leitplanke

⛔ **NIE mit Edit/Write schreiben** — stiller Datenverlust, reproduziert.
⚠ Alter und Datum NUR ueber die API, nie ueber LastWriteTime.
⛔ Aufraeumen heisst verschieben, NIE loeschen.

> **Alles Weitere steht im Command `/ablage`.** Sonst
> `~/.claude/skills/ablage/SKILL.md` direkt lesen.
"""

    k_dick = kandidaten(DICK)
    k_duenn = kandidaten(DUENN)
    klassen = sorted(set(k for _, k, _ in k_dick))

    janein("1 dicke Rule liefert Kandidaten", True, len(k_dick) >= 3)
    # ⛔ JE KLASSE EIN EIGENER TRAEGER. Die erste Fassung hatte nur EINE
    #    Befehlszeile, und die enthielt eine Adresse — die `elif`-Kette stufte
    #    sie als `adresse` ein, `befehl` blieb ungetestet und der Fall meldete
    #    ROT. Nicht der Filter war falsch, sondern der Prueffall: ein Traeger
    #    mit zwei Signalen belegt nur, dass EINES lebt. Dieselbe Lehre wie bei
    #    test_kontext_bilanz.sh Fall 9 (27.08.2026).
    janein("1 alle drei Klassen erkannt", ["adresse", "befehl", "syspfad"], klassen)
    janein("2 NEGATIVKONTROLLE: echte Leitplanke schweigt", [], k_duenn)

    # ⛔ Die Bremszeile der dicken Rule darf NICHT gemeldet werden.
    janein("3 Bremszeile ist kein Kandidat", True,
           not any("ausdrueckliche Ansage" in t for _, _, t in k_dick))

    # ⛔ Und eine Adresse INNERHALB einer Bremse ebenfalls nicht.
    MIT = "⛔ **`10.10.10.1` ZUERST** — sonst ist es ein BEFUND.\n"
    janein("3b Adresse in einer Bremszeile wird verschont", [], kandidaten(MIT))

    # Platzhalter-Befehle bleiben verschont (Form, keine Anleitung)
    FORM = "```bash\nssh … 'kein-suspend an \"<Chat> | <was>\"'\n```\n"
    janein("4 Befehl mit <platzhalter> ist kein Kandidat", [], kandidaten(FORM))
    FORM2 = "```bash\ncp \"$ZIEL_MD\" \"$BDIR/x.bak\"\n```\n"
    janein("4b Befehl mit $VARIABLE ist kein Kandidat", [], kandidaten(FORM2))

    # Zeiger
    janein("5 Pfad+Command erkannt", (True, True), zeiger(DUENN))
    janein("5b nur Pfad erkannt", (True, False), zeiger(DICK))
    janein("5c gar kein Zeiger", (False, False), zeiger("# X\n\nNur Text.\n"))

    # Bremsanteil
    janein("6 duenne Rule hat hohen Bremsanteil", True, bremsanteil(DUENN) > 0.4)
    janein("6b dicke Rule hat niedrigen", True, bremsanteil(DICK) < 0.4)

    # ⚠ Zahlen sind AUSDRUECKLICH keine Klasse — sonst faengt der Filter die
    #   Bremse mit, die ihre Messung nennt.
    ZAHL = "Roh gemessen 834-941 MB/s. Wer darunter misst, hat seinen Aufbau gemessen.\n"
    janein("7 Messwert allein ist kein Kandidat", [], kandidaten(ZAHL))

    # Ende-zu-Ende ueber echte Dateien
    d = tempfile.mkdtemp(prefix="leitplanke_")
    rd, sd = os.path.join(d, "rules"), os.path.join(d, "skills")
    os.makedirs(os.path.join(sd, "maschine"))
    os.makedirs(rd)
    open(os.path.join(rd, "maschine.md"), "w", encoding="utf-8", newline="\n").write(DICK)
    open(os.path.join(sd, "maschine", "SKILL.md"), "w", encoding="utf-8",
         newline="\n").write("# Voll\n\n" + DICK)
    rc = main_mit(["--verzeichnis", rd, "--skills", sd])
    janein("8 Verzeichnislauf meldet Kandidaten (rc=1)", 1, rc)
    # Rule ohne gleichnamigen Command -> nichts zu tun, kein Fehler
    os.remove(os.path.join(rd, "maschine.md"))
    open(os.path.join(rd, "fremd.md"), "w", encoding="utf-8", newline="\n").write(DUENN)
    janein("8b Rule ohne Command wird uebersprungen (rc=0)", 0,
           main_mit(["--verzeichnis", rd, "--skills", sd]))
    shutil.rmtree(d, ignore_errors=True)

    print()
    print("  %d ok, %d rot" % (ok, rot))
    return 3 if rot else 0


def main_mit(argv):
    """main() mit gesetztem argv — damit der Selbsttest den echten Weg faehrt."""
    alt = sys.argv
    sys.argv = ["cleaner_leitplanke.py"] + argv
    try:
        buf = io.StringIO()
        echt, sys.stdout = sys.stdout, buf
        try:
            return main()
        finally:
            sys.stdout = echt
    finally:
        sys.argv = alt


if __name__ == "__main__":
    sys.exit(main())
