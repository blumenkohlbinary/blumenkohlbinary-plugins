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

# ⛔ v5.32.1: WURZEL AUS DER UMGEBUNG. Sie war fest auf den QUELLBAUM
#    verdrahtet — dieselbe Luecke, die v5.7.5 bei drei .sh-Sammlungen behoben
#    hat. 42 von 46 Sammlungen machen es richtig, diese lief nie am gebauten
#    Paket, entgegen ihrer eigenen README.
PLUG = os.environ.get("CLAUDE_PLUGIN_ROOT") or \
    "C:/CD/KOHLEKTIV/Plugin - Entwicklung/hackj-plugins/plugins/claude-mind-manager"
BASH = r"C:\Program Files\Git\bin\bash.exe"
if not os.path.isfile(BASH):
    BASH = r"C:\Program Files\Git\usr\bin\bash.exe"


def _fixture(pfad, mit_bugs=True):
    """Ein synthetisches Transkript — known-issues #13.

    ⛔ WARUM NICHT DAS ECHTE: die Sammlung las bis v5.32.0 das LAUFENDE
       Transkript und verlangte Eintraege in allen vier Kategorien. Hat die
       Sitzung gerade keine offenen Bugs, ist sie rot — ohne dass sich eine
       Zeile Code geaendert haette. Ein Pruefergebnis, das vom Gespraechsverlauf
       abhaengt, kann 'der Hook ist kaputt' nicht von 'heute keine Bugs'
       unterscheiden.
    ⛔ UND WARUM NICHT ALS DATEI IM REPO: `hackj-plugins` liegt auf GitHub. Ein
       Auszug aus dem echten Transkript waere fremder Gespraechsinhalt in einem
       oeffentlichen Repo. Die Fixture entsteht deshalb zur Laufzeit.
    ⚠ Die Zeilen sind nach den Mustern des Samplers geschrieben
      (DECISION_PATTERNS_ASSISTANT / BUG_PATTERNS / CONSTRAINT_PATTERNS_USER)
      und im Format, das er liest.
    """
    def user(t):
        return {"type": "user", "message": {"content": t}}

    def text(t):
        return {"type": "assistant",
                "message": {"content": [{"type": "text", "text": t}]}}

    def schreibt(fp):
        return {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Write", "input": {"file_path": fp}}]}}

    zeilen = [
        # CONSTRAINTS (aus USER-Text): niemals / immer / wichtig / kein push
        user("Wichtig: die Backups gehen immer nach _claude_backups, bevor "
             "irgendetwas geloescht wird."),
        user("NEVER git push aus diesem Workspace — hier gibt es kein Remote."),
        user("Niemals eine Pruefsammlung anfassen, damit der eigene Bau gruen wird."),
        # DECISIONS (aus ASSISTANT-Text): entschieden / stattdessen / architekt
        text("Wir haben entschieden, den Zaehler in lib.sh zu halten statt in "
             "jedem Hook einzeln — eine Stelle, ein Verhalten."),
        text("Stattdessen laeuft die Normalisierung beim LESEN, nicht beim "
             "Schreiben: der rohe Pfad bleibt als Datum erhalten."),
        text("Architektur: der Waechter meldet, er sperrt nicht. Sperren "
             "gehoert in einen eigenen Schritt mit eigener Freigabe."),
        # FILES: zwei Schreibzugriffe
        schreibt("C:/CD/KOHLEKTIV/beispiel/eine-datei.md"),
        schreibt("C:/CD/KOHLEKTIV/beispiel/zweite-datei.py"),
    ]
    if mit_bugs:
        # BUGS (aus BEIDEN Quellen): Traceback / error: / fix:
        zeilen += [
            text("Traceback (most recent call last): ValueError in "
                 "cleaner_tor.py Zeile 118 — die Marke war leer."),
            user("error: der Hook bricht mit Rueckgabewert 2 ab, sobald jq fehlt."),
            text("fix: den Rueckgabewert vor der Pipe abgreifen, sonst "
                 "verschluckt ihn tail."),
        ]
    with io.open(pfad, "w", encoding="utf-8", newline="\n") as fh:
        for z in zeilen:
            fh.write(json.dumps(z, ensure_ascii=False) + "\n")
    return pfad


_FIXDIR = tempfile.mkdtemp(prefix="precompact_fix_")
TRANS = _fixture(os.path.join(_FIXDIR, "fixture.jsonl"), mit_bugs=True)
TRANS_OHNE = _fixture(os.path.join(_FIXDIR, "ohne_bugs.jsonl"), mit_bugs=False)
print("  Fixture: %d Zeilen (synthetisch, nicht das echte Transkript)"
      % sum(1 for _ in open(TRANS, encoding="utf-8")))

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

# --- NEGATIVKONTROLLE (v5.32.1) ---------------------------------------------
# ⛔ OHNE SIE WAERE DIE FIXTURE WERTLOS. Eine Eingabe, die man so lange anpasst,
#    bis der Test gruen ist, beweist nur, dass man sie angepasst hat. Der Beleg,
#    dass der Sampler die EINGABE wirklich liest, ist ein zweiter Durchgang mit
#    einer Fixture OHNE Bug-Muster.
# ⚠ Und die drei ANDEREN Kategorien muessen dabei UNVERAENDERT bleiben — sonst
#   hat sich mehr geaendert als die eine Sache, und der Vergleich sagt nichts.
print()
print("  === NEGATIVKONTROLLE — Fixture OHNE Bug-Muster ===")
_a1 = os.path.join(_FIXDIR, "stand_mit.json")
_a0 = os.path.join(_FIXDIR, "stand_ohne.json")
for _quelle, _ziel in ((TRANS, _a1), (TRANS_OHNE, _a0)):
    subprocess.run([sys.executable, os.path.join(PLUG, "references", "session_sampler.py"),
                    "--arbeitsstand", _quelle, _ziel, "-"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if os.path.exists(_a1) and os.path.exists(_a0):
    _mit = json.load(open(_a1, encoding="utf-8"))
    _ohne = json.load(open(_a0, encoding="utf-8"))
    print("    mit Bugs : %d Entscheidungen · %d Bugs · %d Dateien · %d Constraints"
          % (_mit["decisions_total"], _mit["bugs_total"],
             _mit["files_total"], _mit["constraints_total"]))
    print("    ohne Bugs: %d Entscheidungen · %d Bugs · %d Dateien · %d Constraints"
          % (_ohne["decisions_total"], _ohne["bugs_total"],
             _ohne["files_total"], _ohne["constraints_total"]))
    pruefe("⭐ mit Bug-Mustern werden Bugs gefunden", _mit["bugs_total"] > 0, True)
    pruefe("⛔ OHNE Bug-Muster: bugs_total ist 0", _ohne["bugs_total"], 0)
    pruefe("⚠ die anderen drei bleiben gleich",
           (_ohne["decisions_total"], _ohne["files_total"], _ohne["constraints_total"])
           == (_mit["decisions_total"], _mit["files_total"], _mit["constraints_total"]),
           True)
else:
    # ⛔ Ein uebersprungener Fall darf NIE wie ein bestandener aussehen.
    pruefe("Negativkontrolle konnte laufen (Sampler erreichbar)", False, True)

print()
print("  === %d Abweichung(en) ===" % fehler)
print("  Arbeitsverzeichnisse: %s | %s" % (p1, p2))
sys.exit(1 if fehler else 0)
