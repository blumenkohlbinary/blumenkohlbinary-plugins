#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Erzeugt BEFUNDE.md aus Debug/index.jsonl (NEU v5.7.0).

WOZU. Jeder /mind-all-Lauf protokolliert Probleme und Vorschlaege projektlokal in
listeverbesserungen.md. Gemessen am 21.08.2026: 6 Projekte, 28 Laeufe — verstreut. Dass
DERSELBE Fehler zum dritten Mal auftritt, sah niemand. Genau das ist passiert: der
classify_path()-Nachbau meldete dreimal in Folge Slash-Commands als tote Pfade.

Diese Auswertung beantwortet genau eine Frage, und zwar mechanisch:
    Was ist das hier schon einmal gewesen?

Ab dem ZWEITEN Vorkommen einer Ursachenklasse steht WIEDERHOLT daneben. Das ist der ganze
Zweck — eine Liste, die nur zaehlt, haette den dritten Nachbau ebenso wenig verhindert wie
die zwei Lehren, die schon dazu aufgeschrieben waren.

Aufruf:  python debug_auswertung.py <debug-verzeichnis>
Rueckgabe: 0 = geschrieben · 1 = kein index.jsonl · 2 = Aufruffehler
"""
import json
import os
import re
import sys
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8", newline="")

# Feste Liste. Ein freies Textfeld waere nach drei Laeufen unbrauchbar — dann heisst
# derselbe Fehler dreimal anders und wird nie als Wiederholung erkannt.
KLASSEN = {
    "instrument-nachgebaut": "Ein vorhandenes Pruefwerkzeug wurde nachgebaut statt benutzt",
    "instrument-misst-nichts": "Eine Pruefung lief, konnte ihren Gegenstand aber nicht treffen",
    "windows-pfad": "MSYS-/Windows-Pfad, cygpath, Heredoc-Zerstoerung",
    "zeilenenden": "CRLF/LF gemischt oder unbeabsichtigt umgestellt",
    "agent-fehlbericht": "Ein Subagent gab etwas Falsches zurueck",
    "agent-gestorben": "Ein Subagent lieferte kein Ergebnis (= UNGEPRUEFT, nicht unauffaellig)",
    # NEU v5.19.0. ⛔ NICHT dasselbe wie `agent-gestorben`: dort lieferte ein
    # GESTARTETER Agent nichts, hier wurde nie einer gestartet. Der Unterschied
    # ist nicht akademisch — derselbe Vorfall wurde am 24.08.2026 zweimal
    # verschieden einsortiert (hier als `agent-gestorben`, im Projekt Creator
    # als `sonstiges`). Solange ein Ereignis zwei Namen traegt, kann die
    # Wiederholungserkennung das Muster nicht sehen.
    "lauf-unvollstaendig": "Ein Pflichtteil eines Laufs wurde ausgelassen (Kontext, Abbruch)",
    "plugin-defekt": "Fehler im Plugin selbst",
    "doku-veraltet": "Dokumentation widerspricht dem gemessenen Stand",
    "sichtbarkeit": "Inhalt existiert, wird aber nicht geladen/ausgewaehlt",
    "ungeklaerter-widerspruch": "Zwei Quellen widersprechen sich, keine ist belegt",
    # ⭐ NEU v5.36.0. Die MESSUNG stimmt, die DEUTUNG nicht. ⛔ Bewusst NICHT
    #    dasselbe wie `instrument-misst-nichts`: dort erreicht die Pruefung ihren
    #    Gegenstand nicht. Hier trifft sie ihn und die Zahl wird als etwas anderes
    #    gelesen, als sie ist. Vier Vorkommen an EINEM Abend (03.09.2026), damit
    #    ueber der Schwelle "ab drei ist es ein Konstruktionsfehler":
    #      Ereigniszahl als Rueckstand   (89 Befunde als offene Posten gelesen)
    #      Untergrenze als Zahl          (55 ZUSTAND-offen sind ein Mindestwert)
    #      Bytes mit Faktor 4            (gemessen 1,917 — 2,1x zu wenig)
    #      Hoechststand als Ist-Stand    (922 427 gemeldet, ist-Stand 297 878)
    # ⭐ NEU v5.41.0 — DAS GEGENTEIL von `instrument-misst-nichts`, und es lag
    #    bis heute mit ihr unter EINEM Namen. Gemessen 08.09.2026: von 102
    #    Eintraegen der alten Klasse sind 12 % Fehlalarme ("12 Fehlalarme
    #    statt 1 Befund", "6 Fehlalarme, 0 echte"). Eine Pruefung, die zu VIEL
    #    findet, misst nicht "nichts" — sie misst falsch.
    # ⛔ Zwei entgegengesetzte Fehlermodi unter einem Namen machen die
    #    Klassengroesse RICHTUNGSLOS: sie kann wachsen, weil mehr uebersehen
    #    wird, oder weil mehr faelschlich gemeldet wird. Erst die Trennung
    #    macht das Kriterium "hoert auf zu wachsen" ueberhaupt auswertbar.
    # ⚠ NUR VORWAERTS. Die 102 vorhandenen behalten ihren Namen — eine
    #   nachtraegliche Neuzuordnung waere Geschichtsfaelschung, dieselbe
    #   Begruendung wie im Docstring von debug_aufraeumen.py seit v5.9.2.
    "instrument-meldet-falsch": "Eine Pruefung fand zu VIEL — Fehlalarme statt Befunde",
    "zahl-in-falscher-rolle": "Die Messung stimmt, die Deutung nicht — Hoechst- statt Ist-Stand, Ereignis- statt Bestandszahl, Unter- statt Genauwert",
    "sonstiges": "passt in keine der obigen Klassen",
}

# ⛔ WEM GEHOERT DER BEFUND? (NEU v5.7.3)
#    Der Debug-Ordner ist fuer PLUGIN-Fehler da — das war die ausdrueckliche Absicht.
#    Die Laufberichte mischen aber drei Sorten: Fehler im Plugin, Fehler im Projekt und
#    eigene Methodenfehler. In einem Topf sieht der Plugin-Betreiber nicht, was IHN
#    angeht. Deshalb trennt BEFUNDE.md sie ab jetzt.
PLUGIN_KLASSEN = {
    "instrument-nachgebaut", "instrument-misst-nichts", "plugin-defekt",
    "agent-fehlbericht", "agent-gestorben", "sichtbarkeit",
    # v5.19.0: gehoert zum Plugin, nicht zum Projekt — ein ausgelassener
    # Pflichtteil ist ein Befund ueber den Ablauf, nicht ueber den Inhalt.
    "lauf-unvollstaendig",
}


def lies(pfad):
    eintraege, kaputt = [], 0
    with open(pfad, "rb") as f:
        for roh in f:
            roh = roh.strip()
            if not roh:
                continue
            try:
                e = json.loads(roh.decode("utf-8", "replace"))
            except Exception:
                kaputt += 1
                continue
            if isinstance(e, dict) and e.get("klasse"):
                eintraege.append(e)
            else:
                kaputt += 1
    return eintraege, kaputt


# --- Punkt 14: Art und Status je EINTRAG (NEU v5.35.0) -----------------------
#
# ⛔ JE EINTRAG, NIE JE KLASSE. Gemessen an `instrument-misst-nichts` (90 Eintraege):
#    22 nennen ein benanntes Werkzeug als fehlerhaft und sind damit behebbar, 68
#    nicht. Eine Trennung nach KLASSE haette die 22 zu unantastbarer Geschichte
#    erklaert — derselbe Fehler wie das umgekehrte Schliessen von Logbucheintraegen,
#    nur in die andere Richtung.
#
# ⛔ DIE WERKZEUGNENNUNG IST EIN FORMMERKMAL. Sie liefert KANDIDATEN, keine Urteile
#    — dieselbe Doktrin wie das Kontext-Tor und wie cleaner_leitplanke.py.
#
# ⛔ UND DIE ABWESENHEIT EINES NAMENS BELEGT NICHTS. "nennt kein Werkzeug, also
#    Bedienfehler" waere aus einem Nicht-Treffer ein Befund gemacht — woertlich die
#    Klasse, die hier gezaehlt wird. Deshalb gibt es einen DRITTEN Wert, und
#    `unbestimmt` ist die ehrliche Mehrheit, kein Rest.
#
# ⚠ DIESER AUSDRUCK IST DAS ORIGINAL, kein Nachbau. Beim Abstimmen dieser Aenderung
#   haben Manager und Arbeiter zwei verschiedene Fassungen gemessen (22 gegen 19) —
#   dem Nachbau fehlten `.sh` und `cleaner_*`. Das ist die Klasse
#   `instrument-nachgebaut`, live erzeugt im Gespraech ueber ein Werkzeug, das
#   Nachbauten zaehlt. Wer ihn aendert, misst den Bestand neu und sagt die Zahl dazu.
_WERKZEUG = re.compile(
    r"\b(mind_[a-z_]+|[a-z_]+\.py|[a-z_]+\.sh|claudemd_pipeline"
    r"|zaehl_gate|cleaner_[a-z]+|Check \d+)\b")

# Selbstbericht: der Verfasser nennt sich als Verursacher. Ebenfalls Formmerkmal.
_SELBST = re.compile(
    r"\b(?:ich|mein|meine|meinem|meiner|eigener|eigene|eigenen)\b", re.I)


# --- Feld `ursache` (NEU v5.41.0) --------------------------------------------
#
# ⛔ WARUM ES DAS GIBT. Punkt 9 hat versucht, `instrument-misst-nichts` aus den
#    eigenen Texten zu zerlegen. Ergebnis: 70 % UNBESTIMMT — und das war kein
#    Versagen der Merkmale, sondern eine Eigenschaft der Daten. 66 % der Eintraege
#    sind kuerzer als 120 Zeichen, in freier Formulierung, und jeder beschreibt
#    einen ANDEREN Mechanismus. Es gibt kein gemeinsames Vokabular, an dem ein
#    Formmerkmal greifen koennte.
#
# ⭐ Deshalb ist ein besseres MUSTER die falsche Antwort und ein FELD die richtige.
#    Dieselbe Bauform hat in v5.35.0 zweimal getragen (`art`, `status`); das hier
#    ist ihre dritte Anwendung, kein Neubau.
#
# ⚠ DAS FELD IST OPTIONAL, und das ist Absicht. Ein Pflichtfeld wuerde zum RATEN
#   zwingen — also genau die Klasse erzeugen, die es messen soll. Fehlt es, heisst
#   das `nicht-zugeordnet` und nicht "unbekannte Ursache".
URSACHEN = {
    "erreicht-gegenstand-nicht": "Muster, Bereich oder Quelle lagen daneben — das Werkzeug lief",
    "nicht-treffer-als-befund": "Eine NULL wurde als Aussage gelesen statt als kaputte Messung",
    "werkzeug-falsch-aufgerufen": "Falsche Argumente oder Signatur — es lief gar nicht",
    "falsche-bezugsgroesse": "Richtig gerechnet, falsch bezogen — Zaehleinheit oder Vergleichsgruppe",
    "sonstiges": "passt in keine der obigen",
}


def ursache_von(eintrag):
    """Die Ursache eines Befundes, oder `nicht-zugeordnet`.

    ⛔ Ein unbekannter Wert wird NICHT stillschweigend zu `sonstiges`. Er kommt
       unveraendert zurueck und faellt im Bericht als unbekannt auf — sonst
       verschwindet ein Tippfehler in einer Sammelkategorie.
    """
    u = (eintrag.get("ursache") or "").strip().lower()
    return u or "nicht-zugeordnet"

def art(eintrag):
    """zustand | ereignis | unbestimmt — Formmerkmale, kein Urteil.

    zustand     nennt ein benanntes Werkzeug als fehlerhaft -> behebbar
    ereignis    Selbstbericht ohne Werkzeugnennung -> passiert, nicht behebbar
    unbestimmt  keins von beidem ODER BEIDES

    ⛔ BEIDES -> unbestimmt, nicht zustand. "ich habe session_sampler.py falsch
       aufgerufen" ist ein Bedienfehler und kein Werkzeugdefekt; "mind_agent_bilanz
       meldet DISPATCH=0, obwohl ich vier Agenten startete" ist einer. Der
       Unterschied ist eine BEDEUTUNGSFRAGE. Sie wird ausgewiesen, nicht geraten.
    """
    t = eintrag.get("kurz", "") or ""
    w = bool(_WERKZEUG.search(t))
    s = bool(_SELBST.search(t))
    if w and not s:
        return "zustand"
    if s and not w:
        return "ereignis"
    return "unbestimmt"


def status_von(eintrag):
    """offen | behoben — behoben NUR mit Commit-Beleg.

    ⛔ `status: behoben` OHNE `commit` bleibt OFFEN. Das ist die Negativkontrolle des
       ganzen Mechanismus: ohne sie koennte ein Lauf seine eigenen Befunde
       wegschreiben, und der Zaehler waere schlechter als der heutige, der nur waechst.
    ⛔ Und ein `ereignis` kann NIE behoben sein. Was passiert ist, ist passiert — das
       steht seit v5.9.2 im Docstring von debug_aufraeumen.py und heisst dort
       Geschichtsfaelschung.
    """
    if art(eintrag) == "ereignis":
        return "offen"
    st = (eintrag.get("status") or "").strip().lower()
    commit = (eintrag.get("commit") or "").strip()
    if st == "behoben" and commit:
        return "behoben"
    return "offen"

def projekt_name(eintrag):
    """Der Projektname EINES Eintrags — die einzige Stelle, die das entscheidet.

    ⛔ known-issues #10: `BEFUNDE.md` meldete "Projekte | 16", es waren SECHS.
       Vier Aufrufstellen entschieden das vorher jede fuer sich, zwei mit
       `basename` und zwei ohne — ein Widerspruch INNERHALB einer Datei.

    ⚠ Die Backslashes werden ZUERST ersetzt. `os.path` ist auf Windows `ntpath`
      und nimmt beide Trenner; auf Posix waere es `posixpath`, und dort gaebe
      `basename("C:\\CD\\...\\Projekt")` die GANZE Zeichenkette zurueck.
      Ohne diese Zeile waere der Fehler dort zurueck, nur unsichtbarer.

    ⚠ Zwei Projekte mit demselben Ordnernamen fallen zusammen. Bewusst: der
      Bericht gruppiert nach dem, was ein Mensch als Projekt liest.
    """
    p = (eintrag.get("projekt") or "?").replace("\\", "/").rstrip("/")
    return os.path.basename(p) or p

def main():
    if len(sys.argv) < 2:
        print("Aufruf: debug_auswertung.py <debug-verzeichnis>", file=sys.stderr)
        return 2
    d = sys.argv[1]
    idx = os.path.join(d, "index.jsonl")
    if not os.path.isfile(idx):
        print("kein index.jsonl in %s" % d, file=sys.stderr)
        return 1

    eintraege, kaputt = lies(idx)
    nach_klasse = defaultdict(list)
    for e in eintraege:
        nach_klasse[e["klasse"]].append(e)

    projekte = {projekt_name(e) for e in eintraege}   # #10: normalisiert
    laeufe = {e.get("lauf", "?") for e in eintraege}

    z = []
    z.append("# Befunde aller /mind-all-Laeufe")
    z.append("")
    z.append("Erzeugt von `references/debug_auswertung.py` aus `index.jsonl`.")
    z.append("**Nicht von Hand bearbeiten** — jeder Lauf schreibt die Datei neu.")
    z.append("")
    z.append("| | |")
    z.append("|---|---|")
    z.append("| Befunde gesamt | **%d** |" % len(eintraege))
    z.append("| Laeufe | %d |" % len(laeufe))
    z.append("| Projekte | %d |" % len(projekte))
    if kaputt:
        z.append("| unlesbare Zeilen | %d |" % kaputt)
    z.append("")

    wiederholt = [(k, v) for k, v in nach_klasse.items() if len(v) >= 2]
    z.append("## Wiederholungen — hier zuerst hinsehen")
    z.append("")
    if not wiederholt:
        z.append("(keine — jede Ursachenklasse bisher genau einmal)")
    else:
        z.append("| Klasse | Anzahl | zuerst | zuletzt | Projekte |")
        z.append("|---|---|---|---|---|")
        for k, v in sorted(wiederholt, key=lambda x: -len(x[1])):
            ts = sorted(e.get("ts", "") for e in v)
            pj = sorted({projekt_name(e) for e in v})
            z.append("| **%s** | **%d×** | %s | %s | %s |"
                     % (k, len(v), ts[0][:10] or "?", ts[-1][:10] or "?",
                        ", ".join(pj)[:60]))
        z.append("")
        z.append("⛔ **Eine Klasse mit 3 oder mehr Vorkommen ist kein Einzelfall, sondern "
                 "ein Konstruktionsfehler.** Aufschreiben hat sie nachweislich nicht "
                 "verhindert — es braucht eine mechanische Sperre.")
    z.append("")

    plugin = {a: b for a, b in nach_klasse.items() if a in PLUGIN_KLASSEN}
    projekt = {a: b for a, b in nach_klasse.items() if a not in PLUGIN_KLASSEN}
    z.append("## Zustaendigkeit")
    z.append("")
    z.append("| | Befunde | Klassen |")
    z.append("|---|---|---|")
    z.append("| **Plugin** — hier ist der Mind Manager selbst zu reparieren | **%d** | %d |"
             % (sum(len(v) for v in plugin.values()), len(plugin)))
    z.append("| Projekt / Methode — gehoert in das jeweilige Projekt | %d | %d |"
             % (sum(len(v) for v in projekt.values()), len(projekt)))
    z.append("")
    # --- Punkt 14: Art und Status (NEU v5.35.0) ------------------------------
    #
    # ⛔ Bis v5.34.0 konnte ein Befund nur ENTSTEHEN, nie geschlossen werden. Der
    #    Bestand wuchs 2 -> 333 in 14 Tagen, an keinem Tag abwaerts, waehrend
    #    known-issues.md sechs Eintraege als BEHOBEN fuehrte. Zwei Buchfuehrungen,
    #    eine davon blind.
    nach_art = {"zustand-offen": [], "zustand-behoben": [],
                "ereignis": [], "unbestimmt": []}
    for e in eintraege:
        a = art(e)
        if a == "zustand":
            nach_art["zustand-behoben" if status_von(e) == "behoben"
                     else "zustand-offen"].append(e)
        else:
            nach_art[a].append(e)

    z.append("## Art und Status")
    z.append("")
    z.append("⛔ **Eingeordnet wird je EINTRAG, nie je Klasse.** Gemessen an "
             "`instrument-misst-nichts` (90 Eintraege): 22 nennen ein benanntes "
             "Werkzeug als fehlerhaft und sind behebbar, 68 nicht. Eine Trennung "
             "nach Klasse haette die 22 zu unantastbarer Geschichte erklaert.")
    z.append("")
    z.append("⛔ **Die Werkzeugnennung ist ein FORMMERKMAL — Kandidaten, keine "
             "Urteile.** Und **behoben** wird ein Befund nur mit **Commit-Beleg** "
             "(`status` + `commit`), nie automatisch. Ein Zaehler, der sich selbst "
             "leerraeumt, waere schlimmer als einer, der nur waechst.")
    z.append("")
    z.append("| | Befunde |")
    z.append("|---|---|")
    z.append("| **ZUSTAND — offen** (nennt ein Werkzeug, behebbar) | **%d** |"
             % len(nach_art["zustand-offen"]))
    z.append("| ZUSTAND — behoben, mit Commit-Beleg | %d |"
             % len(nach_art["zustand-behoben"]))
    z.append("| EREIGNIS — Historie, **nie** schliessbar | %d |"
             % len(nach_art["ereignis"]))
    z.append("| unbestimmt — **muss ein Mensch entscheiden** | %d |"
             % len(nach_art["unbestimmt"]))
    z.append("")
    z.append("⛔ **`unbestimmt` ist die groesste Gruppe, und das ist die ehrliche "
             "Antwort — kein Rest.** \"Nennt kein Werkzeug, also Bedienfehler\" waere "
             "aus einem Nicht-Treffer ein Befund gemacht: woertlich die Klasse "
             "`instrument-misst-nichts`, die hier gezaehlt wird. Wer diese Zahl "
             "kleinredet, dreht das Signal weg — *ein Rauschfilter, der nur gegen "
             "Rauschen kalibriert wird, optimiert sich auf Stille* "
             "(`.claude/rules/werkzeuge-zuerst.md`).")
    z.append("")

    for schluessel, ueberschrift in (
            ("zustand-offen", "ZUSTAND — offen: hier ist etwas zu reparieren"),
            ("zustand-behoben", "ZUSTAND — behoben (Commit-Beleg)"),
            ("ereignis", "EREIGNIS — Historie, wird nicht geschlossen")):
        v = nach_art[schluessel]
        if not v:
            continue
        z.append("### %s (%d)" % (ueberschrift, len(v)))
        z.append("")
        for e in sorted(v, key=lambda x: x.get("ts", ""), reverse=True)[:12]:
            beleg = ""
            if schluessel == "zustand-behoben":
                beleg = " · `%s`" % (e.get("commit", "")[:12])
            z.append("- `%s` [%s] %s · %s%s"
                     % (e.get("ts", "?")[:16], e.get("klasse", "?"),
                        projekt_name(e),
                        e.get("kurz", "").replace("\n", " ")[:130], beleg))
        if len(v) > 12:
            z.append("- … %d weitere" % (len(v) - 12))
        z.append("")

    # --- Ursachen-Bilanz (NEU v5.41.0) ---------------------------------------
    #
    # ⛔ Punkt 9 (08.09.2026) hat versucht, `instrument-misst-nichts` aus den
    #    eigenen Texten zu zerlegen: 70 % blieben UNBESTIMMT, weil 66 % der
    #    Eintraege unter 120 Zeichen lang sind und jeder einen anderen
    #    Mechanismus in freier Formulierung beschreibt. Ein besseres Muster war
    #    die falsche Antwort — ein FELD ist die richtige.
    nach_ursache = {}
    for e in eintraege:
        nach_ursache.setdefault(ursache_von(e), []).append(e)

    z.append("## Ursachen")
    z.append("")
    z.append("⚠ **Das Feld `ursache` ist OPTIONAL.** Ein Pflichtfeld wuerde zum "
             "RATEN zwingen — also genau die Fehlerart erzeugen, die es messen "
             "soll. `nicht-zugeordnet` ist deshalb ein gueltiger Zustand und kein "
             "Mangel.")
    z.append("")
    z.append("| Ursache | Befunde | was sie bedeutet |")
    z.append("|---|---:|---|")
    for u, v in sorted(nach_ursache.items(), key=lambda x: -len(x[1])):
        if u == "nicht-zugeordnet":
            was = "kein Feld gesetzt — **kein Mangel**"
        elif u in URSACHEN:
            was = URSACHEN[u]
        else:
            was = "⛔ **unbekannter Wert** — Tippfehler? Steht in keiner Liste"
        z.append("| `%s` | %d | %s |" % (u, len(v), was))
    z.append("")
    _zu = sum(len(v) for u, v in nach_ursache.items() if u != "nicht-zugeordnet")
    if _zu:
        z.append("⭐ **%d von %d Befunden tragen eine Ursache.** Die Frage "
                 "*welche Ursache waechst* ist damit fuer sie beantwortbar statt "
                 "geschaetzt." % (_zu, len(eintraege)))
    else:
        z.append("⚠ **Noch kein Befund traegt eine Ursache.** Das Feld ist seit "
                 "v5.41.0 da; die vorhandenen Eintraege stammen von davor und "
                 "werden NICHT nachtraeglich zugeordnet — das waere "
                 "Geschichtsfaelschung.")
    z.append("")

    z.append("## Alle Klassen")
    z.append("")
    for k, v in sorted(nach_klasse.items(), key=lambda x: -len(x[1])):
        marke = "  — **WIEDERHOLT**" if len(v) >= 2 else ""
        wem = "PLUGIN" if k in PLUGIN_KLASSEN else "Projekt"
        z.append("### [%s] %s (%d×)%s" % (wem, k, len(v), marke))
        beschreibung = KLASSEN.get(k)
        if beschreibung:
            z.append("")
            z.append("*%s*" % beschreibung)
        elif k not in KLASSEN:
            z.append("")
            z.append("⚠ unbekannte Klasse — nicht in der festen Liste von "
                     "`debug_auswertung.py`")
        z.append("")
        for e in sorted(v, key=lambda x: x.get("ts", ""), reverse=True)[:8]:
            z.append("- `%s` %s · %s"
                     % (e.get("ts", "?")[:16], projekt_name(e),
                        e.get("kurz", "").replace("\n", " ")[:150]))
        if len(v) > 8:
            z.append("- … %d weitere" % (len(v) - 8))
        z.append("")

    ziel = os.path.join(d, "BEFUNDE.md")
    # Zeilenenden der bestehenden Datei erhalten (Windows-Arbeitsbaum kann CRLF fuehren)
    ende = "\n"
    if os.path.isfile(ziel):
        roh = open(ziel, "rb").read()
        crlf = roh.count(b"\r\n")
        if crlf > roh.count(b"\n") - crlf:
            ende = "\r\n"
    with open(ziel, "wb") as f:
        f.write(ende.join(z).encode("utf-8") + ende.encode("utf-8"))

    print("BEFUNDE.md: %d Befunde, %d Klassen, %d wiederholt"
          % (len(eintraege), len(nach_klasse), len(wiederholt)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
