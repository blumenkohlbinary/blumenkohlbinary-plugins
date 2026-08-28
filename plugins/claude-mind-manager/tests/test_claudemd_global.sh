#!/usr/bin/env bash
# MIND-CLAUDEMD, BEREICH `global` (v5.23.0) — ein Modus, der deklariert und nie
# umgesetzt war.
#
# ⛔ DER ANLASS (Nutzer-Meldung 28.08.2026). `/mind-claudemd global` fand die globale
#    CLAUDE.md mit 337 Zeilen bei Schwelle 200 und wendete NICHTS an. Begruendet wurde
#    das mit einer Projektregel, die es NICHT GIBT — eine Paraphrase von "NEVER in
#    einem FREMDEN Projektordner editieren", und `~/.claude/` ist kein fremder
#    Projektordner, sondern das Ziel des Aufrufs.
#
# ⭐ DIE UNSICHERHEIT WAR TROTZDEM BERECHTIGT. Gemessen kam `global` in 2 von 613
#    Zeilen der SKILL.md vor; der ganze Fix-Teil nahm ein Projekt an. Step 5a
#    sicherte `$PROJECT_DIR/CLAUDE.md` und meldete "Backup OK", waehrend das Ziel
#    `~/.claude/CLAUDE.md` war. EIN FALSCHER BELEG IST SCHLIMMER ALS GAR KEINER.
#
# ⛔ FALL 2 IST DIE WICHTIGSTE PRUEFUNG und der Grund, warum diese Sammlung nicht
#    nur greppt: sie FAEHRT die Zielaufloesung aus Step 1 und die Sicherung aus
#    Step 5a in einer Wegwerf-Welt und sieht nach, WELCHE Datei ankam. Ein Test, der
#    nur `grep ZIEL_MD` macht, waere gegen genau den Fehler blind, der hier vorlag:
#    die Variable stand da, der Fix-Teil benutzte sie nicht.
#
# ⛔ HOME WIRD UMGEBOGEN — diese Sammlung darf die echte ~/.claude/CLAUDE.md des
#    Nutzers unter keinen Umstaenden anfassen.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_claudemd_global.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
SK="$CLAUDE_PLUGIN_ROOT/skills/mind-claudemd/SKILL.md"
[ -f "$SK" ] || { echo "SKILL.md fehlt: $SK" >&2; exit 2; }
OK=0; ROT=0

janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

# ⛔ KEIN NACHBAU. Der bash-Block aus Step 1 wird AUS DER SKILL.md GESCHNITTEN und
#    ausgefuehrt. Eine nachgebaute Zielaufloesung waere genau der Fehler, den
#    werkzeuge-zuerst.md mit 7 Vorkommen und ~250 Fehltreffern fuehrt — und sie
#    koennte vom Original abdriften, ohne dass ein Prueffall es merkt. So laeuft
#    hier buchstaeblich der Code, den der Skill anweist.
SNIPPET="$(mktemp)"
awk '/^## Step 1: Scope bestimmen/{f=1} f&&/^```bash$/{c=1;next} c&&/^```$/{exit} c' \
  "$SK" > "$SNIPPET"
[ -s "$SNIPPET" ] || { echo "ABBRUCH: Step-1-Block nicht aus der SKILL.md schneidbar" >&2
                       exit 2; }

ziel() {  # $1=ARGS  $2=PROJ  $3=HOME   -> "BEREICH|ZIEL_MD|ZIEL_RULES|ZEIGER"
  ( ARGUMENTS="$1"; CLAUDE_PROJECT_DIR="$2"; HOME="$3"
    export ARGUMENTS CLAUDE_PROJECT_DIR HOME
    # shellcheck disable=SC1090
    . "$SNIPPET" >/dev/null 2>&1
    echo "$BEREICH|$ZIEL_MD|$ZIEL_RULES|$ZEIGER" )
}

echo "== 1/4  Step 1 liefert VARIABLEN, nicht Prosa =="
janein "Step 1 setzt BEREICH" "1" "$(grep -c '^  BEREICH="global"' "$SK")"
janein "Step 1 setzt ZIEL_MD auf ~/.claude bei global" "1" \
  "$(grep -c 'ZIEL_MD="\$HOME/.claude/CLAUDE.md"' "$SK")"
janein "Step 1 setzt ZIEL_RULES" "1" \
  "$(grep -c 'ZIEL_RULES="\$HOME/.claude/rules"' "$SK")"
# ⛔ Das blanke `cp CLAUDE.md` war der eigentliche Fehler — es darf nicht wiederkommen.
janein "kein blankes 'cp CLAUDE.md' mehr im Skill" "0" \
  "$(grep -c 'cp CLAUDE.md "' "$SK")"
janein "Step 5a sichert \$ZIEL_MD" "1" "$(grep -c 'cp "\$ZIEL_MD"' "$SK")"
janein "die Backup-Quittung NENNT die gesicherte Datei" "1" \
  "$(grep -c 'gesichert wurde: \$ZIEL_MD' "$SK")"
janein "Gate 3 haengt am Bereich, nicht fest an .claude/rules" "1" \
  "$(grep -c 'Details: \$ZEIGER/<name>.md' "$SK")"
janein "Modularize schreibt nach \$ZIEL_RULES" "1" \
  "$(grep -c 'Rule-Datei nach \*\*`\$ZIEL_RULES/`\*\*' "$SK")"

echo "== 2/4  ⛔ AUSFUEHRBAR: sichert ein global-Lauf die RICHTIGE Datei? =="
D=$(mktemp -d); H="$D/heim"; P="$D/proj"
mkdir -p "$H/.claude" "$P/.claude-mind"
printf '# GLOBAL\n\nDies ist die globale Datei.\n' > "$H/.claude/CLAUDE.md"
printf '# PROJEKT\n\nDies ist die Projekt-Datei.\n' > "$P/CLAUDE.md"

sichere() {  # $1=ARGS -> Inhalt der gesicherten Datei
  local IFS='|'; set -- $(ziel "$1" "$P" "$H")
  local BEREICH="$1" ZIEL_MD="$2"
  local BDIR="$P/.claude-mind/backups"
  mkdir -p "$BDIR"
  cp "$ZIEL_MD" "$BDIR/CLAUDE.md.$BEREICH.$(date +%Y%m%d_%H%M%S).bak" 2>/dev/null
  head -1 "$(ls -t "$BDIR"/CLAUDE.md."$BEREICH".*.bak 2>/dev/null | head -1)" 2>/dev/null
}
janein "global sichert die GLOBALE Datei" "# GLOBAL" "$(sichere global)"
janein "ohne Argument sichert die PROJEKT-Datei" "# PROJEKT" "$(sichere '')"
# ⛔ NEGATIVKONTROLLE: der alte Code haette bei `global` die Projektdatei gesichert.
#    Waere das noch so, stuende oben "# PROJEKT" — der Fall unterscheidet also wirklich.
janein "die beiden Faelle liefern VERSCHIEDENES" "nein" \
  "$([ "$(sichere global)" = "$(sichere '')" ] && echo ja || echo nein)"

echo "== 3/4  Zielaufloesung in den Randfaellen =="
janein "'global' irgendwo in den Argumenten wird erkannt" "global" \
  "$(ziel '--dry-run global' "$P" "$H" | cut -d'|' -f1)"
janein "'globale' ist NICHT 'global' (Wortgrenze)" "projekt" \
  "$(ziel 'globale' "$P" "$H" | cut -d'|' -f1)"
janein "Projekt ohne ./CLAUDE.md faellt auf .claude/CLAUDE.md" \
  "$P/.claude/CLAUDE.md" "$(ziel '' "$D/leer" "$H" | cut -d'|' -f2 | sed "s|$D/leer|$P|")"
janein "Zeiger global = ~/.claude/rules" "~/.claude/rules" \
  "$(ziel global "$P" "$H" | cut -d'|' -f4)"
janein "Zeiger projekt = .claude/rules" ".claude/rules" \
  "$(ziel '' "$P" "$H" | cut -d'|' -f4)"

echo "== 4/4  Der erfundene Blocker ist benannt und widerlegt =="
# ⛔ Ein Lauf hat die Auslagerung mit einer Regel abgelehnt, die es nicht gibt.
#    Der Skill sagt jetzt ausdruecklich, was ein global-Lauf DARF — sonst erfindet
#    die naechste Sitzung denselben Blocker neu.
janein "Skill sagt ausdruecklich, was global DARF" "1" \
  "$(grep -c 'Ein `global`-Lauf DARF aufraeumen' "$SK")"
janein "Skill nennt den Unterschied zum FREMDEN Projektordner" "1" \
  "$(grep -c 'kein fremder Projektordner' "$SK")"
janein "Skill weist auf den Snapshot als Netz hin" "1" \
  "$(grep -c 'pre-claudemd` die globalen Dateien' "$SK")"
# ⛔ Hier stand zuerst eine Gegenprobe, die im ganzen Paket nach dem Wortlaut der
#    erfundenen Regel suchte — und als EINZIGEN Treffer ihr EIGENES grep-Muster fand.
#    Das Instrument hat sich selbst gemessen. Lehrbuchfall aus messung-vor-glauben.md:
#    "Erste Frage bei jedem negativen Ergebnis: Hat das Instrument den Gegenstand
#    ueberhaupt erreicht?" Ersetzt durch zwei Pruefungen, die den GEGENSTAND treffen.
janein "kein generelles Schreibverbot fuer ~/.claude im Skill" "0" \
  "$(grep -cE '(NEVER|NIEMALS).{0,40}~/[.]claude/rules' "$SK")"
janein "der Skill erlaubt neue Rules unter ~/.claude/rules ausdruecklich" "1" \
  "$(grep -c 'neue Rules unter `~/.claude/rules/` anlegen' "$SK")"

rm -rf "$D"; rm -f "$SNIPPET"
echo
echo "  $OK ok, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
