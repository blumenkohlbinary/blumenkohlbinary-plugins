# -*- coding: utf-8 -*-
"""classify_path — Aufzaehlungen sind keine Pfade (NEU v5.13.0).

⛔ WARUM ES DIESE SAMMLUNG GIBT

Im Zustellplan-Lauf vom 21.08.2026 meldete Check 13 pro Regeldatei **10 bis 21**
tote Pfade, die keine waren: `a/b/c`, `UPDATE/ENRICH/ADD`, `Nutzer/Tester/Betreiber`.
Die vorhandene Regel 3w fing solche Aufzaehlungen ab — aber nur bei GENAU ZWEI
Gliedern (`p.count('/') == 1`). Drei Glieder rutschten durch.

⚠ Das eigentliche Problem war nicht die Zahl der Fehltreffer, sondern was sie mit
der Pruefung machen: eine Ausgabe, die zu 95 % aus Rauschen besteht, wird nicht
mehr gelesen. Ein Instrument, dem niemand mehr glaubt, misst faktisch nichts —
dieselbe Wirkung wie ein Instrument, das nichts misst.

⛔ BEIDE RICHTUNGEN SIND PFLICHT. Eine SKIP-Regel laesst sich beliebig verbreitern,
bis gar nichts mehr gemeldet wird; dann ist die Ausgabe sauber und die Pruefung tot.
Deshalb steht neben jeder Aufzaehlung ein echter Pfad, der CHECK BLEIBEN MUSS.

Rueckgabe: 0 = alle Zusicherungen halten · 1 = mindestens eine nicht
"""

import os
import sys

WURZEL = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(WURZEL, "references"))

from claudemd_pipeline import classify_path                      # noqa: E402

# ⛔ `reconfigure`, NICHT `sys.stdout = io.TextIOWrapper(...)`.
#    `claudemd_pipeline` setzt beim Import selbst einen TextIOWrapper auf
#    `sys.stdout.buffer`. Wer danach EINEN ZWEITEN darueberlegt, laesst den
#    ersten ohne Referenz zurueck — und ein TextIOWrapper SCHLIESST beim
#    Wegraeumen seinen Puffer. Der naechste `print` bricht dann mit
#    `ValueError: I/O operation on closed file`.
#    Zweimal beim Bau dieser Sammlung passiert, beide Male sah es aus wie ein
#    Fehler im Prueffall und war einer in der Reihenfolge.
#    `reconfigure` tauscht kein Objekt aus und hat das Problem nicht.
sys.stdout.reconfigure(encoding="utf-8")

fehler = 0


def pruefe(p, soll):
    global fehler
    ist = classify_path(p)
    ok = ist == soll
    if not ok:
        fehler += 1
    print("    %-4s %-34s ist=%-7s soll=%s" % ("OK" if ok else "FEHL", p, ist, soll))


print("=" * 78)
print("  AUFZAEHLUNGEN — duerfen NICHT als toter Pfad gemeldet werden")
print("=" * 78)
# Die drei aus dem echten Befund
pruefe("a/b/c", "UNSURE")
pruefe("UPDATE/ENRICH/ADD", "UNSURE")
pruefe("Nutzer/Tester/Betreiber", "UNSURE")
# Vier Glieder — eine Aufzaehlung wird nicht dadurch zum Pfad, dass sie waechst
pruefe("rot/gelb/gruen/blau", "UNSURE")
# Die zwei Glieder, die schon vorher funktionierten (Regressionsschutz)
pruefe("ja/nein", "UNSURE")
pruefe("actual/expected", "UNSURE")
# Umlaute — deutsche Regeldateien schreiben so
pruefe("Groesse/Anzahl", "UNSURE")
pruefe("Größe/Anzahl", "UNSURE")

print()
print("=" * 78)
print("  ECHTE PFADE — muessen CHECK BLEIBEN (die Gegenrichtung)")
print("=" * 78)
# ⛔ Ohne diesen Block waere `return 'UNSURE'` fuer alles gruen.
pruefe("tools/rollback.py", "CHECK")
pruefe("hooks/lib.sh", "CHECK")
pruefe("references/session_sampler.py", "CHECK")
pruefe(".claude/rules/env-vars.md", "CHECK")
pruefe("~/.claude/rules/keine-annahmen.md", "CHECK")
pruefe("skills/mind-all/SKILL.md", "CHECK")
# Bindestrich-Segmente sind keine schlichten Woerter -> bleiben CHECK
pruefe("references/doc-templates", "CHECK")
pruefe("plugins/claude-mind-manager", "CHECK")

print()
print("=" * 78)
print("  BEKANNTE GRENZE — dokumentiert, KEINE Zusicherung")
print("=" * 78)
# Der Unterstrich macht das Segment zu keinem schlichten Wort. Der Pfad bleibt
# CHECK und wird weiterhin als tot gemeldet. Das ist ein ANDERER Befund: die
# Datei existiert wirklich nicht, weil sie beim Release geloescht wird.
# Er wird hier nicht miterschlagen, nur weil es bequem waere.
for p in ["dist/unstable/_build_counter"]:
    print("    %-34s -> %s   (bekannt, s. PLAN-debug-befunde.md F4)"
          % (p, classify_path(p)))

print()
print("=== %d Abweichung(en) ===" % fehler)
sys.exit(1 if fehler else 0)
