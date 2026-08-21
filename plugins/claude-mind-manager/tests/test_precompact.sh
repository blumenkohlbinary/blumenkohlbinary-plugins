#!/bin/bash
# pre-compact.sh ist der EINZIGE Hook, der den Chat vor der Kompaktierung rettet.
# Bricht er, merkt es niemand: die Kompaktierung laeuft durch, der Chat ist weg.
#
# Deshalb genau zwei Fragen:
#   A) Entsteht die Rettung auch dann, wenn NUR die neue UEBERGABE-Schreibung scheitert?
#   B) Verhaelt sich die Schuld richtig — OPEN nur ohne vorherigen Sync?

export CLAUDE_PLUGIN_ROOT="C:/CD/KOHLEKTIV/Plugin - Entwicklung/hackj-plugins/plugins/claude-mind-manager"
H="$CLAUDE_PLUGIN_ROOT/hooks"
ok=0; rot=0
pruef() {
  if [ "$2" = "$3" ]; then echo "  [ok ] $1"; ok=$((ok+1))
  else echo "  [ROT] $1 — erwartet '$3', bekommen '$2'"; rot=$((rot+1)); fi
}

bau_projekt() {                       # $1 = Zielverzeichnis
  mkdir -p "$1/.claude-mind/rescued"
  P="$1/t.jsonl"
  : > "$P"
  for i in $(seq 1 40); do
    printf '{"type":"user","message":{"content":[{"type":"text","text":"Frage %d zum Aufbau"}]}}\n' "$i" >> "$P"
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Antwort %d. Entscheidung: wir nehmen Weg A."}],"usage":{"input_tokens":2,"cache_read_input_tokens":1000,"cache_creation_input_tokens":3,"output_tokens":9}}}\n' "$i" >> "$P"
  done
}

ruf() {                               # $1 = projekt, $2 = transcript
  printf '{"hook_event_name":"PreCompact","cwd":"%s","session_id":"S1","transcript_path":"%s","trigger":"auto"}' \
    "$1" "$2" | bash "$H/pre-compact.sh" >/dev/null 2>&1
}

echo "=== A · Normallauf (Bezugspunkt) ==="
T1=$(mktemp -d); bau_projekt "$T1/p"
export CLAUDE_PROJECT_DIR="$T1/p"
ruf "$T1/p" "$T1/p/t.jsonl"
R="$T1/p/.claude-mind/rescued"
pruef "Chat-Rettung entsteht"  "$(ls "$R"/*_chat.md 2>/dev/null | wc -l | tr -d ' ')" "1"
pruef "UEBERGABE-Merker liegt" "$([ -f "$R/UEBERGABE" ] && echo ja || echo nein)" "ja"
pruef "OPEN entsteht (kein Sync gelaufen)" "$([ -f "$R/OPEN" ] && echo ja || echo nein)" "ja"

echo
echo "=== B · SABOTAGE: nur die UEBERGABE-Schreibung scheitert ==="
T2=$(mktemp -d); bau_projekt "$T2/p"
export CLAUDE_PROJECT_DIR="$T2/p"
# Ein VERZEICHNIS namens UEBERGABE laesst die Umleitung scheitern — und sonst nichts.
mkdir -p "$T2/p/.claude-mind/rescued/UEBERGABE/blockiert"
ruf "$T2/p" "$T2/p/t.jsonl"
R="$T2/p/.claude-mind/rescued"
pruef "Chat-Rettung entsteht TROTZDEM" "$(ls "$R"/*_chat.md 2>/dev/null | wc -l | tr -d ' ')" "1"
pruef "Auftrags-Merker entsteht TROTZDEM" "$(ls "$R"/*_RESUME.md 2>/dev/null | wc -l | tr -d ' ')" "1"
pruef "OPEN entsteht TROTZDEM" "$([ -f "$R/OPEN" ] && echo ja || echo nein)" "ja"
pruef "Rettung ist nicht leer" "$([ -s "$(ls "$R"/*_chat.md 2>/dev/null | head -1)" ] && echo ja || echo nein)" "ja"

echo
echo "=== C · sync-stand liegt -> KEINE neue Schuld, aber Rettung + Uebergabe ==="
T3=$(mktemp -d); bau_projekt "$T3/p"
export CLAUDE_PROJECT_DIR="$T3/p"
printf 'ts=vorher\n' > "$T3/p/.claude-mind/rescued/sync-stand"
ruf "$T3/p" "$T3/p/t.jsonl"
R="$T3/p/.claude-mind/rescued"
pruef "Chat-Rettung entsteht"        "$(ls "$R"/*_chat.md 2>/dev/null | wc -l | tr -d ' ')" "1"
pruef "UEBERGABE liegt"              "$([ -f "$R/UEBERGABE" ] && echo ja || echo nein)" "ja"
pruef "KEINE neue Schuld (kein OPEN)" "$([ -f "$R/OPEN" ] && echo ja || echo nein)" "nein"
pruef "sync-stand verbraucht"        "$([ -f "$R/sync-stand" ] && echo da || echo weg)" "weg"

rm -rf "$T1" "$T2" "$T3"
echo
echo "=================================="
echo "  $ok bestanden, $rot rot"
[ "$rot" -eq 0 ]
