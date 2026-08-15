#!/usr/bin/env python3
"""Session-Auszug fuer mind-update Step 3.5 — 3-stufiges Sampling.

NEU v5.0.0 (Befund 9): Ausgelieferte DATEI statt Heredoc nach /tmp.
Grund: der Heredoc-Weg schrieb das Skript zur Laufzeit nach /tmp und war auf
Windows/Git-Bash unzuverlaessig (Pfade mit '&', Leerzeichen, Umlauten).
Aufruf:  python session_sampler.py <transcript.jsonl> <out.json>

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


def main(argv):
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
