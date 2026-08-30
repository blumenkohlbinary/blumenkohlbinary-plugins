#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Schritt 3 von /mind-cleaner — Regeldateien einordnen: Hook · Skill · Command · bleibt.

⛔ DIESE ZAHLEN ENTSCHEIDEN NICHT. SIE SCHLAGEN VOR.

Der Befund vom 21.08.2026, der das begruendet: `workstation-fernzugriff.md` handelt zu
100 % von EINER Maschine — aber nur **15 %** seiner Absaetze nennen sie beim Namen.
Wer den Geltungsbereich per Regex misst, misst **Namensnennungen**, nicht Geltung.
Deshalb legt dieses Werkzeug die Zahlen vor und laesst entscheiden.

## Die vier Wege, nach dem MOMENT DER ERKENNBARKEIT

    woran erkennbar?                     ->  Werkzeug     mechanisch pruefbar?
    am Werkzeugaufruf (Pfad/Endung/Befehl)  Hook          teilweise
    an der Aufgabe                          Skill         teilweise
    der Nutzer ruft es beim Namen           Slash-Command nein, Urteil
    gar nicht, gilt vor jedem Eingriff      bleibt Rule   nein, Urteil

## ⛔ DIE HARTE KANTE (NEU 24.08.2026, gemessen)

**Was ERZWUNGEN werden muss, wird NIE ein Command.** Das ist keine Vorsicht, sondern
Herstelleraussage. `code.claude.com/docs/en/skills` sagt woertlich, wenn ein Command
aufhoert zu wirken: *"the model is choosing other tools or approaches … or use hooks
to enforce behavior deterministically."*

Gemessene Aktivierungsraten von Skills:
    20 %  einfache description, ohne Hook   (200+ Tests, Haiku 4.5)
    84 %  mit erzwingendem Hook
    56 %  NIE aufgerufen                    (Vercel Agent-Evals)
   100 %  persistent geladenes AGENTS.md

Eine Leitplanke, die zu 20-84 % laedt, ist keine Leitplanke.

## ⭐ UND DER GRUND, WARUM UMZIEHEN TROTZDEM FUNKTIONIERT

Nicht die Command-Auswahl traegt den Umzug, sondern der **Pfad in der Kurz-Rule**.
Gemessen 24.08.2026: einem Zeiger auf eine DATEI wurde in **4 von 4** Sonden gefolgt,
je ein Werkzeugaufruf — auch bei beilaeufiger Nennung ohne Verbotszeichen.

Deshalb prueft `cleaner_umzug.py` als Gate, dass die Kurz-Rule den Zielpfad WOERTLICH
nennt. Ein Zeiger auf einen Command-NAMEN faellt auf die 20-%-Mechanik zurueck.

Aufruf:
  python cleaner_einordnung.py <datei.md> [<datei.md> ...]
  python cleaner_einordnung.py --verzeichnis <pfad>
  python cleaner_einordnung.py --selbsttest

Rueckgabe: 0 = eingeordnet · 1 = keine Datei lesbar · 3 = Selbsttest gescheitert
"""
import os
import re
import sys

# ⛔ `newline=""` ist PFLICHT auf Windows. Ohne diesen Zusatz uebersetzt
#    TextIOWrapper jeden Zeilenumbruch in die Windows-Fassung (CR + LF).
#    Jede zeilenverankerte Zusicherung (das Dollarzeichen in grep) bricht
#    dann — und zwar STILL, denn die Ausgabe sieht voellig richtig aus.
#    Gemessen 24.08.2026 an `cleaner_duplikate.py`: zwei Prueffaelle meldeten
#    0 Treffer fuer Zeilen, die dastanden. Dieselbe Klasse wie der in der
#    globalen CLAUDE.md dokumentierte `write_text()`-Fall.
sys.stdout.reconfigure(encoding="utf-8", newline="")

# --- Die Signale ----------------------------------------------------------
# ⚠ Jedes Signal ist eine ENTSCHEIDUNG darueber, was zaehlt. Sie stehen hier
#   sichtbar und einzeln, damit sie bestreitbar sind, statt in einer Regex zu
#   verschwinden.

IMPERATIV = re.compile(
    r"\bMUST\b|\bNEVER\b|\bALWAYS\b|\bniemals\b|\bnie\b|\bimmer\b|\bmuss\b|"
    r"\bdarf nicht\b|\bkeinesfalls\b|\bPflicht\b|⛔", re.IGNORECASE)

# Konkretheit = woran ein Hook anknuepfen koennte: ein PFAD oder ein BEFEHL.
#
# ⛔ Eine blosse Dateiendung zaehlt NICHT — gemessen am echten Bestand 24.08.2026:
#    `keine-annahmen.md` kam damit auf kon=0,67 und wurde als HOOK-KANDIDAT
#    vorgeschlagen. Die Datei ist aber eine reine Haltungsregel ("Ursache im
#    eigenen Code suchen, nicht beim Nutzer") — sie war nur deshalb "konkret",
#    weil sie ANDERE REGELDATEIEN ZITIERT (`messung-vor-glauben.md` …).
#
#    Eine Zitierung ist kein Aufruf-Anker. Ein Hook kann an `dist/` haengen und
#    an `git push`; an der Erwaehnung eines Dateinamens im Fliesstext nicht.
KONKRET = re.compile(
    r"[A-Za-z]:[\\/]"                       # C:\ oder C:/
    r"|(?<![\w.])\.{0,2}/[\w.-]+"           # ./pfad  ../pfad  /pfad
    r"|~/[\w.-]+"                           # ~/pfad
    r"|[\w.-]+/[\w.-]+\.(?:py|sh|md|json|exe|bat|ps1|ts|tsx|jsx|yml|yaml|toml)\b"
    r"|\b(?:git|npm|python3?|bash|rm|cp|mv|pyinstaller|ffmpeg|ssh|rclone|"
    r"taskkill|chmod|sed|grep)\b")

CODEZAUN = re.compile(r"^\s*```")


def absaetze(text):
    """Absaetze OHNE Codebloecke — Code verzerrt jede Dichtemessung.

    ⛔ Ein unabgeschlossener Codezaun wuerde den Rest der Datei verschlucken.
    Deshalb wird der Zustand am Ende geprueft und gemeldet, nicht verschwiegen.
    """
    drin = False
    zeilen, code = [], 0
    for z in text.split("\n"):
        if CODEZAUN.match(z):
            drin = not drin
            code += 1
            continue
        if drin:
            code += 1
        else:
            zeilen.append(z)
    roh = "\n".join(zeilen)
    abs_ = [a.strip() for a in re.split(r"\n\s*\n", roh) if a.strip()]
    return abs_, code, drin


def einordnen(pfad):
    try:
        with open(pfad, encoding="utf-8", errors="replace") as fh:
            t = fh.read()
    except OSError:
        return None

    abs_, codezeilen, zaun_offen = absaetze(t)
    n = len(abs_)
    if n == 0:
        return {"pfad": pfad, "bytes": len(t.encode("utf-8")), "absaetze": 0,
                "imperativ": 0.0, "konkret": 0.0, "code": 0.0,
                "zaun_offen": zaun_offen, "vorschlag": "UNKLAR",
                "grund": "keine Absaetze ausserhalb von Codebloecken"}

    imp = sum(1 for a in abs_ if IMPERATIV.search(a)) / n

    # ⛔ KONKRETHEIT wird MIT Codebloecken gemessen, IMPERATIVDICHTE ohne.
    #
    #    Gemessen 24.08.2026 an `workstation-fernzugriff`: `poweroff`, `suspend`
    #    und `reboot` stehen 31 mal im Skill — die Konkretheit lag trotzdem bei
    #    0,16 und die Einordnung sagte "nichts, woran ein Hook haengen koennte".
    #    Ursache: `absaetze()` schneidet Codebloecke heraus, BEVOR gemessen
    #    wird, und genau dort stehen die Befehle.
    #
    #    ⭐ Ein Befehl in einem Codeblock ist der STAERKSTE denkbare Hook-Anker.
    #    Ihn wegzuschneiden macht das Signal blind fuer seinen wichtigsten Fall.
    #
    #    Die Imperativdichte bleibt ohne Code: ein `MUST` in einem Codekommentar
    #    ist eine Notiz, kein Gebot an den Leser.
    roh_abs = [a.strip() for a in re.split(r"\n\s*\n", t) if a.strip()]
    kon = (sum(1 for a in roh_abs if KONKRET.search(a)) / len(roh_abs)
           if roh_abs else 0.0)
    zeilen_ges = max(1, len(t.split("\n")))
    cod = codezeilen / zeilen_ges

    # --- Der Vorschlag ----------------------------------------------------
    # ⛔ Reihenfolge ist Absicht: die harte Kante zuerst. Eine Datei mit hoher
    #    Imperativdichte ist eine Leitplanke — und Leitplanken werden nie Skills,
    #    egal wie gut die uebrigen Zahlen zu einem Command passen.
    if imp >= 0.30 and kon >= 0.30:
        v, g = "HOOK-KANDIDAT", ("erzwingend UND an konkreten Aufrufen erkennbar — "
                                 "Hook kann das durchsetzen, ein Command nicht")
    elif imp >= 0.30:
        v, g = "BLEIBT RULE", ("erzwingend, aber ohne konkreten Aufruf-Anker — "
                               "nichts, woran ein Hook haengen koennte")
    elif cod >= 0.25:
        v, g = "COMMAND", "hoher Codeanteil: Verfahrensbeschreibung, kein Gebot"
    elif imp < 0.15:
        v, g = "COMMAND", "kaum Gebote: Nachschlagewerk"
    else:
        v, g = "UNKLAR", "zwischen Gebot und Nachschlagewerk — hier entscheidet der Mensch"

    return {"pfad": pfad, "bytes": len(t.encode("utf-8")), "absaetze": n,
            "imperativ": imp, "konkret": kon, "code": cod,
            "zaun_offen": zaun_offen, "vorschlag": v, "grund": g}


# ==========================================================================
# Schritt 5 (v5.17.0) — Lint Leakage und der Zeiger-Zusammenzug
# ==========================================================================

# ⭐ LINT LEAKAGE ist die HAEUFIGSTE Fehlerklasse ueberhaupt.
#
# `[STUDIE, unbestaetigt]` arXiv 2606.15828, 100 Repos: **62 % der Dateien**
# betroffen, 93 % Erkennungspraezision. Haeufiger als alles andere.
#
# Definition: Eine Regel, die ein Hook, Linter oder Formatter BEREITS
# deterministisch durchsetzt, gehoert GANZ weg — nicht verschoben.
#
# ⛔ Bis v5.16.0 kannte die Einordnung "Hook" nur als ZIEL eines Umzugs, nie
#    als Grund zu ENTFERNEN. Der Nutzer hat die Klasse selbst benannt, bevor
#    die Recherche sie fand: "backup-before-delete ist schon eine hook".
#
# ⚠ ABER: Das Gebot bleibt noetig, auch wenn der Hook greift. Der Sicherungs-
#   Hook hat drei dokumentierte Luecken. **Was verschwinden darf, ist die
#   BESCHREIBUNG DES MECHANISMUS — nicht die Leitplanke.**
#   Deshalb heisst der Befund "Beschreibung doppelt", nicht "Regel ueberfluessig".

def _skriptname(befehl):
    """Den Skript-Dateinamen aus einer Hook-Befehlszeile ziehen.

    ⛔ Bis v5.20.0 stand hier `os.path.basename(befehl.split()[-1])`. Bei einem
       GEQUOTETEN Pfad — dem Normalfall auf Windows — nimmt das letzte Wort das
       schliessende Anfuehrungszeichen mit:

           python "C:/.../hooks/sicherung.py"   ->   'sicherung.py"'

       Aus dem Namen wurde in `lint_leakage` der Stamm `sicherung` — ein ganz
       gewoehnliches deutsches Wort. Gemessen am 25.08.2026: **4 Meldungen,
       1 echt, 3 Fehlalarme**. `z-mount-rclone.md` sagte schlicht
       "Vorher Sicherung." und galt als Lint Leakage.
    """
    if not befehl:
        return "?"
    # Anfuehrungszeichen weg, dann das letzte Stueck nehmen, das nach einem
    # Skript aussieht. Argumente hinter dem Skript stoeren damit nicht mehr.
    stuecke = [s.strip("\"'") for s in befehl.replace("\\", "/").split()]
    skripte = [s for s in stuecke if s.lower().endswith((".py", ".sh", ".ps1", ".js"))]
    if skripte:
        return os.path.basename(skripte[-1])
    return os.path.basename(stuecke[-1]) if stuecke else "?"


def hooks_im_projekt(projekt):
    """Welche Hooks laufen, und worauf hoeren sie? {name: [matcher, ...]}"""
    import json
    out = {}
    for kand in (os.path.join(projekt, ".claude", "settings.json"),
                 os.path.join(os.path.expanduser("~"), ".claude", "settings.json")):
        try:
            with open(kand, encoding="utf-8", errors="replace") as fh:
                d = json.load(fh)
        except (OSError, ValueError):
            continue
        for ereignis, eintraege in (d.get("hooks") or {}).items():
            for e in eintraege if isinstance(eintraege, list) else []:
                m = e.get("matcher") or "*"
                for h in e.get("hooks") or []:
                    name = _skriptname(str(h.get("command", "")))
                    out.setdefault(name, []).append("%s:%s" % (ereignis, m))
    return out


def lint_leakage(pfad, projekt):
    """Beschreibt diese Regel einen Mechanismus, den ein Hook schon durchsetzt?

    Rueckgabe: (verdaechtig, hookname, begruendung)
    ⚠ Das ist ein HINWEIS. Ob der Hook wirklich dasselbe durchsetzt, kann kein
      Namensvergleich entscheiden.
    """
    try:
        with open(pfad, encoding="utf-8", errors="replace") as fh:
            t = fh.read()
    except OSError:
        return False, None, "nicht lesbar"
    hooks = hooks_im_projekt(projekt)
    if not hooks:
        return False, None, "keine Hooks registriert oder settings.json nicht lesbar"
    # ⛔ Gesucht wird der VOLLE DATEINAME, nicht sein Stamm.
    #
    #    Bis v5.20.0 stand hier `stamm.lower() in t.lower()` mit
    #    `stamm = splitext(name)[0]`. Fuer `sicherung.py` heisst der Stamm
    #    `sicherung` — ein ganz gewoehnliches deutsches Wort. Gemessen am
    #    25.08.2026 ueber `~/.claude/rules/`: **4 Meldungen, 1 echt, 3
    #    Fehlalarme**; `z-mount-rclone.md` sagte nur "Vorher Sicherung."
    #
    #    ⭐ Ein Dateiname-Stamm gegen deutsche PROSA zu pruefen, ist dieselbe
    #      Klasse wie der Rauschfilter in cleaner_duplikate: das Instrument
    #      trifft den Gegenstand nicht, liefert aber weiter Zahlen.
    #
    #    ⚠ Der Preis ist bewusst: eine Regel, die "der Sicherungs-Hook" schreibt
    #      ohne die Datei zu nennen, wird nicht mehr gefunden. Ein uebersehener
    #      Hinweis kostet nichts; drei Fehlalarme in einer Liste von vier machen
    #      die Liste unlesbar.
    for name in hooks:
        if len(name) >= 5 and name.lower() in t.lower():
            return True, name, ("die Regel nennt `%s` — dieser Hook laeuft bereits "
                                "(%s). Die BESCHREIBUNG des Mechanismus ist damit "
                                "doppelt; die Leitplanke bleibt noetig."
                                % (name, ", ".join(sorted(set(hooks[name])))[:60]))
    return False, None, "kein laufender Hook wird namentlich genannt"


def mit_skill(pfad):
    """Kurz-Rule + zugehoeriger Skill ZUSAMMEN einordnen.

    ⛔ DER BEFUND, DER DAS NOETIG MACHT (24.08.2026):
       Fuer `workstation-fernzugriff` meldete die Einordnung "BLEIBT RULE" mit
       Konkretheit 0,10 — also "nichts, woran ein Hook haengen koennte".
       **Das stimmt nicht.** Die haerteste Leitplanke darin (Suspendieren und
       Herunterfahren nur auf Ansage) ist ein sauberer PreToolUse-Anker auf
       `ssh ... poweroff|reboot|suspend`.

       Ursache: Der Umzug hat die konkreten Befehlsnamen mit dem Rumpf in den
       Skill geschoben. Die Einordnung misst die Kurz-Rule und findet keinen
       Anker mehr.

       > Ein Umzug kann eine Hook-Gelegenheit VERSTECKEN, ohne sie zu beseitigen.
    """
    e = einordnen(pfad)
    if e is None:
        return None
    try:
        with open(pfad, encoding="utf-8", errors="replace") as fh:
            t = fh.read()
    except OSError:
        return e
    m = re.search(r"([~\w./-]*skills/[\w.-]+/SKILL\.md)", t.replace("\\", "/"))
    if not m:
        return e
    ziel = os.path.expanduser(m.group(1))
    if not os.path.isfile(ziel):
        e["skill"] = "genannt, aber nicht gefunden: %s" % m.group(1)
        return e
    zus = einordnen(ziel)
    if zus is None:
        return e
    # Zusammen messen: die hoehere Dichte gilt.
    e["skill"] = os.path.basename(os.path.dirname(ziel))
    e["konkret_zusammen"] = max(e["konkret"], zus["konkret"])
    e["imperativ_zusammen"] = max(e["imperativ"], zus["imperativ"])
    if e["konkret_zusammen"] >= 0.30 and e["imperativ_zusammen"] >= 0.30 \
            and e["vorschlag"] != "HOOK-KANDIDAT":
        e["vorschlag_zusammen"] = "HOOK-KANDIDAT"
        e["grund_zusammen"] = ("allein betrachtet kein Anker (kon %.2f) — MIT dem "
                               "Skill zusammen aber sehr wohl (kon %.2f). Der Umzug "
                               "hat die Hook-Gelegenheit versteckt, nicht beseitigt."
                               % (e["konkret"], e["konkret_zusammen"]))
    return e


# --------------------------------------------------------------------------
# Selbsttest — die Messung muss SCHEITERN KOENNEN
# --------------------------------------------------------------------------
# ⛔ Ohne diesen Lauf ist jede Einordnung wertlos: ein Einordner, der alles in
#    denselben Topf wirft, sieht von aussen aus wie einer, der sich sicher ist.
#    Deshalb je ein bekannt-erzwingender und ein bekannt-nachschlagender Text,
#    plus ein Text, der GENAU DAZWISCHEN liegt und UNKLAR ergeben MUSS.
_T_HOOK = """# Sperre

⛔ NIEMALS `rm -rf` auf `dist/` anwenden. Die Nutzerdaten liegen dort.

⛔ NIE `pyinstaller -y` gegen `dist/` fahren — das loescht `_internal/`.

MUST vor jedem `git push` erst `git pull --rebase` laufen lassen.

⛔ Schreiben auf `Z:\\` ist verboten, immer ueber die API in `C:/CD/KOHLEKTIV`.
"""

_T_SKILL = """# Wie die Aufnahme entsteht

Der Ablauf hat drei Stufen. Zuerst wird ein Bild geholt, danach zusammengesetzt,
zuletzt abgelegt.

Die Zwischenstufe liegt im Arbeitsspeicher und wird nicht sichtbar.

Wer den Ablauf nachvollziehen will, liest die Beschreibung von hinten: das
Ergebnis erklaert die Zwischenschritte besser als umgekehrt.

Historisch gab es eine vierte Stufe, sie ist entfallen.
"""

# ⛔ Dieses Fixture ist ABGEZAEHLT, nicht geschaetzt: 7 Absaetze (Ueberschrift
#    zaehlt mit), davon 2 mit einem Imperativ -> 2/7 = 0,286. Das liegt zwischen
#    0,15 und 0,30 und MUSS UNKLAR ergeben.
#    Die erste Fassung hatte 0 Imperative und landete bei SKILL — sie pruefte
#    nicht "dazwischen", sondern denselben Fall wie das Nachschlagewerk. Ein
#    Fixture, das den Zwischenbereich nie betritt, kann ihn auch nicht pruefen.
_T_UNKLAR = """# Gemischt

Der Ablauf hat drei Stufen und wird hier beschrieben.

Die Reihenfolge muss eingehalten werden.

Die Zwischenstufe liegt im Arbeitsspeicher.

Wer sie ueberspringt, bekommt immer ein anderes Ergebnis.

Historisch gab es eine vierte Stufe.

Sie ist entfallen und taucht in aelteren Beschreibungen noch auf.
"""


def selbsttest():
    import tempfile
    fehler = 0
    faelle = [("erzwingend + konkret", _T_HOOK, "HOOK-KANDIDAT"),
              ("Nachschlagewerk", _T_SKILL, "COMMAND"),
              ("dazwischen", _T_UNKLAR, "UNKLAR")]
    d = tempfile.mkdtemp()
    print("=" * 70)
    print("  Selbsttest — der Einordner muss UNTERSCHEIDEN, nicht nur laufen")
    print("=" * 70)
    for name, text, soll in faelle:
        p = os.path.join(d, name.replace(" ", "_") + ".md")
        with open(p, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        e = einordnen(p)
        ok = e and e["vorschlag"] == soll
        if not ok:
            fehler += 1
        print("  %-4s %-24s ist=%-14s soll=%s  (imp %.2f kon %.2f code %.2f)"
              % ("OK" if ok else "FEHL", name,
                 e["vorschlag"] if e else "?", soll,
                 e["imperativ"] if e else 0, e["konkret"] if e else 0,
                 e["code"] if e else 0))

    # ⛔ Die Gegenprobe, ohne die alles obige nichts wert waere: drei
    #    verschiedene Vorschlaege muessen herauskommen. Ein Einordner, der
    #    IMMER dasselbe sagt, bestuende jeden Einzelfall, an dem er zufaellig
    #    richtig liegt.
    ergebnisse = set()
    for name, text, _ in faelle:
        p = os.path.join(d, name.replace(" ", "_") + ".md")
        ergebnisse.add(einordnen(p)["vorschlag"])
    if len(ergebnisse) < 3:
        fehler += 1
        print("  FEHL Einordner unterscheidet nicht: nur %d verschiedene Urteile"
              % len(ergebnisse))
    else:
        print("  OK   drei verschiedene Urteile — der Einordner unterscheidet")

    # Unabgeschlossener Codezaun MUSS gemeldet werden.
    p = os.path.join(d, "zaun.md")
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("# X\n\n```bash\necho hallo\n")
    e = einordnen(p)
    if not e["zaun_offen"]:
        fehler += 1
        print("  FEHL offener Codezaun nicht gemeldet")
    else:
        print("  OK   offener Codezaun wird gemeldet")

    print("\n=== %d Abweichung(en) ===" % fehler)
    return 3 if fehler else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()

    dateien = []
    if "--verzeichnis" in argv:
        i = argv.index("--verzeichnis")
        wurzel = argv[i + 1] if len(argv) > i + 1 else "."
        for w, _, fs in os.walk(wurzel):
            for f in sorted(fs):
                if f.endswith(".md"):
                    dateien.append(os.path.join(w, f))
    else:
        dateien = [a for a in argv if not a.startswith("--")]

    if not dateien:
        print("usage: cleaner_einordnung.py <datei.md> … | --verzeichnis <pfad> | --selbsttest")
        return 1

    zeilen = [e for e in (einordnen(p) for p in dateien) if e]
    if not zeilen:
        print("⛔ Keine Datei lesbar. Das ist NIE ein gutes Ergebnis — eher ein falscher Pfad.")
        return 1

    zeilen.sort(key=lambda e: -e["bytes"])
    print("=" * 92)
    print("  Einordnung — %d Datei(en)" % len(zeilen))
    print("=" * 92)
    print("  %-34s %7s %5s %5s %5s  %s" % ("Datei", "Bytes", "imp", "kon", "code", "Vorschlag"))
    for e in zeilen:
        print("  %-34s %7d %5.2f %5.2f %5.2f  %s"
              % (os.path.basename(e["pfad"])[:34], e["bytes"], e["imperativ"],
                 e["konkret"], e["code"], e["vorschlag"]))
        if e["zaun_offen"]:
            print("       ⛔ unabgeschlossener Codeblock — Messung dieser Datei unsicher")
    print()
    for e in zeilen:
        print("  %s\n     %s" % (os.path.basename(e["pfad"]), e["grund"]))
    print()
    print("  " + "=" * 88)
    print("  ⛔ ZWEI GEMESSENE FEHLURTEILE DIESES WERKZEUGS (24.08.2026, eigener Bestand)")
    print("  " + "=" * 88)
    print("  Sie stehen hier dauerhaft, weil sie NICHT wegzustellen sind — nicht durch")
    print("  andere Schwellen, sondern nur durch ein menschliches Urteil.")
    print()
    print("  1) `autonom-arbeiten.md`  ->  Vorschlag SKILL, imp 0.00")
    print("     Die Datei enthaelt NULL Imperativ-Woerter (nachgezaehlt: 0 Treffer fuer")
    print("     MUST/NEVER/nie/immer/muss/darf-nicht) und ist trotzdem eine der")
    print("     direktivsten Regeln des Bestands: \"Regelverstoss, kein Ermessen\".")
    print("     ⛔ DEUTSCHE PROSA BEFIEHLT OHNE SCHLUESSELWORT. Imperativdichte kann")
    print("     eine Leitplanke deshalb GRUNDSAETZLICH verfehlen.")
    print()
    print("  2) `keine-annahmen.md`    ->  Vorschlag HOOK-KANDIDAT")
    print("     Eine reine Haltungsregel. Sie wirkt konkret, weil sie ANDERE")
    print("     REGELDATEIEN ZITIERT. Eine Zitierung ist kein Aufruf-Anker.")
    print("     (Die blosse Dateiendung wurde daraufhin aus dem Signal entfernt —")
    print("      kon fiel von 0.67 auf 0.33. Das Fehlurteil blieb trotzdem.)")
    print()
    print("  ⭐ Was daraus folgt und nicht verhandelbar ist:")
    print("     Ein COMMAND-Vorschlag wird NIE ohne menschliche Bestaetigung angewendet.")
    print("     Eine Leitplanke, die faelschlich Skill wird, laedt danach zu 20-84 %%")
    print("     statt zu 100 %% — und faellt erst auf, wenn sie gebraucht wird.")
    print()
    print("  ⛔ HOOK-KANDIDAT heisst NICHT 'wird gebaut'. /mind-cleaner meldet Hooks nur;")
    print("     gebaut wird einer erst auf ausdrueckliche Ansage (--hook-bauen).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
