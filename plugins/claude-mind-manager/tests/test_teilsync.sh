#!/usr/bin/env bash
# TEILSYNC (v5.19.0) — ein abgekuerzter Lauf muss eine Schuld hinterlassen.
#
# ANLASS, dreimal gemessen und in Debug/BEFUNDE.md protokolliert:
#   23.08. 22:21  Claude Mind Manager  Knowledge-Sync-Agents NICHT dispatcht (Kontext)
#   24.08. 23:08  Claude Mind Manager  Knowledge-Sync-Agents NICHT dispatcht (914k)
#   24.08. 23:18  Creator              nur 2 von 4 gefahren (888k)
# Alle drei setzten `sync-stand`, alle drei erzeugten KEINE Schuld, und in allen drei
# Faellen verschwand der ungepruefte Bereich spurlos.
#
# ⛔ Was hier NICHT geprueft wird, weil es nicht geht: dass die Agents wirklich laufen.
#    Geprueft wird, dass ein UNVOLLSTAENDIGER Lauf als solcher erkannt wird und dass die
#    Schuld daraus entsteht.
#
# ⭐ Der wichtigste Fall ist 18: `mind_agent_bilanz` gibt bei "2 dispatcht, beide mit
#    Ergebnis" die Rueckgabe 0 zurueck — "alles gut". Ein NIE dispatchter Agent
#    hinterlaesst keine Zeile und ist unsichtbar. Wer sich auf den Rueckgabewert
#    verlaesst, winkt genau den Creator-Fall durch. Deshalb entscheidet die ZAHL.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_teilsync.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
H="$CLAUDE_PLUGIN_ROOT/hooks"
# shellcheck disable=SC1090
source "$H/lib.sh" 2>/dev/null || { echo "lib.sh nicht ladbar" >&2; exit 2; }
OK=0; ROT=0

janein() { # name erwartung ist
  if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
  else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi
}

neu_projekt() { local d; d=$(mktemp -d); mkdir -p "$d/.claude-mind/rescued"; printf '%s' "$d"; }

# Ein fehlender Befehl (127) darf NICHT als "teil" durchgehen — sonst waere die
# Sammlung auf dem unreparierten Stand teilweise gruen, ohne etwas zu messen.
voll_p() { # datei -> voll|teil|rc<N>
  local rc
  mind_sync_voll "$1" >/dev/null 2>&1; rc=$?
  case $rc in 0) echo voll;; 1) echo teil;; *) echo "rc$rc";; esac
}
frisch_p() { # stand jetzt -> frisch|verbraucht|rc<N>
  local rc
  mind_sync_frisch "$1" "$2" >/dev/null 2>&1; rc=$?
  case $rc in 0) echo frisch;; 1) echo verbraucht;; *) echo "rc$rc";; esac
}
stand() { # projekt umfangzeile-oder-leer [ungepruef]
  { printf 'ts=2026-08-24 23:10:19\ntokens=100000\n'
    [ -n "${2:-}" ] && printf 'umfang=%s\n' "$2"
    [ -n "${3:-}" ] && printf 'ungepruef=%s\n' "$3"
  } > "$1/.claude-mind/rescued/sync-stand"
}

transkript() { # datei
  : > "$1"; local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    printf '{"type":"user","message":{"content":[{"type":"text","text":"Frage %s"}]}}\n' "$i" >> "$1"
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Antwort %s. Entscheidung: Weg A."}],"usage":{"input_tokens":2,"cache_read_input_tokens":1000,"cache_creation_input_tokens":3,"output_tokens":9}}}\n' "$i" >> "$1"
  done
}
precompact() { # projekt logdatei
  printf '{"hook_event_name":"PreCompact","cwd":"%s","session_id":"S1","transcript_path":"%s","trigger":"auto"}' \
    "$1" "$1/t.jsonl" \
    | CLAUDE_PROJECT_DIR="$1" MIND_LOG_FILE="$2" bash "$H/pre-compact.sh" >/dev/null 2>&1
}

echo "=== TEILSYNC ==="
echo "--- A · mind_sync_voll: was ist ein vollstaendiger Merker? ---"

# --- 1 · 4 von 4 Agents -> vollstaendig -----------------------------------
P=$(neu_projekt); stand "$P" "5/5 skills 4/4 agents"
janein "4/4 Agents -> vollstaendig" voll "$(voll_p "$P/.claude-mind/rescued/sync-stand")"
rm -rf "$P"

# --- 2 · 0 von 4 -> Teilsync (mein Lauf, 24.08. 23:08) --------------------
P=$(neu_projekt); stand "$P" "5/5 skills 0/4 agents"
janein "0/4 Agents -> Teilsync" teil "$(voll_p "$P/.claude-mind/rescued/sync-stand")"
rm -rf "$P"

# --- 3 · 2 von 4 -> Teilsync (der Creator-Lauf, 24.08. 23:18) -------------
P=$(neu_projekt); stand "$P" "5/5 skills 2/4 agents"
janein "2/4 Agents -> Teilsync (Creator-Fall)" teil "$(voll_p "$P/.claude-mind/rescued/sync-stand")"
rm -rf "$P"

# --- 4 · auch ein unvollstaendiger SKILL-Teil zaehlt ----------------------
P=$(neu_projekt); stand "$P" "3/5 skills 4/4 agents"
janein "3/5 Skills -> Teilsync" teil "$(voll_p "$P/.claude-mind/rescued/sync-stand")"
rm -rf "$P"

# ===== GEGENKONTROLLEN — ohne sie waere die Sammlung eine Einbahnstrasse =====

# --- 5 · Altbestand ohne umfang= gilt als VOLL ----------------------------
#     Jeder Merker aus v5.18.0 und aelter hat kein umfang=. Wer den als Teilsync
#     wertet, nagelt jede laufende Sitzung fest, die noch einen alten Merker hat.
P=$(neu_projekt); stand "$P" ""
janein "Altbestand ohne umfang= -> vollstaendig" voll "$(voll_p "$P/.claude-mind/rescued/sync-stand")"
rm -rf "$P"

# --- 6 · unparsbares umfang= gilt als VOLL (nagelt nicht fest) ------------
P=$(neu_projekt); stand "$P" "kaputt"
janein "umfang=kaputt -> vollstaendig (fail-safe)" voll "$(voll_p "$P/.claude-mind/rescued/sync-stand")"
rm -rf "$P"

# --- 7 · gar kein Merker ist nicht unsere Frage ---------------------------
P=$(neu_projekt)
janein "kein sync-stand -> vollstaendig" voll "$(voll_p "$P/.claude-mind/rescued/sync-stand")"
rm -rf "$P"

echo "--- B · mind_sync_frisch: schweigt die Mahnung? ---"

# --- 8 · Vollmerker, kleiner Zuwachs -> frisch (GEGENKONTROLLE) -----------
P=$(neu_projekt); stand "$P" "5/5 skills 4/4 agents"
janein "voll + Zuwachs 10k -> frisch (schweigt)" frisch \
       "$(frisch_p "$P/.claude-mind/rescued/sync-stand" 110000)"
rm -rf "$P"

# --- 9 · Teilmerker, GLEICHER Zuwachs -> verbraucht -----------------------
#     Der einzige Unterschied zu Fall 8 ist umfang=. Damit misst der Fall genau
#     die neue Bedingung und nichts sonst.
P=$(neu_projekt); stand "$P" "5/5 skills 0/4 agents"
janein "teil + Zuwachs 10k -> verbraucht (mahnt weiter)" verbraucht \
       "$(frisch_p "$P/.claude-mind/rescued/sync-stand" 110000)"
rm -rf "$P"

# --- 10 · bestehendes Verhalten bleibt: ohne tokens= verbraucht -----------
P=$(neu_projekt)
printf 'ts=x\numfang=5/5 skills 4/4 agents\n' > "$P/.claude-mind/rescued/sync-stand"
janein "voll, aber ohne tokens= -> verbraucht (v5.11.0 unveraendert)" verbraucht \
       "$(frisch_p "$P/.claude-mind/rescued/sync-stand" 110000)"
rm -rf "$P"

# --- 11 · bestehendes Verhalten bleibt: ohne Messung wird nicht gemahnt ---
P=$(neu_projekt); stand "$P" "5/5 skills 4/4 agents"
janein "voll, jetzt-Wert unlesbar -> frisch (keine Zahl ist keine Null)" frisch \
       "$(frisch_p "$P/.claude-mind/rescued/sync-stand" "")"
rm -rf "$P"

echo "--- C · pre-compact.sh: entsteht die Schuld? ---"

# --- 12 · Vollmerker -> KEINE Schuld (bestehendes Verhalten) --------------
P=$(neu_projekt); transkript "$P/t.jsonl"; stand "$P" "5/5 skills 4/4 agents"
LG="$P/log.txt"; : > "$LG"; precompact "$P" "$LG"
[ -f "$P/.claude-mind/rescued/OPEN" ] && A=ja || A=nein
janein "Vollsync -> kein OPEN" nein "$A"
grep -q "keine Schuld angelegt" "$LG" && A=ja || A=nein
janein "Protokoll nennt 'keine Schuld angelegt'" ja "$A"
rm -rf "$P"

# --- 13 · Teilmerker -> Schuld ENTSTEHT ----------------------------------
P=$(neu_projekt); transkript "$P/t.jsonl"
stand "$P" "5/5 skills 0/4 agents" "claude-md,memory,rules,custom-context"
LG="$P/log.txt"; : > "$LG"; precompact "$P" "$LG"
[ -f "$P/.claude-mind/rescued/OPEN" ] && A=ja || A=nein
janein "Teilsync -> OPEN entsteht" ja "$A"
grep -q '^grund=teilsync' "$P/.claude-mind/rescued/OPEN" 2>/dev/null && A=ja || A=nein
janein "OPEN traegt grund=teilsync" ja "$A"
grep -q '^ungepruef=.*custom-context' "$P/.claude-mind/rescued/OPEN" 2>/dev/null && A=ja || A=nein
janein "OPEN nennt die ungeprueften Bereiche" ja "$A"
grep -qi "teilsync" "$LG" && A=ja || A=nein
janein "Protokoll nennt TEILSYNC" ja "$A"
rm -rf "$P"

# --- 14 · der Merker wird in BEIDEN Faellen verbraucht --------------------
#     Ein liegengebliebener sync-stand waere eine Dauersperre (v5.11.0-Lehre).
P=$(neu_projekt); transkript "$P/t.jsonl"; stand "$P" "5/5 skills 0/4 agents"
precompact "$P" "$P/log.txt"
[ -f "$P/.claude-mind/rescued/sync-stand" ] && A=ja || A=nein
janein "Teilsync: sync-stand wird trotzdem verbraucht" nein "$A"
rm -rf "$P"

# --- 15 · gar kein Merker -> Schuld wie bisher, ABER ohne grund=teilsync --
P=$(neu_projekt); transkript "$P/t.jsonl"
LG="$P/log.txt"; : > "$LG"; precompact "$P" "$LG"
[ -f "$P/.claude-mind/rescued/OPEN" ] && A=ja || A=nein
janein "kein sync-stand -> OPEN wie bisher" ja "$A"
grep -q '^grund=teilsync' "$P/.claude-mind/rescued/OPEN" 2>/dev/null && A=ja || A=nein
janein "und NICHT als teilsync markiert" nein "$A"
rm -rf "$P"

# --- 16 · Altbestand: umfang= fehlt -> keine Schuld (Rueckwaertsvertrag) --
P=$(neu_projekt); transkript "$P/t.jsonl"; stand "$P" ""
precompact "$P" "$P/log.txt"
[ -f "$P/.claude-mind/rescued/OPEN" ] && A=ja || A=nein
janein "Merker ohne umfang= -> kein OPEN (Altbestand)" nein "$A"
rm -rf "$P"

echo "--- D · die Bilanz als Belegquelle ---"

# --- 17 · ohne Quittung ist die Rueckgabe 2 (Negativkontrolle) -----------
P=$(neu_projekt)
mind_agent_bilanz "$P" >/dev/null 2>&1; RC=$?
janein "keine Quittung -> Bilanz-Rueckgabe 2" 2 "$RC"
rm -rf "$P"

# --- 18 ⭐ 2 dispatcht, beide mit Ergebnis -> Rueckgabe 0 -----------------
#     DAS ist der Grund, warum die ZAHL entscheiden muss und nicht der
#     Rueckgabewert: ein nie dispatchter Agent hinterlaesst keine Zeile.
#     Ohne diesen Fall haette der Creator-Lauf (2 von 4) als vollstaendig
#     gegolten — genau der Ausfall, den diese Sammlung fangen soll.
P=$(neu_projekt)
mind_agent_quittung_start "$P" >/dev/null 2>&1
mind_agent_dispatch "claude-md" "$P" >/dev/null 2>&1
mind_agent_ergebnis "claude-md" 4096 "$P" >/dev/null 2>&1
mind_agent_dispatch "memory" "$P" >/dev/null 2>&1
mind_agent_ergebnis "memory" 2048 "$P" >/dev/null 2>&1
BIL=$(mind_agent_bilanz "$P" 2>/dev/null); RC=$?
janein "2 dispatcht + 2 Ergebnisse -> Rueckgabe 0 ('alles gut')" 0 "$RC"
D=$(printf '%s' "$BIL" | sed -n 's/.*DISPATCH=\([0-9]*\).*/\1/p' | head -1)
janein "aber DISPATCH= sagt die Wahrheit: 2" 2 "${D:-fehlt}"
rm -rf "$P"

# --- 19 · 4 dispatcht, 2 leer -> Rueckgabe 1 -----------------------------
P=$(neu_projekt)
mind_agent_quittung_start "$P" >/dev/null 2>&1
for b in claude-md memory rules custom-context; do
  mind_agent_dispatch "$b" "$P" >/dev/null 2>&1
done
mind_agent_ergebnis "claude-md" 4096 "$P" >/dev/null 2>&1
mind_agent_ergebnis "memory"   2048 "$P" >/dev/null 2>&1
mind_agent_ergebnis "rules"       0 "$P" >/dev/null 2>&1
mind_agent_ergebnis "custom-context" 0 "$P" >/dev/null 2>&1
mind_agent_bilanz "$P" >/dev/null 2>&1; RC=$?
janein "4 dispatcht, 2 leer -> Rueckgabe 1" 1 "$RC"
rm -rf "$P"

echo "--- E · der Blocktext nennt den Grund ---"

offen() { # projekt [grund] [ungepruef]
  : > "$1/x_chat.md"
  { printf 'path=%s/x_chat.md\nresume=\nts=x\ncompactions=1\nblocks=0\n' "$1"
    [ -n "${2:-}" ] && printf 'grund=%s\nungepruef=%s\n' "$2" "${3:-}"
  } > "$1/.claude-mind/rescued/OPEN"
}
stop_lauf() { # projekt
  printf '{"session_id":"s","transcript_path":"","stop_hook_active":false,"cwd":"%s"}' "$1" \
    | CLAUDE_PROJECT_DIR="$1" MIND_SYNC_FORCE_TOKENS=0 bash "$H/stop.sh" 2>/dev/null
}

# --- 20 · Teilsync-Schuld -> der Blocktext sagt WARUM --------------------
P=$(neu_projekt); offen "$P" teilsync "claude-md,memory"
O=$(stop_lauf "$P")
printf '%s' "$O" | grep -q "TEILSYNC" && A=ja || A=nein
janein "Blocktext nennt TEILSYNC" ja "$A"
printf '%s' "$O" | grep -q "claude-md,memory" && A=ja || A=nein
janein "Blocktext nennt die ungeprueften Bereiche" ja "$A"
# Ein Blocktext, der kein gueltiges JSON mehr ist, blockt gar nicht — das ist
# derselbe Fehler wie v5.7.6 (Klartext neben JSON im selben stdout).
printf '%s' "$O" | grep -q '"decision"' && A=ja || A=nein
janein "Ausgabe bleibt ein gueltiger Block" ja "$A"
rm -rf "$P"

# --- 21 · GEGENKONTROLLE: normale Schuld -> KEIN Teilsync-Text -----------
#     Ohne diesen Fall koennte der Text immer erscheinen und die Pruefung
#     waere blind dafuer.
P=$(neu_projekt); offen "$P"
O=$(stop_lauf "$P")
printf '%s' "$O" | grep -q "TEILSYNC" && A=ja || A=nein
janein "normale Schuld -> KEIN Teilsync-Text" nein "$A"
printf '%s' "$O" | grep -q '"decision"' && A=ja || A=nein
janein "und sie blockt trotzdem" ja "$A"
rm -rf "$P"

echo
echo "  gruen: $OK   rot: $ROT"
[ "$ROT" -eq 0 ] || exit 1
