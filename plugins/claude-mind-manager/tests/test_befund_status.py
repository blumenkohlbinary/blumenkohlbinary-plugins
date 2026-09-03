# -*- coding: utf-8 -*-
"""Punkt 14 (v5.35.0): Art und Status eines Befundes.

⛔ WAS HIER GEPRUEFT WIRD UND WARUM ES EINE POSITIVKONTROLLE BRAUCHT.
   Bis v5.34.0 konnte ein Befund nur ENTSTEHEN. Der Bestand wuchs 2 -> 333 in
   14 Tagen, an keinem Tag abwaerts, waehrend `known-issues.md` sechs Eintraege
   als BEHOBEN fuehrte. Der neue Mechanismus soll das schliessen koennen.

⭐ EINE NEGATIVKONTROLLE ALLEIN WAERE HIER WERTLOS. Ein Mechanismus, der GAR
   NICHTS schliesst, besteht jede Probe der Form "es darf nicht zu viel
   schliessen". Deshalb steht am Anfang die POSITIVKONTROLLE: ein bekannt
   behobener Befund — `known-issues #8`, mind_snapshot sichert ~/.claude/skills/
   nicht, behoben in v5.32.0, Commit 1e6f718 — MUSS als ZUSTAND-behoben
   herauskommen. Tut er das nicht, misst das neue Feld nichts.
   (`.claude/rules/werkzeuge-zuerst.md`: ein Rauschfilter, der nur gegen Rauschen
   kalibriert wird, optimiert sich auf Stille.)

Aufruf:  python tests/test_befund_status.py
Rueckgabe: 0 = alle gruen · 1 = mindestens ein Fall rot
"""
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

WURZEL = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(WURZEL, "references")
sys.path.insert(0, REF)

from debug_auswertung import art, status_von  # noqa: E402

AUFRAEUMEN = os.path.join(REF, "debug_aufraeumen.py")
AUSWERTUNG = os.path.join(REF, "debug_auswertung.py")

gruen = rot = 0


def pruef(name, bedingung, zusatz=""):
    global gruen, rot
    if bedingung:
        gruen += 1
        print("  [ok ] %s" % name)
    else:
        rot += 1
        print("  [ROT] %s %s" % (name, zusatz))


# --- Fixture: ein Bestand mit allen vier Faellen ---------------------------
# Der erste Eintrag ist der ECHTE known-issues-#8-Befund, wortgleich.
FIXTURE = [
    {"ts": "2026-08-27 07:45", "projekt": "Claude Mind Manager",
     "klasse": "plugin-defekt",
     "kurz": "mind_snapshot sichert ~/.claude/rules/ aber NICHT ~/.claude/skills/ "
             "— seit dem 23.08. liegen dort ~107 KB Volltext ohne jedes Netz",
     "lauf": "20260827-0740"},
    {"ts": "2026-08-28 10:00", "projekt": "P", "klasse": "windows-pfad",
     "kurz": "ich habe den Pfad unquotiert uebergeben, er zerlegte am Leerzeichen",
     "lauf": "x"},
    {"ts": "2026-08-29 10:00", "projekt": "P", "klasse": "sonstiges",
     "kurz": "die Doku nennt eine Zahl, die niemand nachzaehlt", "lauf": "x"},
    {"ts": "2026-08-30 10:00", "projekt": "P", "klasse": "plugin-defekt",
     "kurz": "zaehl_gate meldet gruen, obwohl der Befehl gar nicht lief",
     "status": "behoben", "lauf": "x"},          # ⛔ OHNE commit -> bleibt offen
]

print("=== 1) art() — die Einordnung selbst ===")
pruef("known-issues #8 nennt mind_snapshot -> zustand",
      art(FIXTURE[0]) == "zustand", "(ist %s)" % art(FIXTURE[0]))
pruef("Selbstbericht ohne Werkzeug -> ereignis",
      art(FIXTURE[1]) == "ereignis", "(ist %s)" % art(FIXTURE[1]))
pruef("weder Werkzeug noch Selbstbericht -> unbestimmt",
      art(FIXTURE[2]) == "unbestimmt", "(ist %s)" % art(FIXTURE[2]))
pruef("⭐ Abwesenheit eines Namens macht KEIN ereignis",
      art(FIXTURE[2]) != "ereignis")

print()
print("=== 2) status_von() — behoben NUR mit Commit-Beleg ===")
pruef("⛔ NEGATIVKONTROLLE: status=behoben OHNE commit bleibt offen",
      status_von(FIXTURE[3]) == "offen", "(ist %s)" % status_von(FIXTURE[3]))
mit = dict(FIXTURE[3]); mit["commit"] = "1e6f718"
pruef("⭐ POSITIVKONTROLLE: status=behoben MIT commit ist behoben",
      status_von(mit) == "behoben", "(ist %s)" % status_von(mit))
er = dict(FIXTURE[1]); er["status"] = "behoben"; er["commit"] = "1e6f718"
pruef("⛔ ein EREIGNIS wird auch mit Beleg NICHT geschlossen",
      status_von(er) == "offen", "(ist %s)" % status_von(er))

print()
print("=== 3) debug_aufraeumen.py --behoben, am echten Skript ===")
tmp = tempfile.mkdtemp(prefix="p14_")
try:
    idx = os.path.join(tmp, "index.jsonl")
    with io.open(idx, "w", encoding="utf-8", newline="\n") as f:
        for e in FIXTURE:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    vorher = io.open(idx, encoding="utf-8").read()

    def lauf(*args):
        return subprocess.run([sys.executable, AUFRAEUMEN, tmp] + list(args),
                              capture_output=True, text=True, encoding="utf-8",
                              errors="replace")

    r = lauf("--behoben", "1")
    pruef("⛔ --behoben OHNE --commit -> rc 2", r.returncode == 2,
          "(rc=%s)" % r.returncode)
    pruef("   ... und die Datei ist unveraendert",
          io.open(idx, encoding="utf-8").read() == vorher)

    r = lauf("--behoben", "1", "--commit", "kein-hash")
    pruef("⛔ ungueltiger Hash -> rc 2", r.returncode == 2, "(rc=%s)" % r.returncode)

    r = lauf("--behoben", "2", "--commit", "1e6f718")
    pruef("⛔ ein EREIGNIS laesst sich nicht schliessen -> rc 2",
          r.returncode == 2, "(rc=%s)" % r.returncode)

    r = lauf("--behoben", "99", "--commit", "1e6f718")
    pruef("⛔ Zeile ausserhalb -> rc 2", r.returncode == 2, "(rc=%s)" % r.returncode)

    pruef("⛔ nach VIER abgelehnten Aufrufen immer noch unveraendert",
          io.open(idx, encoding="utf-8").read() == vorher)

    r = lauf("--behoben", "1", "--commit", "1e6f718")
    pruef("⭐ POSITIVKONTROLLE: der #8-Befund laesst sich schliessen -> rc 0",
          r.returncode == 0, "(rc=%s · %s)" % (r.returncode, r.stderr.strip()[:90]))
    danach = [json.loads(z) for z in io.open(idx, encoding="utf-8") if z.strip()]
    pruef("   ... status steht in der Datei",
          danach[0].get("status") == "behoben")
    pruef("   ... commit steht daneben", danach[0].get("commit") == "1e6f718")
    pruef("   ... und status_von() sagt jetzt behoben",
          status_von(danach[0]) == "behoben")
    pruef("   ... die drei anderen sind unberuehrt",
          all("status" not in d or d.get("status") == "behoben"
              for d in danach[1:]) and danach[1] == FIXTURE[1])

    print()
    print("=== 3b) --repo: der Beleg wird GEPRUEFT, nicht geglaubt ===")
    # ⛔ DIESE VIER FAELLE FEHLTEN, und ihr Fehlen hat sofort gekostet. Die erste
    #    Fassung dieser Sammlung fuhr --repo NIE. Beim ERSTEN echten Einsatz starb
    #    der Zweig mit UnboundLocalError: ein `import subprocess` im Rumpf von main()
    #    machte den Namen fuer die ganze Funktion lokal. 24 gruene Faelle, und der
    #    einzige Pfad mit echter Aussenwirkung war ungeprueft.
    # ⛔ ZWEI Dirnames, nicht drei: WURZEL ist <repo>/plugins/claude-mind-manager.
    #    Meine erste Fassung nahm drei und landete EINE Ebene ueber dem Repo — der
    #    Fall wurde dadurch stillschweigend uebersprungen und sah wie bestanden aus.
    REPO = os.path.dirname(os.path.dirname(WURZEL))
    ist_repo = os.path.isdir(os.path.join(REPO, ".git"))

    def fixture_neu():
        with io.open(idx, "w", encoding="utf-8", newline="\n") as f:
            for e in FIXTURE:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")

    if ist_repo:
        fixture_neu()
        r = lauf("--behoben", "1", "--commit", "1e6f718", "--repo", REPO)
        pruef("⭐ echter Commit im echten Repo -> rc 0", r.returncode == 0,
              "(rc=%s · %s)" % (r.returncode, (r.stderr or "").strip()[:90]))
        pruef("   ... und die Ausgabe nennt die Existenzpruefung",
              "Existenz in" in (r.stdout or ""))
        fixture_neu()
        r = lauf("--behoben", "1", "--commit", "0123456789abcdef", "--repo", REPO)
        pruef("⛔ formgueltiger, aber NICHT existierender Commit -> rc 2",
              r.returncode == 2, "(rc=%s)" % r.returncode)
        # ⛔ Genau auf EINTRAG 1 pruefen, nicht auf die ganze Datei. FIXTURE[3]
        #    traegt selbst ein `status`-Feld (bewusst, ohne commit) — eine Suche
        #    ueber die Datei findet es immer und ist damit blind fuer den Fall.
        z1 = json.loads(io.open(idx, encoding="utf-8").readline())
        pruef("   ... und Eintrag 1 bleibt dabei ungeschlossen",
              "status" not in z1 and "commit" not in z1, "(%s)" % z1.get("status"))
    else:
        print("  [uebersprungen] kein Git-Repo unter %s — ein uebersprungener Fall\n"
              "                  ist KEIN bestandener" % REPO)

    # ⛔ Zeile 1 ist der ZUSTAND-Befund. Meine erste Fassung nahm Zeile 3 — die ist
    #    `unbestimmt` und wird korrekt abgelehnt; der Fall pruefte also die
    #    Ablehnung und nannte sich Formpruefung.
    fixture_neu()
    r = lauf("--behoben", "1", "--commit", "1e6f718")
    pruef("⚠ OHNE --repo laeuft nur die Formpruefung, und sie sagt es",
          r.returncode == 0 and "Form" in (r.stdout or ""),
          "(rc=%s)" % r.returncode)

    print()
    print("=== 4) BEFUNDE.md — der dreiteilige Abschnitt ===")
    r = subprocess.run([sys.executable, AUSWERTUNG, tmp],
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace")
    bef = os.path.join(tmp, "BEFUNDE.md")
    pruef("debug_auswertung.py laeuft durch", r.returncode == 0,
          "(%s)" % r.stderr.strip()[:120])
    txt = io.open(bef, encoding="utf-8").read() if os.path.isfile(bef) else ""
    pruef("Abschnitt 'Art und Status' steht drin", "## Art und Status" in txt)
    pruef("⭐ ZUSTAND-behoben zeigt den geschlossenen Befund",
          "ZUSTAND — behoben" in txt and "1e6f718" in txt)
    pruef("ZUSTAND-offen ist eine eigene Zeile", "ZUSTAND — offen" in txt)
    pruef("EREIGNIS wird als Historie gefuehrt", "EREIGNIS" in txt)
    pruef("⛔ die unbestimmten werden AUSGEWIESEN, nicht geraten",
          "unbestimmt" in txt)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print()
print("  %d gruen · %d rot" % (gruen, rot))
sys.exit(1 if rot else 0)
