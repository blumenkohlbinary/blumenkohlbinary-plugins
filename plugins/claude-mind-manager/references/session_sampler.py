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
import json, re, sys
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
    re.compile(r'laufender?\s+auftrag|dauerauftrag', re.I),
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


def main(argv):
    # --orders: Auftrags-Sicherung (v5.2.0)
    if len(argv) > 1 and argv[1] == "--orders":
        if len(argv) < 4:
            print("usage: session_sampler.py --orders <transcript.jsonl> <out.md>", file=sys.stderr)
            return 2
        dump_orders(argv[2], argv[3])
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
