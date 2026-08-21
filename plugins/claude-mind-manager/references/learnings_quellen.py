#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Projekt- und Quellenfindung fuer /mind-learnings (NEU v5.9.0).

⛔ WARUM DAS EINE EIGENE DATEI IST. Der erste Stand von `learnings_scan.py` stieg genau
   ZWEI Ebenen ab und uebersprang alles, was mit '.' beginnt. Gemessen: 20 Projekte
   gefunden, 3 uebersehen — und alles unter `.claude/` nie betreten. Die Findung ist der
   Teil, an dem der ganze Pruefer haengt, und sie hatte keine eigene Pruefsammlung.

⛔ VOLLE Rekursion allein ist aber FALSCH. Gemessen am 21.08.2026: mit blossem `os.walk`
   fand sie **57** Projekte statt 23 — 37 davon aus `.claude-mind/backups/` und
   `snapshots/`, den Sicherungskopien des Plugins selbst. Jede Lehre waere dort ein
   halbes Dutzend Mal gezaehlt worden, und ein Schnappschuss haette als eigenes Projekt
   gegolten. **Wer rekursiv sucht, muss ebenso sorgfaeltig ausschliessen.**
"""
import os
import re

# ⛔ Diese Liste ist der Kern. Jeder Eintrag hat einen Grund, keiner ist Vorsichtsmassnahme.
# GitHub-Kennung des Nutzers. Ein Remote, das sie NICHT enthaelt, gehoert jemand
# anderem — dessen Kontextdateien sind nicht unsere Baustelle.
EIGNER = "blumenkohlbinary"


def fremdklon(projekt):
    """True, wenn das Projekt ein Klon eines FREMDEN Repos ist.

    Exakt, nicht heuristisch: gemessen 21.08.2026 hat ComfyUI das Remote
    `github.com/comfyanonymous/ComfyUI.git`, waehrend JEDES eigene Projekt des
    Nutzers ueberhaupt kein Remote hat. Kein Remote -> nie fremd.

    ⛔ Die Datei-Autorschaft taugt dafuer NICHT: Palvedo committet unter der
    lokalen Identitaet `lauf1@palvedo.local`, ein Mail-Vergleich haette das
    eigene Projekt als fremd eingestuft.
    """
    import subprocess
    try:
        r = subprocess.run(["git", "-C", projekt, "remote", "get-url", "origin"],
                           capture_output=True, text=True, timeout=10)
    except Exception:
        return False
    if r.returncode != 0:
        return False                      # kein Remote = eigenes Projekt
    return EIGNER.lower() not in (r.stdout or "").lower()


def upstream_datei(projekt, pfad):
    """True, wenn die Datei in einem Fremdklon liegt UND dort versioniert ist.

    Eine selbst angelegte, NICHT versionierte CLAUDE.md in einem Fremdklon
    gehoert weiter dem Nutzer und wird geprueft.
    """
    import os
    import subprocess
    if not fremdklon(projekt):
        return False
    try:
        r = subprocess.run(
            ["git", "-C", projekt, "ls-files", "--error-unmatch",
             os.path.relpath(pfad, projekt)],
            capture_output=True, text=True, timeout=10)
        return r.returncode == 0
    except Exception:
        return False


AUS = (
    # fremder Code, nie eigenes Wissen
    "node_modules", ".git", "vendor", "target", ".next", "__pycache__", ".pytest_cache",
    ".venv", "venv", "dist", "build", "publish",
    # ⛔ KOPIEN eigener Kontextdateien — hier entstehen Mehrfachzaehlungen
    ".claude-mind",        # Sicherungen und Schnappschuesse des Plugins
    "_claude_backups",     # Handsicherungen
    "Beispiele",           # eingefrorene Referenz-Plugins
    "cache",               # ~/.claude/plugins/cache — installierte Fremdversionen
    "bundled-skills",      # mitgelieferte Skills von Claude Code
    "worktrees",           # git-Arbeitskopien: derselbe Baum ein zweites Mal
    "archive", "archiv",   # bewusst Stillgelegtes
)

# Woran eine LEHRE in diesem Regelwerk erkennbar ist. Das ist keine Heuristik ueber
# Fliesstext, sondern die NOTATION des Nutzers — er markiert Lehren durchgehend so.
LEHRMARKER = re.compile(
    r"⛔|⚠|⭐|\*\*Warum:\*\*|\bDie Lehre\b|\bGegenmittel\b|"
    r"\bgemessen\b|\bbelegt\b|\bnachgewiesen\b|\bFalle\b|\bLehre daraus\b")


# Was in `.claude/` liegen muss, damit es ein PROJEKT ist und nicht nur ein Ordner
# mit lokalen Einstellungen.
KONTEXT_ORDNER = ("rules", "skills", "agents", "commands", "hooks")


def ist_projekt(p):
    """CLAUDE.md, oder ein `.claude/` mit echtem Kontext darin.

    ⛔ ZWEI Fehlalarm-Klassen, beide am 21.08.2026 gemessen und beide hier behoben:

    1. Ein `.claude/`, das NUR `settings.local.json` enthaelt, ist kein Projekt —
       es ist eine Einstellungsdatei. `Plugin - Entwicklung` wurde so gefuehrt und
       meldete "hat .claude/, aber keine CLAUDE.md": ein Befund ueber einen Ordner,
       der gar keiner sein wollte.

    2. Ein Verzeichnis INNERHALB von `skills/`, `agents/`, `commands/` oder `rules/`
       ist nie ein Projekt, auch wenn dort eine `AGENTS.md` liegt. Fremde Skillpakete
       bringen solche Dateien mit: `skills/vercel-react-native-skills/AGENTS.md`.
       Ohne diese Sperre sprang die Projektzahl von 22 auf 30 — die 9 zusaetzlichen
       waren allesamt Unterordner eingekaufter Pakete."""
    teile = {x.lower() for x in os.path.abspath(p).replace("\\", "/").split("/")}
    if teile & {"skills", "agents", "commands", "rules", ".agents"}:
        return False
    if os.path.isfile(os.path.join(p, "CLAUDE.md")) \
            or os.path.isfile(os.path.join(p, "AGENTS.md")):
        return True
    cd = os.path.join(p, ".claude")
    if not os.path.isdir(cd):
        return False
    return any(os.path.isdir(os.path.join(cd, u)) for u in KONTEXT_ORDNER)


def projekte(wurzel):
    """Alle Projekte unter der Wurzel — VOLL rekursiv, versteckte eingeschlossen,
    Kopien ausgeschlossen.

    Ein Projekt in einem Projekt ist ausdruecklich erlaubt: `Plugin - Entwicklung`
    ist selbst eines und enthaelt weitere."""
    raus = []
    wurzel_abs = os.path.abspath(wurzel)
    for wz, dirs, _ in os.walk(wurzel):
        # ⛔ In-place filtern, sonst steigt os.walk trotzdem ab.
        dirs[:] = [d for d in dirs
                   if d not in AUS and not d.startswith("_") and d.lower() not in AUS]
        if os.path.abspath(wz) != wurzel_abs and ist_projekt(wz):
            raus.append(wz)
    return sorted(set(raus))


def quellen(projekt, memory_dir=None):
    """Alle Kontext-Quellen eines Projekts, nach Art getrennt.

    ⚠ `.claude/rules/` wird REKURSIV gelesen — Unterordner darin sind erlaubt und
    wurden vorher uebersehen."""
    q = {"claudemd": [], "rules": [], "skills": [], "hooks": [], "memory": []}

    for kand in (os.path.join(projekt, "CLAUDE.md"),
                 os.path.join(projekt, ".claude", "CLAUDE.md"),
                 os.path.join(projekt, "AGENTS.md")):
        if os.path.isfile(kand):
            q["claudemd"].append(kand)

    cd = os.path.join(projekt, ".claude")
    if os.path.isdir(cd):
        for unter, schl, endungen in (
                ("rules", "rules", (".md",)),
                ("skills", "skills", (".md",)),
                ("agents", "skills", (".md",)),
                ("commands", "skills", (".md",)),
                ("hooks", "hooks", (".sh", ".py", ".json", ".md")),
        ):
            d = os.path.join(cd, unter)
            if not os.path.isdir(d):
                continue
            for wz, dirs, ds in os.walk(d):
                dirs[:] = [x for x in dirs if x not in AUS]
                for f in sorted(ds):
                    if f.endswith(endungen):
                        q[schl].append(os.path.join(wz, f))

    md = memory_dir if memory_dir else memory_pfad(projekt)
    if md and os.path.isdir(md):
        for f in sorted(os.listdir(md)):
            if f.endswith(".md"):
                q["memory"].append(os.path.join(md, f))
    return q


def memory_pfad(projekt):
    """Slug-Regel von Claude Code: JEDES Nicht-Alphanumerische wird zu '-'."""
    slug = re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(projekt))
    d = os.path.join(os.path.expanduser("~"), ".claude", "projects", slug, "memory")
    return d if os.path.isdir(d) else None


def lies(p):
    try:
        return open(p, "rb").read().decode("utf-8", "replace")
    except Exception:
        return ""


def lehren(pfad, min_len=60, max_len=1800):
    """Absaetze mit Lehrmarker.

    ⛔ Absatzweise, nicht zeilenweise. Gemessen am 20.08.2026: eine zeilenbasierte Suche
       fand den Palvedo-Befund nicht, weil der Satz zwischen 'verglich absolute' und
       'Befundzahlen' umbricht. Wer zeilenweise sucht, zerreisst jeden mehrzeiligen
       Befund und misst die Ausbeute systematisch zu niedrig."""
    t = lies(pfad).replace("\r\n", "\n")
    # Codebloecke raus — dort stehen Befehle, keine Lehren
    t = re.sub(r"```.*?```", " ", t, flags=re.S)
    raus = []
    for a in re.split(r"\n\s*\n", t):
        a = a.strip()
        if min_len <= len(a) <= max_len and LEHRMARKER.search(a):
            raus.append(a)
    return raus
