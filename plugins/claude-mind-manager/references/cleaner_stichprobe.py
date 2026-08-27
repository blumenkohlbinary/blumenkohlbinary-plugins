# -*- coding: utf-8 -*-
"""Waehlt aus einem Bestand die am laengsten UNGEPRUEFTEN Eintraege aus.

⛔ WOZU. `/mind-all` ist eine Anhaenge-Maschine: fuenf Skills tragen nach, keiner
   sieht je zurueck. Gemessen 27.08.2026 wuchs der Dauerkontext eines Projekts an
   EINEM Tag um +21 %. Das Gegengewicht `/mind-cleaner` steht bewusst ausserhalb
   der Kette und ist nicht autonom — es kann also nicht der Weg sein, auf dem der
   Bestand routinemaessig geprueft wird.

   Nutzer-Auftrag 27.08.2026: *„die anderen skills sollen von vorne rein sauber
   arbeiten … nicht immer mehr und mehr, auch gucken: braucht man das, kann das
   weg, steht das schon woanders."*

⭐ DIE ANTWORT AUF „NICHT SO INVASIV" IST DIE STICHPROBE. Drei Eintraege je Skill,
   hoechstens 15 im Lauf. Kein Skill kaemmt seinen ganzen Bestand durch — er sieht
   sich jedes Mal einen anderen kleinen Ausschnitt an. Ueber viele Laeufe ist der
   Bestand vollstaendig abgedeckt, ohne dass ein einzelner Lauf teuer wird.

⛔ DER ROTATIONSZUSTAND IST PROJEKTWEIT, NICHT JE SKILL. Sonst legen fuenf Skills
   sich fuenfmal denselben Eintrag vor, und der Rest des Bestands wird nie gesehen.

⛔ DIESES WERKZEUG BERUEHRT NIEMALS EINEN INHALT. Es kennt nur PFADE. Das ist kein
   Zufall, sondern die mechanische Fassung einer Regel: der Bestands-Pass liest auch
   fremde Memory-Bestaende, und in `APP - Zustellplan` stehen dort Abonnenten- und
   Routendaten. Ein Werkzeug, das Inhalte gar nicht anfasst, kann sie auch nicht in
   den gemeinsamen Debug-Ordner tragen. Ort und Klasse, nie Inhalt.

⚠ ES SCHREIBT — und zwar AUSSCHLIESSLICH nach `<projekt>/.claude-mind/`. Ohne
  Gedaechtnis gaebe es keine Rotation, und jeder Lauf saehe dieselben drei Eintraege.
  Es fasst nie eine Context-Datei an; `Learnings/v0_schreibt_nichts.py` prueft das.

Aufruf:
  python cleaner_stichprobe.py <projekt> --skill <name> [--n 3] [--max 15] <ort> [<ort> ...]
  python cleaner_stichprobe.py <projekt> --skill <name> --verzeichnis <pfad>
  python cleaner_stichprobe.py <projekt> --zeige
  python cleaner_stichprobe.py <projekt> --quittung --skill <name> --geprueft <n> --stichprobe <n>
  python cleaner_stichprobe.py --selbsttest

Rueckgabe: 0 = Stichprobe gezogen (auch eine leere)  ·  2 = Aufruffehler
           3 = Selbsttest gescheitert
"""
import io
import json
import os
import shutil
import sys
import tempfile
import time

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROTATION = ".claude-mind/bestand-rotation.jsonl"
SCOPES = ".claude-mind/analyzed-scopes"
N_VORGABE = 3
MAX_VORGABE = 15


# ── Zustand ──────────────────────────────────────────────────────────────────

def rot_pfad(projekt):
    return os.path.join(projekt, *ROTATION.split("/"))


def lesen(projekt):
    """-> (letzte_vorlage: {ort: ts}, alle_zeilen: [dict])

    ⛔ Eine kaputte Zeile wird UEBERSPRUNGEN, nicht als Abbruch behandelt. Ein
       unlesbarer Rotationszustand darf die Stichprobe nicht toeten — er macht sie
       nur schlechter. Fail-open, wie beim Urteilsbuch: "unbekannt" ist immer die
       sichere Antwort, "schon geprueft" waere die gefaehrliche.
    """
    p = rot_pfad(projekt)
    letzte, alle = {}, []
    if not os.path.isfile(p):
        return letzte, alle
    try:
        roh = open(p, "rb").read().decode("utf-8", "replace")
    except OSError:
        return letzte, alle
    for zeile in roh.split("\n"):
        zeile = zeile.strip()
        if not zeile:
            continue
        try:
            e = json.loads(zeile)
        except ValueError:
            continue
        if not isinstance(e, dict) or "ort" not in e:
            continue
        alle.append(e)
        ts = e.get("ts", 0)
        if not isinstance(ts, (int, float)):
            continue
        if ts > letzte.get(e["ort"], 0):
            letzte[e["ort"]] = ts
    return letzte, alle


def anhaengen(projekt, eintraege):
    p = rot_pfad(projekt)
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "a", encoding="utf-8", newline="\n") as fh:
            for e in eintraege:
                fh.write(json.dumps(e, ensure_ascii=True) + "\n")
        return True
    except OSError:
        return False


def lauf_beginn(projekt):
    """`run_started=` aus analyzed-scopes, sonst None.

    ⚠ Nur waehrend einer `/mind-all`-Kette gibt es diese Marke. Ein EINZELLAUF
      hat keine, und dann gilt die 15er-Grenze nicht — richtig so: sie soll einen
      Kettenlauf begrenzen, nicht einen Handaufruf verhindern.
    """
    p = os.path.join(projekt, *SCOPES.split("/"))
    if not os.path.isfile(p):
        return None
    try:
        for zeile in open(p, encoding="utf-8", errors="replace"):
            if zeile.startswith("run_started="):
                w = zeile.split("=", 1)[1].strip()
                return int(w) if w.isdigit() else None
    except OSError:
        pass
    return None


# ── Auswahl ──────────────────────────────────────────────────────────────────


def gesperrte_orte(projekt):
    """Orte mit einem gueltigen zielform/zeiger-Urteil -> nicht erneut vorlegen.

    ⛔ `zielform` und `zeiger` heissen: ein Mensch hat entschieden, das bleibt so.
       Legt die Stichprobe so einen Ort trotzdem wieder vor, steht eine
       menschliche Entscheidung bei JEDEM Lauf erneut zur Debatte — und kippt
       irgendwann versehentlich. Genau davor schuetzt das Urteilsbuch seit v5.16.0.

    ⚠ Das Buch fuehrt PAARE von Orten. Die Sperre ist deshalb bewusst grob: ein
      Ort, der in irgendeinem gueltigen Eintrag vorkommt, faellt raus. Das sperrt
      im Zweifel einen zu viel — die andere Richtung waere schlimmer.

    ⛔ FAIL-OPEN. Fehlt das Buch, ist es unlesbar oder scheitert der Import, wird
       NICHTS gesperrt. "unbekannt" ist die sichere Antwort, "schon entschieden"
       die gefaehrliche. Ein kaputtes Urteilsbuch darf den Bestands-Pass nicht
       blind machen, sondern nur ungeschuetzt.
    """
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from cleaner_urteile import lesen as _urteile_lesen
    except Exception:
        return set()
    try:
        eintraege = _urteile_lesen(projekt)
    except Exception:
        return set()

    gesperrt = set()
    for e in eintraege:
        if not isinstance(e, dict) or e.get("__kaputt__"):
            continue
        if e.get("urteil") not in ("zielform", "zeiger"):
            continue
        for o in e.get("orte") or []:
            if isinstance(o, str):
                gesperrt.add(o)
    return gesperrt


def waehle(projekt, orte, n, maximal):
    """-> (gewaehlt, uebersprungen_im_lauf, rest_im_lauf, gesperrt)"""
    letzte, alle = lesen(projekt)
    beginn = lauf_beginn(projekt)
    gesperrt = gesperrte_orte(projekt)

    # Was ist in DIESEM Lauf schon jemandem vorgelegt worden?
    im_lauf = set()
    if beginn is not None:
        for e in alle:
            ts = e.get("ts", 0)
            if isinstance(ts, (int, float)) and ts >= beginn:
                im_lauf.add(e["ort"])

    rest = maximal - len(im_lauf) if beginn is not None else maximal
    if rest < 0:
        rest = 0

    # ⛔ Zuerst die menschlichen Urteile, dann erst die Rotation.
    frei = [o for o in orte if o not in im_lauf and o not in gesperrt]
    # Am laengsten ungeprueft zuerst; nie vorgelegt == 0 und damit ganz vorn.
    # Bei Gleichstand der Pfad, damit die Reihenfolge reproduzierbar ist.
    frei.sort(key=lambda o: (letzte.get(o, 0), o))

    grenze = min(n, rest)
    return (frei[:grenze], sorted(im_lauf & set(orte)), rest,
            sorted(gesperrt & set(orte)))


def sammle_verzeichnis(pfad):
    aus = []
    for d, unter, dateien in os.walk(pfad):
        unter[:] = [u for u in unter if not u.startswith(".") and u != "__pycache__"]
        for f in sorted(dateien):
            if f.endswith(".md"):
                aus.append(os.path.join(d, f))
    return aus


# ── Bericht ──────────────────────────────────────────────────────────────────

def zeige(projekt):
    letzte, alle = lesen(projekt)
    if not alle:
        print("  (noch keine Rotation — jeder Bestand gilt als ungeprueft)")
        return 0
    print("  %d Vorlage(n) protokolliert, %d verschiedene Orte"
          % (len(alle), len(letzte)))
    print()
    print("  %-19s %-16s %s" % ("zuletzt vorgelegt", "durch", "Ort"))
    print("  " + "-" * 68)
    nach_ort = {}
    for e in alle:
        o = e["ort"]
        if e.get("ts", 0) >= nach_ort.get(o, {}).get("ts", -1):
            nach_ort[o] = e
    for o in sorted(nach_ort, key=lambda x: nach_ort[x].get("ts", 0)):
        e = nach_ort[o]
        ts = e.get("ts", 0)
        stempel = time.strftime("%Y-%m-%d %H:%M", time.localtime(ts)) if ts else "nie"
        print("  %-19s %-16s %s" % (stempel, e.get("skill", "?")[:16], kurz(o)))
    return 0


def kurz(p, n=44):
    return p if len(p) <= n else "..." + p[-(n - 3):]


def quittung(projekt, skill, geprueft, stichprobe):
    """Schreibt `bestand=<skill>:<geprueft>/<stichprobe>` in analyzed-scopes.

    ⛔ WARUM DAS KEIN BEIWERK IST. Ein Skill, der schweigt weil sein Bestand sauber
       ist, und einer, der schweigt weil der Pass ausgefallen ist, sehen von aussen
       IDENTISCH aus. Genau diese Ununterscheidbarkeit hat v5.3.1 bei zwei Hooks
       und v5.19.0 bei der Agent-Quittung gekostet — beide Male war die Loesung
       dieselbe: das FEHLEN messbar machen, nicht das Vorhandensein.
    """
    p = os.path.join(projekt, *SCOPES.split("/"))
    if not os.path.isfile(p):
        # Kein Kettenlauf -> keine Quittung noetig, aber auch kein Fehler.
        print("  (kein Kettenlauf — Quittung entfaellt)")
        return 0
    try:
        with open(p, "a", encoding="utf-8", newline="\n") as fh:
            fh.write("bestand=%s:%d/%d\n" % (skill, geprueft, stichprobe))
    except OSError as e:
        print("  ⚠ Quittung nicht schreibbar: %s" % e)
        return 0
    print("  bestand=%s:%d/%d" % (skill, geprueft, stichprobe))
    return 0


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

    d = tempfile.mkdtemp(prefix="stichprobe_")
    proj = os.path.join(d, "proj")
    os.makedirs(os.path.join(proj, ".claude-mind"))
    orte = ["/a/eins.md", "/a/zwei.md", "/a/drei.md", "/a/vier.md", "/a/fuenf.md"]

    # 1 — frischer Bestand: die ersten drei alphabetisch (alle ts=0)
    g, u, r, sp = waehle(proj, orte, 3, 15)
    janein("1 frischer Bestand liefert 3", 3, len(g))
    janein("1 Reihenfolge bei Gleichstand ist der Pfad",
           ["/a/drei.md", "/a/eins.md", "/a/fuenf.md"], g)

    # 2 — was vorgelegt wurde, kommt beim naechsten Mal NICHT zuerst
    jetzt = int(time.time())
    anhaengen(proj, [{"ts": jetzt, "skill": "t", "ort": o} for o in g])
    g2, _, _, _ = waehle(proj, orte, 3, 15)
    janein("2 die drei frischen Orte kommen zuerst",
           ["/a/vier.md", "/a/zwei.md"], g2[:2])
    janein("2 ein schon vorgelegter Ort rutscht ans Ende", "/a/drei.md", g2[2])

    # 3 — LAUFGRENZE: mit run_started zaehlt alles seit Laufbeginn mit
    with open(os.path.join(proj, ".claude-mind", "analyzed-scopes"), "w",
              encoding="utf-8", newline="\n") as fh:
        fh.write("run_started=%d\n" % (jetzt - 10))
    g3, im_lauf, rest, _ = waehle(proj, orte, 3, 15)
    janein("3 drei Orte gelten als in diesem Lauf erledigt", 3, len(im_lauf))
    janein("3 Restbudget 15-3", 12, rest)
    janein("3 kein Ort wird doppelt vorgelegt", True,
           not (set(g3) & set(im_lauf)))

    # 4 — NEGATIVKONTROLLE: Budget erschoepft -> LEERE Stichprobe, kein Absturz
    viele = [{"ts": jetzt, "skill": "t", "ort": "/b/%d.md" % i} for i in range(15)]
    anhaengen(proj, viele)
    g4, _, rest4, _ = waehle(proj, orte, 3, 15)
    janein("4 Budget erschoepft -> Restbudget 0", 0, rest4)
    janein("4 Budget erschoepft -> leere Stichprobe", [], g4)

    # 5 — NEGATIVKONTROLLE: kaputte Zeile toetet die Rotation nicht
    with open(rot_pfad(proj), "a", encoding="utf-8", newline="\n") as fh:
        fh.write("{kein json\n")
        fh.write(json.dumps({"ohne_ort": 1}) + "\n")
    letzte, alle = lesen(proj)
    janein("5 kaputte Zeilen werden uebersprungen, nicht gezaehlt", 18, len(alle))
    janein("5 lesen() stuerzt nicht ab", True, isinstance(letzte, dict))

    # 6 — ohne analyzed-scopes gilt keine Laufgrenze
    proj2 = os.path.join(d, "proj2")
    os.makedirs(proj2)
    _, _, rest6, _ = waehle(proj2, orte, 3, 15)
    janein("6 Einzellauf: volles Budget", 15, rest6)

    # 7 — Stichprobe groesser als Bestand -> min(n, Bestand)
    g7, _, _, _ = waehle(proj2, ["/c/nur-einer.md"], 3, 15)
    janein("7 Stichprobe > Bestand -> nur was da ist", 1, len(g7))

    # 8 — leerer Bestand -> leere Stichprobe, kein Fehler
    g8, _, _, _ = waehle(proj2, [], 3, 15)
    janein("8 leerer Bestand -> leere Stichprobe", [], g8)

    # 8b — zielform-Urteil sperrt den Ort  ⛔ NEGATIVKONTROLLE aus dem Plan
    import subprocess
    ub = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cleaner_urteile.py")
    proj3 = os.path.join(d, "proj3")
    os.makedirs(os.path.join(proj3, ".claude-mind"))
    orte3 = ["/z/a.md", "/z/b.md", "/z/c.md", "/z/d.md"]
    subprocess.run([sys.executable, ub, "--schreiben", proj3, "--orte", "/z/a.md",
                    "/z/b.md", "--urteil", "zielform", "--werkzeug", "test",
                    "--von", "mensch", "--grund", "bewusst so gelassen"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    g9, _, _, sp9 = waehle(proj3, orte3, 3, 15)
    janein("8b zielform sperrt BEIDE Orte des Paares",
           ["/z/a.md", "/z/b.md"], sp9)
    janein("8b gesperrte Orte kommen NICHT in die Stichprobe",
           ["/z/c.md", "/z/d.md"], g9)

    # 8c — NEGATIVKONTROLLE zur Negativkontrolle: `duplikat` sperrt NICHT.
    #      Ohne diesen Fall wuerde eine Sperre, die ALLES sperrt, gruen bleiben.
    proj4 = os.path.join(d, "proj4")
    os.makedirs(os.path.join(proj4, ".claude-mind"))
    subprocess.run([sys.executable, ub, "--schreiben", proj4, "--orte", "/z/a.md",
                    "/z/b.md", "--urteil", "duplikat", "--werkzeug", "test",
                    "--von", "autonom", "--grund", "gleiche Aussage"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _, _, _, sp10 = waehle(proj4, orte3, 3, 15)
    janein("8c `duplikat` sperrt NICHT (nur zielform/zeiger)", [], sp10)

    # 8d — FAIL-OPEN: ohne Urteilsbuch wird nichts gesperrt
    janein("8d kein Urteilsbuch -> keine Sperre", set(), gesperrte_orte(proj2))

    # 9 — Quittung landet in analyzed-scopes
    quittung(proj, "mind-rules", 2, 3)
    inhalt = open(os.path.join(proj, ".claude-mind", "analyzed-scopes"),
                  encoding="utf-8").read()
    janein("9 Quittung steht in analyzed-scopes", True,
           "bestand=mind-rules:2/3" in inhalt)

    # 10 — NEGATIVKONTROLLE: ohne analyzed-scopes wird NICHTS geschrieben
    vorher = sorted(os.listdir(proj2))
    quittung(proj2, "mind-files", 0, 0)
    janein("10 ohne Kettenlauf entsteht keine Datei", vorher,
           sorted(os.listdir(proj2)))

    shutil.rmtree(d, ignore_errors=True)
    print()
    print("  %d ok, %d rot" % (ok, rot))
    return 3 if rot else 0


# ── CLI ──────────────────────────────────────────────────────────────────────

def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()

    def hol(flag, vorgabe=None):
        if flag not in argv:
            return vorgabe
        i = argv.index(flag) + 1
        return argv[i] if i < len(argv) and not argv[i].startswith("--") else vorgabe

    frei = [a for a in argv if not a.startswith("--")]
    # Werte, die zu einer Flagge gehoeren, sind keine freien Argumente.
    for flag in ("--skill", "--n", "--max", "--verzeichnis", "--geprueft", "--stichprobe"):
        w = hol(flag)
        if w is not None and w in frei:
            frei.remove(w)

    if not frei:
        print(__doc__.split("Aufruf:")[1])
        return 2
    projekt = frei[0]
    orte = frei[1:]

    if "--zeige" in argv:
        return zeige(projekt)

    skill = hol("--skill")
    if not skill:
        print("--skill fehlt")
        return 2

    if "--quittung" in argv:
        g, s = hol("--geprueft", "0"), hol("--stichprobe", "0")
        if not g.isdigit() or not s.isdigit():
            print("--geprueft und --stichprobe brauchen Zahlen")
            return 2
        return quittung(projekt, skill, int(g), int(s))

    verz = hol("--verzeichnis")
    if verz:
        orte = orte + sammle_verzeichnis(verz)
    if not orte:
        print("  (nichts) — kein Bestand uebergeben")
        return 0

    n = hol("--n", str(N_VORGABE))
    maximal = hol("--max", str(MAX_VORGABE))
    if not n.isdigit() or not maximal.isdigit():
        print("--n und --max brauchen Zahlen")
        return 2

    gewaehlt, im_lauf, rest, gesperrt = waehle(projekt, orte, int(n), int(maximal))

    print("  Bestand: %d Eintrag/Eintraege · Stichprobe: %d · Restbudget im Lauf: %d"
          % (len(orte), len(gewaehlt), rest))
    if im_lauf:
        print("  %d in diesem Lauf schon von einem anderen Skill vorgelegt"
              % len(im_lauf))
    if gesperrt:
        # ⛔ NENNEN, nicht verschweigen. Ein stillschweigend uebersprungener Ort
        #    ist von einem gar nicht vorhandenen nicht zu unterscheiden — und
        #    genau diese Ununterscheidbarkeit ist die Fehlerklasse, gegen die
        #    dieser ganze Pass gebaut ist.
        print("  %d durch ein zielform/zeiger-Urteil gesperrt (Mensch hat entschieden)"
              % len(gesperrt))
    if not gewaehlt:
        print("  (nichts) — %s" % ("Laufbudget erschoepft" if rest <= 0
                                   else "kein ungepruefter Eintrag uebrig"))
        return 0

    print()
    for o in gewaehlt:
        print("  PRUEFEN: %s" % o)
    anhaengen(projekt, [{"ts": int(time.time()), "skill": skill, "ort": o}
                        for o in gewaehlt])
    return 0


if __name__ == "__main__":
    sys.exit(main())
