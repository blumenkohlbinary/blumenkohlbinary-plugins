# -*- coding: utf-8 -*-
"""v5.41.0: Feld `ursache` und die Klasse `instrument-meldet-falsch`.

⛔ WARUM ES DAS FELD GIBT. Punkt 9 (08.09.2026) hat versucht,
   `instrument-misst-nichts` aus den eigenen Texten zu zerlegen. 70 % blieben
   UNBESTIMMT — nicht weil die Merkmale schlecht waren, sondern weil 66 % der
   Einträge kürzer als 120 Zeichen sind und jeder einen anderen Mechanismus in
   freier Formulierung beschreibt. Ein besseres Muster war die falsche Antwort.

⛔ WARUM DIE KLASSE GETEILT WURDE. 12 % der 102 Einträge waren FEHLALARME — die
   Prüfung fand zu VIEL, nicht zu wenig. Zwei entgegengesetzte Fehlermodi unter
   einem Namen machen die Klassengröße richtungslos.

⭐ DIE TRAGENDEN FÄLLE sind 2 und 4: das Feld darf NICHT zum Pflichtfeld werden
   (das zwänge zum Raten), und ein unbekannter Wert darf NICHT still in
   `sonstiges` verschwinden (dort verschwände jeder Tippfehler).
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

from debug_auswertung import KLASSEN, URSACHEN, ursache_von  # noqa: E402

gruen = rot = 0


def pruef(name, bed, zusatz=""):
    global gruen, rot
    if bed:
        gruen += 1
        print("  [ok ] %s" % name)
    else:
        rot += 1
        print("  [ROT] %s %s" % (name, zusatz))


print("=== 1) Die neue Klasse existiert und beschreibt das Gegenteil ===")
pruef("`instrument-meldet-falsch` steht in KLASSEN",
      "instrument-meldet-falsch" in KLASSEN)
pruef("   ... und `instrument-misst-nichts` steht weiter daneben",
      "instrument-misst-nichts" in KLASSEN)
pruef("⭐ die Beschreibungen sind gegensätzlich (VIEL gegen nichts)",
      "VIEL" in KLASSEN.get("instrument-meldet-falsch", "")
      and "nicht treffen" in KLASSEN.get("instrument-misst-nichts", ""),
      "(%r)" % KLASSEN.get("instrument-meldet-falsch"))

print()
print("=== 2) ⭐ Das Feld ist OPTIONAL — der tragende Fall ===")
pruef("fehlendes Feld -> `nicht-zugeordnet`",
      ursache_von({}) == "nicht-zugeordnet",
      "(ist %s)" % ursache_von({}))
pruef("leeres Feld -> `nicht-zugeordnet`",
      ursache_von({"ursache": "   "}) == "nicht-zugeordnet")
pruef("⛔ es wird NICHT geraten — kein Rückfall auf `sonstiges`",
      ursache_von({}) != "sonstiges")

print()
print("=== 3) Gesetzte Werte kommen durch ===")
for u in URSACHEN:
    pruef("`%s`" % u, ursache_von({"ursache": u}) == u)
pruef("Großschreibung wird normalisiert",
      ursache_von({"ursache": "Falsche-Bezugsgroesse"}) == "falsche-bezugsgroesse")

print()
print("=== 4) ⛔ Ein unbekannter Wert verschwindet NICHT ===")
# Sonst verschwände jeder Tippfehler still in einer Sammelkategorie — und die
# Ursachen-Bilanz wäre um genau die Fälle falsch, die jemand falsch getippt hat.
pruef("Tippfehler bleibt Tippfehler",
      ursache_von({"ursache": "falsche-bezugsgroese"}) == "falsche-bezugsgroese")
pruef("   ... und wird nicht zu `sonstiges`",
      ursache_von({"ursache": "quatsch"}) != "sonstiges")

print()
print("=== 5) Die Bilanz erscheint in BEFUNDE.md ===")
tmp = tempfile.mkdtemp(prefix="urs_")
try:
    idx = os.path.join(tmp, "index.jsonl")
    zeilen = [
        {"ts": "2026-09-08 10:00", "projekt": "P", "klasse": "instrument-meldet-falsch",
         "kurz": "Tote-Pfad-Check traf // in Kommentaren, 6 Fehlalarme",
         "ursache": "erreicht-gegenstand-nicht", "lauf": "x"},
        {"ts": "2026-09-08 10:01", "projekt": "P", "klasse": "instrument-misst-nichts",
         "kurz": "Summe ueber Teilstring gebildet",
         "ursache": "falsche-bezugsgroesse", "lauf": "x"},
        # ⭐ EINER OHNE Feld — er muss als `nicht-zugeordnet` auftauchen und
        #   ausdruecklich NICHT als Mangel bezeichnet werden.
        {"ts": "2026-09-08 10:02", "projekt": "P", "klasse": "sonstiges",
         "kurz": "irgendetwas", "lauf": "x"},
        # ⛔ und EINER mit Tippfehler — er muss als unbekannt auffallen
        {"ts": "2026-09-08 10:03", "projekt": "P", "klasse": "sonstiges",
         "kurz": "noch etwas", "ursache": "tippfehlr", "lauf": "x"},
    ]
    with io.open(idx, "w", encoding="utf-8", newline="\n") as f:
        for z in zeilen:
            f.write(json.dumps(z, ensure_ascii=False) + "\n")
    r = subprocess.run([sys.executable, os.path.join(REF, "debug_auswertung.py"), tmp],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    pruef("debug_auswertung laeuft durch", r.returncode == 0,
          "(%s)" % (r.stderr or "").strip()[:110])
    txt = io.open(os.path.join(tmp, "BEFUNDE.md"), encoding="utf-8").read()
    pruef("Abschnitt `## Ursachen` steht drin", "## Ursachen" in txt)
    pruef("die gesetzten Ursachen erscheinen",
          "erreicht-gegenstand-nicht" in txt and "falsche-bezugsgroesse" in txt)
    pruef("⭐ `nicht-zugeordnet` erscheint AUSDRUECKLICH als kein Mangel",
          "nicht-zugeordnet" in txt and "kein Mangel" in txt)
    pruef("⛔ der Tippfehler wird als UNBEKANNT gemeldet",
          "tippfehlr" in txt and "unbekannter Wert" in txt)
    pruef("die Zaehlung stimmt (3 von 4 tragen eine Ursache)",
          "3 von 4 Befunden tragen eine Ursache" in txt,
          "(gesucht in %d Zeichen)" % len(txt))
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print()
print("  %d gruen · %d rot" % (gruen, rot))
sys.exit(1 if rot else 0)
