# -*- coding: utf-8 -*-
"""Hat der angewendete Fix die Zahl bewegt, die er bewegen soll?

⛔ DER ANLASS (Nutzer-Meldung 30.08.2026, woertlich): *„cleaner_duplikate.py hat mir
   447 Duplikate gemeldet … Ich habe die Zahl gelesen und trotzdem nur umgeraeumt.
   Ein Duplikat, das umzieht, ist immer noch ein Duplikat — jetzt nur in zwei
   Dateien, die beide immer laden."*

⭐ DAS IST EINE ANDERE FEHLERKLASSE ALS DIE SCHRITT-QUITTUNG (v5.25.0). Die belegt,
   dass ein Schritt LIEF. Sie kann nicht sehen, ob der Befund BEHANDELT wurde —
   und schon gar nicht, ob die Behandlung die richtige war. Hier lag beides vor:
   der Schritt lief, der Befund wurde gelesen, und der angewendete Fix konnte die
   gemeldete Zahl per Konstruktion nicht senken.

⛔ MODULARIZE UND DEDUPLICATE SIND NICHT AUSTAUSCHBAR — das steht im Skill selbst:

     Modularize   VERSCHIEBT. Die Summe bleibt gleich; mind-claudemd Step 4e sagt
                  woertlich "Modularize spart KEINEN Kontext" (eine Rule laedt
                  auch mit `globs:` ohne Treffer, gemessen an CC 2.1.237).
     Deduplicate  macht EINE Stelle zum Zeiger. Erst dadurch sinkt die Summe.

   Wer auf einen DUPLIKAT-Befund ein Modularize anwendet, hat den Befund nicht
   behoben, sondern auf zwei Dateien verteilt, die beide immer laden.

⭐ DIE MESSUNG IST TRIVIAL UND WAR TROTZDEM NICHT DA: die Kennzahl vor dem Fix
   gegen die Kennzahl danach. Sinkt sie nicht, hat der Fix nicht gewirkt — egal
   wie gut der Bericht klingt.

⚠ WAS ES NICHT KANN. Es misst die WIRKUNG auf eine Kennzahl, nicht die GUETE der
  Aenderung. Ein Fix, der die Zahl senkt und dabei Wissen zerstoert, besteht dieses
  Gate. Deshalb ersetzt es die Gates aus `cleaner_umzug.py` nicht, es kommt dazu.

Aufruf:
  python cleaner_wirkung.py --vorher <bereich>              # Kennzahlen merken
  python cleaner_wirkung.py --nachher <bereich> [--erwartet duplikate,zeilen]
  python cleaner_wirkung.py --selbsttest

Rueckgabe: 0 = jede erwartete Kennzahl ist gesunken (oder nichts erwartet)
           1 = eine erwartete Kennzahl ist NICHT gesunken
           2 = Aufruffehler / kein Vorher-Stand
           3 = Selbsttest gescheitert
"""
import io
import json
import os
import shutil
import subprocess
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

STAND = ".claude-mind/wirkung-vorher.json"
HIER = os.path.dirname(os.path.abspath(__file__))


def _stand_pfad(bereich):
    return os.path.join(bereich, *STAND.split("/"))


def kennzahlen(bereich):
    """-> {name: zahl}. Fehlende Werkzeuge fehlen still — fail-open.

    ⛔ Ein Werkzeug, das hier abstuerzt, darf das Gate nicht toeten. Eine fehlende
       Kennzahl wird spaeter als NICHT MESSBAR ausgewiesen, nie als "gesunken".
    """
    aus = {}

    # 1) Duplikate — die Zahl aus dem Anlass.
    p = os.path.join(HIER, "cleaner_duplikate.py")
    if os.path.isfile(p):
        try:
            r = subprocess.run([sys.executable, p, "--bereich", bereich],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=180)
            for z in r.stdout.decode("utf-8", "replace").split("\n"):
                if "in mehr als einer Ablage" in z:
                    teile = z.replace("·", " ").split()
                    for i, w in enumerate(teile):
                        if w.isdigit() and i + 1 < len(teile) and teile[i + 1] == "in":
                            aus["duplikate"] = int(w)
                            break
                    break
        except (OSError, subprocess.SubprocessError):
            pass

    # 2) Zeilen des immer geladenen Satzes — was Modularize NICHT senkt.
    #    ⭐ Genau die Gegenprobe: ein Modularize laesst `zeilen` gleich und
    #       `wurzelzeilen` sinken. Nur beide zusammen zeigen, was passiert ist.
    zeilen = wurzel = 0
    for rel in ("CLAUDE.md", ".claude/CLAUDE.md"):
        f = os.path.join(bereich, *rel.split("/"))
        if os.path.isfile(f):
            n = _zeilen(f)
            zeilen += n
            wurzel += n
    rd = os.path.join(bereich, ".claude", "rules")
    if os.path.isdir(rd):
        for w, _u, ds in os.walk(rd):
            for d in ds:
                if d.endswith(".md"):
                    zeilen += _zeilen(os.path.join(w, d))
    if zeilen:
        aus["zeilen"] = zeilen
        aus["wurzelzeilen"] = wurzel
    return aus


def _zeilen(p):
    try:
        with open(p, "rb") as fh:
            roh = fh.read()
    except OSError:
        return 0
    return len([z for z in roh.decode("utf-8", "replace").split("\n") if z.strip()])


def vorher(bereich):
    k = kennzahlen(bereich)
    p = _stand_pfad(bereich)
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(k, fh, ensure_ascii=True, indent=1, sort_keys=True)
    except OSError as e:
        print("  ⛔ Vorher-Stand nicht schreibbar: %s" % e)
        return 2
    print("  Vorher-Stand gemerkt:")
    for n in sorted(k):
        print("     %-14s %d" % (n, k[n]))
    if not k:
        print("     (nichts messbar — Werkzeuge fehlen oder Bereich ist leer)")
    return 0


def nachher(bereich, erwartet):
    p = _stand_pfad(bereich)
    if not os.path.isfile(p):
        print("  ⛔ KEIN VORHER-STAND. Ohne ihn ist jede Aussage ueber Wirkung geraten.")
        print("     `--vorher` laeuft VOR dem ersten Fix, nicht danach.")
        return 2
    try:
        alt = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        print("  ⛔ Vorher-Stand unlesbar — als NICHT MESSBAR behandelt, nicht als 0.")
        return 2
    neu = kennzahlen(bereich)

    print("  %-14s %8s %8s %8s" % ("Kennzahl", "vorher", "nachher", "Differenz"))
    print("  " + "-" * 44)
    verletzt = []
    for n in sorted(set(alt) | set(neu)):
        a, b = alt.get(n), neu.get(n)
        if a is None or b is None:
            print("  %-14s %8s %8s   NICHT MESSBAR"
                  % (n, "—" if a is None else a, "—" if b is None else b))
            if n in erwartet:
                verletzt.append((n, "nicht messbar"))
            continue
        d = b - a
        print("  %-14s %8d %8d %+9d" % (n, a, b, d))
        if n in erwartet and d >= 0:
            verletzt.append((n, "%+d" % d))

    if not erwartet:
        print()
        print("  ⚠ Keine Kennzahl als ERWARTET benannt — dieser Lauf misst nur.")
        return 0

    print()
    if verletzt:
        print("  ⛔ DER FIX HAT NICHT GEWIRKT:")
        for n, d in verletzt:
            print("     %-14s sollte sinken, ist aber %s" % (n, d))
        print()
        print("     ⭐ Der haeufigste Grund ist ein VERTAUSCHTER FIX-TYP:")
        print("        Modularize VERSCHIEBT — die Summe bleibt gleich.")
        print("        Deduplicate macht eine Stelle zum ZEIGER — erst dann sinkt sie.")
        print("        Ein Duplikat, das umzieht, ist immer noch ein Duplikat.")
        return 1
    print("  ✓ Jede erwartete Kennzahl ist gesunken.")
    return 0


# ── Selbsttest ───────────────────────────────────────────────────────────────

def selbsttest():
    ok = rot = 0

    def janein(name, erw, ist):
        nonlocal ok, rot
        if erw == ist:
            print("  [ok ] %s" % name)
            ok += 1
        else:
            print("  [ROT] %s — erwartet %r, bekommen %r" % (name, erw, ist))
            rot += 1

    d = tempfile.mkdtemp(prefix="wirkung_")
    b = os.path.join(d, "proj")
    os.makedirs(os.path.join(b, ".claude", "rules"))

    def schreib(rel, text):
        p = os.path.join(b, *rel.split("/"))
        with open(p, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    # ⚠ Die Wurzeldatei muss beim Modularize WIRKLICH schrumpfen, sonst prueft
    #   Fall 2b nichts. Erste Fassung: 3 Zeilen vorher, 3 nachher — die
    #   Zusicherung war echt und scheiterte zu Recht.
    schreib("CLAUDE.md", "# P\n\nMUST `alpha` beachten.\nMUST `beta` beachten.\n"
                         "Und `beta` hat einen zweiten Satz.\nUnd einen dritten.\n")
    schreib(".claude/rules/a.md", "# A\n\nMUST `alpha` beachten.\n")

    janein("1 vorher schreibt einen Stand", 0, vorher(b))
    janein("1b Standdatei existiert", True, os.path.isfile(_stand_pfad(b)))

    # ⛔ NEGATIVKONTROLLE / der Anlass: MODULARIZE. Eine Zeile wandert aus der
    #    Wurzeldatei in eine Rule. Die Wurzeldatei schrumpft, die SUMME nicht.
    schreib("CLAUDE.md", "# P\n\nMUST `alpha` beachten.\nDetails: .claude/rules/b.md\n")
    schreib(".claude/rules/b.md", "# B\n\nMUST `beta` beachten.\n")
    alt_k = json.load(open(_stand_pfad(b), encoding="utf-8"))
    rc = nachher(b, {"zeilen"})
    neu_k = kennzahlen(b)
    janein("2 Modularize senkt `zeilen` NICHT -> Rueckgabe 1", 1, rc)
    # ⛔ Hier stand zuerst `janein("2b ...", True, True)` — eine Zusicherung, die
    #    NICHT SCHEITERN KANN. messung-vor-glauben.md §1: eine Messung, die nicht
    #    scheitern kann, ist keine Messung. Jetzt der echte Unterschied:
    #    Modularize senkt die WURZELDATEI und laesst die SUMME stehen. Genau diese
    #    Schere ist der Fingerabdruck eines verschobenen statt behobenen Befunds.
    janein("2b Wurzeldatei ist geschrumpft", True,
           neu_k.get("wurzelzeilen", 0) < alt_k.get("wurzelzeilen", 0))
    janein("2b Summe ist NICHT geschrumpft", True,
           neu_k.get("zeilen", 0) >= alt_k.get("zeilen", 0))

    # POSITIVKONTROLLE: echtes Deduplicate — die Zeile wird durch einen Zeiger
    # ersetzt, ohne dass anderswo eine neue Datei entsteht.
    vorher(b)
    schreib("CLAUDE.md", "# P\n\nDetails: .claude/rules/a.md\n")
    janein("3 Deduplicate senkt `zeilen` -> Rueckgabe 0", 0, nachher(b, {"zeilen"}))

    # ⛔ Ohne Vorher-Stand gibt es keine Aussage.
    b2 = os.path.join(d, "leer")
    os.makedirs(b2)
    janein("4 kein Vorher-Stand -> Rueckgabe 2", 2, nachher(b2, {"zeilen"}))

    # Ohne Erwartung wird nur gemessen, nie geurteilt.
    vorher(b)
    janein("5 ohne ERWARTET -> Rueckgabe 0", 0, nachher(b, set()))

    shutil.rmtree(d, ignore_errors=True)
    print()
    print("  %d ok, %d rot" % (ok, rot))
    return 3 if rot else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()

    def hol(f):
        return argv[argv.index(f) + 1] if f in argv and argv.index(f) + 1 < len(argv) else None

    v, n = hol("--vorher"), hol("--nachher")
    if v:
        return vorher(v)
    if n:
        e = hol("--erwartet") or ""
        return nachher(n, {x.strip() for x in e.split(",") if x.strip()})
    print(__doc__.split("Aufruf:")[1])
    return 2


if __name__ == "__main__":
    sys.exit(main())
