#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Negativkontrolle fuer die Fremdklon-Erkennung (v5.10.0).

⛔ Diese Pruefung greift auf RUECKGABEWERTE zu, nie auf den formatierten Bericht.
Am 21.08.2026 sind drei Kontrollen genau daran gescheitert: sie suchten einen
Namen in einer Berichtszeile, die gekuerzt wurde, und meldeten "nicht gefunden",
waehrend der Mechanismus tadellos funktionierte.

Die Kontrolle muss SCHEITERN KOENNEN — deshalb steht neben jedem Positivfall ein
Negativfall, der bei einer zu weiten Erkennung rot wird.
"""
import io
import os
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.environ.get("CLAUDE_PLUGIN_ROOT", os.path.dirname(HIER))
sys.path.insert(0, os.path.join(WURZEL, "references"))

from learnings_quellen import AUS, fremdklon, upstream_datei  # noqa: E402

K = "C:\\CD\\KOHLEKTIV"
FREMD = os.path.join(K, "Creator", "ComfyUI")
EIGEN_A = os.path.join(K, "Creator")
EIGEN_B = os.path.join(K, "APP - Palvedo")

ok = fehl = uebersprungen = 0


def pruefe(name, ist, soll):
    global ok, fehl
    if ist == soll:
        print("  OK    %s" % name)
        ok += 1
    else:
        print("  FEHL  %s -> %r, erwartet %r" % (name, ist, soll))
        fehl += 1


def ueberspringe(name, grund):
    global uebersprungen
    print("  UEBERSPRUNGEN  %s (%s)" % (name, grund))
    uebersprungen += 1


print("=== fremdklon() ===")

if os.path.isdir(os.path.join(FREMD, ".git")):
    # POSITIV: ComfyUI, Remote github.com/comfyanonymous/ComfyUI.git
    pruefe("Fremdklon mit fremdem Remote wird erkannt", fremdklon(FREMD), True)
else:
    ueberspringe("Fremdklon", "ComfyUI liegt hier nicht")

# NEGATIV: eigene Projekte ohne Remote duerfen NIE fremd sein.
# Ohne diese beiden waere eine Funktion, die immer True liefert, gruen.
for p in (EIGEN_A, EIGEN_B):
    if os.path.isdir(p):
        pruefe("eigenes Projekt ohne Remote ist nicht fremd: %s" % os.path.basename(p),
               fremdklon(p), False)
    else:
        ueberspringe(os.path.basename(p), "Projekt liegt hier nicht")

# NEGATIV: ein Verzeichnis ganz ohne git darf nicht abstuerzen und nicht fremd sein.
pruefe("Verzeichnis ohne git ist nicht fremd", fremdklon(HIER), False)

# NEGATIV: ein gar nicht existierender Pfad darf nicht abstuerzen.
pruefe("nicht existierender Pfad stuerzt nicht ab",
       fremdklon(os.path.join(K, "gibt-es-nicht-4711")), False)

print("\n=== upstream_datei() ===")

agents = os.path.join(FREMD, "AGENTS.md")
if os.path.isfile(agents):
    # POSITIV: versioniert im Fremdklon -> gehoert Upstream
    pruefe("versionierte Datei im Fremdklon gilt als Upstream",
           upstream_datei(FREMD, agents), True)

    # NEGATIV, der eigentliche Kern: eine NICHT versionierte Datei im SELBEN
    # Fremdklon gehoert weiter dem Nutzer. Ohne diesen Fall wuerde eine
    # Erkennung, die pauschal jeden Fremdklon ausblendet, gruen bleiben --
    # und dem Nutzer seine eigene CLAUDE.md unterschlagen.
    eigen = os.path.join(FREMD, "NUR-EIN-TEST-4711.md")
    try:
        with open(eigen, "w", encoding="utf-8") as fh:
            fh.write("# temporaer\n")
        pruefe("unversionierte eigene Datei im Fremdklon ist NICHT Upstream",
               upstream_datei(FREMD, eigen), False)
    finally:
        if os.path.isfile(eigen):
            os.remove(eigen)
else:
    ueberspringe("upstream_datei", "ComfyUI/AGENTS.md liegt hier nicht")

# NEGATIV: im eigenen Projekt ist NICHTS Upstream.
if os.path.isfile(os.path.join(EIGEN_B, "CLAUDE.md")):
    pruefe("eigene CLAUDE.md ist nicht Upstream",
           upstream_datei(EIGEN_B, os.path.join(EIGEN_B, "CLAUDE.md")), False)
else:
    ueberspringe("eigene CLAUDE.md", "Palvedo liegt hier nicht")

print("\n=== Ausschlussliste ===")
pruefe("publish/ ist ausgeschlossen", "publish" in AUS, True)
# NEGATIV: ein normaler Projektname darf NICHT ausgeschlossen sein.
pruefe("Creator ist NICHT ausgeschlossen", "Creator" in AUS, False)

print("\n%d OK, %d FEHL, %d uebersprungen" % (ok, fehl, uebersprungen))
sys.exit(1 if fehl else 0)
