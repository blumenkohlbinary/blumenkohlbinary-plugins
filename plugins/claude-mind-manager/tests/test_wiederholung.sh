#!/usr/bin/env bash
# INTRA-DATEI-WIEDERHOLUNG (v5.21.0) — L5 aus PLAN-mind-cleaner-vollstaendig.md,
# urspruenglich B5 des ersten Cleaner-Plans, nie gebaut.
#
# ⛔ WARUM KEINE VORHANDENE PRUEFUNG DAS FINDET: `ablagen()` vergleicht Ablagen
#    GEGENEINANDER. Eine Datei, die dieselbe Sache viermal sagt, ist in jeder
#    dieser Pruefungen unauffaellig — sie ist ja nur EINE Ablage.
#
# ⚠ DER BEFUND HEISST SCHNITT, NICHT DEDUPLIZIERUNG. Eine Datei mit
#   Versionsabschnitten SOLL dieselbe Sache mehrfach nennen; jede Nennung
#   gehoert zu ihrer Version. Was fehlt, ist die Trennung zwischen "gilt heute"
#   und "galt damals". Wer hier dedupliziert, loescht Historie.
#
# ⛔ DER ERSTE ANLAUF MELDETE NULL BEFUNDE ueber 34 echte Dateien und war damit
#    nach messung-vor-glauben.md §1 Gate 3 ein Abbruchgrund, kein Ergebnis.
#    Ursache war NICHT die Schwelle, sondern die Gruppenbildung: transitiv
#    verkettete Absaetze wachsen zu einer grossen Gruppe zusammen, deren
#    gemeinsamer Kern dabei unter die Schwelle faellt. Deshalb enthaelt diese
#    Sammlung eine POSITIVKONTROLLE AN ECHTEM MATERIAL (Fall 8) — konstruierte
#    Faelle bilden nur die eigene Erwartung ab (werkzeuge-zuerst.md, Lehre 3).
#
# ⛔ WINDOWS-PFADE: python bekommt IMMER cygpath -w.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_wiederholung.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
command -v cygpath >/dev/null 2>&1 || { echo "cygpath fehlt" >&2; exit 2; }
RW=$(cygpath -w "$CLAUDE_PLUGIN_ROOT/references")
OK=0; ROT=0
D=$(mktemp -d)

janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

# Helfer als DATEI — keine Anfuehrungszeichen-Hoelle.
cat > "$D/h.py" <<'PYEOF'
import os
import sys
sys.path.insert(0, sys.argv[1])
sys.stdout.reconfigure(encoding="utf-8", newline="")
import cleaner_duplikate as C

datei = sys.argv[2]
was = sys.argv[3]
f = C.wiederholung_in_datei(datei)

if was == "anzahl":
    print(len(f))
elif was == "absaetze":
    print(f[0]["anzahl"] if f else 0)
elif was == "kern":
    print(",".join(f[0]["geteilt"]) if f else "")
elif was == "zurueck":
    print(f[0]["nimmt_zurueck"] if f else "kein-befund")
elif was == "hat":
    # enthaelt der Kern des ersten Befunds den gesuchten Namen?
    print("ja" if f and sys.argv[4] in f[0]["geteilt"] else "nein")
PYEOF

lauf() { python "$(cygpath -w "$D/h.py")" "$RW" "$(cygpath -w "$1")" "$2" "${3:-}" 2>&1 | tr -d '\r'; }

echo "=============================================================================="
echo "  L5 — sagt EINE Datei dieselbe Sache mehr als zweimal?"
echo "=============================================================================="

# --- 1) Der Positivfall: drei gleiche Absaetze ------------------------------
ABS='`pre-compact.sh` schreibt `<ts>_RESUME.md`, `stop.sh` blockt, `prompt-submit.sh` erinnert.'
{ echo "# A"; echo; echo "## v1"; echo; echo "$ABS"; echo;
  echo "## v2"; echo; echo "$ABS"; echo;
  echo "## v3"; echo; echo "$ABS"; } > "$D/drei.md"
echo
echo "  --- Positivfall ---"
janein "3x derselbe Absatz -> genau 1 Befund" 1 "$(lauf "$D/drei.md" anzahl)"
janein "und er nennt alle drei Absaetze" 3 "$(lauf "$D/drei.md" absaetze)"
janein "der Kern nennt pre-compact.sh" ja "$(lauf "$D/drei.md" hat pre-compact.sh)"

# --- 2) Negativkontrollen ---------------------------------------------------
echo
echo "  --- Negativkontrollen ---"
{ echo "# A"; echo; echo "$ABS"; } > "$D/eins.md"
janein "1x -> kein Befund" 0 "$(lauf "$D/eins.md" anzahl)"

{ echo "# A"; echo; echo "$ABS"; echo; echo "$ABS"; } > "$D/zwei.md"
janein "2x -> kein Befund (Aussage + Korrektur ist normal)" 0 "$(lauf "$D/zwei.md" anzahl)"

# ⛔ DER WICHTIGSTE NEGATIVFALL: dieselben ZAHLEN, andere Aussage.
#    Ohne den Anteils-Filter meldet das Werkzeug jede Regeldatei gegen sich
#    selbst, weil dieselben drei Umgebungsvariablen ueberall vorkommen.
{ echo "# A"; echo;
  echo 'Die Schwelle `MIND_SYNC_AT_TOKENS` steht auf 810000 und mahnt.'; echo;
  echo 'Der Zwang `MIND_SYNC_FORCE_TOKENS` steht auf 850000 und blockt das Turn-Ende.'; echo;
  echo 'Der Regler `MIND_AGENT_VOLL_TOKENS` steht auf 600000 und steuert die Agentenzahl.'; } > "$D/zahlen.md"
janein "gleiche Zahlenform, andere Aussage -> kein Befund" 0 "$(lauf "$D/zahlen.md" anzahl)"

# Zu duenne Absaetze
{ echo "# A"; echo; echo 'Nur `eins.sh`.'; echo; echo 'Nur `eins.sh`.'; echo;
  echo 'Nur `eins.sh`.'; } > "$D/duenn.md"
janein "Absaetze unter der Markenzahl -> kein Befund" 0 "$(lauf "$D/duenn.md" anzahl)"

# --- 3) EIN Befund je Gruppe, nicht je Paar ---------------------------------
echo
echo "  --- ein Befund je Gruppe, nicht je Paar ---"
{ echo "# A"; echo; echo "## v1"; echo; echo "$ABS"; echo;
  echo "## v2"; echo; echo "$ABS"; echo;
  echo "## v3"; echo; echo "$ABS"; echo;
  echo "## v4"; echo; echo "$ABS"; } > "$D/vier.md"
# vier Absaetze ergaeben paarweise SECHS Meldungen ueber eine einzige Sache
janein "4 Absaetze -> 1 Befund (nicht 6)" 1 "$(lauf "$D/vier.md" anzahl)"
janein "und er zaehlt vier" 4 "$(lauf "$D/vier.md" absaetze)"

# --- 4) Zuruecknahme wird GEMELDET, nicht unterdrueckt ----------------------
echo
echo "  --- Zuruecknahme meldet, unterdrueckt nicht ---"
{ echo "# A"; echo; echo "$ABS"; echo; echo "$ABS"; echo;
  echo "~~$ABS~~ — seit v5.7.0 anders."; } > "$D/zurueck.md"
janein "Zuruecknahme unterdrueckt den Befund NICHT" 1 "$(lauf "$D/zurueck.md" anzahl)"
janein "und sie wird ausgewiesen" True "$(lauf "$D/zurueck.md" zurueck)"

# --- 5) POSITIVKONTROLLE AN ECHTEM MATERIAL --------------------------------
# ⛔ Woertlich aus `.claude/rules/hooks.md` uebernommen (Zeilen 47ff und 328ff):
#    ZWEI Hook-x-Zweck-Tabellen ueber dieselben vier Hooks, 280 Zeilen
#    auseinander. Genau der Fall, den der erste Anlauf still uebersehen hat.
echo
echo "  --- Positivkontrolle an ECHTEM Material (hooks.md, woertlich) ---"
cat > "$D/echt.md" <<'MDEOF'
# Hook-Regeln

| Hook | Event | Zweck |
|---|---|---|
| `pre-compact.sh` | PreCompact | Backups + Voll-Rettung des Chats + `<ts>_RESUME.md` + Schuld-Merker `OPEN` |
| `prompt-submit.sh` | UserPromptSubmit | Weist auf eine offene Schuld hin — seit v5.5.1 wiederholt |
| `session-start.sh` | SessionStart | Zweites Netz + Herzschlag + Legacy-Merker uebernehmen |
| `stop.sh` | Stop | Erzwingt den Sync: `decision:block`, bis die Schuld beglichen ist |

Dazwischen steht anderer Text ueber `lib.sh` und `hash_project_dir` und `cygpath`,
der mit den Hooks nichts zu tun hat und keine gemeinsamen Marken traegt.

Deshalb `COMPACT-FAELLIG`: `/mind-all` legt ihn an, `stop.sh` blockt, solange er liegt,
`prompt-submit.sh` erinnert als Rueckfallnetz, `pre-compact.sh` verbraucht ihn.

| Hook | neu ab v5.7.0 |
|---|---|
| `prompt-submit.sh` | misst den Kontext, mahnt ab `MIND_SYNC_AT_TOKENS` |
| `stop.sh` | blockt ab `MIND_SYNC_FORCE_TOKENS` — auch ohne Schuld |
| `pre-compact.sh` | schreibt `UEBERGABE` immer; erzeugt keine Schuld bei `sync-stand` |
| `session-start.sh` | uebergibt den Arbeitsstand nach der Kompaktierung |
MDEOF
janein "zwei Hook-Tabellen + Fliesstext -> Befund" 1 "$(lauf "$D/echt.md" anzahl)"
janein "der Kern nennt stop.sh" ja "$(lauf "$D/echt.md" hat stop.sh)"

# --- 6) NEGATIVKONTROLLE AN ECHTEM MATERIAL --------------------------------
# Eine Datei, die viele Namen nennt, aber jeden in EINER Sache. Ohne diesen
# Fall waere Fall 5 nur die halbe Messung.
echo
echo "  --- Negativkontrolle an ECHTEM Material ---"
cat > "$D/sauber.md" <<'MDEOF'
# Environment-Variablen

| Variable | Default | Beschreibung |
|---|---|---|
| MIND_BACKUP_KEEP_COUNT | 3 | Backups pro Typ behalten |
| MIND_SNAPSHOT_KEEP_COUNT | 3 | Snapshots behalten |
| MIND_LOG_MAX_LINES | 500 | Log-Rotation Schwellwert |

## Der Ablauf

Bei `MIND_SYNC_AT_TOKENS` wird gemahnt, bei `MIND_SYNC_FORCE_TOKENS` erzwungen.

## Die Merker

`sync-stand` legt `/mind-all` an, `UEBERGABE` schreibt `pre-compact.sh` immer,
`OPEN` entsteht nur ohne `sync-stand`.

## Rotation

`_mind_rotate()` in `lib.sh` ersetzt das alte `xargs`-Muster.
MDEOF
janein "jede Sache nur einmal -> kein Befund" 0 "$(lauf "$D/sauber.md" anzahl)"

rm -rf "$D"
echo
echo "=============================================================================="
echo "  $OK ok, $ROT rot"
echo "=============================================================================="
[ "$ROT" -eq 0 ]
