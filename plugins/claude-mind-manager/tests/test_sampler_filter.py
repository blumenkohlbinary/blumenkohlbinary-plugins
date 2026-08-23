# -*- coding: utf-8 -*-
"""Die vier Kategorie-Filter des Samplers — gegen FESTE Saetze (NEU v5.13.0).

⛔ WARUM ES DIESE SAMMLUNG GIBT, OBWOHL test_precompact.py SCHON EXISTIERT

`test_precompact.py` faehrt den Hook gegen ein ECHTES Transkript und waehlt dafuer
`kandidaten[1]` — das zweitkleinste `.jsonl` im Projektordner. Welche Datei das ist,
haengt davon ab, welche Sitzungen gerade herumliegen. Am 23.08.2026 traf es erst ein
Transkript mit 0 Entscheidungen (rot) und Minuten spaeter eines mit 2 (gruen), ohne
dass sich eine Zeile Code geaendert haette.

**Ein Prueffall, dessen Urteil davon abhaengt, welche Datei er zufaellig greift, ist
keine Messung.** Er kann den Defekt anzeigen, aber er kann ihn nicht ausschliessen —
und genau das braucht man von einer Pruefung.

Deshalb hier: feste Eingaben, festes Urteil. Die Transkript-Sammlung bleibt daneben
bestehen (sie prueft den Hook als Ganzes), diese hier prueft den FILTER.

⛔ BEIDE RICHTUNGEN SIND PFLICHT. Ein Muster, das alles trifft, waere mit einer reinen
Positivliste gruen — und waere der schlimmere Fehler: ein Arbeitsstand voller Rauschen
ist unbrauchbarer als einer mit einer leeren Kategorie, weil das Rauschen wie Inhalt
aussieht.

Rueckgabe: 0 = alle Zusicherungen halten · 1 = mindestens eine nicht
"""
import io
import os
import sys

# ⛔ PFLICHT auf Windows. Ohne diese Zeile bricht der Lauf beim ersten ⚠ mit
#    UnicodeEncodeError ab — und zwar NACH den Zusicherungen, sodass der
#    Rueckgabewert noch 0 sein kann. Ein gruener Abbruch ist das Schlimmste,
#    was eine Pruefsammlung tun kann.
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

WURZEL = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(WURZEL, "references"))

from session_sampler import (                                    # noqa: E402
    DECISION_PATTERNS_ASSISTANT, BUG_PATTERNS,
    CONSTRAINT_PATTERNS_USER, RELEVANT_PATTERNS, NICHT_BUG,
)

fehler = 0


def pruefe(name, ist, soll):
    global fehler
    ok = ist == soll
    if not ok:
        fehler += 1
    print("    %-4s %-52s ist=%-7s soll=%s"
          % ("OK" if ok else "FEHL", name, ist, soll))


def trifft(muster, s):
    return any(p.search(s) for p in muster)


# ---------------------------------------------------------------------------
# 1) ENTSCHEIDUNGEN
# ---------------------------------------------------------------------------
# Alle zehn stammen woertlich oder sinngemaess aus echten Sitzungen dieses
# Projekts. Die alte Fassung traf davon NULL.
ENTSCHEIDUNG_JA = [
    "Die Entscheidung ist gefallen: 5 von 12 Regeln werden Skills.",
    "Nutzer-Entscheidung 23.08.2026: Phase E wird gestrichen.",
    "Wir haben uns fuer die zuwachsbasierte Loesung entschieden.",
    "Das ist eine architektonische Entscheidung, kein Detail.",
    "Stattdessen wird der Anteil verglichen, nicht die absolute Zahl.",
    "Der Regler ist entfallen; die Auto-Kompaktierung wurde umgestellt.",
    "Wir setzen auf einen Sammel-Laeufer statt auf namentliche Aufrufe.",
    "Festgelegt: kein neuer Zwang, nur eine Mahnung.",
    "Bewusst NICHT gemacht: unveraenderte Dateien nur referenzieren.",
    "Der Ansatz wurde verworfen, weil das Instrument den Gegenstand verfehlt.",
]

# ⚠ Die Negativliste traegt die eigentliche Beweislast. Ohne sie waere
#   `re.compile(r'.')` gruen.
ENTSCHEIDUNG_NEIN = [
    "Der Testlauf dauerte elf Sekunden.",
    "Die Datei hat 645 Zeilen.",
    "Ich lese jetzt den Debug-Ordner.",
    "Guten Morgen, wie ist der Stand?",
    "Das Transkript liegt bei 4,1 MB.",
    # Der Grenzfall, an dem der Fix haette ueberschiessen koennen:
    # "entscheidend" ist ein Adjektiv, keine Entscheidung.
    "Das war die entscheidende Zeile in der Schleife.",
    "Ein entscheidender Unterschied zur vorigen Fassung.",
]

print("=" * 78)
print("  1) ENTSCHEIDUNGEN")
print("=" * 78)
tref = sum(1 for s in ENTSCHEIDUNG_JA if trifft(DECISION_PATTERNS_ASSISTANT, s))
falsch = sum(1 for s in ENTSCHEIDUNG_NEIN if trifft(DECISION_PATTERNS_ASSISTANT, s))
for s in ENTSCHEIDUNG_JA:
    if not trifft(DECISION_PATTERNS_ASSISTANT, s):
        print("    verfehlt: %s" % s[:66])
for s in ENTSCHEIDUNG_NEIN:
    if trifft(DECISION_PATTERNS_ASSISTANT, s):
        print("    fehltreffer: %s" % s[:66])
pruefe("echte Entscheidungen getroffen", tref, len(ENTSCHEIDUNG_JA))
pruefe("Fehltreffer auf Nicht-Entscheidungen", falsch, 0)

# Die beiden Staemme einzeln — sie waren die konkrete Ursache.
print()
for wort, soll in [("Entscheidung", True), ("entschieden", True),
                   ("architektonisch", True), ("Architektur", True),
                   ("entscheidend", False)]:
    pruefe("Stamm %r" % wort, trifft(DECISION_PATTERNS_ASSISTANT, wort), soll)

# Dasselbe fuer die Relevanz-Muster (`--full`), die denselben Defekt trugen.
print()
for wort, soll in [("Entscheidung", True), ("entschieden", True),
                   ("architektonisch", True), ("Kaffeetasse", False)]:
    pruefe("RELEVANT_PATTERNS[0] %r" % wort,
           bool(RELEVANT_PATTERNS[0].search(wort)), soll)

# ---------------------------------------------------------------------------
# 2) BUGS — und die Abgrenzung gegen Transportfehler
# ---------------------------------------------------------------------------
print()
print("=" * 78)
print("  2) BUGS")
print("=" * 78)
BUG_JA = [
    "Traceback (most recent call last):",
    "fix: die Wortgrenze hinter dem Stamm entfernt",
    "error: cannot open file",
    "Der Prozess crasht beim zweiten Lauf.",
]
BUG_NEIN = [
    "Der Lauf war unauffaellig.",
    "Alle 11 Sammlungen gruen.",
]
# ⚠ BEKANNTE GRENZE, beim Bau dieser Sammlung aufgefallen und BEWUSST offen
#   gelassen: deutsche Partizipien mit Vorsilbe treffen nicht. "gecrasht"
#   scheitert an `\bcrash`, weil "ge" davorsteht — das ist DERSELBE
#   Wortgrenzen-Fehler wie F1, nur in dieser Kategorie.
#
#   Nicht mitrepariert, weil die Bug-Kategorie im Betrieb funktioniert
#   (2 Treffer im Lauf vom 23.08.) und eine Verbreiterung auf `crash\w*` ohne
#   fuehrende Grenze Dateinamen und Pfade mitfangen wuerde. Erst messen,
#   was in echten Transkripten vorkommt, dann erweitern — nicht umgekehrt.
BUG_GRENZFALL = ["Der Hook ist gecrasht.", "Das Skript ist abgestuerzt."]
pruefe("Bugs getroffen", sum(1 for s in BUG_JA if trifft(BUG_PATTERNS, s)), len(BUG_JA))
pruefe("Fehltreffer auf Nicht-Bugs",
       sum(1 for s in BUG_NEIN if trifft(BUG_PATTERNS, s)), 0)
print("    ---- Grenzfaelle (dokumentiert, KEINE Zusicherung) ----")
for s in BUG_GRENZFALL:
    print("    %-8s %s" % ("faengt" if trifft(BUG_PATTERNS, s) else "still", s))
print("    -> deutsche Partizipien mit Vorsilbe treffen nicht. Bekannt, s. Kommentar.")

# ⛔ Transportfehler sind KEINE Projekt-Bugs (v5.7.0). Wer sie nach einer
#    Kompaktierung liest, sucht einen Fehler, den es im Projekt nie gab.
for s in ["API Error: Connection lost mid-response", "rate limit erreicht"]:
    pruefe("NICHT_BUG faengt %r" % s[:28],
           any(n in s.lower() for n in NICHT_BUG), True)

# ---------------------------------------------------------------------------
# 3) CONSTRAINTS — der zweite schwache Filter
# ---------------------------------------------------------------------------
print()
print("=" * 78)
print("  3) CONSTRAINTS")
print("=" * 78)
CON_JA = [
    "NEVER benutze git add -A in diesem Repo.",
    "Du sollst niemals Nutzerdaten committen, das ist wichtig.",
    "kein push ohne Freigabe",
    "bitte nicht die dist/ loeschen",
]
# ⚠ Das ist die Schwachstelle, die im /mind-compact-Lauf sichtbar wurde:
#   `\bimmer\b.{10,}` faengt JEDEN Satz mit "immer" — auch Beschreibungen.
#   Die Faelle stehen hier als DOKUMENTIERTE Grenze, nicht als Zusicherung.
CON_GRENZFALL = [
    "vorher hat er immer bei 1mio kontext autocompact gemacht",
    "es soll immer eine aktuelle kopie in SKILLS sein",
]
pruefe("Constraints getroffen",
       sum(1 for s in CON_JA if trifft(CONSTRAINT_PATTERNS_USER, s)), len(CON_JA))
print("    ---- Grenzfaelle (kein Urteil, nur sichtbar machen) ----")
for s in CON_GRENZFALL:
    print("    %-8s %s" % ("faengt" if trifft(CONSTRAINT_PATTERNS_USER, s) else "still",
                           s[:60]))
print("    ⚠ Der zweite ist ein echter Constraint, der erste eine Beschreibung —")
print("      und der Filter kann sie nicht unterscheiden. Bekannt, siehe PLAN F5.")

print()
print("=== %d Abweichung(en) ===" % fehler)
sys.exit(1 if fehler else 0)
