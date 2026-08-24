#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Braucht es diese Regel noch? — Belege statt Selbsteinschaetzung.

⛔ DIE FRAGE, DIE MAN SICH NICHT SELBST BEANTWORTEN KANN

Die naheliegende Frage lautet: "wuerdest du das auch ohne die Regel tun?"
**Sie ist nicht zuverlaessig beantwortbar.** Belegt an einem einzigen
Arbeitstag (24.08.2026): vier Regeln, die WOERTLICH in der geladenen CLAUDE.md
standen, wurden im selben Lauf gebrochen — MSYS-Pfad an Windows-Python,
Suchbefehl ohne `-i` (zweimal), Trennzeichen im Suchmuster, Pipe verschluckt
den Rueckgabewert. Vor dem Lauf haette die Selbsteinschaetzung bei JEDER
gelautet: "das mache ich sowieso richtig."

Also: **zwei unabhaengige Belegquellen statt Bauchgefuehl.**

    1  VERSTOESSE   Debug/index.jsonl — datiert, nach Klassen sortiert
    2  GIT          Ein-Commit-Historie = seit Anlage nie ueberarbeitet
                    ("Init Fossilization")

⭐ **Warum zwei.** Quelle 1 allein laesst "nie verletzt" unentscheidbar. Quelle 2
ist davon unabhaengig: wer eine Datei nie wieder angefasst hat, hat sie
vermutlich auch nie gebraucht. Zusammen ergeben sie ein Urteil, das keine der
beiden allein tragen wuerde.

## ⛔ Die Zeile, die dieses Werkzeug ehrlich macht

    keine Verstoesse + viele Commits  ->  NICHT ENTSCHEIDBAR

Eine Regel, die nie gebrochen wurde, kann ueberfluessig sein — oder GENAU
DESHALB nie gebrochen worden sein, WEIL sie da ist. Aus den Daten ist das
**nicht unterscheidbar**. Jedes Werkzeug, das hier ein Urteil faellt, raet.

## ⚠ Und die Verstossquelle ist strukturell blind

Urteils- und Prozessregeln (`keine-annahmen`, `plan-mode`, `autonom-arbeiten`)
erzeugen kaum je einen maschinell loggbaren Verstoss. Sie landen in
"nicht entscheidbar" **nicht weil sie unbeobachtet blieben, sondern weil sie
unbeobachtBAR sind.** Der Bericht trennt das als 5a gegen 5b.

Aufruf:
  python cleaner_belege.py --datei <regel.md> [--debug <index.jsonl>]
  python cleaner_belege.py --bereich <projekt> [--debug <index.jsonl>]
  python cleaner_belege.py --selbsttest

Rueckgabe: 0 = ausgewertet · 1 = Veralterungs-Kandidaten gefunden · 2 = nicht messbar
"""
import json
import os
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", newline="")

# ⚠ Wie weit zurueck gilt ein Verstoss als "aktuell"? Ein Regler mit Herkunft:
#    die Debug-Daten reichen ueber wenige Wochen, deshalb 21 Tage. Wer laengere
#    Reihen hat, setzt ihn hoch.
FRISCH_TAGE = int(os.environ.get("MIND_BELEG_FRISCH_TAGE", "21") or 21)


def _lies(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return None


def debug_pfad(projekt):
    for k in (os.environ.get("MIND_DEBUG_DIR"),
              os.path.join(projekt, "Debug")):
        if k and os.path.isfile(os.path.join(k, "index.jsonl")):
            return os.path.join(k, "index.jsonl")
    return None


def verstoesse(index_pfad, stichworte):
    """Befunde, die eines der Stichworte nennen. (gesamt, letztes_datum, liste)"""
    t = _lies(index_pfad)
    if t is None:
        return None
    treffer = []
    for z in t.split("\n"):
        z = z.strip()
        if not z:
            continue
        try:
            e = json.loads(z)
        except ValueError:
            continue
        txt = (e.get("kurz", "") + " " + e.get("klasse", "")).lower()
        if any(s.lower() in txt for s in stichworte):
            treffer.append(e)
    treffer.sort(key=lambda e: e.get("ts", ""))
    letztes = treffer[-1].get("ts", "")[:10] if treffer else ""
    return len(treffer), letztes, treffer


def stichworte_aus(pfad):
    """Woran erkennt man einen Verstoss GEGEN DIESE Regel?

    ⛔ DIE ERSTE FASSUNG WAR VIEL ZU LOCKER UND HAT SICH SELBST BEGRABEN.

    Sie zog jedes Wort ab 5 Zeichen aus den ersten drei Ueberschriften. Fuer
    `plan-mode.md` ergab das unter anderem `Nicht`, `gegen`, `Regeln`; fuer
    `env-vars.md` sogar `NICHT`, `nicht`, `gemessen`, `liegt`. Solche Woerter
    stehen in fast JEDEM Befund.

    GEMESSEN am echten Bestand (106 Befunde): `env-vars.md` bekam 56 Treffer
    zugeschrieben, `plan-mode.md` 53, `ursache-vor-reparatur.md` 54. Damit
    landete praktisch alles in "belegt noetig", und Gruppe 5b — der eigentliche
    Kern des Berichts — blieb LEER.

    ⭐ Eine Belegquelle, die fast alles belegt, belegt nichts.

    Deshalb jetzt eng: nur der DATEINAME (in beiden Schreibweisen) und
    Bezeichner mit technischer Form (Unterstrich, Punkt oder ALLCAPS ab 6
    Zeichen). Fliesstextwoerter fallen raus.

    ⚠ Der Preis ist ehrlich: manche echten Verstoesse werden nicht mehr
      zugeordnet. "Kein Verstoss gefunden" ist deshalb erst recht kein Urteil,
      sondern nur die Abwesenheit eines Belegs.
    """
    name = os.path.splitext(os.path.basename(pfad))[0]
    worte = {name, name.replace("-", " ")}
    t = _lies(pfad) or ""
    for m in re.findall(r"^#+\s+(.{3,60})$", t, re.M)[:3]:
        for w in re.findall(r"\b[A-Za-z_][A-Za-z0-9_.-]{5,}\b", m):
            technisch = ("_" in w or "." in w
                         or (w.isupper() and len(w) >= 6))
            if technisch and w.lower() not in ("claude", "diese", "regeln"):
                worte.add(w)
    return sorted(worte)


def git_commits(pfad):
    """Wie oft wurde die Datei ueberarbeitet? None = kein Git / nicht messbar."""
    d = os.path.dirname(os.path.abspath(pfad))
    try:
        r = subprocess.run(["git", "-C", d, "log", "--oneline", "--follow", "--",
                            os.path.basename(pfad)],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return len([z for z in r.stdout.split("\n") if z.strip()])


def _frisch(datum):
    if not datum:
        return False
    import datetime
    try:
        d = datetime.date.fromisoformat(datum)
    except ValueError:
        return False
    return (datetime.date.today() - d).days <= FRISCH_TAGE


def urteile(pfad, index_pfad):
    """(urteil, begruendung, zahlen)"""
    sw = stichworte_aus(pfad)
    v = verstoesse(index_pfad, sw) if index_pfad else None
    n_v, letztes = (v[0], v[1]) if v else (None, "")
    commits = git_commits(pfad)
    z = {"verstoesse": n_v, "letzter": letztes, "commits": commits,
         "stichworte": sw[:4]}

    if n_v is None:
        return "NICHT MESSBAR", "kein Verstoss-Protokoll erreichbar", z
    if n_v > 0 and _frisch(letztes):
        return "BELEGT NOETIG", ("%d Verstoss/Verstoesse, letzter am %s"
                                 % (n_v, letztes)), z
    if n_v > 0:
        if commits == 1:
            return "VERALTUNGS-KANDIDAT", (
                "%d Verstoesse, letzter am %s (aelter als %d Tage) UND seit Anlage "
                "nie ueberarbeitet" % (n_v, letztes, FRISCH_TAGE)), z
        return "VERALTUNGS-KANDIDAT", (
            "%d Verstoesse, letzter am %s — aelter als %d Tage"
            % (n_v, letztes, FRISCH_TAGE)), z
    if commits == 1:
        return "SCHWACHER KANDIDAT", (
            "kein Verstoss gefunden UND seit Anlage nie ueberarbeitet "
            "(Ein-Commit-Historie)"), z
    # ⛔ Die ehrliche Zeile.
    return "NICHT ENTSCHEIDBAR", (
        "kein Verstoss gefunden, aber %s — ueberfluessig und wirksam sind aus "
        "den Daten NICHT unterscheidbar"
        % ("Historie nicht messbar" if commits is None
           else "%d Commits, jemand pflegt sie" % commits)), z


def bericht(zeilen):
    print("=" * 92)
    print("  Belege — braucht es diese Regel noch?")
    print("=" * 92)
    print("  Frischefenster: %d Tage (MIND_BELEG_FRISCH_TAGE)" % FRISCH_TAGE)
    print()
    print("  %-30s %-20s %5s %8s  %s"
          % ("Datei", "Urteil", "Verst", "Commits", "letzter"))
    for pfad, u, g, z in zeilen:
        print("  %-30s %-20s %5s %8s  %s"
              % (os.path.basename(pfad)[:30], u,
                 "?" if z["verstoesse"] is None else z["verstoesse"],
                 "?" if z["commits"] is None else z["commits"], z["letzter"] or "—"))
    print()
    for pfad, u, g, z in zeilen:
        if u in ("VERALTUNGS-KANDIDAT", "SCHWACHER KANDIDAT"):
            print("  ⚠ %s\n     %s" % (os.path.basename(pfad), g))
    print()
    print("  " + "=" * 88)
    print("  ⛔ NICHT ENTSCHEIDBAR ist kein Restposten, sondern der Kern.")
    print("  " + "=" * 88)
    print("     Eine nie gebrochene Regel kann ueberfluessig sein — oder GENAU")
    print("     DESHALB nie gebrochen worden sein, WEIL sie da ist. Aus den Daten")
    print("     ist das nicht unterscheidbar. Wer hier urteilt, raet.")
    print()
    print("  ⚠ Und die Verstossquelle ist strukturell blind fuer Urteils- und")
    print("    Prozessregeln (keine-annahmen, plan-mode, autonom-arbeiten): deren")
    print("    Verstoesse sind kaum maschinell loggbar. Sie landen hier NICHT weil")
    print("    sie unbeobachtet blieben, sondern weil sie unbeobachtBAR sind.")
    kand = [z for z in zeilen if z[1] in ("VERALTUNGS-KANDIDAT", "SCHWACHER KANDIDAT")]
    return 1 if kand else 0


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
        print("    %-4s %-52s ist=%-20s soll=%s"
              % ("OK" if ok else "FEHL", name, ist, soll))

    import datetime
    heute = datetime.date.today().isoformat()
    alt = (datetime.date.today() - datetime.timedelta(days=90)).isoformat()

    idx = os.path.join(d, "index.jsonl")
    with open(idx, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps({"ts": heute + " 10:00", "klasse": "windows-pfad",
                             "kurz": "msyspfad an Windows-Python"}) + "\n")
        fh.write(json.dumps({"ts": alt + " 10:00", "klasse": "zeilenenden",
                             "kurz": "zeilenenden gekippt"}) + "\n")

    def regel(name):
        p = os.path.join(d, name + ".md")
        open(p, "w", encoding="utf-8", newline="\n").write("# %s\n\nText.\n" % name)
        return p

    print("=" * 78)
    print("  Selbsttest — die Belege muessen UNTERSCHEIDEN")
    print("=" * 78)

    u, g, z = urteile(regel("msyspfad"), idx)
    pruef("frischer Verstoss -> BELEGT NOETIG", u, "BELEGT NOETIG")

    u, g, z = urteile(regel("zeilenenden"), idx)
    pruef("alter Verstoss -> VERALTUNGS-KANDIDAT", u, "VERALTUNGS-KANDIDAT")

    # ⛔ Ohne Verstoss und ohne Git-Historie: KEIN Urteil.
    u, g, z = urteile(regel("nieverletzt"), idx)
    pruef("kein Verstoss, kein Git -> NICHT ENTSCHEIDBAR", u, "NICHT ENTSCHEIDBAR")

    # Kein Protokoll ist NICHT "alles gut".
    u, g, z = urteile(regel("x"), None)
    pruef("kein Protokoll -> NICHT MESSBAR", u, "NICHT MESSBAR")

    # ⛔ Die Gegenprobe: drei verschiedene Urteile aus denselben Daten.
    ergebnisse = {urteile(regel("msyspfad"), idx)[0],
                  urteile(regel("zeilenenden"), idx)[0],
                  urteile(regel("nieverletzt"), idx)[0]}
    pruef("drei verschiedene Urteile", len(ergebnisse), 3)

    # Stichwortbildung
    sw = stichworte_aus(regel("backup-before-delete"))
    pruef("Dateiname wird Stichwort", "backup-before-delete" in sw, True)
    pruef("und die Wortfassung auch", "backup before delete" in sw, True)

    # Kaputte Zeile im Protokoll darf es nicht unlesbar machen.
    with open(idx, "a", encoding="utf-8", newline="\n") as fh:
        fh.write("{kein json\n")
    r = verstoesse(idx, ["msyspfad"])
    pruef("kaputte Zeile: Protokoll bleibt lesbar", r[0] if r else -1, 1)

    print("\n=== %d Abweichung(en) ===" % fehler)
    return 3 if fehler else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()

    def hol(f):
        return argv[argv.index(f) + 1] if f in argv and len(argv) > argv.index(f) + 1 else None

    projekt = hol("--bereich") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    idx = hol("--debug") or debug_pfad(projekt)

    dateien = []
    if hol("--datei"):
        dateien = [hol("--datei")]
    else:
        H = os.path.expanduser("~")
        for wurzel in (os.path.join(H, ".claude", "rules"),
                       os.path.join(projekt, ".claude", "rules")):
            if os.path.isdir(wurzel):
                dateien += [os.path.join(wurzel, f) for f in sorted(os.listdir(wurzel))
                            if f.endswith(".md")]
    if not dateien:
        print("⛔ Keine Regeldatei gefunden. Eher ein falscher Pfad als ein leerer Bestand.")
        return 2
    if idx is None:
        print("⚠ Kein Verstoss-Protokoll erreichbar (MIND_DEBUG_DIR oder <projekt>/Debug).")
        print("  Alle Urteile lauten deshalb NICHT MESSBAR — das ist KEIN 'alles gut'.")

    zeilen = [(p,) + urteile(p, idx) for p in dateien]
    return bericht(zeilen)


if __name__ == "__main__":
    sys.exit(main())
