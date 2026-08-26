#!/usr/bin/env bash
# TOOL->RULE: DRITTER ORT UND AKTUALITAETS-VERDACHT (v5.21.2)
#
# B5 ⛔ `mind_check_tools_have_rules` sah NUR `tools/` und die Projektwurzel.
#    Gemessen 26.08.2026: drei Werkzeuge unter `Learnings/` waren unsichtbar,
#    zwei davon (`bestandsaufnahme.py`, `messung_phase0.py`) standen in KEINER
#    Context-Datei — und die Pruefung meldete `PASS`. Das liest sich wie
#    "alle Werkzeuge erreichbar" und war es nicht.
#    ⭐ Der Fix ist keine dritte Sonderregel, sondern die VERALLGEMEINERUNG der
#       zweiten: im Wurzelverzeichnis zaehlt, was CLAUDE.md namentlich nennt —
#       jetzt gilt das fuer jeden Unterordner ueber die AUFRUFFORM.
#
# B6 ⛔ Die Pruefung misst ERREICHBARKEIT, nicht AKTUALITAET. `backup-usage.md`
#    beschrieb `rollback.py` im Stand VOR dem Fix desselben Tages — `PASS` die
#    ganze Zeit. Eine Rule, die das Werkzeug von gestern beschreibt, ist von
#    einer richtigen nicht zu unterscheiden.
#    ⚠ Der Fix ist ein VERDACHT, kein Gate: `PRUEFEN` statt `FAIL`, und der
#      Rueckgabewert bleibt unberuehrt. Ein Werkzeug kann sich aendern, ohne
#      dass seine Nutzung sich aendert. Wer daraus ein Gate macht, baut die
#      naechste Pruefung, der man gewohnheitsmaessig nicht mehr glaubt.
#
# ⛔ NEUE DATEI. tests/test_toolrule.sh bleibt unangetastet.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_toolrule_orte.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
. "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
OK=0; ROT=0
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

pruefe() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — ist '$2', soll '$3'"; ROT=$((ROT+1)); fi; }

# Ein Projekt bauen: $1 = Name
mach_projekt() {
  P="$T/$1"; rm -rf "$P"
  mkdir -p "$P/.claude/rules" "$P/tools" "$P/Learnings" "$P/still"
  printf -- '---\nglobs: ["**/*"]\ndescription: Nutzung der Werkzeuge dieses Projekts\n---\n' \
    > "$P/.claude/rules/werkzeuge.md"
}

echo "=============================================================================="
echo "  B5 — der dritte Ort"
echo "=============================================================================="

# --- 1) Werkzeug im Unterordner, in CLAUDE.md genannt, MIT Rule -------------
mach_projekt a
echo "x" > "$P/Learnings/zaehl_gate.py"
printf '# P\n\nZahlen pruefen: `python Learnings/zaehl_gate.py`\n' > "$P/CLAUDE.md"
printf 'Fahre `Learnings/zaehl_gate.py` nach jeder Zahlenaenderung.\n' \
  >> "$P/.claude/rules/werkzeuge.md"
AUS=$(mind_check_tools_have_rules "$P"); RC=$?
pruefe "Unterordner-Werkzeug wird gefunden" "$(echo "$AUS" | grep -c 'PASS  zaehl_gate.py')" "1"
pruefe "und meldet Rueckgabe 0" "$RC" "0"
pruefe "sagt, WO gesucht wurde" "$(echo "$AUS" | grep -c 'geprueft in:')" "1"

# --- 2) dasselbe OHNE Rule -> FAIL -----------------------------------------
mach_projekt b
echo "x" > "$P/Learnings/messung_phase0.py"
printf '# P\n\nSiehe `python Learnings/messung_phase0.py`\n' > "$P/CLAUDE.md"
AUS=$(mind_check_tools_have_rules "$P"); RC=$?
pruefe "ohne Rule -> FAIL" "$(echo "$AUS" | grep -c 'FAIL  messung_phase0.py')" "1"
pruefe "und Rueckgabe 1" "$RC" "1"

# --- 3) ⛔ NEGATIVKONTROLLE: Unterordner NICHT in CLAUDE.md -> ignorieren ----
#     Sonst waere jedes Wegwerfskript in jedem Unterordner ein Befund.
mach_projekt c
echo "x" > "$P/still/wegwerf.py"
printf '# P\n\nNichts Besonderes.\n' > "$P/CLAUDE.md"
AUS=$(mind_check_tools_have_rules "$P"); RC=$?
pruefe "unerwaehntes Unterordner-Skript wird ignoriert" \
       "$(echo "$AUS" | grep -c 'wegwerf.py')" "0"
pruefe "und faellt nicht durch" "$RC" "0"

# --- 4) Regression: tools/ verhaelt sich unveraendert -----------------------
mach_projekt d
echo "x" > "$P/tools/backup_tools.py"
printf '# P\n\nnichts\n' > "$P/CLAUDE.md"
printf 'Vor dem Loeschen `tools/backup_tools.py verify` aufrufen.\n' \
  >> "$P/.claude/rules/werkzeuge.md"
AUS=$(mind_check_tools_have_rules "$P"); RC=$?
pruefe "tools/ weiterhin ueber die Aufrufform" \
       "$(echo "$AUS" | grep -c 'PASS  backup_tools.py')" "1"
# ⛔ Die Rule muss den PFAD nennen, nicht nur den Namen — sonst zaehlt eine
#    blosse Erwaehnung in einer Versions-Historie als Nachweis (Fehler von v5.2.1).
mach_projekt e
echo "x" > "$P/tools/backup_tools.py"
printf '# P\n\nnichts\n' > "$P/CLAUDE.md"
printf 'In v3.3.0 kam backup_tools.py dazu.\n' >> "$P/.claude/rules/werkzeuge.md"
AUS=$(mind_check_tools_have_rules "$P"); RC=$?
pruefe "blosse Namensnennung reicht NICHT" "$(echo "$AUS" | grep -c 'FAIL')" "1"

echo
echo "=============================================================================="
echo "  B6 — Aktualitaet ist ein VERDACHT, kein Gate"
echo "=============================================================================="

# --- 5) Werkzeug JUENGER als seine Rule -> PRUEFEN --------------------------
mach_projekt f
echo "x" > "$P/tools/rollback.py"
printf '# P\n\nnichts\n' > "$P/CLAUDE.md"
printf 'Rueckweg: `tools/rollback.py list`, dann `restore`.\n' \
  >> "$P/.claude/rules/werkzeuge.md"
touch -d '2020-01-01 00:00' "$P/.claude/rules/werkzeuge.md"
touch -d '2026-01-01 00:00' "$P/tools/rollback.py"
AUS=$(mind_check_tools_have_rules "$P"); RC=$?
pruefe "juengeres Werkzeug -> PRUEFEN" "$(echo "$AUS" | grep -c 'PRUEFEN: rollback.py')" "1"
pruefe "nennt es Verdacht, nicht Befund" "$(echo "$AUS" | grep -c 'Verdacht, kein Befund')" "1"
# ⛔ DIE KERNZUSICHERUNG: kein Gate. Sonst wird aus einem Hinweis eine Pruefung,
#    die man gewohnheitsmaessig ignoriert.
pruefe "Rueckgabe bleibt 0" "$RC" "0"
pruefe "weiterhin PASS, nicht FAIL" "$(echo "$AUS" | grep -c 'PASS  rollback.py')" "1"

# --- 6) ⛔ NEGATIVKONTROLLE: Rule juenger -> still --------------------------
#     Ohne diesen Fall waere "melde immer PRUEFEN" gruen.
touch -d '2026-06-01 00:00' "$P/.claude/rules/werkzeuge.md"
AUS=$(mind_check_tools_have_rules "$P"); RC=$?
pruefe "juengere Rule -> KEIN PRUEFEN" "$(echo "$AUS" | grep -c 'PRUEFEN')" "0"
pruefe "und weiterhin Rueckgabe 0" "$RC" "0"

# --- 7) FAIL bleibt FAIL, auch mit Datumsspiel ------------------------------
mach_projekt g
echo "x" > "$P/tools/ohne_rule.py"
printf '# P\n\nnichts\n' > "$P/CLAUDE.md"
AUS=$(mind_check_tools_have_rules "$P"); RC=$?
pruefe "Werkzeug ohne Rule bleibt FAIL" "$(echo "$AUS" | grep -c 'FAIL  ohne_rule.py')" "1"
pruefe "und Rueckgabe 1" "$RC" "1"
pruefe "kein PRUEFEN ohne Rule" "$(echo "$AUS" | grep -c 'PRUEFEN')" "0"

echo
echo "=============================================================================="
echo "  $OK ok, $ROT rot"
echo "=============================================================================="
[ "$ROT" -eq 0 ]
