#!/usr/bin/env python3
"""coverage_gate.py — belegt, ob Quellwissen in einer Zieldatei angekommen ist.

WOZU: Wurde Wissen aus mehreren Quelldateien in ein Zieldokument uebertragen (Referenzen ->
Leitfaden, Recherche -> Notiz, Rohmaterial -> Doku), soll Vollstaendigkeit GEMESSEN werden,
nicht behauptet. Das Skript zieht aus jeder Quelle sprachunabhaengige Pruefpunkte und sucht
sie im Zieltext.

Reines Markdown rein, Prozentzahl raus — keine Anbindung an irgendein Notiz-System.
(Hiess bis v5.2.2 `joplin_coverage_gate.py`; der Name behauptete eine Bindung, die es nie gab.)

⛔ DIE GEGENPROBE IST TEIL DES LAUFS, NICHT OPTIONAL.
Vor der eigentlichen Messung wird ein Stichwort geprueft, das nachweislich NICHT im Ziel steht.
Meldet das Gate dafuer "belegt", misst es nichts — dann bricht der Lauf ab und ALLE Ergebnisse
dieses Laufs sind ungueltig. Genau dieser Fehler (Treffer ueber eine beliebige Namensnennung)
steckte am 2026-08-16 real in `mind_check_tools_have_rules` und meldete ein totes Tool als PASS.

⚠ EHRLICHE GRENZE 1: Gemessen wird ERWAEHNUNG, nicht inhaltliche Treue. Ein Stichwort kann
vorkommen, waehrend der Punkt verstuemmelt uebertragen wurde. Das Gate schliesst AUSLASSUNGEN
aus, nicht VERFAELSCHUNGEN. Wer mehr behauptet, benutzt es falsch.

⚠ EHRLICHE GRENZE 2: Die absolute Prozentzahl allein ist wertlos. Gemessen 2026-08-16: gegen
einen Stand, in dem das Material nachweislich FEHLTE, meldete das Gate trotzdem 43 % — teils
echte thematische Ueberlappung, teils Zufallstreffer. Aussagekraeftig ist der ZUWACHS zwischen
Vorher- und Nachher-Stand. Bleibt die Zahl gleich, ist nichts angekommen — egal wie hoch sie ist.

Aufruf:
    python tools/coverage_gate.py <zieltext.md> <quelle1.md> [quelle2.md ...]

Rueckgabe: 0 = alle Pruefpunkte belegt · 1 = offene Punkte (einzeln gelistet)
           2 = falscher Aufruf · 3 = MESSUNG UNGUELTIG (Negativkontrolle hat angeschlagen)
"""
import io
import re
import sys
import unicodedata

# Windows-Konsole ist cp1252 und stirbt an Pfeilen/Umlauten aus den Quelldateien.
# (Eigene Regel, beim ersten Entwurf missachtet und prompt abgestuerzt.)
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

NEG_CONTROL = "zzznichtvorhandenerbegriff"


def normalize(text: str) -> str:
    """Kleinschreibung + Umlaute/Akzente entfernen, damit ae/ä beide treffen."""
    text = text.lower()
    text = (text.replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
                .replace("ß", "ss"))
    text = unicodedata.normalize("NFKD", text)
    return "".join(c for c in text if not unicodedata.combining(c))


def checkpoints(path: str):
    """Pruefpunkte einer Quelldatei — SPRACHUNABHAENGIGE Marker.

    Dieses Verfahren ist der dritte Entwurf. Die beiden verworfenen stehen hier, weil beide
    plausibel aussahen und trotzdem nichts massen:

    ⛔ ENTWURF 1 — EIN Stichwort je Pruefpunkt. Gemessen gegen einen Stand, in dem das Material
    nachweislich fehlte, meldete er **58,6 % belegt**: generische Woerter wie "detection" oder
    "estimation" treffen irgendwo immer. Ein Gate mit dieser Falsch-Positiv-Rate behauptet
    Abdeckung, statt sie zu zeigen — und faellt in die gefaehrliche Richtung.

    ⛔ ENTWURF 2 — mehrere Stichwoerter, aber aus dem QUELLTEXT gezogen (Ueberschriften, fett
    Markiertes). Die Quellen waren englisch, die Uebertragung deutsch. Ein Gate, das
    "programmatic"+"access" sucht, findet "Kein programmatischer Zugriff" nie — es meldete
    Vorher und Nachher fast identisch (4/13 in BEIDEN Faellen), obwohl der Abschnitt
    nachweislich uebertragen war. Die Messung war strukturell blind fuer ihren Gegenstand,
    und die unbewegte Zahl sah aus wie ein Befund.

    Was eine Uebersetzung UEBERLEBT und deshalb hier gezaehlt wird:
      - Zahlen mit Bedeutung:        22.5 · 7.5 · 167K · 96% · 71% · 14,000 · 200
      - Codebezeichner in Backticks: `globs:` · `MEMORY.md` · `@import` · `PreCompact`
      - Eigennamen/Produkte:         SFEIR · Cursor · Cline · Aider · Copilot
    Ein uebersetzter Text, der diese Marker nicht enthaelt, hat den Inhalt tatsaechlich nicht
    uebernommen — das ist der Punkt. Fliesstext-Substantive werden bewusst NICHT gezaehlt:
    die sind genau das, was beim Uebersetzen verschwindet.
    """
    out, seen = [], set()
    text = open(path, encoding="utf-8", errors="replace").read()

    # 1) Inline-Code — Bezeichner, Pfade, Frontmatter-Schluessel
    for m in re.findall(r"`([^`\n]{3,40})`", text):
        tok = normalize(m).strip()
        if len(tok) >= 4 and not tok.isdigit():
            out.append((f"`{m}`", (tok,)))

    # 2) Zahlen mit Aussage: Prozent, Tausender, K-Angaben, Dezimalwerte
    for m in re.findall(r"\b\d[\d.,]*\s?(?:%|K\b|T/line|tokens?\b|lines?\b|Zeilen\b)", text):
        tok = normalize(re.sub(r"\s+", "", m))
        num = re.match(r"[\d.,]+", tok)
        if num and len(num.group(0).strip(".,")) >= 2:
            out.append((m.strip(), (num.group(0).rstrip(".,"),)))

    # 3) Eigennamen: GrossKleinSchreibung oder Versalien, technisch/Produkt
    for m in re.findall(r"\b(?:[A-Z][a-z]+[A-Z][A-Za-z]+|[A-Z]{4,})\b", text):
        out.append((m, (normalize(m),)))

    uniq = []
    for phrase, kw in out:
        if kw not in seen:
            seen.add(kw)
            uniq.append((phrase, kw))
    return uniq


def main(argv):
    if len(argv) < 3:
        print("Aufruf: coverage_gate.py <ziel.md> <quelle.md> [...]")
        return 2

    target = normalize(open(argv[1], encoding="utf-8", errors="replace").read())

    # --- Gegenprobe zuerst: die Messung muss scheitern koennen ---
    if NEG_CONTROL in target:
        print("ABBRUCH: Negativkontrolle im Ziel gefunden — Messung unbrauchbar.")
        return 3
    print("Gegenprobe: Kontrollbegriff NICHT im Ziel -> das Gate kann scheitern. OK\n")

    total_ok = total = 0
    for src in argv[2:]:
        pts = checkpoints(src)
        missing = [(p, k) for p, k in pts if not all(t in target for t in k)]
        ok = len(pts) - len(missing)
        total_ok += ok
        total += len(pts)
        name = src.replace("\\", "/").split("/")[-1]
        print(f"{name}: {ok}/{len(pts)} belegt")
        for phrase, kw in missing:
            print(f"    OFFEN  [{'+'.join(kw)}]  {phrase}")
        if missing:
            print()

    pct = (100 * total_ok / total) if total else 0
    print(f"\nGESAMT: {total_ok}/{total} Pruefpunkte belegt ({pct:.1f} %)")
    print("HINWEIS: gemessen wurde ERWAEHNUNG, nicht inhaltliche Treue.")
    return 0 if total_ok == total else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
