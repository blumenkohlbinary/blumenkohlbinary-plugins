#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Wertet das Ladeprotokoll aus: was laedt wirklich, wann und warum?

Gegenstueck zu `hooks/instructions-loaded.sh`. Beantwortet die Frage, an der zwei
fruehere Messversuche gescheitert sind:

  1. das Minimum der `usage`-Werte ueber heterogene Sitzungen genommen und fuer
     "Startkontext" gehalten -- ergab eine Anomalie, die es nicht gibt
  2. den Regeltext im Transkript gesucht; die Gegenprobe fand die EIGENEN
     Suchbefehle

⛔ WAS DIESES WERKZEUG NICHT SAGT: was das Laden an Tokens KOSTET. Es zaehlt
   Ladevorgaenge, nicht Kontextanteile. Wer daraus ein Budget ableitet, misst
   wieder etwas anderes als er glaubt.

⚠ Eine Datei, die NICHT im Protokoll steht, ist nicht bewiesen "laedt nicht" --
   sie kann auch schlicht in keiner protokollierten Sitzung dran gewesen sein.
   Der Bericht trennt das ausdruecklich.

Aufruf:  python ladeprotokoll_auswertung.py [--log <pfad>] [--rules <ordner>]
Rueckgabe: 0 = ausgewertet · 2 = kein Protokoll · 3 = Schema unbekannt
"""
import io
import os
import sys
import collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


def finde_log():
    for k in ("MIND_LADEPROTOKOLL",):
        if os.environ.get(k):
            return os.environ[k]
    d = os.environ.get("MIND_DEBUG_DIR")
    if d and os.path.isdir(d):
        return os.path.join(d, "ladeprotokoll.log")
    return "/tmp/mind-ladeprotokoll.log"


def main():
    log = finde_log()
    if "--log" in sys.argv:
        log = sys.argv[sys.argv.index("--log") + 1]
    rules = os.path.expanduser("~/.claude/rules")
    if "--rules" in sys.argv:
        rules = sys.argv[sys.argv.index("--rules") + 1]

    if not os.path.isfile(log):
        print("Kein Ladeprotokoll unter %s" % log, file=sys.stderr)
        print("Der Hook feuert beim SITZUNGSSTART - eine neue Sitzung noetig.",
              file=sys.stderr)
        return 2

    zeilen = [z for z in open(log, encoding="utf-8", errors="replace").read()
              .replace("\r\n", "\n").split("\n") if z.strip()]

    schema, kein_jq, eintraege = 0, 0, []
    for z in zeilen:
        t = z.split("\t")
        if len(t) < 3:
            continue
        if t[1] == "SCHEMA?":
            schema += 1
            continue
        if t[1] == "KEIN-JQ":
            kein_jq += 1
            continue
        eintraege.append({"ts": t[0], "grund": t[1], "pfad": t[2],
                          "sid": t[3] if len(t) > 3 else ""})

    print("=" * 78)
    print("  LADEPROTOKOLL  %s" % log)
    print("=" * 78)
    print("  %d Zeilen · %d auswertbar · %d mit unbekanntem Schema · %d ohne jq"
          % (len(zeilen), len(eintraege), schema, kein_jq))

    if schema and not eintraege:
        print()
        print("  ⛔ KEINE Zeile war lesbar - die Feldnamen des Ereignisses sind")
        print("     andere als angenommen. Die rohen Zeilen stehen im Protokoll und")
        print("     sagen, wie es richtig geht. Erst danach hat eine Auswertung Sinn.")
        for z in zeilen[:3]:
            print("     %s" % z[:150])
        return 3
    if schema:
        print("  ⚠ %d Zeilen mit unbekanntem Schema - Teilbild, nicht vollstaendig"
              % schema)
    if not eintraege:
        print("\n  Noch keine auswertbaren Eintraege. Der Hook feuert beim START -")
        print("  es braucht eine neue Sitzung.")
        return 2

    # --- nach Ladegrund ------------------------------------------------
    print()
    print("  " + "-" * 74)
    print("  NACH LADEGRUND")
    print("  " + "-" * 74)
    gruende = collections.Counter(e["grund"] for e in eintraege)
    for g, n in gruende.most_common():
        print("    %-22s %5d" % (g, n))

    # ⭐ Die Frage, wegen der das Werkzeug gebaut wurde.
    print()
    if "path_glob_match" in gruende:
        print("  ✅ `path_glob_match` KOMMT VOR (%d x) - pfadgebundenes Scoping"
              % gruende["path_glob_match"])
        print("     greift auf dieser Maschine.")
    else:
        print("  ⚠ `path_glob_match` kommt NICHT vor. Entweder traegt keine")
        print("     erreichte Regel ein `paths:`, oder das Scoping greift hier nicht.")
        print("     ⛔ Das ist noch KEIN Befund - erst mit einer Sonde, die ein")
        print("     `paths:` auf eine wirklich gelesene Datei setzt, wird es einer.")

    # --- nach Sitzung --------------------------------------------------
    sids = collections.Counter(e["sid"] for e in eintraege if e["sid"])
    if sids:
        print()
        print("  " + "-" * 74)
        print("  NACH SITZUNG  (%d Sitzungen protokolliert)" % len(sids))
        print("  " + "-" * 74)
        for s, n in sids.most_common(8):
            start = min(e["ts"] for e in eintraege if e["sid"] == s)
            print("    %-10s %4d Ladevorgaenge   ab %s" % (s, n, start))

    # --- welche Dateien ------------------------------------------------
    print()
    print("  " + "-" * 74)
    print("  GELADENE DATEIEN")
    print("  " + "-" * 74)
    dateien = collections.Counter(os.path.basename(e["pfad"]) for e in eintraege)
    for d, n in dateien.most_common(30):
        g = sorted({e["grund"] for e in eintraege
                    if os.path.basename(e["pfad"]) == d})
        print("    %-38s %4d x   %s" % (d[:38], n, ", ".join(g)[:28]))

    # --- was NICHT vorkam ----------------------------------------------
    if os.path.isdir(rules):
        vorhanden = {n for n in os.listdir(rules) if n.endswith(".md")}
        fehlend = sorted(vorhanden - set(dateien))
        print()
        print("  " + "-" * 74)
        print("  NICHT im Protokoll  (%d von %d Regeldateien in %s)"
              % (len(fehlend), len(vorhanden), rules))
        print("  " + "-" * 74)
        if fehlend:
            for f in fehlend:
                print("    ? %s" % f)
            print()
            print("  ⚠ \"Nicht im Protokoll\" heisst NICHT \"laedt nicht\". Es kann auch")
            print("     heissen, dass keine protokollierte Sitzung sie erreicht hat.")
            print("     Belastbar wird es erst, wenn eine Sitzung ohne sie startet und")
            print("     alle anderen im selben Lauf erscheinen.")
        else:
            print("    (keine - alle Regeldateien tauchen auf)")

    print()
    print("  ⛔ Gezaehlt werden LADEVORGAENGE, nicht Tokens. Ein Budget laesst sich")
    print("     daraus NICHT ableiten.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
