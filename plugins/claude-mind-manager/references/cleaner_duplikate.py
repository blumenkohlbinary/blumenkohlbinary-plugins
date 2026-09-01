#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Dieselbe Information an mehreren Orten — vier Kategorien, nicht zwei.

⛔ DER FEHLER, DEN DIE ERSTE PLANFASSUNG GEMACHT HAETTE

Sie kannte nur **Duplikat** (beide behaupten es -> eine wird Zeiger) und
**Zeiger** (eine nennt die andere -> nichts tun).

**Der reale Bestand ist ueberwiegend BEIDES GLEICHZEITIG.** Die globale
`CLAUDE.md` fasst eine Regel zusammen UND nennt ihren Pfad. Wer das binaer als
Duplikat einordnet, entfernt genau den Inhalt aus der IMMER LADENDEN Datei,
dessen 100-%-Trefferquote der ganze Zweck war.

    Kurz-Regel in rules/         laedt zu 100 %
    Volltext ueber den Pfad      4 von 4 (gemessen)
    Volltext ueber Skill-Auswahl 20-84 %

## Die vier Kategorien

    duplikat     zwei etwa gleich lange Fassungen, kein Zeiger  -> eine wird Zeiger
    zielform     kuerzere Fassung PLUS Pfad                     -> ✅ NICHTS TUN
    zeiger       nennt die andere, wiederholt fast nichts       -> ✅ nichts tun
    zahlendrift  gleicher Bezeichner, ABWEICHENDE Zahl/Status   -> melden

## ⭐ ZAHLENDRIFT ist der Fall, den Textaehnlichkeit NIE findet

Marken-Ueberlappung sieht "derselbe Begriff kommt zweimal vor". Sie kann nicht
unterscheiden, ob die zweite Stelle dasselbe oder das GEGENTEIL sagt.

**Verifiziert am 24.08.2026 im eigenen Bestand:**

    Hook-Code            MIND_NOTFALL_TOKENS wird NIRGENDS gelesen
    env-vars.md:178      "entfallen v5.9.3"                        ✅
    env-vars.md:191      zeigt 940 000 -> NOTFALL als aktiv        ⛔
    globale CLAUDE.md    fuehrt ihn als geltenden Schwellwert      ⛔

Zwei von drei Stellen falsch, eine widerspricht sich INNERHALB derselben Datei.

⛔ **Das Werkzeug entscheidet NICHT, welche Stelle recht hat.** Es legt sie
nebeneinander. Und es sagt dazu: eine dritte Quelle — der CODE — schlaegt beide
Textstellen.

## ⚠ Der Rauschfilter ist tragend, nicht kosmetisch

Gemessen ueber fuenf Ablagen: 103 von 696 Marken standen in mehr als einer.
**44 davon waren Allerweltswoerter** ("nicht", "claude", "keine") — fast die
Haelfte. Echt sind 59, also 8 %.

Eine Liste, die zur Haelfte Muell ist, wird nicht gelesen.

Aufruf:
  python cleaner_duplikate.py --bereich <projektpfad>
  python cleaner_duplikate.py --selbsttest

Rueckgabe: 0 = gelaufen · 1 = keine Ablage lesbar · 3 = Selbsttest gescheitert
"""
import os
import re
import sys
import collections

# ⛔ `newline=""` ist PFLICHT auf Windows. Ohne diesen Zusatz uebersetzt
#    TextIOWrapper jeden Zeilenumbruch in die Windows-Fassung (CR + LF).
#    Jede zeilenverankerte Zusicherung (das Dollarzeichen in grep) bricht
#    dann — und zwar STILL, denn die Ausgabe sieht voellig richtig aus.
#    Gemessen 24.08.2026 an `cleaner_duplikate.py`: zwei Prueffaelle meldeten
#    0 Treffer fuer Zeilen, die dastanden. Dieselbe Klasse wie der in der
#    globalen CLAUDE.md dokumentierte `write_text()`-Fall.
sys.stdout.reconfigure(encoding="utf-8", newline="")


def _md_rekursiv(d):
    """Alle .md unter d, REKURSIV, sortiert.

    ⛔ Bis v5.20.1 stand hier ueberall `os.listdir` — flach. Ein Unterordner
       (etwa ein `archive/`) war damit unsichtbar. Genau daran hing der
       teuerste Einzelbefund dieses Bestands: am 23.08.2026 kamen **267 von
       920** Ladevorgaengen aus einem `archive/`-Ordner, der angelegt worden
       war, UM den Bestand zu kuerzen.

    ⭐ Nicht nachgebaut: dieselbe Schleife steht seit v5.17.0 in
       cleaner_ratsche.py:90 (`geladene_dateien`).
    """
    aus = []
    if not os.path.isdir(d):
        return aus
    for wurzel, _dirs, dateien in os.walk(d):
        for f in dateien:
            if f.endswith(".md"):
                aus.append(os.path.join(wurzel, f))
    return sorted(aus)

# Marken, die eine Uebersetzung ueberleben und spezifisch genug sind.
# ⚠ Bewusst ENG. Lieber ein Duplikat uebersehen als eine Liste voller Rauschen.
_MARKE = re.compile(
    r"`([^`\n]{3,60})`"                       # Inline-Code
    r"|\b([A-Z][A-Z0-9_]{4,})\b"              # ALLCAPS_BEZEICHNER
    r"|\b(\d[\d\s.,]{2,}\s?(?:%|B|KB|MB|Zeichen|Zeilen|Tokens?|s|ms))\b")

_STOPP = {"claude", "nicht", "keine", "kein", "memory", "skill", "rules", "hook",
          "hooks", "datei", "dateien", "immer", "code", "projekt", "kohlektiv"}


def _spezifisch(m):
    """⛔ Ohne diesen Filter ist fast die Haelfte der Meldungen Rauschen."""
    m = m.strip()
    if len(m) < 4 or m.lower() in _STOPP:
        return False
    return bool(re.search(r"[/\\.\d_-]", m)) or m.isupper()


def marken(text):
    out = set()
    for t in _MARKE.findall(text):
        for g in t:
            if g and _spezifisch(g):
                out.add(g.strip())
    return out


def _inhalt(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def _zeilen_mit(text, marke):
    return [z.strip() for z in text.split("\n") if marke in z and z.strip()]


# ⛔ Die erste Fassung war VIEL zu locker und hat sich selbst begraben.
#
#    Sie nahm als Statuswoerter unter anderem `aus` und `an` — im Deutschen
#    Allerweltswoerter — und zaehlte JEDE Zahl als Wert, auch Datumsangaben und
#    Versionsnummern. Gemessen am echten Bestand: **12 Treffer, davon 11
#    Fehlalarme**. `/mind-all` stand in zwei Dateien mit verschiedenen DATEN
#    daneben und galt als Drift.
#
#    Der eine echte Treffer (`MIND_NOTFALL_TOKENS`: 940 000 gegen "entfallen")
#    war da, aber im Rauschen nicht auffindbar. Genau der Zustand, vor dem der
#    Rauschfilter-Abschnitt oben warnt.
#
# ⭐ Scharfe Fassung: Drift heisst, eine Stelle erklaert etwas fuer TOT, waehrend
#    die andere es als LEBEND oder mit einem konkreten Wert fuehrt.
_TOT = re.compile(r"\b(entfallen|gestrichen|veraltet|abgeschaltet|ersetzt|"
                  r"entfernt|aufgehoben|wird nicht mehr)\b", re.IGNORECASE)
_LEBT = re.compile(r"\b(aktiv|scharf|gilt|eingeschaltet|wieder an)\b", re.IGNORECASE)

# Werte, KEINE Datumsangaben und KEINE Versionsnummern.
_DATUM = re.compile(r"\b\d{1,2}\.\d{1,2}\.\d{4}\b|\b20\d\d\b")
_VERSION = re.compile(r"\bv?\d+\.\d+(\.\d+)?\b")
_WERT = re.compile(r"\b\d[\d\s.]{2,}\b")


# ==========================================================================
# v5.20.0 — die zweite Achse: ERLEDIGT gegen OFFEN
# ==========================================================================
# _TOT/_LEBT deckt "entfallen gegen aktiv" ab. Die SIEBEN Halb-Korrekturen,
# die der /mind-all-Lauf im Projekt `Creator` am 24.08.2026 fand, lagen aber
# auf einer ANDEREN Achse -- und die gab es hier nicht:
#
#   stimme-qwen-kette.md:14   "Echo-Fix eingebaut"
#   stimme-qwen-kette.md:124  "⛔ OFFEN ... NICHT eingebaut"
#   110 Zeilen auseinander, beide gleich glaubwuerdig.
#
# `doku-veraltet` ist mit 25 Vorkommen die haeufigste Projekt-Klasse im
# Debug-Ordner ueberhaupt. Der Lauf nannte auch das Gegenmittel:
#
#   "Sechs von sieben Funden waeren mit einem grep auf den KERNBEGRIFF --
#    nicht auf die Ueberschrift -- vor dem Anhaengen aufgefallen."
#
# ⛔ Das ist eine ERGAENZUNG des vorhandenen Werkzeugs, kein Zweitbau.
#    Marken-Erkennung, Zeilensuche und Rauschfilter waren schon da; gefehlt
#    hat nur die Achse. `werkzeuge-zuerst.md` verlangt genau das: den Fall
#    benennen, an dem das Original scheitert, ihn als Prueffall hinzufuegen,
#    das Original erweitern.
_FERTIG_WORT = (r"eingebaut|behoben|umgesetzt|erledigt|gefixt|geloest|"
                r"abgeschlossen|nachgetragen|repariert")
_ERLEDIGT = re.compile(r"\b(%s)\b|✅" % _FERTIG_WORT, re.IGNORECASE)
_OFFEN = re.compile(
    r"\b(noch nicht|steht\s+(noch\s+)?aus|ausstehend|ungeloest|fehlt noch)\b"
    r"|\bnicht\s+(mehr\s+)?(%s)\b"
    r"|\bTODO\b|\bOFFEN\b|❌" % _FERTIG_WORT, re.IGNORECASE)

# ⛔ DIE NEGATION MUSS VOR DER ERKENNUNG WEG — sonst faellt der Hauptfall durch.
#
#    "NOCH NICHT eingebaut" ENTHAELT "eingebaut". Ohne dieses Ausschneiden
#    zaehlt die Zeile als erledigt UND offen, und die Regel "eine Zeile mit
#    beidem ist ein aufloesender Satz" wirft sie hinaus. Gemessen beim ersten
#    Lauf des Selbsttests: **alle Gegenkontrollen gruen, alle Positivfaelle
#    rot** -- ein Detektor, der nichts findet, besteht jede Negativprobe.
#    Und "NICHT eingebaut" ist woertlich die Formulierung des Creator-Falls.
_NEG_FERTIG = re.compile(r"\b(?:noch\s+)?nicht\s+(?:mehr\s+)?(?:%s)\b" % _FERTIG_WORT,
                         re.IGNORECASE)


def _sagt_erledigt(zeile):
    """ERLEDIGT, nachdem die Negationen ausgeschnitten sind."""
    return bool(_ERLEDIGT.search(_NEG_FERTIG.sub(" ", zeile)))


# ⛔ DIE NAEHE ENTSCHEIDET, OB DAS STATUSWORT UEBERHAUPT ZU DIESER MARKE GEHOERT.
#
#    Erste Messung am echten Bestand (28 Dateien): **2 Befunde, beide falsch** —
#    dieselbe Klasse wie die erste Zahlendrift-Fassung, nur in kleinerem Massstab.
#
#      known-issues.md:136  "mind-memory ✅ — ABER **mind-files ❌**: ..."
#                           Das Haekchen gehoert zu mind-memory, das Kreuz zu
#                           mind-files. Ohne ❌ als Offen-Signal las das Werkzeug
#                           die Zeile als "mind-files erledigt".
#      ladeverhalten.md:30  "**Behoben** durch Verschieben ... (ausserhalb von `rules/`)"
#                           "Behoben" steht 70 Zeichen vor der Marke und meint
#                           einen voellig anderen Sachverhalt.
#
#    Eine Zeile kann mehrere Subjekte tragen. Ein Statuswort irgendwo darin sagt
#    nichts darueber, WELCHES gemeint ist.
_NAH = 40

# ⛔ EINE MARKE, DIE EINE DATEI SAETTIGT, IST EIN THEMA — KEIN ANSPRUCH.
#
#    Zweite Messung (79 Dateien): **1 Befund, wieder falsch.**
#    `known-issues.md` nannte `mind-files` in Zeile 479 mit ✅ (ein geloestes
#    Problem) und in Zeile 217 mit TODO (ein anderes Problem). Zwei
#    Listeneintraege ueber verschiedene Sachen, beide nennen den Skill.
#
#    Die Verteilung in derselben Datei ist eindeutig:
#        199 von 280 Marken stehen in GENAU EINER Zeile
#         49                              in zwei
#         `mind-files`                    in 22   <- Hoechstwert
#
#    Ueber dieser Schwelle beschreibt die Marke, WOVON die Datei handelt.
#    Ein Statuswort in ihrer Naehe sagt dann nichts ueber sie aus.
#    ⚠ 8 ist bewusst grosszuegig: in der Messdatei ueberschreiten nur 7 von
#      280 Marken die Grenze. Der echte Creator-Fall stand in ZWEI Zeilen.
_MAX_ZEILEN = 8


# ⛔ EIN STATUSZEICHEN AM ZEILENANFANG REGIERT DIE GANZE ZEILE.
#
#    ⚠ DIESE AUSNAHME IST NICHT KOSMETIK — ohne sie faellt der einzige echte
#      Fall durch, an dem sich das Werkzeug ueberhaupt pruefen laesst:
#
#        stimme.md:93  "⛔ **NOCH NICHT IM CODE.** Der Schnitt gehoert in
#                       `qwen_vertonen.py:rand_weg()` als fester Vorabschnitt"
#
#      Das Signal steht bei Zeichen 4, die Marke bei Zeichen 47 — Abstand 43,
#      und _NAH war 40. **Um DREI ZEICHEN verfehlt.** Aufgefallen erst in der
#      Positivkontrolle gegen den bekannt kaputten Creator-Bestand; die
#      Selbsttests und die Rauschmessung waren beide gruen.
#
#    ⭐ Die Lehre, und sie ist groesser als dieser Fall: ich hatte _NAH und
#      _MAX_ZEILEN gegen EINEN Fehlalarm gedreht und dabei das Signal
#      erschlagen. Ein Rauschfilter, der nur gegen Rauschen kalibriert wird,
#      optimiert sich auf Stille. Deshalb steht jede dieser Zahlen jetzt
#      zwischen einer Positiv- UND einer Negativkontrolle.
_KOPF = 32


def _naehe(zeile, marke, muster, max_abstand=_NAH):
    """Steht ein Treffer des Musters nahe genug an der Marke?

    Nahe heisst: innerhalb von `max_abstand` Zeichen — ODER im Kopf der Zeile.
    So sind Ueberschriften und vorangestellte Merker (`## ⛔ OFFEN: ...`)
    erfasst, die sich auf den ganzen Absatz beziehen und nicht auf ein
    benachbartes Wort.
    """
    stellen = [m.start() for m in re.finditer(re.escape(marke), zeile)]
    if not stellen:
        return False
    return any(t.start() <= _KOPF or any(abs(t.start() - p) <= max_abstand
                                         for p in stellen)
               for t in muster.finditer(zeile))

# ⭐ DER WICHTIGSTE FILTER — und er entscheidet ueber Nutzen oder Rauschen.
#
#    Eine Zeile, die den Widerspruch SELBST AUFLOEST, ist die RICHTIGE Form.
#    Genau die darf nie gemeldet werden. Dieses Repo benutzt sie staendig:
#
#        ✅ ~~alte Aussage~~ — BEHOBEN in v5.2.2
#        Bis v5.6.0 stand hier ...
#
#    Wer das meldet, bestraft das gute Muster und belohnt das schlechte.
#    ⛔ Deshalb entwertet EINE aufloesende Fundstelle den ganzen Befund --
#       nicht nur ihre eigene Zeile.
_AUFLOESEND = re.compile(
    r"~~"                                       # durchgestrichen = zurueckgenommen
    r"|\b(bis|seit|ab)\s+v?\d"                  # "bis v5.6.0", "seit 21.08."
    r"|\b(vorher|frueher|damals|inzwischen|stand hier|galt)\b", re.IGNORECASE)


# ---------------------------------------------------------------------------
# L5 — WIEDERHOLUNG INNERHALB EINER DATEI
#
# ⛔ Warum das keine Duplikat-Pruefung findet: `ablagen()` vergleicht Ablagen
#    GEGENEINANDER. Eine Datei, die dieselbe Sache viermal sagt, ist in jeder
#    dieser Pruefungen unauffaellig — sie ist ja nur EINE Ablage.
#
#    Gemessen an `.claude/rules/hooks.md`: die Kaskade 810k/850k/940k steht in
#    den Abschnitten v5.7.0, v5.7.5, v5.7.6 und v5.7.7. Vier Mal.
#
# ⚠ DER BEFUND HEISST SCHNITT, NICHT DEDUPLIZIERUNG.
#    Eine Datei mit Versionsabschnitten SOLL dieselbe Sache mehrfach nennen —
#    jede Nennung gehoert zu ihrer Version. Was fehlt, ist die Trennung
#    zwischen "gilt heute" und "galt damals". Wer hier dedupliziert, loescht
#    Historie; wer schneidet, macht sie auffindbar.

# Ein Absatz unter dieser Markenzahl ist zu duenn fuer ein Urteil.
_WDH_MIN_MARKEN = 3
# So viele Marken muessen zwei Absaetze TEILEN, damit sie als dieselbe Sache gelten.
_WDH_MIN_GETEILT = 3
# ⛔ Und der Anteil muss stimmen. NUR die Zahl der geteilten Marken zu fordern
#    meldet jeden langen Absatz gegen jeden anderen langen Absatz — dieselben
#    drei Umgebungsvariablen kommen in einer Regeldatei staendig vor.
#    Der Anteil ist das, was "gleiche Zahlen, andere Aussage" ausschliesst.
_WDH_ANTEIL = 0.55
# Erst ab drei Vorkommen ist es ein Muster. Zwei sind in einer versionierten
# Datei der Normalfall: eine Aussage und ihre spaetere Korrektur.
_WDH_MIN_GRUPPE = 3


def _absaetze(text):
    """[(startzeile, text)] — Bloecke, getrennt durch Leerzeilen.

    ⚠ Ueberschriften bleiben bei ihrem Absatz. Ein "## v5.7.5" allein traegt
      keine Marken und faellt ohnehin unter _WDH_MIN_MARKEN heraus.
    """
    aus = []
    zeilen = text.split("\n")
    puffer = []
    start = 1
    for i, z in enumerate(zeilen, 1):
        if z.strip():
            if not puffer:
                start = i
            puffer.append(z)
        elif puffer:
            aus.append((start, "\n".join(puffer)))
            puffer = []
    if puffer:
        aus.append((start, "\n".join(puffer)))
    return aus


def wiederholung_in_datei(pfad, text=None):
    """Sagt EINE Datei dieselbe Sache mehr als zweimal?

    Gibt eine Liste von dicts zurueck:
      zeilen     Startzeilen der beteiligten Absaetze
      geteilt    die Marken, die alle teilen (sortiert)
      anzahl     wie viele Absaetze
      nimmt_zurueck  True, wenn mindestens einer der Absaetze eine frueherere
                     Aussage ausdruecklich zurueckehmt (~~, "bis v5.6.0",
                     "stand hier"). ⛔ Das UNTERDRUECKT den Befund NICHT — es
                     ist genau das Muster, das einen Schnitt verdient.

    ⛔ Ein Befund JE GRUPPE, nicht je Paar. Vier Absaetze ergeben sonst sechs
       Meldungen ueber eine einzige Sache.
    """
    if text is None:
        text = _inhalt(pfad)
    bloecke = [(zl, t, marken(t)) for zl, t in _absaetze(text)]
    bloecke = [b for b in bloecke if len(b[2]) >= _WDH_MIN_MARKEN]

    # ⛔ NICHT transitiv gruppieren. Der erste Anlauf tat das und meldete NULL
    #    Befunde ueber 34 Dateien: transitiv verkettete Absaetze wachsen zu
    #    einer grossen Gruppe zusammen, deren gemeinsamer Kern dabei unter die
    #    Schwelle faellt. Gemessen an hooks.md: sechs Absaetze in einer Kette,
    #    gemeinsamer Kern zu klein, Ergebnis still.
    #
    #    Stattdessen: aus jedem Paar den KERN nehmen und die Gruppe als die
    #    Menge ALLER Absaetze bilden, die diesen Kern vollstaendig tragen.
    #    Dann sagt jedes Mitglied nachweislich dieselbe Sache.
    kerne = {}
    for i in range(len(bloecke)):
        for j in range(i + 1, len(bloecke)):
            a, b = bloecke[i][2], bloecke[j][2]
            geteilt = a & b
            if len(geteilt) < _WDH_MIN_GETEILT:
                continue
            # Anteil an der KLEINEREN Menge — sonst schlaegt jeder kurze Absatz
            # gegen einen langen an, der ihn zufaellig enthaelt. Das ist der
            # Filter, der "gleiche Zahlen, andere Aussage" ausschliesst.
            if len(geteilt) / float(min(len(a), len(b))) < _WDH_ANTEIL:
                continue
            kerne[frozenset(geteilt)] = None

    roh = []
    for kern in kerne:
        mit = [k for k in range(len(bloecke)) if kern <= bloecke[k][2]]
        if len(mit) < _WDH_MIN_GRUPPE:
            continue
        roh.append((kern, tuple(mit)))

    # ⛔ Ein Kern, der in einem groesseren Kern MIT DERSELBEN Absatzmenge steckt,
    #    ist dieselbe Meldung noch einmal. Nur den groessten behalten — sonst
    #    ergaeben vier Absaetze mit 5 gemeinsamen Marken bis zu zehn Befunde.
    roh.sort(key=lambda x: -len(x[0]))
    behalten = []
    for kern, mit in roh:
        if any(kern < k2 and mit == m2 for k2, m2 in behalten):
            continue
        behalten.append((kern, mit))

    aus = []
    for kern, mit in behalten:
        aus.append({
            "datei": pfad,
            "zeilen": sorted(bloecke[k][0] for k in mit),
            "geteilt": sorted(kern),
            "anzahl": len(mit),
            "nimmt_zurueck": any(_AUFLOESEND.search(bloecke[k][1]) for k in mit),
        })
    return sorted(aus, key=lambda x: (-x["anzahl"], -len(x["geteilt"])))


def widerspruch_in_datei(pfad, text=None, min_abstand=10):
    """Widerspricht sich EINE Datei selbst?

    Gibt eine Liste von dicts zurueck: marke, zeile_erledigt, zeile_offen,
    text_erledigt, text_offen, abstand.

    ⛔ Gemeldet wird nur, wenn ALLE FUENF Bedingungen halten:
       1. dieselbe Marke steht an mindestens zwei Stellen
       2. eine sagt ERLEDIGT, eine sagt OFFEN -- und keine von beiden sagt beides
          (eine Zeile mit beidem ist fast immer ein aufloesender Satz);
          das Statuswort muss NAHE an der Marke stehen, s. _naehe()
       3. KEINE Fundstelle der Marke loest den Widerspruch auf
       4. selbst das NAECHSTE Paar liegt >= min_abstand Zeilen auseinander
       5. die Marke steht in hoechstens _MAX_ZEILEN Zeilen -- darueber ist sie
          das THEMA der Datei und kein einzelner Anspruch

    ⚠ Bedingung 4 ist bewusst konservativ: gemessen wird der KLEINSTE Abstand,
      nicht der groesste. Zwei Saetze direkt untereinander sind eine Erzaehlung
      ("war offen, ist jetzt gebaut"), keine zwei konkurrierenden Wahrheiten.
      Der Creator-Fall lag 110 Zeilen auseinander.
    """
    if text is None:
        text = _inhalt(pfad)
    zeilen = text.split("\n")
    befunde = []
    for marke in marken(text):
        treffer = [(i, z.strip()) for i, z in enumerate(zeilen, 1)
                   if marke in z and z.strip()]
        if len(treffer) < 2:
            continue
        if len(treffer) > _MAX_ZEILEN:
            continue                                    # Bedingung 5 (Thema)
        if any(_AUFLOESEND.search(z) for _, z in treffer):
            continue                                    # Bedingung 3
        # ⛔ NAHE an der Marke, nicht irgendwo in der Zeile — siehe _naehe().
        erl = [(i, z) for i, z in treffer
               if _naehe(_NEG_FERTIG.sub(" ", z), marke, _ERLEDIGT)
               and not _naehe(z, marke, _OFFEN)]
        off = [(i, z) for i, z in treffer
               if _naehe(z, marke, _OFFEN)
               and not _naehe(_NEG_FERTIG.sub(" ", z), marke, _ERLEDIGT)]
        if not (erl and off):                           # Bedingung 2
            continue
        a, b = min(((x, y) for x in erl for y in off),
                   key=lambda p: abs(p[0][0] - p[1][0]))
        abstand = abs(a[0] - b[0])
        if abstand < min_abstand:                       # Bedingung 4
            continue
        befunde.append({"marke": marke,
                        "zeile_erledigt": a[0], "text_erledigt": a[1][:110],
                        "zeile_offen": b[0], "text_offen": b[1][:110],
                        "abstand": abstand})
    # Teilstring-Artefakte entfernen: `vertonen.py` ist keine eigene Marke,
    # sondern ein Stueck von `qwen_vertonen.py`. Bei gleichem Zeilenpaar
    # gewinnt die laengste Marke.
    beste = {}
    for b in befunde:
        s = (b["zeile_erledigt"], b["zeile_offen"])
        if s not in beste or len(b["marke"]) > len(beste[s]["marke"]):
            beste[s] = b
    return sorted(beste.values(), key=lambda x: -x["abstand"])


def einordnen(marke, a_pfad, a_text, b_pfad, b_text):
    """Fuenf Kategorien. Gibt (kategorie, begruendung) zurueck."""
    a_zeilen = _zeilen_mit(a_text, marke)
    b_zeilen = _zeilen_mit(b_text, marke)

    # --- Zahlendrift zuerst: er ist der einzige, der GEFAHR bedeutet ---------
    def merkmale(zeilen):
        tot = lebt = False
        werte = set()
        for x in zeilen:
            # ⛔ _naehe, NICHT .search — sonst faerbt ein Statuswort irgendwo in
            #    der Zeile die ganze Seite ein. Gemessen 25.08.2026 am einzigen
            #    zahlendrift-Befund des L4-Laufs: in env-vars.md:17 stand
            #    "entfernt" 76 Zeichen von `.sync-protect.json` entfernt und
            #    meinte den ZWECK des Schutzes ("damit der Aufraeumer keine
            #    frisch installierte Version entfernt"), nicht sein Ende.
            #    Dieselbe Klasse, die Zeile 205-219 fuer die Status-Achse schon
            #    beschreibt — der zahlendrift-Pfad war der einzige ohne den Filter.
            tot = tot or _naehe(x, marke, _TOT)
            lebt = lebt or _naehe(x, marke, _LEBT)
            # Datum und Version herausschneiden, BEVOR Werte gelesen werden.
            rest = _VERSION.sub(" ", _DATUM.sub(" ", x))
            werte.update(w.strip() for w in _WERT.findall(rest) if len(w.strip()) >= 3)
        return tot, lebt, werte
    a_tot, a_lebt, a_w = merkmale(a_zeilen)
    b_tot, b_lebt, b_w = merkmale(b_zeilen)

    # ⛔ NUR wenn eine Seite etwas fuer TOT erklaert und die andere es als
    #    lebend oder mit konkretem Wert fuehrt. Alles Weichere erzeugt
    #    Fehlalarme, die den einen echten Treffer begraben.
    # ⛔ v5.31.0: WENN BEIDE TOT SAGEN, IST ES KEIN DRIFT.
    #    Der Fehler verriet sich in der eigenen Ausgabe: der einzige
    #    zahlendrift-Treffer dieses Projekts lautete woertlich
    #    'tot gegen tot' — ein Widerspruch, der keiner sein kann.
    #    Gemessen 01.09.2026 an `MIND_NOTFALL_TOKENS`: beide Stellen
    #    fuehren es als entfallen, beide lebt=False. Gezogen hat allein
    #    `or b_w`, weil env-vars.md die Zahl 940000 NENNT — in dem Satz,
    #    der sie fuer tot erklaert ('940000 — seit v5.9.3 von keinem Hook
    #    gelesen'). Eine tote Stelle darf ihren eigenen Altwert nennen.
    #    ⚠ Das SCHAERFT die Bedingung, es lockert sie nicht: ein echter
    #      Drift (tot gegen 'ist aktiv') hat b_tot=False und laeuft
    #      unveraendert durch. Pruefsammlung 3) belegt genau das, 3c) den
    #      neuen Fall.
    if not (a_tot and b_tot) and \
       ((a_tot and (b_lebt or b_w)) or (b_tot and (a_lebt or a_w))):
        links = "tot" if a_tot else (sorted(a_w)[:2] or "lebend")
        rechts = "tot" if b_tot else (sorted(b_w)[:2] or "lebend")
        return "zahlendrift", ("eine Stelle fuehrt es als entfallen, die andere "
                               "als geltend: %s gegen %s" % (links, rechts))

    # --- v5.20.0: dieselbe Achse ueber ZWEI Dateien -------------------------
    #     Der Creator-Lauf fand genau das: `video-chatterbox-stand.md` fuehrte
    #     Lautheit, Kompressor, Komfortrauschen und Tempo als offen -- alle vier
    #     seit dem 22.08. entschieden, an anderer Stelle nachlesbar.
    #     ⚠ Steht NACH zahlendrift: "entfallen gegen aktiv" ist der schwerere
    #       Befund und darf nicht von diesem hier verdeckt werden.
    def status(zeilen):
        return (any(_sagt_erledigt(x) and not _OFFEN.search(x) for x in zeilen),
                any(_OFFEN.search(x) and not _sagt_erledigt(x) for x in zeilen),
                any(_AUFLOESEND.search(x) for x in zeilen))
    a_erl, a_off, a_aufl = status(a_zeilen)
    b_erl, b_off, b_aufl = status(b_zeilen)
    if not (a_aufl or b_aufl) and ((a_erl and b_off) or (b_erl and a_off)):
        wo = a_pfad if a_off else b_pfad
        return "statusdrift", ("eine Stelle fuehrt es als erledigt, die andere "
                               "als offen — offen steht in %s"
                               % os.path.basename(wo))

    # --- Zeigt eine Stelle auf die andere? ----------------------------------
    def zeigt_auf(text, ziel):
        n = os.path.basename(ziel)
        stamm = os.path.basename(os.path.dirname(ziel))
        return n in text or ("%s/%s" % (stamm, n)) in text.replace("\\", "/")
    a_zeigt = zeigt_auf(a_text, b_pfad)
    b_zeigt = zeigt_auf(b_text, a_pfad)

    la, lb = len(a_zeilen), len(b_zeilen)
    if not (a_zeigt or b_zeigt):
        return "duplikat", "beide behaupten es, keine nennt die andere"

    # ⭐ DIE KATEGORIE, DIE GEFEHLT HAT.
    #    Kuerzere Fassung PLUS Zeiger = Zielform. Nicht anfassen.
    kurz, lang = (la, lb) if a_zeigt else (lb, la)
    if lang and kurz < 0.6 * lang:
        return "zielform", ("kuerzere Fassung (%d gegen %d Zeilen) nennt den Pfad "
                            "— das ist die Zielform" % (kurz, lang))
    if kurz <= 1:
        return "zeiger", "nennt die andere, wiederholt fast nichts"
    return "duplikat", ("etwa gleich lang (%d gegen %d Zeilen), trotz Zeiger"
                        % (la, lb))



def _slug(win_pfad):
    """Spiegelbild von hash_project_dir() aus hooks/lib.sh (Regel ab v5.7.0).

    ⛔ NICHT nachgebaut: dieselbe Formel steht in references/slug_regression.py
       und ist dort gegen 12 Vektoren geprueft — einschliesslich des `&`-Falls,
       der Memory einst in den Fallback schickte.
    """
    return re.sub(r"^-*", "", re.sub(r"[^A-Za-z0-9]", "-", win_pfad))


def _memory_dir(heim, projekt=None):
    """Das Memory-Verzeichnis — oder ein leerer Pfad.

    ⛔ KEIN FALLBACK. `get_memory_dir` in lib.sh faellt bei Slug-Mismatch auf
       das NEUESTE FREMDE Projekt zurueck. `mind_snapshot` sichert seit v5.2.1
       dagegen ab, indem es den Pfad nur nimmt, wenn GENAU DIESES Verzeichnis
       existiert — derselbe Schutz gilt hier. Lieber eine Ablage weniger als
       Marken aus einem fremden Projekt.
    """
    if projekt is None:
        return ""
    d = os.path.join(heim, ".claude", "projects", _slug(os.path.abspath(projekt)),
                     "memory")
    return d if os.path.isdir(d) else ""


def ablage_wurzeln(projekt, bereich="alles"):
    """{name: verzeichnis} — die VERZEICHNISSE der Ablagen, nicht ihre Dateien.

    ⭐ EINE Quelle fuer beides. Bis v5.20.2 stand dieselbe Liste ein zweites
       Mal hartcodiert in `cleaner_ratsche.verlauf_schreiben()` — ein
       Typ-2-Duplikat, das bei einer Erweiterung von 4 auf 9 still
       auseinandergedriftet waere (gefunden im Plan-Review 25.08.2026).

    ⚠ NICHT aus `ablagen()` ableitbar: dort steht nur die Dateiliste, und
      `dirname(erste_datei)` liefert bei rekursiver Suche einen UNTERordner —
      und bei leerer Ablage gar nichts. Genau daran ist der erste Anlauf
      gescheitert (Selbsttest "Verlauf hat Ablagen" wurde rot).
    """
    H = os.path.expanduser("~")
    w = {}
    if bereich in ("alles", "global"):
        w["g:rules"] = os.path.join(H, ".claude", "rules")
        w["g:skills"] = os.path.join(H, ".claude", "skills")
        # kein "g:memory" — siehe ablagen()
    if bereich in ("alles", "projekt"):
        w["p:rules"] = os.path.join(projekt, ".claude", "rules")
        w["p:skills"] = os.path.join(projekt, ".claude", "skills")
        w["p:memory"] = _memory_dir(H, projekt)
    return {k: v for k, v in w.items() if v}


def _ahnen(projekt):
    """CLAUDE.md und CLAUDE.local.md in den ELTERNverzeichnissen.

    Sie laden laut Doku mit ("alle CLAUDE.md/CLAUDE.local.md entlang der
    Verzeichniskette aufwaerts"), wurden aber von keinem Werkzeug je gesehen.
    ⚠ Nur AUFWAERTS und nur bis zur Laufwerkswurzel — nie seitwaerts.
    """
    aus = []
    d = os.path.abspath(projekt)
    while True:
        eltern = os.path.dirname(d)
        if not eltern or eltern == d:
            break
        d = eltern
        for n in ("CLAUDE.md", "CLAUDE.local.md", ".claude.local.md"):
            p = os.path.join(d, n)
            if os.path.isfile(p):
                aus.append(p)
    return aus

def ablagen(projekt, bereich="alles"):
    """Welche Ablagen verglichen werden.

    ⛔ `bereich` ist nicht Bequemlichkeit, sondern eine Messvoraussetzung.
       Ohne ihn liest JEDER Lauf auch den globalen Bestand mit. Gemessen
       24.08.2026: ein Prueffall mit zwei kuenstlichen Dateien bekam dadurch
       199 Marken und 2 Zahlendrift-Treffer aus dem ECHTEN Bestand des
       Rechners — die Zusicherung mass etwas anderes als das, was sie
       aufgebaut hatte.
    """
    H = os.path.expanduser("~")

    def md(d):
        return _md_rekursiv(d)
    a = {}
    if bereich in ("alles", "global"):
        a["g:CLAUDE.md"] = [os.path.join(H, ".claude", "CLAUDE.md")]
        a["g:rules"] = md(os.path.join(H, ".claude", "rules"))
        # v5.21.0 — die drei Ablagen, die dein AUDIT-Prompt woertlich nennt
        # ("CLAUDE.md, Rules-Dateien, Skills, Hooks und Memory") und die bis
        # v5.20.2 NIE verglichen wurden.
        a["g:skills"] = md(os.path.join(H, ".claude", "skills"))
        # ⛔ KEIN "g:memory": ein globales Memory-Verzeichnis GIBT ES NICHT.
        #    `get_memory_dir` (lib.sh:372) bildet den Pfad IMMER aus dem
        #    Projekt-Slug. Die Ablage war in der ersten L4-Fassung dabei und
        #    haette in keinem Lauf je eine Datei enthalten — gefunden von
        #    tests/test_ablagen.sh, weil es auf die Dict-SCHLUESSEL zusichert.
    if bereich in ("alles", "projekt"):
        a["p:CLAUDE.md"] = [os.path.join(projekt, "CLAUDE.md")]
        a["p:rules"] = md(os.path.join(projekt, ".claude", "rules"))
        a["p:memory"] = md(_memory_dir(H, projekt))
        a["p:skills"] = md(os.path.join(projekt, ".claude", "skills"))
        # ⭐ AHNEN: CLAUDE.md/CLAUDE.local.md in den Elternverzeichnissen laden
        #    laut Doku MIT. Gemessen liegt hier eine:
        #    `Plugin - Entwicklung/.claude.local.md`, 2 445 B — von keinem
        #    Werkzeug je gesehen.
        a["ahnen"] = _ahnen(projekt)
    return {k: [p for p in v if os.path.isfile(p)] for k, v in a.items()}


def lauf(projekt, bereich="alles"):
    abl = ablagen(projekt, bereich)
    if not any(abl.values()):
        print("⛔ Keine Ablage lesbar unter %s" % projekt)
        print("   Das ist NIE ein gutes Ergebnis — eher ein falscher Pfad.")
        return 1

    text = {}
    wo = collections.defaultdict(set)
    for name, pfade in abl.items():
        for p in pfade:
            t = _inhalt(p)
            text[p] = t
            for m in marken(t):
                wo[m].add((name, p))

    print("=" * 86)
    print("  Duplikat-Pruefung ueber %d Ablagen" % len(abl))
    print("=" * 86)
    for name, pfade in abl.items():
        print("  %-14s %2d Datei(en)" % (name, len(pfade)))

    mehrfach = {m: s for m, s in wo.items() if len({n for n, _ in s}) >= 2}
    print("\n  %d Marken gesamt · %d in mehr als einer Ablage" % (len(wo), len(mehrfach)))

    treffer = collections.Counter()
    zeilen = []
    for m, stellen in sorted(mehrfach.items()):
        st = sorted(stellen)
        for i in range(len(st)):
            for j in range(i + 1, len(st)):
                (na, pa), (nb, pb) = st[i], st[j]
                if na == nb:
                    continue
                kat, grund = einordnen(m, pa, text[pa], pb, text[pb])
                treffer[kat] += 1
                zeilen.append((kat, m, na, nb, grund, pa, pb))

    print()
    for kat in ("zahlendrift", "duplikat", "zielform", "zeiger"):
        n = treffer[kat]
        marke = "⛔" if kat == "zahlendrift" else ("⚠" if kat == "duplikat" else "✅")
        print("  %s %-12s %3d" % (marke, kat, n))

    # ⛔ Zahlendrift zuerst und im Volltext — es ist die einzige Kategorie,
    #    bei der eine Stelle FALSCH ist statt nur redundant.
    drift = [z for z in zeilen if z[0] == "zahlendrift"]
    if drift:
        print("\n  " + "=" * 82)
        print("  ⛔ ZAHLENDRIFT — hier ist eine Stelle FALSCH, nicht nur doppelt")
        print("  " + "=" * 82)
        for _, m, na, nb, grund, pa, pb in drift[:12]:
            print("\n  %s" % m)
            print("     %-14s %s" % (na, os.path.basename(pa)))
            print("     %-14s %s" % (nb, os.path.basename(pb)))
            print("     %s" % grund)
        print("\n  ⛔ Welche Stelle recht hat, entscheidet dieses Werkzeug NICHT.")
        print("     ⭐ Und eine dritte Quelle schlaegt beide: der CODE.")

    dup = [z for z in zeilen if z[0] == "duplikat"]
    if dup:
        print("\n  ⚠ DUPLIKAT — eine Stelle koennte zum Zeiger werden")
        for _, m, na, nb, grund, _, _ in dup[:10]:
            print("     %-30s %s + %s  (%s)" % (m[:30], na, nb, grund))

    ziel = [z for z in zeilen if z[0] == "zielform"]
    if ziel:
        print("\n  ✅ ZIELFORM — bewusst so, NICHT anfassen (%d)" % len(ziel))
        for _, m, na, nb, grund, _, _ in ziel[:6]:
            print("     %-30s %s + %s" % (m[:30], na, nb))

    print()
    print("  ⛔ Vor jeder Aenderung das Urteilsbuch fragen:")
    print("     cleaner_urteile.py <projekt> --orte <a> <b>")
    print("  ⚠ Gemessen wird ERWAEHNUNG derselben Marke, nicht Bedeutungsgleichheit.")
    print("     Zwei Stellen, die dasselbe ANDERS formulieren, findet das hier NICHT.")
    return 0


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
        print("    %-4s %-46s ist=%-12s soll=%s"
              % ("OK" if ok else "FEHL", name, ist, soll))

    def schreib(n, t):
        p = os.path.join(d, n)
        open(p, "w", encoding="utf-8", newline="\n").write(t)
        return p

    print("=" * 78)
    print("  Selbsttest — vier Kategorien muessen UNTERSCHIEDEN werden")
    print("=" * 78)

    # 1) Zielform: kurze Fassung + Zeiger auf die lange
    lang = schreib("lang.md", "# L\n\n" + "\n\n".join(
        "Zeile %d ueber `MIND_SYNC_AT_TOKENS`." % i for i in range(10)))
    kurz = schreib("kurz.md", "# K\n\n`MIND_SYNC_AT_TOKENS` steuert die Mahnung.\n"
                              "Volltext: `lang.md`\n")
    k, _ = einordnen("MIND_SYNC_AT_TOKENS", kurz, _inhalt(kurz), lang, _inhalt(lang))
    pruef("kurz + Zeiger -> zielform", k, "zielform")

    # 2) Duplikat: zwei etwa gleich lange, keiner zeigt
    d1 = schreib("d1.md", "# A\n\n" + "\n\n".join(
        "Etwas ueber `MIND_BACKUP_KEEP_COUNT` Nummer %d." % i for i in range(6)))
    d2 = schreib("d2.md", "# B\n\n" + "\n\n".join(
        "Etwas ueber `MIND_BACKUP_KEEP_COUNT` Nummer %d." % i for i in range(6)))
    k, _ = einordnen("MIND_BACKUP_KEEP_COUNT", d1, _inhalt(d1), d2, _inhalt(d2))
    pruef("gleich lang, kein Zeiger -> duplikat", k, "duplikat")

    # 3) ⭐ Zahlendrift — der Fall, den Textaehnlichkeit nie findet
    z1 = schreib("z1.md", "# A\n\n`MIND_NOTFALL_TOKENS` ist entfallen in v5.9.3.\n")
    z2 = schreib("z2.md", "# B\n\n`MIND_NOTFALL_TOKENS` steht auf 940000 und ist aktiv.\n")
    k, grund = einordnen("MIND_NOTFALL_TOKENS", z1, _inhalt(z1), z2, _inhalt(z2))
    pruef("gleicher Name, anderer Status -> zahlendrift", k, "zahlendrift")

    # 3c) ⭐ POSITIVKONTROLLE MIT ECHTEM WORTLAUT (01.09.2026) — der Fall, an
    #     dem drei Fassungen dieses Werkzeugs vorbeigelaufen sind.
    #     Beide Stellen erklaeren die Marke fuer entfallen; EINE nennt dabei
    #     ihren alten Wert. Das ist KEIN Drift, sondern die normale Form eines
    #     Nachrufs. Der Wortlaut ist woertlich aus `env-vars.md` und
    #     `kontext-und-umgebung.md` uebernommen, nicht konstruiert —
    #     `werkzeuge-zuerst.md`: ein Detektor braucht ECHTES Material.
    t3a = schreib("t3a.md", "# A\n\n`MIND_NOTFALL_TOKENS` ist mit v5.9.3 "
                            "**entfallen** — im Hook-Code nirgends mehr "
                            "gelesen.\n")
    # ⛔ BEIDE Zeilen aus env-vars.md, nicht nur eine. Die erste traegt das
    #    Totsagen (`entfallen`), die zweite den Altwert (940000). Ein erster
    #    Versuch nahm nur die zweite — `wirkungslos` steht nicht in `_TOT`,
    #    damit war es ein ECHTER Drift und der Fall blieb zu Recht rot.
    #    Ein gekuerzter Wortlaut kann das Merkmal verlieren, um das es geht.
    t3b = schreib("t3b.md", "# B\n\n"
                            "| ~~MIND_NOTFALL_TOKENS~~ | **entfallen v5.9.3** | "
                            "Wird nicht mehr gelesen |\n"
                            "| ~~`MIND_NOTFALL_TOKENS`~~ | ja, **wirkungslos** | "
                            "940000 — seit v5.9.3 von keinem Hook gelesen |\n")
    k3, g3 = einordnen("MIND_NOTFALL_TOKENS", t3a, _inhalt(t3a),
                       t3b, _inhalt(t3b))
    pruef("⭐ beide tot, eine nennt den Altwert -> KEIN zahlendrift",
          k3 == "zahlendrift", False)
    # ⛔ Und die Gegenprobe zur Gegenprobe: der Befund darf nicht einfach
    #    verschwinden, er soll als gewoehnliches Duplikat weiterlaufen.
    pruef("   ... sondern duplikat", k3, "duplikat")

    # 3b) ⛔ NEGATIVKONTROLLE mit ECHTEM Wortlaut (25.08.2026).
    #     Der einzige zahlendrift-Befund des ersten Laufs ueber acht Ablagen
    #     war ein Fehlalarm: "entfernt" stand 76 Zeichen von der Marke weg
    #     und meinte den ZWECK des Schutzes, nicht sein Ende. Vor dem
    #     Naehe-Filter im zahlendrift-Pfad war dieser Fall ROT.
    #     ⚠ Der Wortlaut ist woertlich aus `.claude/rules/env-vars.md:17`
    #       und `memory/sync-loescht-laufende-version.md:33` uebernommen —
    #       konstruierte Faelle bilden nur die eigene Erwartung ab
    #       (werkzeuge-zuerst.md, Lehre 3).
    n1 = schreib("n1.md", "# A\n\n| MIND_SYNC_PROTECT_HOURS | 168 | Schutzfenster "
                          "in Stunden fuer `.sync-protect.json`, damit der "
                          "Aufraeumer keine frisch installierte Version "
                          "entfernt |\n")
    n2 = schreib("n2.md", "# B\n\n| Schutz | aus der Registry | "
                          "**`.sync-protect.json`** neben den "
                          "Versionsverzeichnissen, `PROTECT_HOURS=168` |\n")
    k, _ = einordnen(".sync-protect.json", n1, _inhalt(n1), n2, _inhalt(n2))
    pruef("Statuswort 76 Zeichen weg -> KEIN zahlendrift",
          k != "zahlendrift", True)

    # 3c) ⭐ POSITIVKONTROLLE zur selben Schwelle — sonst ist 3b nur Stille.
    #     Dasselbe Wort, aber NAH an der Marke: dann MUSS es anschlagen.
    #     (werkzeuge-zuerst.md: "Jede Schwelle steht zwischen einer
    #      Positiv- UND einer Negativkontrolle.")
    p1 = schreib("p1.md",
                 "# A\n\n`.sync-protect.json` entfernt, gibt es nicht mehr.\n")
    p2 = schreib("p2.md",
                 "# B\n\n`.sync-protect.json` steht auf 168 und ist aktiv.\n")
    k, _ = einordnen(".sync-protect.json", p1, _inhalt(p1), p2, _inhalt(p2))
    pruef("Statuswort direkt an der Marke -> zahlendrift", k, "zahlendrift")

    # 4) Reiner Zeiger
    r1 = schreib("r1.md", "# A\n\nSiehe `r2.md` fuer `MIND_LOG_MAX_LINES`.\n")
    r2 = schreib("r2.md", "# B\n\n" + "\n\n".join(
        "`MIND_LOG_MAX_LINES` Absatz %d." % i for i in range(8)))
    k, _ = einordnen("MIND_LOG_MAX_LINES", r1, _inhalt(r1), r2, _inhalt(r2))
    pruef("eine Zeile + Zeiger -> zeiger oder zielform", k in ("zeiger", "zielform"), True)

    # ⛔ Die Gegenprobe: vier Faelle, mindestens drei VERSCHIEDENE Urteile.
    #    Ein Einordner, der immer dasselbe sagt, bestuende jeden Einzelfall.
    ergebnisse = {
        einordnen("MIND_SYNC_AT_TOKENS", kurz, _inhalt(kurz), lang, _inhalt(lang))[0],
        einordnen("MIND_BACKUP_KEEP_COUNT", d1, _inhalt(d1), d2, _inhalt(d2))[0],
        einordnen("MIND_NOTFALL_TOKENS", z1, _inhalt(z1), z2, _inhalt(z2))[0],
    }
    pruef("drei verschiedene Urteile", len(ergebnisse), 3)

    # ======================================================================
    # v5.20.0 — die zweite Achse: erledigt gegen offen
    # ======================================================================
    print("\n  --- Widerspruch INNERHALB einer Datei ---")

    def fuell(n):
        return "\n".join("Fuelltext Absatz %d ohne Marken." % i for i in range(n))

    # 5) ⭐ Der Creator-Fall, nachgebaut: 110 Zeilen auseinander
    w1 = schreib("w1.md", "# Kette\n\nDer `VORAB_MS`-Fix ist eingebaut.\n\n"
                          + fuell(30) +
                          "\n\n⛔ OFFEN — `VORAB_MS` ist NOCH NICHT eingebaut.\n")
    b = widerspruch_in_datei(w1)
    pruef("weit auseinander, erledigt vs offen -> Befund", len(b), 1)
    pruef("und die Marke stimmt", b[0]["marke"] if b else "-", "VORAB_MS")

    # ===== GEGENKONTROLLEN — jede einzelne verhindert eine Fehlalarm-Klasse =====

    # 6) ⛔ Der aufloesende Satz ist die RICHTIGE Form und darf NIE gemeldet werden.
    #    Dieses Repo benutzt sie staendig: "✅ ~~alt~~ — BEHOBEN in v5.2.2".
    w2 = schreib("w2.md", "# Kette\n\nDer `VORAB_MS`-Fix ist eingebaut.\n\n"
                          + fuell(30) +
                          "\n\n✅ ~~`VORAB_MS` ist NOCH NICHT eingebaut~~ — behoben.\n")
    pruef("aufloesender Satz (~~) -> kein Befund", len(widerspruch_in_datei(w2)), 0)

    # 7) "Bis v5.6.0 stand hier ..." ist ebenfalls eine Ruecknahme
    w3 = schreib("w3.md", "# Kette\n\n`VORAB_MS` ist eingebaut.\n\n" + fuell(30) +
                          "\n\nBis v5.6.0 galt: `VORAB_MS` steht noch nicht im Code.\n")
    pruef("Ruecknahme per 'Bis vX' -> kein Befund", len(widerspruch_in_datei(w3)), 0)

    # 8) Zwei Saetze direkt untereinander sind eine ERZAEHLUNG, kein Widerspruch
    w4 = schreib("w4.md", "# Kette\n\n`VORAB_MS` war noch nicht eingebaut.\n"
                          "Jetzt ist `VORAB_MS` eingebaut.\n")
    pruef("dicht beieinander -> kein Befund", len(widerspruch_in_datei(w4)), 0)

    # 9) Eine Zeile mit BEIDEM ist fast immer ein aufloesender Satz
    w5 = schreib("w5.md", "# Kette\n\n`VORAB_MS` war nicht eingebaut, ist jetzt "
                          "eingebaut.\n\n" + fuell(30) +
                          "\n\nNochmal `VORAB_MS` erwaehnt, ohne Status.\n")
    pruef("eine Zeile mit beidem -> kein Befund", len(widerspruch_in_datei(w5)), 0)

    # 10) Eine Datei ohne jeden Status sagt gar nichts
    w6 = schreib("w6.md", "# Kette\n\n`VORAB_MS` steuert den Vorlauf.\n\n" + fuell(30) +
                          "\n\n`VORAB_MS` steht in der Konfiguration.\n")
    pruef("kein Statuswort -> kein Befund", len(widerspruch_in_datei(w6)), 0)

    # 10a) ⛔ JEDES Offen-Signal EINZELN — sonst deckt ein reichhaltiger
    #      Prueffall eine kaputte Alternative zu.
    #      GEMESSEN 25.08.2026: ein Heredoc machte aus `\b` (Wortgrenze) das
    #      Backspace-Zeichen 0x08. `OFFEN` und `TODO` matchten danach NIE —
    #      und dieser Selbsttest blieb GRUEN, weil Fall 5 zusaetzlich
    #      "NOCH NICHT eingebaut" enthaelt. Ein Prueffall mit zwei Signalen
    #      prueft nur, dass EINES davon lebt.
    for wort, txt in (("OFFEN", "⛔ OFFEN: `PEGEL_MS` fehlt hier."),
                      ("TODO", "TODO — `PEGEL_MS` fehlt hier."),
                      ("Kreuz", "❌ `PEGEL_MS` fehlt hier."),
                      ("steht noch aus", "`PEGEL_MS` steht noch aus."),
                      ("nicht umgesetzt", "`PEGEL_MS` ist nicht umgesetzt.")):
        wx = schreib("w10_%s.md" % wort.replace(" ", "_"),
                     "# K\n\n`PEGEL_MS` ist eingebaut.\n\n" + fuell(30) +
                     "\n\n" + txt + "\n")
        pruef("Offen-Signal '%s' greift" % wort, len(widerspruch_in_datei(wx)), 1)

    # 10b) GEGENKONTROLLE zu 10a: "offene Frage" darf NICHT anschlagen
    w11 = schreib("w11.md", "# K\n\n`PEGEL_MS` ist eingebaut.\n\n" + fuell(30) +
                            "\n\nEine offene Frage zu `PEGEL_MS` bleibt.\n")
    pruef("'offene Frage' ist kein Signal", len(widerspruch_in_datei(w11)), 0)

    print("  --- statusdrift ueber ZWEI Dateien ---")

    # 11) Der video-chatterbox-stand.md-Fall
    s1 = schreib("s1.md", "# Stand\n\n`KOMFORT_RAUSCHEN` ist umgesetzt seit dem Test.\n")
    s2 = schreib("s2.md", "# Liste\n\n`KOMFORT_RAUSCHEN` steht noch aus.\n")
    k, _ = einordnen("KOMFORT_RAUSCHEN", s1, _inhalt(s1), s2, _inhalt(s2))
    pruef("erledigt in A, offen in B -> statusdrift", k, "statusdrift")

    # 12) ⛔ GEGENKONTROLLE: zahlendrift wiegt schwerer und darf NICHT verdeckt werden
    t1 = schreib("t1.md", "# A\n\n`MIND_NOTFALL_TOKENS` ist entfallen, also erledigt.\n")
    t2 = schreib("t2.md", "# B\n\n`MIND_NOTFALL_TOKENS` steht auf 940000, steht noch aus.\n")
    k, _ = einordnen("MIND_NOTFALL_TOKENS", t1, _inhalt(t1), t2, _inhalt(t2))
    pruef("zahlendrift geht vor statusdrift", k, "zahlendrift")

    # Rauschfilter
    print("  --- Rauschfilter ---")
    pruef("Allerweltswort gefiltert", _spezifisch("claude"), False)
    pruef("kurzes Wort gefiltert", _spezifisch("abc"), False)
    pruef("Pfad ist spezifisch", _spezifisch("tools/rollback.py"), True)
    pruef("ALLCAPS ist spezifisch", _spezifisch("MIND_SYNC_AT_TOKENS"), True)
    m = marken("Text mit `tools/x.py` und MIND_ABC_DEF und claude und 200 Zeilen.")
    pruef("claude nicht in den Marken", "claude" in m, False)
    pruef("Pfad in den Marken", "tools/x.py" in m, True)

    print("\n=== %d Abweichung(en) ===" % fehler)
    return 3 if fehler else 0


def widersprueche_lauf(projekt, bereich="alles"):
    """`--widersprueche`: nur die Selbstwidersprueche, datei fuer datei."""
    abl = ablagen(projekt, bereich)
    dateien = [p for pfade in abl.values() for p in pfade]
    print("=" * 86)
    print("  Selbstwidersprueche — %d Datei(en)" % len(dateien))
    print("=" * 86)
    gesamt = 0
    for p in sorted(dateien):
        befunde = widerspruch_in_datei(p)
        if not befunde:
            continue
        print("\n  %s" % p)
        for x in befunde:
            gesamt += 1
            print("    %-24s Z%-5d erledigt | Z%-5d offen  (%d auseinander)"
                  % (x["marke"][:24], x["zeile_erledigt"], x["zeile_offen"],
                     x["abstand"]))
            print("        + %s" % x["text_erledigt"])
            print("        - %s" % x["text_offen"])
    print()
    print("  %d Widerspruch/Widersprueche" % gesamt)
    if gesamt == 0:
        print()
        print("  ⚠ NULL ist hier ein zulaessiges Ergebnis — aber nur, weil die")
        print("    Positivkontrolle im Selbsttest anschlaegt (`--selbsttest`).")
        print("    Ohne sie waere eine Null von einem stummen Werkzeug nicht")
        print("    zu unterscheiden.")
    print()
    print("  ⛔ GRENZE: gefunden werden nur Widersprueche, deren beide Stellen")
    print("     eine GEMEINSAME MARKE tragen (Bezeichner, Pfad, Zahlenwert).")
    print("     Sagt die eine Seite `VORAB_MS` und die andere umschreibt es in")
    print("     Prosa, ist der Widerspruch fuer dieses Werkzeug unsichtbar.")
    print("     Die tragende Massnahme ist die SUCHE VOR DEM SCHREIBEN —")
    print("     siehe mind-claudemd/mind-rules, 'SUCHEN, BEVOR DU ERGAENZT'.")
    return 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()
    projekt = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    # ⚠ --nur global|projekt|alles schraenkt die Ablagen ein. Vorgabe: alles.
    bereich = "alles"
    if "--bereich" in argv:
        i = argv.index("--bereich") + 1
        if i < len(argv):
            # ⛔ VERWECHSLUNGSSCHUTZ (25.08.2026): SKILL.md:22 und die CLAUDE.md
            #    versprechen dem Nutzer `--bereich global|projekt|alles`, im Code
            #    ist `--bereich` aber der PROJEKTPFAD und `--nur` der Bereich.
            #    Wer die dokumentierte Form eintippt, setzte den Pfad auf die
            #    Zeichenkette "projekt" — und die Ausgabe zeigte dann `p:rules 0`,
            #    was wie ein Befund ueber das Projekt aussieht statt wie ein
            #    Bedienfehler. Klasse `instrument-misst-nichts`.
            if argv[i] in ("global", "projekt", "alles") and not os.path.isdir(argv[i]):
                bereich = argv[i]
                print("Hinweis: --bereich %s als BEREICH verstanden "
                      "(--nur waere die Tool-Form)." % argv[i])
            else:
                projekt = argv[i]
    if "--nur" in argv:
        i = argv.index("--nur") + 1
        if i < len(argv) and argv[i] in ("global", "projekt", "alles"):
            bereich = argv[i]
        else:
            print("--nur braucht global|projekt|alles")
            return 2
    # ⛔ Ein Projektpfad, den es nicht gibt, bricht AB. Vorher wurde still ein
    #    leeres Projekt gemessen und das Ergebnis sah aus wie ein Befund.
    if not os.path.isdir(projekt):
        print("Projektpfad existiert nicht: %s" % projekt)
        return 2
    if "--widersprueche" in argv:
        return widersprueche_lauf(projekt, bereich)
    return lauf(projekt, bereich)


if __name__ == "__main__":
    sys.exit(main())
