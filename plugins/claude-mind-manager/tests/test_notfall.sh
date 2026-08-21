#!/usr/bin/env bash
# MIND_NOTFALL_TOKENS (v5.7.7) — die Schwelle, die nichts stumm schalten kann.
#
# Anlass: Der Nutzer hat die Auto-Kompaktierung abgeschaltet. Damit feuert pre-compact.sh
# nur noch bei einem von Hand getippten /compact — und er ist der einzige Hook, der Chat,
# Auftrag und Arbeitsstand rettet. Wer die Aufforderung bei 850 000 ueberliest, faehrt
# ohne Netz gegen die Wand des Kontextfensters.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_notfall.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
H="$CLAUDE_PLUGIN_ROOT/hooks"
OK=0; ROT=0

janein() { # name erwartung ist
  if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
  else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi
}

projekt() { local d; d=$(mktemp -d); mkdir -p "$d/.claude-mind/rescued"; printf '%s' "$d"; }

transkript() { # datei tokenzahl
  printf '{"type":"user","message":{"content":[{"type":"text","text":"x"}]}}\n' > "$1"
  printf '{"type":"assistant","message":{"role":"assistant","content":"y","usage":{"input_tokens":%s,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":5}}}\n' \
    "$2" >> "$1"
}

lauf() { # projekt notfallschwelle
  printf '{"session_id":"sN","transcript_path":"%s","prompt":"hi","cwd":"%s"}' "$1/t.jsonl" "$1" \
    | CLAUDE_PROJECT_DIR="$1" MIND_NOTFALL_TOKENS="$2" MIND_SYNC_AT_TOKENS=0 \
      bash "$H/prompt-submit.sh" 2>/dev/null
}

echo "=== Notfallschwelle ==="

# --- 1/2 · Der Umschlag sitzt genau auf der Grenze -----------------------
for N in 939999 940000; do
  P=$(projekt); transkript "$P/t.jsonl" "$N"
  O=$(lauf "$P" 940000)
  printf '%s' "$O" | grep -q 'NOTFALL' && A=ja || A=nein
  [ "$N" = 940000 ] && E=ja || E=nein
  janein "$N Tokens -> Notfall=$E" "$E" "$A"
  rm -rf "$P"
done

# --- 3 · NICHTS schaltet ihn stumm --------------------------------------
#     Weder ein liegender sync-stand noch eine offene Schuld. Nahe der Wand ist jede
#     Beruhigung falsch — und `sync-stand` beruhigt sonst Mahnung UND Zwang.
P=$(projekt); transkript "$P/t.jsonl" 960000
printf 'ts=x\n' > "$P/.claude-mind/rescued/sync-stand"
printf 'path=%s/c.md\nblocks=0\n' "$P/.claude-mind/rescued" > "$P/.claude-mind/rescued/OPEN"
echo "## [x]" > "$P/.claude-mind/rescued/c.md"
O=$(lauf "$P" 940000)
printf '%s' "$O" | grep -q 'NOTFALL' && A=ja || A=nein
janein "sync-stand UND OPEN schalten ihn NICHT stumm" ja "$A"
rm -rf "$P"

# --- 4 · Keine Zahl ist KEINE Null --------------------------------------
#     Ein Transkript ohne usage-Felder darf NICHT als "0 Tokens" durchgehen — sonst
#     schwiege der Notfall genau dann, wenn die Messung kaputt ist.
P=$(projekt)
printf '{"type":"user","message":{"content":[{"type":"text","text":"ohne usage"}]}}\n' > "$P/t.jsonl"
O=$(lauf "$P" 940000)
printf '%s' "$O" | grep -q 'NOTFALL' && A=ja || A=nein
janein "Transkript ohne usage: keine Aussage, keine Warnung" nein "$A"
rm -rf "$P"

# --- 5 · Schwelle 0 = aus (Vorgabe fuer alle anderen Projekte) ----------
P=$(projekt); transkript "$P/t.jsonl" 990000
O=$(lauf "$P" 0)
printf '%s' "$O" | grep -q 'NOTFALL' && A=ja || A=nein
janein "MIND_NOTFALL_TOKENS=0 schaltet ab" nein "$A"
rm -rf "$P"

# --- 6 · Ausgabe ist gueltiges JSON -------------------------------------
if command -v jq >/dev/null 2>&1; then
  P=$(projekt); transkript "$P/t.jsonl" 960000
  O=$(lauf "$P" 940000)
  printf '%s' "$O" | jq -e . >/dev/null 2>&1 && A=ja || A=nein
  janein "Ausgabe ist gueltiges JSON" ja "$A"
  rm -rf "$P"
else
  echo "  [ -- ] kein jq — JSON-Fall UEBERSPRUNGEN, nichts gemessen"
fi

# --- 7 · Der Text nennt die FOLGE, nicht nur die Zahl -------------------
#     Eine Warnung, die nur "viele Tokens" sagt, aendert kein Verhalten. Sie muss sagen,
#     WAS verloren geht: Chat, Auftrag, Arbeitsstand.
P=$(projekt); transkript "$P/t.jsonl" 960000
O=$(lauf "$P" 940000)
A=ja
for W in "Auffangnetz" "/compact" "Arbeitsstand"; do
  printf '%s' "$O" | grep -q -- "$W" || A=nein
done
janein "Text nennt Auffangnetz, /compact und Arbeitsstand" ja "$A"
rm -rf "$P"

# --- 8 · NEGATIVKONTROLLE, die scheitern KANN ---------------------------
#     Ein Hook-Ersatz, der IMMER 'NOTFALL' sagt, muss an Fall 5 (Schwelle 0) durchfallen.
stub() { echo "NOTFALL immer"; }
printf '%s' "$(stub)" | grep -q 'NOTFALL' && A=ja || A=nein
if [ "$A" = "ja" ]; then
  echo "  [ok ] Negativkontrolle: Dauer-Warner faellt an Fall 5 durch"; OK=$((OK+1))
else
  echo "  [ROT] Negativkontrolle misst nichts — Fall 5 waere immer gruen"; ROT=$((ROT+1))
fi

echo
echo "=================================="
echo "  $OK bestanden, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
