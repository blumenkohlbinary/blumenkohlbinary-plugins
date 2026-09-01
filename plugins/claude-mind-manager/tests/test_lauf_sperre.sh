#!/usr/bin/env bash
# SPERRE GEGEN PARALLELE /mind-all-LAEUFE (v5.30.0) — zwei Teile, beide noetig.
#
# ⛔ DER BEFUND kam aus dem Projekt `Creator` (30.08.2026) und ist HIER
#    unabhaengig nachgemessen worden:
#      grep -rciE 'flock|lockfile|\.lock|mkdir .*lock'  ->  0 / 0
#      mind-all/SKILL.md:158  `: > "$SCOPES_FILE"`      ->  bedingungslos
#      mind-all/SKILL.md:493  `grep -c '^skill='`       ->  zaehlt ALLE Zeilen
#
# ⭐ WARUM ES MEHR IST ALS EINE UEBERSCHRIEBENE DATEI — und das ist Fall 4:
#    Aus `SCOPES_FILE` wird `SYNC_LIEF` abgeleitet, daran haengt `rm -f "$OPEN"`.
#    Zwei Laeufe, die an DIESELBE Datei anhaengen, kommen zusammen auf 5 und
#    tilgen die Sync-Schuld fuer Arbeit, die KEIN EINZELNER geleistet hat.
#    Die naechste Kompaktierung findet dann keinen Merker, und die
#    Rettungsdatei wird nie eingespeist.
#
# ⛔ TEIL 2 IST NICHT KUER. Die Sperre VERHINDERT die Kollision; die
#    Laufkennung macht sie ERKENNBAR, wenn die Sperre versagt. Ohne Teil 2
#    entsteht ein Instrument, das im Ausfall schweigt.
#
# ⛔ WARUM NICHT CLAUDE_SESSION_ID: sie ist in einer Skill-Bash LEER (gemessen).
#    Ein Waechter darauf matcht gegen den leeren String, zaehlt ALLE Zeilen auch
#    fremde, und SIEHT AUS als greife er — schlimmer als keine Sperre.
#    Fall 3 prueft genau das nach.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_lauf_sperre.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
LIB="$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
SK="$CLAUDE_PLUGIN_ROOT/skills/mind-all/SKILL.md"
for f in "$LIB" "$SK"; do [ -f "$f" ] || { echo "fehlt: $f" >&2; exit 2; }; done
# shellcheck disable=SC1090
. "$LIB"

OK=0; ROT=0
janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P/.claude-mind"
L1="20260901_230000_pre-mind-all"; L2="20260901_230500_pre-mind-all"

echo "== 1/6  mkdir IST hier atomar — die Grundlage, nicht geglaubt =="
A="$TMP/atom"; : > "$TMP/gewinner"
for _i in $(seq 40); do ( mkdir "$A" 2>/dev/null && echo x >> "$TMP/gewinner" ) & done
wait
janein "40 gleichzeitige mkdir -> genau 1 gewinnt" "1" \
       "$(grep -c x "$TMP/gewinner" 2>/dev/null)"
janein "⛔ Gegenprobe: zweiter mkdir wird abgewiesen (kann nein sagen)" "1" \
       "$(mkdir "$A" 2>/dev/null; echo $?)"

echo "== 2/6  Sperre: erster bekommt sie, zweiter nicht =="
janein "1. Lauf bekommt die Sperre" "0" \
       "$(mind_lauf_sperre "$P" "$L1" >/dev/null 2>&1; echo $?)"
janein "⭐ 2. Lauf wird ABGEWIESEN" "1" \
       "$(mind_lauf_sperre "$P" "$L2" >/dev/null 2>&1; echo $?)"
janein "Abweisung nennt den haltenden Lauf" "1" \
       "$(mind_lauf_sperre "$P" "$L2" 2>/dev/null | grep -c "$L1")"
janein "Abweisung nennt die FOLGE, nicht nur den Zustand" "1" \
       "$(mind_lauf_sperre "$P" "$L2" 2>/dev/null | grep -c 'kein Lauf geleistet')"

echo "== 3/6  ⭐ Freigabe NUR durch den Eigentuemer =="
janein "⭐ Fremdfreigabe wird verweigert" "1" \
       "$(mind_lauf_frei "$P" "$L2" >/dev/null 2>&1; echo $?)"
janein "⛔ und die Sperre liegt danach NOCH" "1" \
       "$(ls -d "$P/.claude-mind/mind-all.lock" 2>/dev/null | wc -l)"
janein "eigene Freigabe geht" "0" \
       "$(mind_lauf_frei "$P" "$L1" >/dev/null 2>&1; echo $?)"
janein "danach ist sie weg" "0" \
       "$(ls -d "$P/.claude-mind/mind-all.lock" 2>/dev/null | wc -l)"

echo "== 4/6  ⭐ TEIL 2: nur die EIGENEN Marken zaehlen =="
# ⭐ DER FALL, GEGEN DEN ALLES GEBAUT IST: zwei Laeufe, eine Datei, Summe 5.
SF="$P/.claude-mind/analyzed-scopes"
{ echo "skill=mind-files|$L1";    echo "skill=mind-claudemd|$L1"
  echo "skill=mind-memory|$L1";   echo "skill=mind-rules|$L2"
  echo "skill=mind-update|$L2"; } > "$SF"
janein "⛔ ALT: grep -c '^skill=' zaehlt 5 — die Summe ZWEIER Laeufe" "5" \
       "$(grep -c '^skill=' "$SF")"
janein "⭐ NEU: Lauf 1 zaehlt nur seine eigenen 3" "3" \
       "$(grep -c "^skill=.*|$L1\$" "$SF")"
janein "⭐ NEU: Lauf 2 zaehlt nur seine eigenen 2" "2" \
       "$(grep -c "^skill=.*|$L2\$" "$SF")"
# ⛔ Die Folge in einem Satz: mit der alten Zaehlung waere SYNC_LIEF="ja"
#    geworden und `rm -f "$OPEN"` gelaufen — fuer Arbeit, die keiner tat.
janein "⛔ ALT haette 5/5 erreicht (Schuld getilgt), NEU nicht" "1" \
       "$([ "$(grep -c '^skill=' "$SF")" -ge 5 ] && [ "$(grep -c "^skill=.*|$L1\$" "$SF")" -lt 5 ] && echo 1 || echo 0)"

echo "== 5/6  ⛔ KEINE Abhaengigkeit von CLAUDE_SESSION_ID =="
# ⛔ Ein Waechter auf einer LEEREN Variablen matcht ALLES und sieht aus, als
#    greife er. Deshalb darf die Kennung nirgends daraus kommen.
janein "⛔ lib.sh baut die Sperre NICHT auf CLAUDE_SESSION_ID" "0" \
       "$(sed -n '/^mind_lauf_sperre/,/^}/p' "$LIB" | grep -c 'CLAUDE_SESSION_ID')"
janein "⛔ auch die Kennung nicht" "0" \
       "$(sed -n '/^mind_lauf_kennung/,/^}/p' "$LIB" | grep -c 'CLAUDE_SESSION_ID')"
janein "Kennung kommt aus dem Snapshot-Basename" "$L1" \
       "$(mind_lauf_kennung "/pfad/zu/.claude-mind/snapshots/$L1")"
janein "ohne Snapshot -> 'probelauf', nicht leer" "probelauf" \
       "$(mind_lauf_kennung "")"

echo "== 6/6  Verwaiste Sperre + Verdrahtung =="
mind_lauf_sperre "$P" "$L1" >/dev/null 2>&1
printf '%s' "$(( $(date +%s) - 99999 ))" > "$P/.claude-mind/mind-all.lock/ts"
janein "⭐ verwaiste Sperre (zu alt) wird uebernommen" "0" \
       "$(mind_lauf_sperre "$P" "$L2" >/dev/null 2>&1; echo $?)"
mind_lauf_frei "$P" "$L2" >/dev/null 2>&1
# ⛔ Die AUFRUFFORM, nicht die Erwaehnung.
janein "mind-all HOLT die Sperre" "1" \
       "$(grep -c 'mind_lauf_sperre "\$PROJ" "\$LAUF"' "$SK")"
janein "mind-all GIBT sie frei" "1" \
       "$(grep -c 'mind_lauf_frei "\$PROJ" "\${LAUF:-}"' "$SK")"
janein "⭐ mind-all haengt die Kennung an jede skill=-Marke" "1" \
       "$(grep -c 'echo "skill=<name>|\$LAUF"' "$SK")"
janein "⭐ mind-all zaehlt auf die eigene Kennung" "1" \
       "$(grep -c 'grep -c "\^skill=.\*|\$LAUF' "$SK")"
janein "⛔ Abbruch mit rc 0, nicht 1 (kein kaputter Lauf im Log)" "1" \
       "$(grep -c 'exit 0    # ⛔ 0, NICHT 1' "$SK")"

echo
echo "  $OK gruen, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
exit 0
