#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Schritt 5 von /mind-cleaner — die Gates, ohne die ein Umzug nicht stattfindet.

⛔ EIN UMZUG VERSCHIEBT. ER KUERZT NICHT.

Geprueft wird ein Tripel: die ALTE Regel, die zurueckbleibende KURZ-Rule und der
neue SKILL. Vier Gates, alle muessen halten. Ein gebrochenes Gate heisst: NICHT
umziehen, listen.

## Die vier Gates

  1 ERHALTUNG    Inhaltszeilen(Kurz) + Inhaltszeilen(Skill) >= Inhaltszeilen(Alt)
                 Frontmatter zaehlt nicht mit, Leerzeilen auch nicht.

  2 ERREICHBARKEIT  Die Kurz-Rule traegt KEIN `paths:`/`globs:` — sie muss IMMER
                 laden. Eine Leitplanke mit Ladebedingung ist keine.

  3 ⭐ PFAD      Die Kurz-Rule nennt den ZIELPFAD WOERTLICH.
                 Das ist das wichtigste Gate und das neueste.

  4 BESCHREIBUNG Der Skill hat eine `description` zwischen 40 und 200 Zeichen,
                 und Name+description bleiben unter der Kappungsgrenze.

## ⭐ WARUM GATE 3 DAS WICHTIGSTE IST — gemessen 24.08.2026

    Zugriffsweg                       Trefferquote   Beleg
    Kurz-Rule in rules/               100 %          Ladeprotokoll, 884x session_start
    Volltext ueber den PFAD           4 von 4        eigene Sonden, je 1 Werkzeugaufruf
    Volltext ueber SKILL-AUSWAHL      20-84 %        Vercel-Evals, 200+ Tests Haiku 4.5

Ein Zeiger auf einen Skill-NAMEN verlaesst sich auf die 20-%-Mechanik.
Ein Zeiger auf einen PFAD nicht. Der Unterschied ist der ganze Umzug.

⚠ Sonde D war die aussagekraeftige: sie nannte die Datei BEILAEUFIG
("Alles Weitere steht in …"), ohne Verbotszeichen — und wurde trotzdem gelesen.

## ⛔ WAS DIESE GATES NICHT KOENNEN

Sie zaehlen Zeilen. Ob der richtige Satz in der Kurz-Rule geblieben ist und der
richtige in den Skill gewandert, koennen sie NICHT sehen. Ein Umzug, der die
Leitplanke in den Skill schiebt und die Erklaerung in der Rule laesst, besteht
alle vier Gates.

**Das ist der Grund, warum ein SKILL-Vorschlag nie ohne menschliche Bestaetigung
angewendet wird.** Die Gates schliessen VERLUST aus, nicht VERTAUSCHUNG.

Aufruf:
  python cleaner_umzug.py --alt <a.md> --kurz <k.md> --skill <s.md>
  python cleaner_umzug.py --selbsttest

Rueckgabe: 0 = alle Gates halten · 1 = mindestens eines gebrochen
           2 = nicht messbar (Datei fehlt) · 3 = Selbsttest gescheitert
"""
import io
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
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", newline="")

# --- Beschreibungs-Grenzen, mit HERKUNFT ----------------------------------
#
# ⛔ DIE 200 AUS DER MEMORY-WELT GELTEN HIER NICHT.
#
# Die erste Fassung dieses Gates nahm 40-200 Zeichen — uebernommen von
# `MIND_MEMORY_DESC_MIN` und der Zustellplan-Messung, wo eine 1033-Zeichen-
# `description` (ein Aenderungsprotokoll v13..v34) den Auswaehler unbrauchbar
# machte. Gegen den ECHTEN Umzug vom 23.08. gefahren, brach das Gate sofort:
# `z-mount-rclone` 314 Zeichen, `workflow-agent-rate-limit` 286.
#
# Nachgesehen, woher die Zahl kommt — und sie traegt hier nicht:
#   Memory: eigener Modellaufruf, sieht NUR Name + description, Grenze 5 je Anfrage.
#   Skills: KEIN eigener Auswaehler (am Binaerprogramm 2.1.237 nachgesehen),
#           das Hauptmodell waehlt, keine Obergrenze gefunden.
#   `[DOKU]` Kappung erst bei 1536 Zeichen fuer description + when_to_use.
#   `[MESSUNG]` Der Hebel von 37 % auf 100 % war der DIREKTIVE STIL
#           ("ALWAYS invoke"), nicht die Kuerze.
#
# Also: harte Grenze nur dort, wo sie BELEGT ist (1536). Dazwischen ein Hinweis,
# kein Bruch. Der Regler traegt seine Herkunft, statt eine Zahl zu behaupten.
DESC_MIN = int(os.environ.get("MIND_CLEANER_DESC_MIN", "40") or 40)
DESC_WARN = int(os.environ.get("MIND_CLEANER_DESC_WARN", "500") or 500)
# `[DOKU]` code.claude.com/docs/en/skills: description + when_to_use werden in der
# Skill-Liste bei 1536 Zeichen gekappt ("truncated ... to reduce context usage").
KAPPUNG = 1536


def _lies(p):
    if not p or not os.path.isfile(p):
        return None
    with open(p, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def _ohne_frontmatter(t):
    """Rumpf ohne YAML-Kopf. ⛔ Ein OFFENES Frontmatter (erste Zeile ---, keine
    zweite) wuerde sonst die ganze Datei verschlucken — dann waeren 0 Zeilen
    uebrig und das Erhaltungs-Gate bestuende trivial."""
    z = t.split("\n")
    if not z or z[0].strip() != "---":
        return t, False
    for i in range(1, len(z)):
        if z[i].strip() == "---":
            return "\n".join(z[i + 1:]), False
    return t, True          # offen -> Rumpf unveraendert, Flagge setzen


def inhaltszeilen(t):
    """Zeilen mit Substanz: keine Leerzeilen, keine Trennlinien, KEINE HTML-Kommentare.

    ⛔ HTML-Kommentare werden VOR jeder Injektion in den Kontext entfernt `[DOKU]`.
       Ihr Text erreicht das Modell NIE — sichtbar ist er nur beim direkten Read.

       Die erste Fassung zaehlte sie mit. Gemessen 24.08.2026: `.claude/rules/hooks.md`
       enthaelt einen Kommentar mit 3 Inhaltszeilen. Ein Umzug haette damit eine
       Erhaltung bestaetigt, die es nicht gibt — 3 Zeilen galten als gerettet,
       obwohl sie in KEINER der beiden Dateien je gelesen werden.

       > Ein Gate, das unsichtbaren Text als erhaltenen Inhalt zaehlt, bestaetigt
       > eine Erhaltung, die es nicht gibt.

    ⚠ Deshalb auch: NIEMALS Inhalt in HTML-Kommentare "archivieren". Er ist dann
      weg, nicht versteckt.
    """
    rumpf, offen = _ohne_frontmatter(t)
    rumpf = re.sub(r"<!--.*?-->", "", rumpf, flags=re.S)
    n = 0
    for z in rumpf.split("\n"):
        s = z.strip()
        if not s or re.fullmatch(r"[-=_*]{3,}", s):
            continue
        n += 1
    return n, offen


def beschreibung(t):
    """`description:` aus dem Frontmatter, ein- oder mehrzeilig (`|`)."""
    z = t.split("\n")
    if not z or z[0].strip() != "---":
        return None
    ende = None
    for i in range(1, len(z)):
        if z[i].strip() == "---":
            ende = i
            break
    if ende is None:
        return None
    kopf = z[1:ende]
    for i, zeile in enumerate(kopf):
        m = re.match(r"^description:\s*(.*)$", zeile)
        if not m:
            continue
        rest = m.group(1).strip()
        if rest not in ("|", ">", "|-", ">-"):
            return rest
        teile = []
        for w in kopf[i + 1:]:
            if w.strip() and not w.startswith((" ", "\t")):
                break
            teile.append(w.strip())
        return " ".join(x for x in teile if x)
    return None


def pruefe(alt_p, kurz_p, skill_p):
    alt, kurz, skill = _lies(alt_p), _lies(kurz_p), _lies(skill_p)
    fehlt = [n for n, t in (("alt", alt), ("kurz", kurz), ("skill", skill)) if t is None]
    if fehlt:
        return None, fehlt

    a_n, a_offen = inhaltszeilen(alt)
    k_n, k_offen = inhaltszeilen(kurz)
    s_n, s_offen = inhaltszeilen(skill)
    desc = beschreibung(skill)
    name = os.path.basename(os.path.dirname(skill_p)) or os.path.basename(skill_p)

    gates = []

    # --- 1 ERHALTUNG ------------------------------------------------------
    gates.append(("ERHALTUNG", k_n + s_n >= a_n,
                  "Kurz %d + Skill %d = %d gegen Alt %d" % (k_n, s_n, k_n + s_n, a_n)))

    # ⛔ Ein offenes Frontmatter macht die Zaehlung unbrauchbar und muss den
    #    Lauf brechen — sonst besteht das Gate, weil nichts gezaehlt wurde.
    if a_offen or k_offen or s_offen:
        wo = ", ".join(n for n, f in (("alt", a_offen), ("kurz", k_offen),
                                      ("skill", s_offen)) if f)
        gates.append(("FRONTMATTER", False,
                      "OFFEN in: %s — Zeilenzaehlung unbrauchbar" % wo))

    # --- 2 ERREICHBARKEIT -------------------------------------------------
    kopf_kurz = "\n".join(kurz.split("\n")[:15])
    hat_bedingung = bool(re.search(r"^\s*(paths|globs):", kopf_kurz, re.M))
    gates.append(("ERREICHBARKEIT", not hat_bedingung,
                  "Kurz-Rule traegt paths:/globs: — laedt dann NICHT immer"
                  if hat_bedingung else "Kurz-Rule ohne Ladebedingung"))

    # --- 3 ⭐ PFAD --------------------------------------------------------
    # ⛔ Verglichen wird NICHT zeichengleich, sondern auf den PFAD-SCHWANZ.
    #
    # Der erste Entwurf suchte den vollen Pfad als Teilzeichenkette. Er brach im
    # eigenen Prueffall, obwohl der Zeiger dastand: MSYS wandelt ein Argument
    # `/tmp/x` beim Aufruf eines Windows-Programms nach `C:/Users/.../Temp/x` um,
    # waehrend im DATEITEXT weiter `/tmp/x` steht. Zwei Schreibweisen derselben
    # Datei, kein Treffer.
    #
    # Derselbe Bruch trifft ~ gegen Heimatverzeichnis und \ gegen /. Entscheidend
    # ist aber nicht die Schreibweise, sondern ob die Kurz-Rule die DATEI BENENNT,
    # sodass ein Leser sie findet. Deshalb genuegt der Schwanz aus drei Segmenten
    # (`skills/<name>/SKILL.md`) — das ist ein Pfad und kann kein blosser
    # Skill-NAME sein, auf den das Gate ja gerade nicht hereinfallen darf.
    kurz_n = kurz.replace("\\", "/")
    sp = skill_p.replace("\\", "/")
    kand = {skill_p, sp}
    home = os.path.expanduser("~").replace("\\", "/")
    if sp.startswith(home):
        kand.add("~" + sp[len(home):])
    teile = [t for t in sp.split("/") if t]
    if len(teile) >= 3:
        kand.add("/".join(teile[-3:]))
    elif len(teile) >= 2:
        kand.add("/".join(teile[-2:]))
    getroffen = next((k for k in sorted(kand, key=len, reverse=True)
                      if k.replace("\\", "/") in kurz_n), None)
    gates.append(("PFAD", getroffen is not None,
                  "Kurz-Rule nennt %s" % getroffen if getroffen
                  else "Kurz-Rule nennt den ZIELPFAD NICHT — faellt auf die "
                       "Skill-Auswahl zurueck (20-84 %)"))

    # --- 4 BESCHREIBUNG ---------------------------------------------------
    if desc is None:
        gates.append(("BESCHREIBUNG", False, "Skill hat KEINE description"))
    else:
        laenge = len(desc)
        # Gebrochen wird nur, wo es BELEGT ist: zu schwach, oder ueber der
        # dokumentierten Kappungsgrenze. Dazwischen: Hinweis.
        if laenge < DESC_MIN:
            gates.append(("BESCHREIBUNG", False,
                          "%d Zeichen — zu schwach; das Modell sieht in der Liste "
                          "nur Name+description" % laenge))
        elif len(name) + laenge > KAPPUNG:
            gates.append(("BESCHREIBUNG", False,
                          "Name+description = %d > %d — wird in der Skill-Liste "
                          "GEKAPPT [DOKU]" % (len(name) + laenge, KAPPUNG)))
        else:
            gates.append(("BESCHREIBUNG", True, "%d Zeichen" % laenge))
            if laenge > DESC_WARN:
                gates.append(("~hinweis", True,
                              "description ist %d Zeichen (Richtwert %d). Kein Bruch — "
                              "die Kappung liegt erst bei %d. Gemessen half DIREKTIVER "
                              "STIL, nicht Kuerze." % (laenge, DESC_WARN, KAPPUNG)))

    return gates, []


def _bericht(gates):
    print("=" * 78)
    print("  Umzugs-Gates")
    print("=" * 78)
    for n, ok, txt in gates:
        print("  %-4s %-16s %s" % ("OK" if ok else "BRUCH", n, txt))
    gebrochen = [n for n, ok, _ in gates if not ok]
    print()
    if gebrochen:
        print("  ⛔ NICHT UMZIEHEN. Gebrochen: %s" % ", ".join(gebrochen))
        print("     Ein Umzug bei gebrochenem Gate findet nicht statt — listen statt anwenden.")
    else:
        print("  Alle Gates halten.")
    print()
    print("  ⚠ Die Gates schliessen VERLUST aus, nicht VERTAUSCHUNG. Ob der richtige")
    print("    Satz in der Kurz-Rule geblieben ist, sehen sie NICHT. Deshalb wird ein")
    print("    SKILL-Vorschlag nie ohne menschliche Bestaetigung angewendet.")
    return 1 if gebrochen else 0


# --------------------------------------------------------------------------
def selbsttest():
    import tempfile
    d = tempfile.mkdtemp()
    fehler = 0

    def schreib(rel, text):
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        return p

    alt = schreib("alt.md", "---\ndescription: x\n---\n# A\n\nEins\n\nZwei\n\nDrei\n\nVier\n")
    skill = schreib("skills/beispiel/SKILL.md",
                    "---\nname: beispiel\ndescription: Sagt genau worum es geht und "
                    "nennt die Woerter die ein Nutzer wirklich benutzt\n---\n"
                    "# A\n\nEins\n\nZwei\n\nDrei\n")

    def kurz_mit(pfad_drin, bedingung=False):
        kopf = "---\ndescription: Leitplanke\n"
        if bedingung:
            kopf += "globs: [\"**/*.md\"]\n"
        kopf += "---\n"
        rumpf = "# A\n\nVier\n"
        if pfad_drin:
            rumpf += "\nAlles Weitere steht in `%s`.\n" % skill.replace("\\", "/")
        return schreib("kurz_%s_%s.md" % (pfad_drin, bedingung), kopf + rumpf)

    faelle = [
        ("alles gut", kurz_mit(True), 0),
        ("⭐ PFAD fehlt", kurz_mit(False), 1),
        ("Ladebedingung in der Kurz-Rule", kurz_mit(True, True), 1),
    ]
    print("=" * 78)
    print("  Selbsttest — die Gates muessen BRECHEN KOENNEN")
    print("=" * 78)
    for name, kurz, soll in faelle:
        gates, fehlt = pruefe(alt, kurz, skill)
        rc = 1 if any(not ok for _, ok, _ in gates) else 0
        ok = rc == soll
        if not ok:
            fehler += 1
        print("  %-4s %-34s Rueckgabe %d (soll %d)"
              % ("OK" if ok else "FEHL", name, rc, soll))

    # Erhaltung muss brechen, wenn wirklich etwas verloren geht.
    kurz_leer = schreib("kurz_leer.md", "---\ndescription: L\n---\n# A\n\n`%s`\n"
                        % skill.replace("\\", "/"))
    skill_leer = schreib("skills/leer/SKILL.md",
                         "---\nname: leer\ndescription: Eine ausreichend lange "
                         "Beschreibung die sagt worum es geht und nichts weiter\n---\n# A\n")
    gates, _ = pruefe(alt, kurz_leer, skill_leer)
    erh = next(ok for n, ok, _ in gates if n == "ERHALTUNG")
    if erh:
        fehler += 1
        print("  FEHL Erhaltungs-Gate haelt, obwohl Zeilen verloren gingen")
    else:
        print("  OK   Erhaltungs-Gate bricht bei echtem Verlust")

    # ⛔ Offenes Frontmatter darf das Erhaltungs-Gate nicht trivial bestehen lassen.
    offen = schreib("offen.md", "---\ndescription: x\n# A\n\nEins\n")
    gates, _ = pruefe(offen, kurz_mit(True), skill)
    if not any(n == "FRONTMATTER" and not ok for n, ok, _ in gates):
        fehler += 1
        print("  FEHL offenes Frontmatter wird nicht gemeldet")
    else:
        print("  OK   offenes Frontmatter bricht den Lauf")

    # Fehlende Datei = NICHT MESSBAR, nicht 'bestanden'.
    gates, fehlt = pruefe(os.path.join(d, "gibtsnicht.md"), kurz_mit(True), skill)
    if gates is not None or "alt" not in fehlt:
        fehler += 1
        print("  FEHL fehlende Datei wird nicht als unmessbar gemeldet")
    else:
        print("  OK   fehlende Datei -> nicht messbar, kein Urteil")

    print("\n=== %d Abweichung(en) ===" % fehler)
    return 3 if fehler else 0


def main():
    argv = sys.argv[1:]
    if "--selbsttest" in argv:
        return selbsttest()

    def hol(flag):
        return argv[argv.index(flag) + 1] if flag in argv and len(argv) > argv.index(flag) + 1 else None

    alt, kurz, skill = hol("--alt"), hol("--kurz"), hol("--skill")
    if not (alt and kurz and skill):
        print("usage: cleaner_umzug.py --alt <a.md> --kurz <k.md> --skill <s.md>")
        print("       cleaner_umzug.py --selbsttest")
        return 2

    gates, fehlt = pruefe(alt, kurz, skill)
    if gates is None:
        print("⛔ NICHT MESSBAR — fehlende Datei(en): %s" % ", ".join(fehlt))
        print("   Das ist KEIN bestandenes Gate. Ohne alle drei Staende gibt es kein Urteil.")
        return 2
    return _bericht(gates)


if __name__ == "__main__":
    sys.exit(main())
