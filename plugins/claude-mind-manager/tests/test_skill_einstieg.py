# -*- coding: utf-8 -*-
"""Kontrollen fuer den Skill-Einstiegs-Check — jeder Fall EINZELN.

⛔ Die erste Fassung fuhr alle vier Faelle in EINEM Projekt und suchte danach die
   Dateinamen in der Ausgabe. Die Berichtszeile kuerzt aber bei 150 Zeichen: bei zwei
   Treffern fiel der zweite Pfad heraus, und die Kontrolle meldete ihn als "nicht
   gefunden". Der Check war in Ordnung, die Kontrolle nicht — zum dritten Mal heute
   derselbe Fehler.

   Jeder Fall laeuft deshalb in einem EIGENEN Projekt, und geprueft wird die ANZAHL
   in der Meldung, nicht der (gekuerzte) Pfad.
"""
import io
import os
import re
import subprocess
import sys
import tempfile

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# Am gebauten Paket pruefen, nicht am Quellbaum — respektiert CLAUDE_PLUGIN_ROOT.
_WURZEL = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(_WURZEL, "references", "learnings_scan.py")

FAELLE = [
    ("echter SKILL.md ohne description",
     [(".claude/skills/echt/SKILL.md", "---\nname: echt\nallowed-tools: Bash\n---\n\nX\n")], 1),
    ("Agent direkt in agents/ ohne description",
     [(".claude/agents/pruefer.md", "---\nname: pruefer\n---\n\nX\n")], 1),
    ("Command direkt in commands/ ohne description",
     [(".claude/commands/tu-was.md", "---\nname: tu-was\n---\n\nX\n")], 1),
    ("Fremdpaket-Inhaltsdatei (eigenes Schema)",
     [(".claude/skills/fremd/regeln/r1.md",
       "---\ntitle: Regel\nimpact: MEDIUM\ntags: a, b\n---\n\nX\n")], 0),
    ("SKILL.md MIT description",
     [(".claude/skills/gut/SKILL.md",
       "---\nname: gut\ndescription: Tut etwas Bestimmtes und sagt es auch.\n---\n\nX\n")], 0),
    ("Fremdpaket komplett: SKILL.md gut + 5 Inhaltsdateien",
     [(".claude/skills/paket/SKILL.md",
       "---\nname: paket\ndescription: Ein Regelpaket fuer React Native.\n---\n\nX\n")]
     + [(".claude/skills/paket/regeln/r%d.md" % i,
         "---\ntitle: R%d\nimpact: LOW\n---\n\nX\n" % i) for i in range(5)], 0),
]

ok = rot = 0
for name, dateien, erwartet in FAELLE:
    T = tempfile.mkdtemp()
    pr = os.path.join(T, "proj")
    os.makedirs(pr, exist_ok=True)
    open(os.path.join(pr, "CLAUDE.md"), "w", encoding="utf-8").write("# P\n")
    for rel, inhalt in dateien:
        p = os.path.join(pr, *rel.split("/"))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w", encoding="utf-8").write(inhalt)
    r = subprocess.run([sys.executable, P, T], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    m = re.search(r"(\d+) Skills/Agents mit Frontmatter, aber ohne `description`", r.stdout)
    ist = int(m.group(1)) if m else 0
    gut = ist == erwartet
    print("  %s %-48s erwartet %d, gemeldet %d"
          % ("[ok ]" if gut else "[ROT]", name, erwartet, ist))
    ok, rot = (ok + 1, rot) if gut else (ok, rot + 1)
    import shutil
    shutil.rmtree(T, ignore_errors=True)

print()
print("  %d bestanden, %d rot" % (ok, rot))
sys.exit(1 if rot else 0)
