#!/usr/bin/env bash
# Tool->Rule-Nachweis (mind_check_tools_have_rules) — Regression zu v5.7.1/v5.7.3.
#
# Der Befund kam aus einem FREMDEN Projekt (APP - Zustellplan) ueber den Debug-Ordner:
# die Pruefung sah nur tools/. v5.7.1 hat den Fix als KOMMENTAR eingebaut, nicht als Code —
# `_wurzel_py` wurde gesammelt und nie benutzt, und bei fehlendem tools/ stieg die Funktion
# vorher mit `return 0` aus. Fall 5 unten ist genau dieser Fall.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_toolrule.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
. "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"

OK=0; ROT=0
pruef() { # name erwartet_rc erwartet_text ist_rc ist_text
  local n="$1" erc="$2" etxt="$3" irc="$4" itxt="$5"
  if [ "$irc" = "$erc" ] && printf '%s' "$itxt" | grep -q -- "$etxt"; then
    echo "  [ok ] $n"; OK=$((OK+1))
  else
    echo "  [ROT] $n"
    echo "        erwartet rc=$erc + '$etxt'"
    echo "        bekommen rc=$irc"
    printf '%s\n' "$itxt" | sed 's/^/        | /'
    ROT=$((ROT+1))
  fi
}

bau() { # verzeichnis
  local d="$1"; mkdir -p "$d/.claude/rules"
}

echo "=== Tool->Rule-Nachweis ==="

# --- 1 · tools/ + Rule mit globs, die den AUFRUFPFAD nennt -> PASS ---------
T=$(mktemp -d); bau "$T"; mkdir -p "$T/tools"
echo 'print(1)' > "$T/tools/backup_tools.py"
printf 'globs: **/*\n---\npython tools/backup_tools.py verify <snap>\n' > "$T/.claude/rules/backup.md"
O=$(mind_check_tools_have_rules "$T" 2>&1); R=$?
pruef "tools/ mit Aufrufpfad in glob-Rule" 0 "PASS  backup_tools.py" "$R" "$O"
rm -rf "$T"

# --- 2 · Rule OHNE globs -> FAIL (sie wuerde nie laden) --------------------
T=$(mktemp -d); bau "$T"; mkdir -p "$T/tools"
echo 'print(1)' > "$T/tools/backup_tools.py"
printf '# Backup\npython tools/backup_tools.py verify\n' > "$T/.claude/rules/backup.md"
O=$(mind_check_tools_have_rules "$T" 2>&1); R=$?
# ⛔ v5.34.0: DIESE ZUSICHERUNG WAR UMGEKEHRT — und sie kodierte das Gegenteil
#    der eigenen Referenz. Bis v5.33.0 stand hier:
#        pruef "Rule ohne globs zaehlt nicht" 1 "FAIL  backup_tools.py"
#    `references/context-mechanics.md:59` sagt aber woertlich:
#        "Rule without `paths:`/`globs:` frontmatter -> ALWAYS LOADED"
#    Eine Rule OHNE globs ist damit die am SICHERSTEN erreichbare — und der
#    Nachweis verwarf genau sie und meldete das Werkzeug als unerreichbar.
#
# ⭐ In VIER Projekten gemessen (20.08. hier, 30.08. APP - Zustellplan,
#    03.09. Creator, 03.09. hier): der Ladegrund `path_glob_match` kommt in
#    3667 Protokollzeilen NULL MAL vor. `globs:` steuert das Laden nicht. Die
#    alte Bedingung war also nicht nur invertiert, sondern WIRKUNGSLOS.
#
# ⚠ WARUM DAS KEIN WEGKALIBRIEREN IST (messung-vor-glauben.md §2): die
#   Zusicherung bleibt gleich streng — sie verlangt weiter ein Urteil zu diesem
#   Fall. Umgedreht wurde der ERWARTETE WERT, weil die Spezifikation dahinter
#   falsch war. Derselbe Weg wie test_cleaner.sh in v5.27.0 und
#   test_leitplanke.sh in v5.25.0, beide mit Grund im Test.
pruef "⭐ Rule OHNE globs ist IMMER erreichbar -> PASS" 0 "PASS  backup_tools.py" "$R" "$O"
pruef "   ... und der Text sagt WIE" 0 "[immer]" "$R" "$O"
rm -rf "$T"

# --- 3 · nur der NAME genannt (Historien-Aufzaehlung) -> FAIL -------------
#     Der Zufallstreffer-Fall aus v5.2.2: architecture.md nannte mutation_guard.py
#     in einer Versionsliste, und die Pruefung meldete PASS.
T=$(mktemp -d); bau "$T"; mkdir -p "$T/tools"
echo 'print(1)' > "$T/tools/mutation_guard.py"
printf 'globs: **/*\n---\nv4.0 lieferte mutation_guard.py aus.\n' > "$T/.claude/rules/historie.md"
O=$(mind_check_tools_have_rules "$T" 2>&1); R=$?
pruef "blosse Nennung ist kein Nachweis" 1 "FAIL  mutation_guard.py" "$R" "$O"
rm -rf "$T"

# --- 4 · KEIN tools/, Werkzeug im Wurzelverzeichnis + Rule -> PASS --------
T=$(mktemp -d); bau "$T"
echo 'print(1)' > "$T/pruefer.py"
printf '# Projekt\nWerkzeug: pruefer.py\n' > "$T/CLAUDE.md"
printf 'globs: **/*.py\n---\nAufruf: python pruefer.py --alle\n' > "$T/.claude/rules/pruef.md"
O=$(mind_check_tools_have_rules "$T" 2>&1); R=$?
pruef "Wurzel-Werkzeug MIT Rule" 0 "PASS  pruefer.py" "$R" "$O"
rm -rf "$T"

# --- 5 · DIE REGRESSION: kein tools/, Wurzel-Werkzeug OHNE Rule -> FAIL ---
#     Bis v5.7.2 meldete das "kein tools/ vorhanden — nichts zu pruefen", rc 0.
T=$(mktemp -d); bau "$T"
echo 'print(1)' > "$T/pruefer.py"
printf '# Projekt\nWerkzeug: pruefer.py\n' > "$T/CLAUDE.md"
printf 'globs: **/*.md\n---\nIrgendeine andere Regel.\n' > "$T/.claude/rules/andere.md"
O=$(mind_check_tools_have_rules "$T" 2>&1); R=$?
pruef "REGRESSION: Wurzel-Werkzeug ohne Rule wird gefunden" 1 "FAIL  pruefer.py" "$R" "$O"
rm -rf "$T"

# --- 6 · kein Fehlalarm: setup.py, das CLAUDE.md NICHT nennt -------------
T=$(mktemp -d); bau "$T"
echo 'print(1)' > "$T/setup.py"
printf '# Projekt ohne Werkzeuge\n' > "$T/CLAUDE.md"
O=$(mind_check_tools_have_rules "$T" 2>&1); R=$?
# Die Zusicherung prueft ABWESENHEIT, nicht einen Meldungstext. Ein Text aendert sich beim
# naechsten Umbau; "setup.py darf nicht als Befund auftauchen" bleibt richtig.
if [ "$R" = "0" ] && ! printf '%s' "$O" | grep -q "setup.py"; then
  echo "  [ok ] ungenanntes setup.py ist kein Befund"; OK=$((OK+1))
else
  echo "  [ROT] ungenanntes setup.py wurde faelschlich gemeldet (rc=$R)"
  printf '%s\n' "$O" | sed 's/^/        | /'; ROT=$((ROT+1))
fi
rm -rf "$T"

# --- 7 · NEGATIVKONTROLLE: unterscheidet die Pruefung ueberhaupt? --------
#     Ein Stub, der immer 0 liefert, MUSS an Fall 5 scheitern. Ohne diesen Lauf
#     waere nicht belegt, dass die Zusicherung oben etwas misst.
mind_check_tools_have_rules_STUB() { echo "  alles in Ordnung"; return 0; }
T=$(mktemp -d); bau "$T"
echo 'print(1)' > "$T/pruefer.py"
printf '# Projekt\nWerkzeug: pruefer.py\n' > "$T/CLAUDE.md"
O=$(mind_check_tools_have_rules_STUB "$T" 2>&1); R=$?
if [ "$R" = "1" ]; then
  echo "  [ROT] Negativkontrolle: Stub haette bestehen muessen"; ROT=$((ROT+1))
else
  echo "  [ok ] Negativkontrolle: blinder Stub faellt an Fall 5 durch"; OK=$((OK+1))
fi
rm -rf "$T"

echo
echo "=================================="
echo "  $OK bestanden, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
