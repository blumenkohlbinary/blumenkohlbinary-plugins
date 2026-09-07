# -*- coding: utf-8 -*-
"""D1 „Wohin gehört diese Aussage?" (v5.39.0, ZIEL 3).

⛔ DIE LÜCKE. Die acht Tore des Plugins fragen alle „darf das rein?". KEINES fragt
   „wohin?". B3 prüft, ob eine Aussage am SCHON GEWÄHLTEN Ort wirkt — es kann
   zustimmen oder ablehnen, nicht umleiten. Ein Türsteher, kein Wegweiser.

⭐ DIE POSITIVKONTROLLE HAT DIE ERSTE FASSUNG VERWORFEN, und das ist der Grund,
   warum diese Sammlung existiert. Fassung 1 nahm ⛔/NIE/MUSS als alleiniges
   Merkmal und zählte ZEILEN. Ergebnis:

     Leitplanke (bekannt BREMSE)      38 % BREMSE
     Command-Volltext (bekannt ANL.)  47 % BREMSE   <- MEHR, also falsch herum

   Zwei Fehler auf einmal: der Nutzer schreibt ⛔ auch in langer Prosa, und ein
   einziger 147-Wörter-Absatz überwog beim Zeilenzählen zehn kurze.

Aufruf:  python tests/test_d1_wohin.py
Rückgabe: 0 = alle grün · 1 = mindestens ein Fall rot
"""
import io
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

WURZEL = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(WURZEL, "references"))

from cleaner_einordnung import d1_wohin, _D1_MAX_WOERTER  # noqa: E402

gruen = rot = 0


def pruef(name, bed, zusatz=""):
    global gruen, rot
    if bed:
        gruen += 1
        print("  [ok ] %s" % name)
    else:
        rot += 1
        print("  [ROT] %s %s" % (name, zusatz))


LANG = " ".join(["wort"] * (_D1_MAX_WOERTER + 10))

print("=== 1) Die vier Klassen ===")
pruef("kurzes Verbot -> BREMSE",
      d1_wohin("⛔ NIE `git push` aus diesem Workspace.") == "BREMSE",
      "(ist %s)" % d1_wohin("⛔ NIE `git push` aus diesem Workspace."))
pruef("Aufruf mit Schalter -> ANLEITUNG",
      d1_wohin("Aufruf: `python tools/rollback.py list --alle`") == "ANLEITUNG",
      "(ist %s)" % d1_wohin("Aufruf: `python tools/rollback.py list --alle`"))
pruef("Messung mit Datum -> BELEG",
      d1_wohin("Gemessen am 21.08.2026 lagen dort 32 MB in neun Kopien.") == "BELEG",
      "(ist %s)" % d1_wohin("Gemessen am 21.08.2026 lagen dort 32 MB in neun Kopien."))
pruef("⚠ nichts trifft -> UNBESTIMMT, NICHT Anleitung",
      d1_wohin("Dieser Abschnitt beschreibt den Aufbau des Ordners.") == "UNBESTIMMT",
      "(ist %s)" % d1_wohin("Dieser Abschnitt beschreibt den Aufbau des Ordners."))

print()
print("=== 2) ⭐ Der Fehler, an dem Fassung 1 gescheitert ist ===")
kurz = "⛔ NIE mit Edit auf Z: schreiben."
lang = "⛔ " + LANG
pruef("kurzer Absatz mit ⛔ -> BREMSE", d1_wohin(kurz) == "BREMSE")
pruef("⭐ LANGER Absatz mit ⛔ -> NICHT Bremse, sondern ANLEITUNG",
      d1_wohin(lang) == "ANLEITUNG", "(ist %s)" % d1_wohin(lang))
pruef("   ... denn das Zeichen allein hob den Command ueber die Leitplanke",
      d1_wohin(kurz) != d1_wohin(lang))

print()
print("=== 3) Die Schwelle steht zwischen zwei Messungen ===")
# 39,5 Woerter = gui-Leitplanke (BREMSE) · 56,0 = z-mount-Command (ANLEITUNG)
pruef("Schwelle liegt ueber der gemessenen Bremse (39,5)", _D1_MAX_WOERTER > 40,
      "(ist %d)" % _D1_MAX_WOERTER)
pruef("Schwelle liegt unter der gemessenen Anleitung (56,0)", _D1_MAX_WOERTER < 56,
      "(ist %d)" % _D1_MAX_WOERTER)
knapp_drunter = "⛔ " + " ".join(["w"] * (_D1_MAX_WOERTER - 2))
knapp_drueber = "⛔ " + " ".join(["w"] * (_D1_MAX_WOERTER + 2))
pruef("knapp darunter -> BREMSE", d1_wohin(knapp_drunter) == "BREMSE")
pruef("knapp darueber -> ANLEITUNG", d1_wohin(knapp_drueber) == "ANLEITUNG")

print()
print("=== 4) ⭐ POSITIVKONTROLLE an ECHTEN Dateien ===")
# ⛔ Konstruierte Faelle bilden die eigene Erwartung ab. Diese fuenf sind echt
#    und ihre Rolle steht fest: zwei Leitplanken, zwei Commands, ein Archiv.
H = os.path.expanduser("~")
PROJ = os.path.dirname(os.path.dirname(os.path.dirname(WURZEL)))
FAELLE = [
    ("Leitplanke z-mount", os.path.join(H, ".claude/rules/z-mount-rclone.md"), "hoch"),
    ("Leitplanke gui", os.path.join(H, ".claude/rules/gui-pruefung-in-vm.md"), "hoch"),
    ("Command z-mount", os.path.join(H, ".claude/skills/z-mount-rclone/SKILL.md"), "niedrig"),
    ("Command gui", os.path.join(H, ".claude/skills/gui-pruefung-in-vm/SKILL.md"), "niedrig"),
]


def bremse_anteil(pfad):
    from cleaner_einordnung import absaetze
    with io.open(pfad, encoding="utf-8", errors="replace") as fh:
        a, _, _ = absaetze(fh.read())
    if not a:
        return None
    return 100.0 * sum(1 for x in a if d1_wohin(x) == "BREMSE") / len(a)


werte = {}
for name, pfad, erwartet in FAELLE:
    if not os.path.isfile(pfad):
        print("  [uebersprungen] %s fehlt — ein uebersprungener Fall ist KEIN"
              " bestandener" % name)
        continue
    p = bremse_anteil(pfad)
    werte[name] = p
    print("      %-22s BREMSE %4.0f %%  (erwartet %s)" % (name, p, erwartet))

if len(werte) == 4:
    tiefste_leitplanke = min(werte["Leitplanke z-mount"], werte["Leitplanke gui"])
    hoechster_command = max(werte["Command z-mount"], werte["Command gui"])
    pruef("⭐ JEDE Leitplanke hat mehr BREMSE als JEDER Command",
          tiefste_leitplanke > hoechster_command,
          "(niedrigste Leitplanke %.0f %% vs hoechster Command %.0f %%)"
          % (tiefste_leitplanke, hoechster_command))
    pruef("   ... und der Abstand ist nicht knapp (Faktor >= 2)",
          tiefste_leitplanke >= 2 * hoechster_command,
          "(%.0f %% gegen %.0f %%)" % (tiefste_leitplanke, hoechster_command))
else:
    print("  [uebersprungen] nicht alle vier Dateien vorhanden")

arch = os.path.join(PROJ, "Claude Mind Manager/.claude/archiv/env-vars.archiv.md")
if os.path.isfile(arch):
    p = bremse_anteil(arch)
    pruef("⭐ NEGATIVKONTROLLE: ein Archiv hat 0 %% BREMSE", p == 0,
          "(ist %.0f %%)" % p)
else:
    print("  [uebersprungen] Archiv nicht gefunden: %s" % arch)

print()
print("  %d gruen · %d rot" % (gruen, rot))
sys.exit(1 if rot else 0)
