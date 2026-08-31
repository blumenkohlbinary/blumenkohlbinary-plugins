#!/usr/bin/env bash
# PLAN-PAUSE (v5.28.0) — /mind-all schweigt, solange ein freigegebener Plan laeuft.
#
# Nutzer-Auftrag 31.08.2026, woertlich: "wenn er einen plan abarbeitet soll er kein
# mind all machen bis der plan durch ist — aber nur bei einem offiziellen plan im
# planmodus, plan.md".
#
# ⭐ FALL 2 IST DER GRUND, WARUM DER NAHELIEGENDE BAU NICHT GEHT.
#    Gemessen 31.08.2026 in diesem Projekt: 10 Plan-Dateien, davon `plan.md`,
#    und KEINE EINZIGE mit Checkboxen. Ein Kriterium "plan.md existiert" haette
#    den Sync FUER IMMER stillgelegt; "offene Checkbox" haette NIE gefeuert.
#    Beides waere ein Filter, der sich auf Stille kalibriert (werkzeuge-zuerst.md).
#    Deshalb haengt die Pause an einem MERKER mit Zeitstempel, nicht an einer Datei.
#
# ⭐ FALL 4 UND 5 SIND DIE EIGENTLICHE ABSICHERUNG. Der Ausloeser ist mechanisch
#    (`ExitPlanMode`), das ENDE ist es NICHT — nichts sagt "Plan fertig". Ohne die
#    zwei Ausstiege fraesse die Pause die Rettungsdatei: jede Kompaktierung waehrend
#    der Pause erzeugt eine neue, und ab der dritten rotiert die aelteste weg
#    (MIND_RESCUE_KEEP_COUNT=3).
#
# ⛔ WAS DIESE SAMMLUNG NICHT PRUEFT: ob `ExitPlanMode` als `tool_name` im
#    PostToolUse-Hook tatsaechlich ankommt. Das ist an diesem Aufbau NICHT
#    nachstellbar — die Hook-Referenz nennt das Feld, aber nicht diesen
#    Tool-Namen. Der Hook protokolliert deshalb jeden gesehenen Namen; ob er je
#    feuert, steht nach dem ersten Planmodus im Log und nicht hier.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_plan_pause.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
LIB="$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
PM="$CLAUDE_PLUGIN_ROOT/hooks/plan-modus.sh"
HJ="$CLAUDE_PLUGIN_ROOT/hooks/hooks.json"
for f in "$LIB" "$PM" "$HJ"; do
  [ -f "$f" ] || { echo "fehlt: $f" >&2; exit 2; }
done
# shellcheck disable=SC1090
. "$LIB"

OK=0; ROT=0
janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P/.claude-mind/rescued"

echo "== 1/7  Ohne Merker gilt KEINE Pause (Fail-safe-Richtung) =="
janein "kein Merker -> rc 1" "1" "$(mind_plan_pause "$P" >/dev/null 2>&1; echo $?)"
janein "leeres Projektargument -> rc 1" "1" "$(mind_plan_pause "" >/dev/null 2>&1; echo $?)"

echo "== 2/7  ⭐ Eine blosse plan.md loest NICHTS aus =="
printf '# Plan\n\nSchritt eins.\nSchritt zwei.\n' > "$P/plan.md"
janein "⭐ plan.md allein -> KEINE Pause" "1" \
       "$(mind_plan_pause "$P" >/dev/null 2>&1; echo $?)"
printf -- '- [ ] offen\n' >> "$P/plan.md"
janein "⭐ plan.md MIT offener Checkbox -> immer noch KEINE Pause" "1" \
       "$(mind_plan_pause "$P" >/dev/null 2>&1; echo $?)"

echo "== 3/7  Merker setzen -> Pause gilt, mit Begruendung =="
mind_plan_merken "$P" "plan.md"
janein "Merker gesetzt -> rc 0 (Pause)" "0" \
       "$(mind_plan_pause "$P" >/dev/null 2>&1; echo $?)"
janein "Begruendung nennt den Plannamen" "1" \
       "$(mind_plan_pause "$P" 2>/dev/null | grep -c 'plan.md')"
janein "Begruendung nennt die Restzeit" "1" \
       "$(mind_plan_pause "$P" 2>/dev/null | grep -c 'Ablauf in')"
janein "⛔ die Schuld wird NICHT angefasst" "0" \
       "$(ls "$P/.claude-mind/rescued"/OPEN 2>/dev/null | wc -l)"

echo "== 4/7  ⭐ AUSSTIEG 1: zu alt — die Pause hebt sich selbst auf =="
printf 'ts=%s\nplan=alt.md\n' "$(( $(date +%s) - 9 * 3600 ))" \
  > "$P/.claude-mind/PLAN-AKTIV"
janein "⭐ 9 h alt bei Grenze 8 -> KEINE Pause" "1" \
       "$(mind_plan_pause "$P" >/dev/null 2>&1; echo $?)"
janein "⭐ abgelaufener Merker wird ENTFERNT, nicht liegengelassen" "0" \
       "$(ls "$P/.claude-mind/PLAN-AKTIV" 2>/dev/null | wc -l)"
printf 'ts=%s\nplan=alt.md\n' "$(( $(date +%s) - 9 * 3600 ))" \
  > "$P/.claude-mind/PLAN-AKTIV"
janein "Regler wirkt: MIND_PLAN_PAUSE_HOURS=24 -> Pause gilt wieder" "0" \
       "$(MIND_PLAN_PAUSE_HOURS=24 mind_plan_pause "$P" >/dev/null 2>&1; echo $?)"

echo "== 5/7  ⭐ AUSSTIEG 2: Kompaktierungen waehrend der Pause =="
rm -f "$P/.claude-mind/PLAN-AKTIV"
mind_plan_merken "$P" "plan.md"
sleep 1
printf 'x\n' > "$P/.claude-mind/rescued/20260831-000001_chat.md"
janein "1 Kompaktierung (Grenze 2) -> Pause gilt noch" "0" \
       "$(mind_plan_pause "$P" >/dev/null 2>&1; echo $?)"
printf 'x\n' > "$P/.claude-mind/rescued/20260831-000002_chat.md"
janein "⭐ 2 Kompaktierungen -> Pause hebt sich auf" "1" \
       "$(mind_plan_pause "$P" >/dev/null 2>&1; echo $?)"
janein "⭐ Merker danach WEG" "0" \
       "$(ls "$P/.claude-mind/PLAN-AKTIV" 2>/dev/null | wc -l)"
# ⛔ Eine AELTERE Rettung darf nicht mitzaehlen — sonst waere die Pause schon
#    beim Setzen verbraucht, wenn im Projekt alte Rettungen liegen.
rm -f "$P/.claude-mind/rescued"/*_chat.md
printf 'x\n' > "$P/.claude-mind/rescued/20260101-000000_chat.md"
sleep 1
mind_plan_merken "$P" "plan.md"
janein "⛔ AELTERE Rettung zaehlt NICHT mit -> Pause gilt" "0" \
       "$(mind_plan_pause "$P" >/dev/null 2>&1; echo $?)"

echo "== 6/7  Unparsbarer Merker, Freigabe, Verdrahtung =="
printf 'ts=morgen\nplan=x\n' > "$P/.claude-mind/PLAN-AKTIV"
janein "⛔ unparsbares ts -> KEINE Pause (fail-safe)" "1" \
       "$(mind_plan_pause "$P" >/dev/null 2>&1; echo $?)"
mind_plan_merken "$P" "plan.md"
mind_plan_frei "$P"
janein "mind_plan_frei entfernt den Merker" "0" \
       "$(ls "$P/.claude-mind/PLAN-AKTIV" 2>/dev/null | wc -l)"
# ⛔ Die AUFRUFFORM, nicht die Erwaehnung — dieselbe Umstellung wie in
#    test_leitplanke.sh (v5.25.0): "nennt es" ist kein Beleg fuer "ruft es".
# ⛔ Und es MUSS der Subprozess sein, nicht `command -v mind_plan_pause`:
#    stop.sh sourct lib.sh nur im Token-Zweig, prompt-submit.sh gar nicht.
#    Die erste Fassung nutzte den Funktionsnamen — er war IMMER unbekannt,
#    der Block wurde IMMER still uebersprungen, und beide Hooks verhielten
#    sich exakt wie vorher. Gefunden nur von Fall 7 unten.
janein "stop.sh ruft plan-pause.sh als SUBPROZESS" "1" \
       "$(grep -c 'bash "$_PP" "$PROJ"' "$CLAUDE_PLUGIN_ROOT/hooks/stop.sh")"
janein "prompt-submit.sh ruft plan-pause.sh als SUBPROZESS" "1" \
       "$(grep -c 'bash "$_PP" "$PROJ"' \
          "$CLAUDE_PLUGIN_ROOT/hooks/prompt-submit.sh")"
janein "⛔ KEIN command-v-Waechter mehr in stop.sh" "0" \
       "$(grep -c 'command -v mind_plan_pause' "$CLAUDE_PLUGIN_ROOT/hooks/stop.sh")"
janein "plan-pause.sh meldet unerreichbare lib.sh statt zu schweigen" "1" \
       "$(grep -c 'lib.sh unerreichbar' "$CLAUDE_PLUGIN_ROOT/hooks/plan-pause.sh")"
janein "mind-all HEBT die Pause auf" "1" \
       "$(grep -c 'mind_plan_frei "$PROJ"' \
          "$CLAUDE_PLUGIN_ROOT/skills/mind-all/SKILL.md")"
janein "hooks.json registriert PostToolUse/ExitPlanMode" "1" \
       "$(grep -c '"matcher": "ExitPlanMode"' "$HJ")"
# ⛔ Der Hook prueft den Tool-Namen SELBST nach, nicht nur ueber den Matcher.
#    Faellt der Matcher aus, setzte er sonst bei JEDEM Werkzeug eine Pause.
janein "plan-modus.sh prueft tool_name selbst nach" "1" \
       "$(grep -c 'ExitPlanMode|exit_plan_mode' "$PM")"
janein "plan-modus.sh protokolliert auch den STILLEN Fall" "1" \
       "$(grep -c 'ist nicht ExitPlanMode' "$PM")"

echo "== 7/7  ⭐ POSITIVKONTROLLE AM LEBENDEN HOOK — beide Richtungen =="
# ⭐ DIESER FALL HAT DEN EINZIGEN ECHTEN FEHLER GEFUNDEN. Alle Faelle oben
#    pruefen `mind_plan_pause` direkt; sie waren gruen, waehrend die Pause in
#    den HOOKS wirkungslos war (`command -v` auf eine nie gesourcte Funktion).
# ⛔ Die Richtung OHNE Pause ist die tragende. "Mit Pause schweigt er" allein
#    ist wertlos — er schweigt auch, wenn die Pause nie ankommt.
H="$TMP/hooklauf"; mkdir -p "$H/.claude-mind/rescued"
_R="$H/.claude-mind/rescued/20260831-000000_chat.md"; printf '## [x]\n' > "$_R"
printf 'path=%s\ncompactions=1\n' "$_R" > "$H/.claude-mind/rescued/OPEN"
_A=$(echo '{"stop_hook_active":false}' \
     | CLAUDE_PROJECT_DIR="$H" bash "$CLAUDE_PLUGIN_ROOT/hooks/stop.sh" 2>&1)
janein "⭐ OHNE Pause blockt stop.sh (die tragende Richtung)" "1" \
       "$(printf '%s' "$_A" | grep -c '\"decision\"')"
printf 'ts=%s\nplan=plan.md\n' "$(date +%s)" > "$H/.claude-mind/PLAN-AKTIV"
_B=$(echo '{"stop_hook_active":false}' \
     | CLAUDE_PROJECT_DIR="$H" bash "$CLAUDE_PLUGIN_ROOT/hooks/stop.sh" 2>&1)
janein "⭐ MIT Pause blockt stop.sh NICHT" "0" \
       "$(printf '%s' "$_B" | grep -c '\"decision\"')"
janein "⛔ und die SCHULD liegt danach noch da" "1" \
       "$(ls "$H/.claude-mind/rescued/OPEN" 2>/dev/null | wc -l)"
# Der Setz-Hook, live, mit echtem JSON auf stdin.
rm -f "$H/.claude-mind/PLAN-AKTIV"
echo "{\"tool_name\":\"ExitPlanMode\",\"cwd\":\"$H\"}" \
  | CLAUDE_PROJECT_DIR="$H" bash "$PM" >/dev/null 2>&1
janein "plan-modus.sh setzt den Merker bei ExitPlanMode" "1" \
       "$(ls "$H/.claude-mind/PLAN-AKTIV" 2>/dev/null | wc -l)"
rm -f "$H/.claude-mind/PLAN-AKTIV"
echo "{\"tool_name\":\"Bash\",\"cwd\":\"$H\"}" \
  | CLAUDE_PROJECT_DIR="$H" bash "$PM" >/dev/null 2>&1
janein "⛔ und NICHT bei einem anderen Werkzeug (Matcher-Ausfall)" "0" \
       "$(ls "$H/.claude-mind/PLAN-AKTIV" 2>/dev/null | wc -l)"

echo
echo "  $OK gruen, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
exit 0
