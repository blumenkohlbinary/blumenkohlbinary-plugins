"""pre-compact.sh gegen ein echtes Transkript — heiler Sampler UND nur --arbeitsstand kaputt.

Der zweite Lauf ist der eigentliche Zweck: pre-compact.sh ist der einzige Hook, der den
Chat rettet. Bricht er, merkt es niemand.

⛔ Die Gegenprobe bricht NUR den neuen Modus. Den ganzen Sampler zu zerstoeren waere keine
Gegenprobe: --full braucht ihn auch, dann faellt die Chat-Rettung ohnehin aus und der Test
beweist nichts ueber die neue Aenderung. (Genau das war der erste, wertlose Entwurf — mit
einer Zusicherung `len(chat) >= 0`, die nie scheitern kann.)
"""
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

PLUG = "C:/CD/KOHLEKTIV/Plugin - Entwicklung/hackj-plugins/plugins/claude-mind-manager"
PROJ = "C:/Users/HackJ/.claude/projects/C--CD-KOHLEKTIV-Plugin---Entwicklung-Claude-Mind-Manager"
BASH = r"C:\Program Files\Git\bin\bash.exe"
if not os.path.isfile(BASH):
    BASH = r"C:\Program Files\Git\usr\bin\bash.exe"

kandidaten = sorted((os.path.join(PROJ, f) for f in os.listdir(PROJ) if f.endswith(".jsonl")),
                    key=os.path.getsize)
TRANS = kandidaten[1] if len(kandidaten) > 1 else kandidaten[0]
print("  Transkript: %s (%.1f MB)" % (os.path.basename(TRANS)[:8], os.path.getsize(TRANS) / 1048576))

fehler = 0


def pruefe(was, ist, soll):
    global fehler
    ok = ist == soll
    print("    %s %-42s ist=%-6s soll=%s" % ("OK  " if ok else "FEHL", was, ist, soll))
    if not ok:
        fehler += 1


def lauf(name, nur_arbeitsstand_kaputt):
    projekt = tempfile.mkdtemp(prefix="pcz_")
    plugin = tempfile.mkdtemp(prefix="pcp_")
    shutil.copytree(PLUG, plugin, dirs_exist_ok=True)

    if nur_arbeitsstand_kaputt:
        q = plugin + "/references/session_sampler.py"
        s = open(q, encoding="utf-8").read()
        anker = "dump_arbeitsstand(argv[2], argv[3], selbst)"
        if s.count(anker) != 1:
            print("    ABBRUCH: Sabotage-Anker %dx gefunden" % s.count(anker))
            sys.exit(2)
        s = s.replace(anker, 'raise RuntimeError("absichtlich kaputt: nur --arbeitsstand")', 1)
        open(q, "w", encoding="utf-8", newline="\n").write(s)

    eingabe = json.dumps({
        "session_id": "pruefstand-0000",
        "transcript_path": TRANS.replace("/", "\\"),
        "cwd": projekt.replace("/", "\\"),
        "trigger": "auto",
        "hook_event_name": "PreCompact",
    })
    env = dict(os.environ)
    env["CLAUDE_PLUGIN_ROOT"] = plugin.replace("\\", "/")
    env["CLAUDE_PROJECT_DIR"] = projekt.replace("\\", "/")

    r = subprocess.run([BASH, plugin.replace("\\", "/") + "/hooks/pre-compact.sh"],
                       input=eingabe, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=env, timeout=300)

    d = projekt + "/.claude-mind/rescued"
    dateien = sorted(os.listdir(d)) if os.path.isdir(d) else []
    chat = [f for f in dateien if f.endswith("_chat.md")]
    resume = [f for f in dateien if f.endswith("_RESUME.md")]
    arb = [f for f in dateien if f.endswith("_ARBEITSSTAND.json")]
    offen = os.path.join(d, "OPEN")

    print()
    print("  === %s ===" % name)
    print("    Rueckgabewert: %d" % r.returncode)
    for zeile in (r.stdout or "").splitlines()[:6]:
        print("    | " + zeile)

    # Diese vier gelten in BEIDEN Laeufen — das ist der Kern der Zusicherung.
    pruefe("Chat gerettet", len(chat), 1)
    pruefe("Auftrag gesichert", len(resume), 1)
    pruefe("OPEN angelegt", os.path.exists(offen), True)
    pruefe("Hook bricht nicht ab (rc==0)", r.returncode, 0)

    if nur_arbeitsstand_kaputt:
        pruefe("kein halber Arbeitsstand liegt herum", len(arb), 0)
    else:
        pruefe("Arbeitsstand geschrieben", len(arb), 1)
        if arb:
            data = json.load(open(os.path.join(d, arb[0]), encoding="utf-8"))
            print("    Arbeitsstand: %d Entscheidungen · %d Bugs · %d Dateien · %d Constraints"
                  % (data["decisions_total"], data["bugs_total"],
                     data["files_total"], data["constraints_total"]))
            pruefe("alle vier Kategorien haben Eintraege",
                   all(data[k] > 0 for k in ("decisions_total", "bugs_total",
                                             "files_total", "constraints_total")), True)

    if os.path.exists(offen):
        inhalt = open(offen, encoding="utf-8").read()
        pruefe("OPEN nennt path=", "path=" in inhalt, True)
        pruefe("OPEN nennt resume=", "resume=" in inhalt, True)
        pruefe("OPEN nennt arbeitsstand=", "arbeitsstand=" in inhalt, True)
    return projekt


p1 = lauf("HEILER Sampler — alles muss entstehen", False)
p2 = lauf("NUR --arbeitsstand kaputt — Rettung muss TROTZDEM da sein", True)

print()
print("  === %d Abweichung(en) ===" % fehler)
print("  Arbeitsverzeichnisse: %s | %s" % (p1, p2))
sys.exit(1 if fehler else 0)
