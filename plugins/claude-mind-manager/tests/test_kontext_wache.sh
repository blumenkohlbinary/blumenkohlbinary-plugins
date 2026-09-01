#!/usr/bin/env bash
# KONTEXT-WACHE (v5.33.0) — meldet Wachstum, das an den Commands vorbei entsteht.
#
# ⛔ DER ANLASS IST GEMESSEN, nicht vermutet. Ueber die Git-Historie des Projekts
#    `Claude Mind Manager`, alle Commits an CLAUDE.md und .claude/rules/:
#
#      Commits             117 Handarbeit  ·  43 Command
#      hinzugefuegte Zeilen 1991 Handarbeit ·  620 Command   -> 76 % Handarbeit
#
#    Das Kontext-Tor (v5.26.0) greift nur bei ADD/NEW_FILE INNERHALB der fuenf
#    Commands. Drei Viertel des Wachstums sah es nie.
#
# ⭐ FALL 5 IST DER KERN DES ENTWURFS. `mind_kontext_bilanz --vergleichen`
#    SCHREIBT den gemerkten Stand mit fort (lib.sh: `--merken` ODER
#    `--vergleichen`). Ein Hook, der das je Turn riefe, wuerde den Bezugswert
#    der fuenf Skills ueberschreiben — und damit die Wirkungsmessung jedes
#    /mind-all- und /mind-cleaner-Laufs. Die Wache misst deshalb OHNE Modus und
#    fuehrt eine EIGENE Merkdatei. Fall 5 prueft das byte-genau.
#
# ⭐ FALL 6 IST DIE POSITIVKONTROLLE AM LEBENDEN HOOK, und sie ist Pflicht.
#    In v5.28.0 war die Plan-Pause ein STILLER No-op: `command -v` auf eine
#    Funktion, die nie geladen war. Der Test "mit Pause schweigt er" war gruen
#    und wertlos — er schwieg, weil die Pause nie ankam. Nur die umgekehrte
#    Richtung findet so etwas.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_kontext_wache.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
W="$CLAUDE_PLUGIN_ROOT/hooks/kontext-wache.sh"
PS="$CLAUDE_PLUGIN_ROOT/hooks/prompt-submit.sh"
ST="$CLAUDE_PLUGIN_ROOT/hooks/stop.sh"
for f in "$W" "$PS" "$ST"; do [ -f "$f" ] || { echo "fehlt: $f" >&2; exit 2; }; done

OK=0; ROT=0
janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$3', bekommen '$2'"; ROT=$((ROT+1)); fi; }

D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
P="$D/proj"; mkdir -p "$P/.claude/rules" "$P/.claude-mind"
# 30 Zeilen Ausgangsbestand, damit ein Zuwachs messbar ist.
seq 1 30 | sed 's/^/- Regel /' > "$P/.claude/rules/eine.md"
printf '# Projekt\n' > "$P/CLAUDE.md"
MERKER="$P/.claude-mind/KONTEXT-GEWACHSEN"
STAND="$P/.claude-mind/kontext-wache"

echo "== 1/6  erster Lauf merkt nur, meldet NICHT =="
janein "erster Lauf meldet nicht (rc 1)" \
       "$(bash "$W" "$P" >/dev/null 2>&1; echo $?)" "1"
janein "aber der Bezugswert ist angelegt" \
       "$([ -f "$STAND" ] && echo ja || echo nein)" "ja"
janein "und KEIN Merker" "$([ -f "$MERKER" ] && echo ja || echo nein)" "nein"

echo "== 2/6  Zuwachs ueber der Schwelle -> Merker mit Zahlen =="
_IST=$(grep -m1 -oE '[0-9]+' "$STAND")
printf 'ZEILEN=%s\nts=1\n' "$(( _IST - 40 ))" > "$STAND"
janein "meldet (rc 0)" "$(bash "$W" "$P" >/dev/null 2>&1; echo $?)" "0"
janein "Merker liegt" "$([ -f "$MERKER" ] && echo ja || echo nein)" "ja"
janein "delta ist 40" "$(grep -m1 '^delta=' "$MERKER" | cut -d= -f2)" "40"
janein "jetzt= ist der echte Stand" "$(grep -m1 '^jetzt=' "$MERKER" | cut -d= -f2)" "$_IST"

echo "== 3/6  unter der Schwelle -> still (Grenze bei 20) =="
rm -f "$MERKER"
printf 'ZEILEN=%s\nts=1\n' "$(( _IST - 19 ))" > "$STAND"
janein "19 Zeilen Zuwachs meldet NICHT" "$(bash "$W" "$P" >/dev/null 2>&1; echo $?)" "1"
janein "kein Merker bei 19" "$([ -f "$MERKER" ] && echo ja || echo nein)" "nein"
printf 'ZEILEN=%s\nts=1\n' "$(( _IST - 20 ))" > "$STAND"
janein "⭐ 20 Zeilen meldet SEHR WOHL (Grenze scharf)" \
       "$(bash "$W" "$P" >/dev/null 2>&1; echo $?)" "0"

echo "== 4/6  Schrumpfen -> still, Bezugswert wird trotzdem nachgefuehrt =="
# ⚠ Sonst meldet der naechste Zuwachs gegen einen veralteten Hochstand.
rm -f "$MERKER"
printf 'ZEILEN=%s\nts=1\n' "$(( _IST + 500 ))" > "$STAND"
janein "Schrumpfen meldet nicht" "$(bash "$W" "$P" >/dev/null 2>&1; echo $?)" "1"
janein "⚠ Bezugswert ist NACHGEFUEHRT, nicht stehengeblieben" \
       "$(grep -m1 -oE '[0-9]+' "$STAND")" "$_IST"

echo "== 5/6  ⭐ der Bezugswert der SKILLS bleibt unberuehrt =="
# ⛔ Der Kern des Entwurfs: --vergleichen wuerde ihn ueberschreiben.
printf 'ZEILEN=999\nANWEISUNGEN=99\nDATEIEN=9\nBYTES=9999\n' > "$P/.claude-mind/kontext-bilanz"
_H1=$(cksum < "$P/.claude-mind/kontext-bilanz")
printf 'ZEILEN=%s\nts=1\n' "$(( _IST - 40 ))" > "$STAND"
bash "$W" "$P" >/dev/null 2>&1
janein "⭐ kontext-bilanz BYTE-GLEICH nach dem Lauf" \
       "$(cksum < "$P/.claude-mind/kontext-bilanz")" "$_H1"

echo "== 6/6  ⭐ POSITIVKONTROLLE AM LEBENDEN HOOK =="
# ⛔ Ohne sie waere ein stiller No-op nicht von Erfolg zu unterscheiden — der
#    v5.28.0-Fall. Erst OHNE Merker (muss schweigen), dann MIT (muss reden).
_EIN='{"session_id":"t1","cwd":"'"$P"'","transcript_path":"/nichts.jsonl"}'
rm -f "$MERKER"
_A=$(printf '%s' "$_EIN" | CLAUDE_PROJECT_DIR="$P" bash "$PS" 2>/dev/null)
janein "⛔ OHNE Merker schweigt prompt-submit" \
       "$(printf '%s' "$_A" | grep -c 'gewachsen')" "0"
printf 'vorher=100\njetzt=180\ndelta=80\nts=1\n' > "$MERKER"
_B=$(printf '%s' "$_EIN" | CLAUDE_PROJECT_DIR="$P" bash "$PS" 2>/dev/null)
janein "⭐ MIT Merker meldet er den Zuwachs" \
       "$(printf '%s' "$_B" | grep -c 'um 80 Zeilen gewachsen')" "1"
janein "die Meldung nennt die acht Fragen" \
       "$(printf '%s' "$_B" | grep -c 'A1')" "1"
janein "⛔ Merker ist VERBRAUCHT (sonst meldet es bei jedem Prompt)" \
       "$([ -f "$MERKER" ] && echo ja || echo nein)" "nein"
_C=$(printf '%s' "$_EIN" | CLAUDE_PROJECT_DIR="$P" bash "$PS" 2>/dev/null)
janein "zweiter Prompt schweigt" "$(printf '%s' "$_C" | grep -c 'gewachsen')" "0"
# ⛔ stop.sh darf NICHTS ausgeben — sonst zwei Ausgaben in einem stdout (v5.7.6).
janein "⛔ stop.sh nennt die Wache, gibt aber keinen Klartext aus" \
       "$(grep -c 'kontext-wache.sh' "$ST")" "1"
janein "⛔ und tut es OHNE echo" \
       "$(sed -n '/kontext-wache.sh/,/^fi$/p' "$ST" | grep -cE '^\s*(echo|printf)')" "0"

echo
echo "  $OK gruen, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
exit 0
