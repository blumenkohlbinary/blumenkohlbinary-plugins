#!/usr/bin/env bash
# Punkt 19 (v5.37.0): kein Sync-Zwang unter einem ausgenommenen Modell.
#
# NUTZER-ENTSCHEIDUNG 04.09.2026: "wenn der fable aktiviert ist soll er kein
# mind all machen".
#
# ⭐ DIE POSITIVKONTROLLE IST DER TRAGENDE TEIL. Ein Tor, das IMMER schweigt,
#    besteht jede Probe der Form "unter Fable darf nichts kommen". Deshalb steht
#    neben jedem Fable-Fall ein Opus-Fall, der weiterhin blocken MUSS.
#
# ⛔ UND DIE FAIL-SAFE-RICHTUNG WIRD MITGEPRUEFT: ohne erkennbares Modell bleibt
#    der Zwang. Ein ausgefallener Zwang kostet einen Sync, ein faelschlich
#    stummer verliert Arbeit.
set -u
R="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
GRUEN=0; ROT=0

pruef() { # <name> <erwartet-rc> <ist-rc>
  if [ "$2" = "$3" ]; then GRUEN=$((GRUEN+1)); echo "  [ok ] $1"
  else ROT=$((ROT+1)); echo "  [ROT] $1 (erwartet rc=$2, war rc=$3)"; fi
}
enthaelt() { # <name> <nadel> <heuhaufen>
  case "$3" in *"$2"*) GRUEN=$((GRUEN+1)); echo "  [ok ] $1" ;;
  *) ROT=$((ROT+1)); echo "  [ROT] $1 — '$2' fehlt" ;; esac
}
fehlt() { # <name> <nadel> <heuhaufen>
  case "$3" in *"$2"*) ROT=$((ROT+1)); echo "  [ROT] $1 — '$2' steht da, sollte nicht" ;;
  *) GRUEN=$((GRUEN+1)); echo "  [ok ] $1" ;; esac
}

# --- Transkript-Fixtures --------------------------------------------------
# ⚠ Eine Zeile mit "<synthetic>" ganz am Ende. Gemessen 04.09.2026: die gibt es
#   wirklich (13 Stueck in diesem Projekt, in EINEM Transkript als letzte Zeile).
#   Wer blind die letzte Zeile nimmt, liest dort einen Platzhalter.
mk() { printf '%s\n' "$2" > "$TMP/$1.jsonl"; }
printf '%s\n' \
  '{"message":{"model":"claude-opus-5","usage":{"input_tokens":10}}}' \
  '{"message":{"model":"claude-fable-5-1","usage":{"input_tokens":20}}}' \
  '{"message":{"model":"<synthetic>"}}' > "$TMP/fable.jsonl"
printf '%s\n' \
  '{"message":{"model":"claude-opus-5","usage":{"input_tokens":10}}}' \
  '{"message":{"model":"<synthetic>"}}' > "$TMP/opus.jsonl"
printf '%s\n' '{"type":"user"}' > "$TMP/ohne.jsonl"

# shellcheck disable=SC1091
. "$R/hooks/lib.sh" 2>/dev/null

echo "=== 1) mind_modell — letztes ECHTES Modell, <synthetic> uebersprungen ==="
M=$(mind_modell "$TMP/fable.jsonl"); pruef "Fable-Transkript -> claude-fable-5-1" "claude-fable-5-1" "$M"
M=$(mind_modell "$TMP/opus.jsonl");  pruef "Opus-Transkript  -> claude-opus-5"    "claude-opus-5"    "$M"
mind_modell "$TMP/ohne.jsonl" >/dev/null 2>&1; pruef "⛔ ohne Modell-Feld -> rc 1" 1 $?
mind_modell "$TMP/gibtsnicht.jsonl" >/dev/null 2>&1; pruef "⛔ Datei fehlt -> rc 1" 1 $?

echo
echo "=== 2) mind_sync_modell_aus — Tor und Gegenprobe ==="
mind_sync_modell_aus "$TMP/fable.jsonl"; pruef "⭐ Fable -> AUS (rc 0)" 0 $?
mind_sync_modell_aus "$TMP/opus.jsonl";  pruef "⭐ POSITIVKONTROLLE: Opus -> AN (rc 1)" 1 $?
mind_sync_modell_aus "$TMP/ohne.jsonl";  pruef "⛔ FAIL-SAFE: kein Modell -> AN (rc 1)" 1 $?
( MIND_SYNC_AUS_MODELLE="opus" mind_sync_modell_aus "$TMP/opus.jsonl" )
pruef "Regler greift: opus eingetragen -> AUS" 0 $?
( MIND_SYNC_AUS_MODELLE="" mind_sync_modell_aus "$TMP/fable.jsonl" )
pruef "⛔ leerer Regler schaltet das Tor GANZ ab -> AN" 1 $?
( MIND_SYNC_AUS_MODELLE="haiku, fable" mind_sync_modell_aus "$TMP/fable.jsonl" )
pruef "Liste mit Leerzeichen: 'haiku, fable' trifft" 0 $?

echo
echo "=== 3) stop.sh am echten Hook — blockt es noch? ==="
P="$TMP/proj"; mkdir -p "$P/.claude-mind/rescued"
printf 'ts=x\npath=%s\n' "$TMP/chat.md" > "$P/.claude-mind/rescued/OPEN"
: > "$TMP/chat.md"
lauf() { # <transkript>
  printf '{"stop_hook_active":false,"cwd":"%s","transcript_path":"%s"}' "$P" "$1" \
    | CLAUDE_PLUGIN_ROOT="$R" CLAUDE_PROJECT_DIR="$P" bash "$R/hooks/stop.sh" 2>/dev/null
}
AUS=$(lauf "$TMP/opus.jsonl")
enthaelt "⭐ POSITIVKONTROLLE: unter Opus wird geblockt" '"decision":"block"' "$AUS"
AUS=$(lauf "$TMP/fable.jsonl")
fehlt "⭐ unter Fable KEIN Block" '"decision"' "$AUS"
AUS=$(lauf "$TMP/ohne.jsonl")
enthaelt "⛔ FAIL-SAFE: ohne Modell wird weiter geblockt" '"decision":"block"' "$AUS"

echo
echo "=== 4) prompt-submit.sh — schweigt die Schuld-Mahnung? ==="
# ⛔ JEDER Fall bekommt ein EIGENES Projekt. Die OFFEN-Mahnung hat einen Zaehler
#    je Sitzung (MIND_REMIND_EVERY); teilen sich drei Faelle ein Projekt, schweigt
#    der zweite und dritte wegen des ZAEHLERS und nicht wegen des Modells.
# ⚠ Genau das ist beim ersten Lauf passiert: der Fall war rot, der Hook korrekt.
#   Ein Prueffall, der die falsche Ursache misst, meldet einen Fehler, den es
#   nicht gibt — dieselbe Klasse wie einer, der einen echten uebersieht.
lauf2() {
  local pp="$TMP/ps$2"
  mkdir -p "$pp/.claude-mind/rescued"
  printf 'ts=x\npath=%s\n' "$TMP/chat.md" > "$pp/.claude-mind/rescued/OPEN"
  printf '{"cwd":"%s","transcript_path":"%s","prompt":"hallo"}' "$pp" "$1" \
    | CLAUDE_PLUGIN_ROOT="$R" CLAUDE_PROJECT_DIR="$pp" bash "$R/hooks/prompt-submit.sh" 2>/dev/null
}
AUS=$(lauf2 "$TMP/opus.jsonl" a)
enthaelt "⭐ POSITIVKONTROLLE: unter Opus wird gemahnt" "OFFENE Sync-Schuld" "$AUS"
AUS=$(lauf2 "$TMP/fable.jsonl" b)
fehlt "⭐ unter Fable KEINE Mahnung" "OFFENE Sync-Schuld" "$AUS"
AUS=$(lauf2 "$TMP/ohne.jsonl" c)
enthaelt "⛔ FAIL-SAFE: ohne Modell wird weiter gemahnt" "OFFENE Sync-Schuld" "$AUS"

echo
echo "  $GRUEN gruen · $ROT rot"
[ "$ROT" -eq 0 ]
