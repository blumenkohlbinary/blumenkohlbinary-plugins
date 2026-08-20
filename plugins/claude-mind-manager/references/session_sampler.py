#!/usr/bin/env python3
"""Session-Auszug fuer mind-update Step 3.5 — 3-stufiges Sampling.

NEU v5.0.0 (Befund 9): Ausgelieferte DATEI statt Heredoc nach /tmp.
Grund: der Heredoc-Weg schrieb das Skript zur Laufzeit nach /tmp und war auf
Windows/Git-Bash unzuverlaessig (Pfade mit '&', Leerzeichen, Umlauten).
Zwei Modi:
  python session_sampler.py <transcript.jsonl> <out.json>            # Sampling (Step 3.5)
  python session_sampler.py --full <transcript.jsonl> <out.md>       # VOLL-RETTUNG (v5.1.0)

--full (NEU v5.1.0): rettet das GESAMTE Gespraech vor einer Kompaktierung — kein Pre-Filter,
kein 300er-Deckel, keine 500-Zeichen-Kuerzung. Nur USER+ASSISTANT-Text, chronologisch, als
lesbares Markdown. Tool-Aufrufe/-Ergebnisse bleiben draussen: die sind das Volumen (12 MB
Roh-JSONL vs ~350 KB reines Gespraech), nicht der Inhalt.

Stage 1 Pre-Filter : Events mit Entscheidungs-/Fehler-/Architektur-/Constraint-Markern
Stage 2 Stratified : bei >300 Treffern -> 5 Buckets, Top-60 je Bucket nach Score
Stage 3 Hint       : bei >1000 Events -> long_session_hint (Skill warnt dann)

Sprachabdeckung (Befund 9): Die Musterliste war ueberwiegend englisch
(decision|bug|error|install|deploy). In einem deutschsprachigen Projekt untersampelt
das massiv — der groesste Einzelbefund eines echten Laufs (ein kompletter
Hardware-Zusammenbau, in keiner Regeldatei dokumentiert) haette diesen Filter NICHT
passiert. Deshalb: deutsche Begriffe gleichberechtigt + USER-Aussagen hoeher gewichtet
(was der Mensch sagt, ist fuer den Knowledge-Sync wertvoller als Assistant-Prosa).
"""
import json, os, re, sys
from pathlib import Path

# --- Stage-1-Muster: EN + DE gleichberechtigt ---
RELEVANT_PATTERNS = [
    # Entscheidungen / Architektur
    re.compile(r'\b(decision|architekt|pattern|wir entscheiden|wir nutzen|wir machen|'
               r'entscheid|festgelegt|stattdessen|lieber|besser so|umgestellt)\b', re.I),
    # Fehler / Korrekturen
    re.compile(r'\b(bug|error|fail|crash|fix|tool_use_error|cancelled|'
               r'fehler|falsch|kaputt|geht nicht|korrigiert|behoben|klappt nicht)\b', re.I),
    # Constraints / Regeln
    re.compile(r'\b(MUST|NEVER|niemals|immer|wichtig|kein push|'
               r'soll|muss|darf nicht|pflicht|regel|vorgabe)\b', re.I),
    # Versionen
    re.compile(r'\bversion\s+(?:v?\d+\.\d+|\d+\.\d+\.\d+)|v\d+\.\d+\.\d+', re.I),
    # Build / Release / Betrieb
    re.compile(r'\b(install|deploy|release|commit|push|merge|'
               r'gebaut|installiert|eingerichtet|aufgesetzt|konfiguriert)\b', re.I),
    # Belege / Verifikation (oft der Kern eines Wissens-Gaps)
    re.compile(r'\b(belegt|gemessen|verifiziert|geprueft|ungepruef|nachgewiesen|'
               r'getestet|reproduziert)\b', re.I),
]

# USER-Aussagen zaehlen mehr: der Mensch nennt Ziele, Entscheidungen, Korrekturen.
USER_WEIGHT = 2


def dump_full(jsonl_path, out_path):
    """Voll-Rettung: jedes USER/ASSISTANT-Text-Event, ungekuerzt, chronologisch."""
    import datetime
    rows, n_user, n_asst = [], 0, 0
    with open(jsonl_path, encoding='utf-8', errors='replace') as f:
        for lineno, line in enumerate(f, 1):
            try:
                obj = json.loads(line.strip())
            except json.JSONDecodeError:
                continue
            if obj.get('isSidechain') or obj.get('type') == 'queue-operation':
                continue
            msg = obj.get('message', {}) or {}
            content = msg.get('content')
            text, role = "", ""
            if obj.get('type') == 'user' and isinstance(content, str):
                text, role = content, "USER"
            elif obj.get('type') == 'assistant' and isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get('type') == 'text':
                        text += block.get('text', '') + "\n"
                role = "ASSISTANT"
            if not text.strip():
                continue
            ts = obj.get('timestamp', '')
            rows.append((lineno, role, ts, text.rstrip()))
            if role == "USER": n_user += 1
            else: n_asst += 1

    out = ["# Geretteter Chat (Voll-Rettung vor Kompaktierung)",
           "",
           f"- Quelle: `{jsonl_path}`",
           f"- Beitraege: {len(rows)}  ({n_user} USER / {n_asst} ASSISTANT)",
           f"- Gerettet: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
           "",
           "> Vollstaendig und ungekuerzt. Tool-Aufrufe/-Ergebnisse sind bewusst nicht enthalten.",
           "", "---", ""]
    for lineno, role, ts, text in rows:
        out.append(f"## [{lineno}] {role}" + (f" — {ts}" if ts else ""))
        out.append("")
        out.append(text)
        out.append("")
    Path(out_path).write_text("\n".join(out), encoding='utf-8')
    print(f"OK-FULL: {len(rows)} Beitraege ({n_user} USER / {n_asst} ASSISTANT) -> {out_path}")
    return len(rows)


"""--- Dauerauftrags-Marker (v5.2.0) ---
Formulierungen, die einen laufenden Auftrag ueber die Kompaktierung hinweg signalisieren.
Ein erkannter Marker heisst: der Sync ist NACHRANGIG, die Arbeit hat Vorrang.
"""
STANDING_ORDER_PATTERNS = [
    re.compile(r'arbeite\s+autonom|mach\s+(komplett\s+)?autonom|autonom\s+weiter', re.I),
    re.compile(r'mach\s+(weiter|durch)|nicht\s+stoppen|weiterarbeiten', re.I),
    re.compile(r'bis\s+(sp(ae|ä)ter|es\s+fertig|alles\s+fertig|du\s+fertig)', re.I),
    re.compile(r'ich\s+bin\s+(nicht\s+da|weg)|bin\s+gleich\s+wieder', re.I),
    # v5.2.1 ENTFERNT: r'laufender?\s+auftrag|dauerauftrag'
    # Das sind META-Woerter — sie stehen in einer FRAGE ueber Dauerauftraege genauso wie in
    # einem. Gemessen 2026-08-16: der Nutzer fragte "was ist wenn er in einem dauerauftrag
    # ist", und RESUME.md meldete daraufhin "Moeglicher Dauerauftrag". Was bleibt, sind
    # ANWEISUNGEN im Imperativ — die sagt niemand beilaeufig ueber sich selbst.
]


def dump_orders(jsonl_path, out_path, keep=5, min_len=30, max_chars=800):
    """Die letzten substanziellen USER-Auftraege sichern (v5.2.0).

    Warum deterministisch und nicht 'Claude merkt es sich': Der PreCompact-Hook hat das
    Transkript. Er kann die Auftraege HERAUSZIEHEN, bevor sie wegkompaktiert werden — das
    haengt an keiner Entscheidung eines Modells.

    min_len filtert Bestaetigungen ('ok', 'ja mach', 'passt') — das sind keine Auftraege.
    """
    import datetime
    users = []
    with open(jsonl_path, encoding='utf-8', errors='replace') as f:
        for line in f:
            try:
                obj = json.loads(line.strip())
            except json.JSONDecodeError:
                continue
            if obj.get('isSidechain') or obj.get('type') != 'user':
                continue
            c = (obj.get('message') or {}).get('content')
            if not isinstance(c, str):
                continue
            txt = c.strip()
            # Harness-Rauschen raus: Slash-Command-Wrapper, Hook-/Systemblöcke
            if txt.startswith('<') or '<command-name>' in txt or '<local-command' in txt:
                continue
            # ⛔ SELBST-KONTAMINATION (Fix v5.2.1, gemessen 2026-08-16)
            # Die eigenen Hooks speisen Text als Nutzer-Kontext ein — darin steht woertlich
            # "WEITERARBEITEN" und "Laeuft der Auftrag oben noch?". Beim naechsten Lauf las der
            # Marker-Scan genau das zurueck und meldete "Moeglicher Dauerauftrag". Das Plugin
            # zitierte sich selbst und hielt es fuer einen Befund — eine Rueckkopplung, die mit
            # jeder Kompaktierung stabiler geworden waere.
            # Eigene Einspeisungen sind KEINE Nutzer-Auftraege und fliegen komplett raus.
            if '[Mind Manager]' in txt or 'Auftrags-Merker' in txt:
                continue
            if len(txt) < min_len:
                continue
            users.append(txt)

    recent = users[-keep:][::-1]          # juengste zuerst
    # BELEG statt Behauptung (Fehlalarm-Fix): den GEFUNDENEN WORTLAUT sammeln, nicht nur
    # "erkannt: ja". Gemessen 2026-08-16: ein einmaliges "mach weiter" loeste faelschlich
    # "DAUERAUFTRAG ERKANNT" aus. Mit Zitat kann der Leser selbst urteilen.
    hits = []
    for u in users[-15:]:
        for p in STANDING_ORDER_PATTERNS:
            m = p.search(u)
            if m and m.group(0).lower() not in [h.lower() for h in hits]:
                hits.append(m.group(0))
    standing = hits[:3]

    out = ["# Unterbrochener Auftrag (vor der Kompaktierung gesichert)",
           "",
           f"- Gesichert: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
           f"- Quelle: `{jsonl_path}`",
           ""]
    if standing:
        zitate = " · ".join(f'"{h}"' for h in standing)
        out += ["## Moeglicher Dauerauftrag — BELEG (kein Urteil)",
                "",
                f"Im Verlauf stehen diese Formulierungen: {zitate}",
                "",
                "Das KANN ein durchgehender Auftrag sein — oder eine einmalige Fortsetzungs-",
                "Anweisung (ein blosses \"mach weiter\" loeste hier schon einen Fehlalarm aus).",
                "**Pruefe am Auftragstext unten, ob wirklich noch etwas laeuft.** Wenn ja:",
                "der laufende Auftrag hat Vorrang vor dem Context-Sync.", ""]
    out += ["## Zuletzt beauftragt (juengste zuerst)", ""]
    if recent:
        for i, u in enumerate(recent, 1):
            t = u if len(u) <= max_chars else u[:max_chars] + " […]"
            out.append(f"{i}. {t}")
            out.append("")
    else:
        out += ["_keine substanzielle Nutzer-Anweisung im Verlauf gefunden_", ""]
    out += ["---",
            "> Vollstaendiger Wortlaut: die Chat-Rettung `*_chat.md` im selben Ordner."]

    Path(out_path).write_text("\n".join(out), encoding='utf-8')
    print(f"OK-ORDERS: {len(recent)} Auftraege gesichert"
          f"{' | DAUERAUFTRAG erkannt' if standing else ''} -> {out_path}")
    return len(recent)



# ---------------------------------------------------------------------------
# --arbeitsstand (NEU v5.6.0): die 4 Kategorien fuer den Arbeitsstand.
#
# Herkunft: die Muster und die Klassifikation standen bis v5.5.2 als HEREDOC in
# skills/mind-compact/SKILL.md und wurden zur Laufzeit nach /tmp geschrieben.
# Das ist genau der Weg, den "Befund 9" (siehe Kopf dieser Datei) fuer diese
# Datei bereits als Windows-fragil verworfen hat.
#
# ⛔ Die Ausgabe ist BYTE-GLEICH zur alten Heredoc-Fassung — mind-compact rendert
#    sie mit seinem eigenen Renderer weiter. Wer hier etwas an der JSON-Struktur
#    aendert, bricht mind-compact Step 5, ohne dass eine Fehlermeldung erscheint.
TOP_N = 10
LONG_SESSION_TOP_N = 5
LONG_SESSION_THRESHOLD = 500

DECISION_PATTERNS_ASSISTANT = [
    re.compile(r'\bdecision\s*:', re.IGNORECASE),
    re.compile(r'\barchitekt(?:ur)?\b', re.IGNORECASE),
    re.compile(r'\bpattern\s*:', re.IGNORECASE),
    re.compile(r'\bwir\s+(?:entscheiden|nehmen\s+.{0,30}\s+statt|nutzen\s+.{0,30}\s+statt)', re.IGNORECASE),
    re.compile(r'\binstead\s+of\b', re.IGNORECASE),
    re.compile(r'\bwir\s+machen\s+.{0,40}?\b(?:weil|because|denn)\b', re.IGNORECASE),
    re.compile(r'\bentschieden\s*:', re.IGNORECASE),
]

# ⛔ KEIN Bug im Projekt, sondern Transport/Infrastruktur (NEU v5.7.0).
#    Gemessen: 'API Error: Connection lost mid-response' stand als 'aktiver Bug' im
#    Arbeitsstand. Wer das nach einer Kompaktierung liest, sucht einen Fehler, den es
#    im Projekt nie gab.
NICHT_BUG = (
    'api error', 'connection lost', 'connection error', 'request timed out',
    'rate limit', 'overloaded', 'stream error', 'server is temporarily',
    'the response above may be incomplete',
)

# Satzenden fuer den Schnitt: Punkt/Ausrufe-/Fragezeichen/Doppelpunkt + Leerraum, oder Umbruch
_SATZ_ENDE = re.compile(r'[.!?:](?=\s|$)|\n')
_MAX_DEHNUNG = 200      # so weit darf ein Rand hoechstens wandern, um eine Grenze zu finden


def _schnitt(text, a, e, kappe):
    """Fensterraender auf SATZGRENZEN ziehen, statt mitten im Wort zu kappen.

    Vorher: text[a:e][:kappe] — 77 % der Eintraege begannen dadurch mitten im Satz.
    Findet sich in Reichweite keine Satzgrenze, wird auf die naechste WORTgrenze
    ausgewichen; eine harte Kappung bekommt ein sichtbares Auslassungszeichen.
    """
    letzte = None
    for m in _SATZ_ENDE.finditer(text[:a]):
        letzte = m
    if letzte is not None and a - letzte.end() <= _MAX_DEHNUNG:
        a = letzte.end()
    else:
        while a > 0 and not text[a - 1].isspace():
            a -= 1
    m2 = _SATZ_ENDE.search(text, e)
    if m2 is not None and m2.end() - e <= _MAX_DEHNUNG:
        e = m2.end()
    else:
        while e < len(text) and not text[e].isspace():
            e += 1
    s = re.sub(r'\s+', ' ', text[a:e].replace('\n', ' ')).strip()
    if len(s) > kappe:
        s = s[:kappe].rsplit(' ', 1)[0] + '…'
    return s

BUG_PATTERNS = [
    re.compile(r'tool_use_error', re.IGNORECASE),
    re.compile(r'\bcancelled\s*:', re.IGNORECASE),
    re.compile(r'\bcrash(?:ed|t)?\b', re.IGNORECASE),
    re.compile(r'\bfix\s*:', re.IGNORECASE),
    re.compile(r'\bbug\s+#\d+', re.IGNORECASE),
    re.compile(r'\berror\s*:\s', re.IGNORECASE),
    re.compile(r'\bfailed\s*:', re.IGNORECASE),
    re.compile(r'Traceback', re.IGNORECASE),
]

# Constraints: NUR USER, mind. 10 Zeichen Kontext-Match
CONSTRAINT_PATTERNS_USER = [
    re.compile(r'\bMUST\b.{10,}', re.IGNORECASE),
    re.compile(r'\bNEVER\b.{10,}', re.IGNORECASE),
    re.compile(r'\bniemals\b.{10,}', re.IGNORECASE),
    re.compile(r'\bimmer\b.{10,}', re.IGNORECASE),
    re.compile(r'\bwichtig\b.{10,}', re.IGNORECASE),
    re.compile(r'\bkein(?:e[rn]?)?\s+push\b', re.IGNORECASE),
    re.compile(r'\bnicht\s+.{0,30}(?:committen|pushen|loeschen|ueberschreiben)', re.IGNORECASE),
]


def dump_arbeitsstand(jsonl_path, out_path, self_cmd="mind-compact"):
    """4-Kategorie-Extraktion -> JSON. Aufrufer rendern selbst.

    self_cmd steuert die Self-Exclusion: mind-compact schliesst seinen eigenen
    Aufruf aus, pre-compact.sh braucht das nicht (uebergibt None).
    """
    self_re = (re.compile(r'<command-name>/(?:[^/<]+:)?' + re.escape(self_cmd) +
                          r'</command-name>') if self_cmd else None)
    exclude_from = None
    if self_re:
        with open(jsonl_path, encoding='utf-8', errors='replace') as f:
            for lineno, line in enumerate(f, 1):
                if self_re.search(line):
                    exclude_from = lineno

    user_texts, assistant_texts = [], []
    modified_files = set()
    total_events = parse_errors = 0

    with open(jsonl_path, encoding='utf-8', errors='replace') as f:
        for lineno, line in enumerate(f, 1):
            if exclude_from and lineno >= exclude_from:
                break
            try:
                obj = json.loads(line.strip())
            except json.JSONDecodeError:
                parse_errors += 1
                continue
            if obj.get('isSidechain') or obj.get('type') == 'queue-operation':
                continue
            msg = obj.get('message', {}) or {}
            content = msg.get('content')
            if obj.get('type') == 'user' and isinstance(content, str):
                user_texts.append((lineno, content))
                total_events += 1
            elif obj.get('type') == 'assistant' and isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    btype = block.get('type')
                    if btype == 'text':
                        assistant_texts.append((lineno, block.get('text', '')))
                        total_events += 1
                    elif btype == 'tool_use' and block.get('name') in ('Write', 'Edit', 'NotebookEdit'):
                        inp = block.get('input', {})
                        if isinstance(inp, dict):
                            fp = inp.get('file_path') or inp.get('notebook_path')
                            if fp:
                                modified_files.add(fp)

    top_n = LONG_SESSION_TOP_N if total_events > LONG_SESSION_THRESHOLD else TOP_N

    def _sammle(quellen, muster, vor, nach, kappe, mit_quelle=False):
        treffer = []
        for eintrag in quellen:
            src, lineno, text = eintrag if mit_quelle else ('', eintrag[0], eintrag[1])
            for p in muster:
                m = p.search(text)
                if m:
                    a = max(0, m.start() - vor)
                    e = min(len(text), m.end() + nach)
                    schnipsel = _schnitt(text, a, e, kappe)
                    if any(w in schnipsel.lower() for w in NICHT_BUG):
                        break          # Transportmeldung, kein Projekt-Bug
                    treffer.append((lineno, schnipsel, src) if mit_quelle else (lineno, schnipsel))
                    break
        treffer.sort(key=lambda x: -x[0])
        return treffer[:top_n], len(treffer)

    decisions, dec_total = _sammle(assistant_texts, DECISION_PATTERNS_ASSISTANT, 50, 150, 200)
    alle = ([('U', l, t) for (l, t) in user_texts] +
            [('A', l, t) for (l, t) in assistant_texts])
    bugs, bug_total = _sammle(alle, BUG_PATTERNS, 30, 120, 180, mit_quelle=True)
    constraints, con_total = _sammle(user_texts, CONSTRAINT_PATTERNS_USER, 20, 80, 160)

    # ⛔ Existenz pruefen (NEU v5.7.0). Gemessen 20.08.2026: von 57 genannten Dateien
    #    existierten nur noch 29 — der Rest waren Scratchpad- und Zwischenstaende. Eine
    #    Uebergabe, die zur Haelfte ins Leere zeigt, kostet mehr Zeit als sie spart.
    _vorhanden = [f for f in sorted(modified_files) if os.path.exists(f)]
    files_weg = len(modified_files) - len(_vorhanden)
    files_list = _vorhanden[:top_n * 3]

    result = {
        "total_events": total_events,
        "parse_errors": parse_errors,
        "self_exclusion_line": exclude_from,
        "top_n": top_n,
        "long_session": total_events > LONG_SESSION_THRESHOLD,
        "decisions": [{"line": l, "text": t} for (l, t) in decisions],
        "decisions_total": dec_total,
        "bugs": [{"line": l, "text": t, "src": s} for (l, t, s) in bugs],
        "bugs_total": bug_total,
        "files": files_list,
        "files_total": len(modified_files),
        "files_weg": files_weg,
        "constraints": [{"line": l, "text": t} for (l, t) in constraints],
        "constraints_total": con_total,
    }
    Path(out_path).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print("OK-ARBEITSSTAND: %d events, %d Entscheidungen / %d Bugs / %d Dateien / %d Constraints -> %s"
          % (total_events, dec_total, bug_total, len(modified_files), con_total, out_path))
    return total_events


def main(argv):
    # --orders: Auftrags-Sicherung (v5.2.0)
    if len(argv) > 1 and argv[1] == "--orders":
        if len(argv) < 4:
            print("usage: session_sampler.py --orders <transcript.jsonl> <out.md>", file=sys.stderr)
            return 2
        dump_orders(argv[2], argv[3])
        return 0

    # --arbeitsstand: 4-Kategorie-Extraktion (v5.6.0)
    # ⛔ VOR dem Default-Check und mit return — faellt der Zweig durch, landet der
    #    Aufruf im positional-Zweig und schreibt die falsche Datei.
    if len(argv) > 1 and argv[1] == "--arbeitsstand":
        if len(argv) < 4:
            print("usage: session_sampler.py --arbeitsstand <transcript.jsonl> <out.json> [self_cmd]",
                  file=sys.stderr)
            return 2
        selbst = argv[4] if len(argv) > 4 else "mind-compact"
        if selbst in ("-", "none", "None"):
            selbst = None
        dump_arbeitsstand(argv[2], argv[3], selbst)
        return 0

    # --full: Voll-Rettung (v5.1.0)
    if len(argv) > 1 and argv[1] == "--full":
        if len(argv) < 4:
            print("usage: session_sampler.py --full <transcript.jsonl> <out.md>", file=sys.stderr)
            return 2
        return 0 if dump_full(argv[2], argv[3]) > 0 else 1

    if len(argv) < 3:
        print("usage: session_sampler.py <transcript.jsonl> <out.json>", file=sys.stderr)
        return 2
    jsonl_path, out_path = argv[1], argv[2]

    # Self-Exclusion: den laufenden mind-update-Aufruf nicht mitsampeln
    self_re = re.compile(r'<command-name>/(?:[^/<]+:)?mind-(?:update|all)</command-name>')
    exclude_from = None
    with open(jsonl_path, encoding='utf-8', errors='replace') as f:
        for lineno, line in enumerate(f, 1):
            if self_re.search(line):
                exclude_from = lineno

    events, total = [], 0
    with open(jsonl_path, encoding='utf-8', errors='replace') as f:
        for lineno, line in enumerate(f, 1):
            if exclude_from and lineno >= exclude_from:
                continue
            try:
                obj = json.loads(line.strip())
            except json.JSONDecodeError:
                continue
            if obj.get('isSidechain') or obj.get('type') == 'queue-operation':
                continue
            msg = obj.get('message', {}) or {}
            content = msg.get('content')
            text, role = "", ""
            if obj.get('type') == 'user' and isinstance(content, str):
                text, role = content, "USER"
            elif obj.get('type') == 'assistant' and isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get('type') == 'text':
                        text += block.get('text', '') + "\n"
                role = "ASSISTANT"
            if not text:
                continue
            total += 1
            score = sum(1 for p in RELEVANT_PATTERNS if p.search(text))
            if role == "USER":
                score *= USER_WEIGHT
            if score > 0:
                events.append((lineno, role, text[:500], score))

    # Stage 2: stratifiziert, damit die Mitte langer Sessions nicht verloren geht
    if len(events) > 300:
        events.sort(key=lambda x: x[0])
        b = len(events) // 5
        buckets = [events[i * b:(i + 1) * b] for i in range(5)]
        buckets[-1] = events[4 * b:]
        selected = []
        for bucket in buckets:
            bucket.sort(key=lambda x: -x[3])
            selected.extend(bucket[:60])
        events = selected

    out = {
        "total_events": total,
        "filtered_events": len(events),
        "long_session_hint": total > 1000,
        "self_exclusion_line": exclude_from,
        "user_weight": USER_WEIGHT,
        "sample": [{"line": l, "role": r, "text": t} for (l, r, t, _) in events],
    }
    Path(out_path).write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f"OK: {total} total -> {len(events)} sampled")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
