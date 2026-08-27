#!/usr/bin/env bash
# BESTANDS-PASS (v5.22.0) — jeder Skill sieht sich seinen eigenen Bestand an.
#
# ⛔ WOZU. `/mind-all` ist eine Anhaenge-Maschine: fuenf Skills tragen nach, keiner
#    sieht zurueck. Gemessen wuchs der Dauerkontext an EINEM Tag um +21 %.
#    Nutzer-Auftrag 27.08.2026: "die anderen skills sollen von vorne rein sauber
#    arbeiten … auch gucken: braucht man das, kann das weg, steht das schon woanders."
#
# ⛔ DIE WICHTIGSTE PRUEFUNG IST FALL 4: kein Inhalt aus einer Memory-Datei darf je
#    in einer Ausgabe landen. Der Pass liest fremde Memory-Bestaende, und in
#    `APP - Zustellplan` stehen dort Abonnenten- und Routendaten; `mind_debug_write`
#    schickt Befundtexte in den GEMEINSAMEN Debug-Ordner aller Projekte.
#    Geprueft wird mit einer Losung, die NUR im Dateiinhalt steht.
#
# ⛔ DIE ZWEITWICHTIGSTE IST FALL 3: ein Skill ohne Bestands-Block macht den Lauf
#    zum Teilsync. Ohne diese Kopplung waere der ganze Pass unverbindlich —
#    Schweigen und Sauberkeit waeren wieder ununterscheidbar (v5.3.1, v5.19.0).
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_bestandspass.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
ST="$CLAUDE_PLUGIN_ROOT/references/cleaner_stichprobe.py"
LIB="$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
[ -f "$ST" ]  || { echo "cleaner_stichprobe.py fehlt: $ST" >&2; exit 2; }
[ -f "$LIB" ] || { echo "lib.sh fehlt: $LIB" >&2; exit 2; }
command -v cygpath >/dev/null 2>&1 && STW=$(cygpath -w "$ST") || STW="$ST"
OK=0; ROT=0

janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

echo "== 1/6  Alle fuenf Skills tragen den Block und zeigen auf die Referenz =="
for s in mind-claudemd mind-memory mind-rules mind-files mind-update; do
  F="$CLAUDE_PLUGIN_ROOT/skills/$s/SKILL.md"
  janein "$s ruft cleaner_stichprobe" "ja" \
    "$(grep -q 'cleaner_stichprobe.py' "$F" && echo ja || echo nein)"
  janein "$s zeigt auf references/bestands-pass.md" "ja" \
    "$(grep -q 'references/bestands-pass.md' "$F" && echo ja || echo nein)"
  janein "$s quittiert mit --quittung" "ja" \
    "$(grep -q -- '--quittung --skill' "$F" && echo ja || echo nein)"
done
janein "die Referenz existiert" "ja" \
  "$([ -f "$CLAUDE_PLUGIN_ROOT/references/bestands-pass.md" ] && echo ja || echo nein)"

echo "== 2/6  Stichprobe: die am laengsten ungeprueften zuerst =="
D=$(mktemp -d); P="$D/proj"; mkdir -p "$P/.claude/rules" "$P/.claude-mind"
for n in alpha beta gamma delta; do
  printf -- '---\ndescription: Regel %s\nglobs: ["**/*"]\n---\n\n# %s\n\nMUST etwas.\n' \
    "$n" "$n" > "$P/.claude/rules/$n.md"
done
A=$(python "$STW" "$P" --skill mind-rules --verzeichnis "$P/.claude/rules" 2>&1)
janein "3 Eintraege vorgelegt" "3" "$(echo "$A" | grep -c '^  PRUEFEN:')"
B=$(python "$STW" "$P" --skill mind-rules --verzeichnis "$P/.claude/rules" 2>&1)
ERSTE_A=$(echo "$A" | grep -m1 '^  PRUEFEN:' | sed 's/.*rules.//')
janein "zweiter Lauf legt NICHT dieselbe Datei zuerst vor" "nein" \
  "$(echo "$B" | grep -m1 '^  PRUEFEN:' | grep -q "$ERSTE_A" && echo ja || echo nein)"

echo "== 3/6  NEGATIVKONTROLLE: fehlender Block -> TEILSYNC =="
tsync() { # $1 = umfang-Zeile  -> RC von mind_sync_voll
  ( . "$LIB" >/dev/null 2>&1
    T=$(mktemp)
    printf 'ts=x\ntokens=1\numfang=%s\nungepruef=\n' "$1" > "$T"
    mind_sync_voll "$T"; R=$?; rm -f "$T"; exit $R )
}
tsync "5/5 skills 4/4 agents 5/5 bestand"; janein "5/5 bestand = vollstaendig" "0" "$?"
tsync "5/5 skills 4/4 agents 4/5 bestand"; janein "4/5 bestand = TEILSYNC" "1" "$?"
tsync "5/5 skills 4/4 agents 0/5 bestand"; janein "0/5 bestand = TEILSYNC" "1" "$?"
# ⛔ FAIL-SAFE-RICHTUNG: ein Merker OHNE bestand-Paar (Bestand aus v5.21.x und
#    aelter) gilt weiter als vollstaendig. Diese Aenderung kann das Tor also nur
#    STRENGER machen, nie milder — dieselbe Richtung wie bei ungepruef= in v5.21.1.
tsync "5/5 skills 4/4 agents"; janein "Altmerker ohne bestand = vollstaendig" "0" "$?"
# ⛔ Die vier Faelle oben pruefen mind_sync_voll gegen einen HANDGESCHRIEBENEN
#    Merker. Sie belegen NICHT, dass /mind-all das Paar ueberhaupt erzeugt — und
#    ohne den Erzeuger ist das Tor wirkungslos. Zwei Signale, eine Zusicherung:
#    genau der Fehler, den die Gegenkontrolle zu test_kontext_bilanz.sh am
#    27.08.2026 aufgedeckt hat. Deshalb hier die zweite Haelfte.
MA="$CLAUDE_PLUGIN_ROOT/skills/mind-all/SKILL.md"
janein "mind-all zaehlt bestand= und haengt <n>/5 an" "ja" \
  "$(grep -q '_BEST/5 bestand' "$MA" && echo ja || echo nein)"
janein "mind-all liest auch analyzed-scopes.done" "ja" \
  "$(grep -q 'analyzed-scopes.done' "$MA" && echo ja || echo nein)"
janein "fehlende Quittungen landen in ungepruef=" "ja" \
  "$(grep -q 'UNGEPRUEFT_BESTAND' "$MA" && echo ja || echo nein)"

echo "== 4/6  ⛔ KEIN Memory-INHALT in irgendeiner Ausgabe =="
MEM="$D/memory"; mkdir -p "$MEM"
LOSUNG="ZZQX-ABONNENT-4711-GEHEIM"
printf -- '---\nname: kunden\ndescription: Kundendaten\n---\n\n%s\nRoute 12\n' \
  "$LOSUNG" > "$MEM/kunden.md"
printf -- '---\nname: MEMORY\ndescription: Index\n---\n\n- [kunden](kunden.md)\n' \
  > "$MEM/MEMORY.md"
C=$(python "$STW" "$P" --skill mind-memory --verzeichnis "$MEM" 2>&1)
janein "Ausgabe nennt die Dateien" "ja" \
  "$(echo "$C" | grep -q 'kunden.md' && echo ja || echo nein)"
janein "Ausgabe enthaelt die Losung NICHT" "nein" \
  "$(echo "$C" | grep -q "$LOSUNG" && echo ja || echo nein)"
E=$(python "$STW" "$P" --zeige 2>&1)
janein "--zeige enthaelt die Losung NICHT" "nein" \
  "$(echo "$E" | grep -q "$LOSUNG" && echo ja || echo nein)"
janein "der Rotationszustand enthaelt die Losung NICHT" "nein" \
  "$(grep -q "$LOSUNG" "$P/.claude-mind/bestand-rotation.jsonl" && echo ja || echo nein)"

echo "== 5/6  Laufbudget: 15 im Kettenlauf, dann (nichts) mit Begruendung =="
D2=$(mktemp -d); P2="$D2/proj"; mkdir -p "$P2/.claude/rules" "$P2/.claude-mind"
n=0; while [ $n -lt 30 ]; do
  printf '# R%s\n\nMUST etwas.\n' "$n" > "$P2/.claude/rules/r$n.md"; n=$((n+1)); done
echo "run_started=$(date +%s)" > "$P2/.claude-mind/analyzed-scopes"
GES=0
for s in mind-claudemd mind-memory mind-rules mind-files mind-update; do
  R=$(python "$STW" "$P2" --skill "$s" --verzeichnis "$P2/.claude/rules" 2>&1)
  GES=$((GES + $(echo "$R" | grep -c '^  PRUEFEN:')))
done
janein "fuenf Skills ziehen zusammen 15" "15" "$GES"
SECHS=$(python "$STW" "$P2" --skill mind-extra --verzeichnis "$P2/.claude/rules" 2>&1)
janein "der sechste bekommt (nichts)" "ja" \
  "$(echo "$SECHS" | grep -q '(nichts)' && echo ja || echo nein)"
janein "und die Meldung nennt den GRUND" "ja" \
  "$(echo "$SECHS" | grep -q 'Laufbudget erschoepft' && echo ja || echo nein)"

echo "== 6/6  Fail-open: fehlendes Werkzeug toetet nichts =="
janein "Aufruf ohne --skill -> Rueckgabe 2, kein Absturz" "2" \
  "$(python "$STW" "$P2" --verzeichnis "$P2/.claude/rules" >/dev/null 2>&1; echo $?)"
janein "Quittung ohne analyzed-scopes -> Rueckgabe 0" "0" \
  "$(python "$STW" "$D2" --quittung --skill mind-rules --geprueft 0 --stichprobe 0 \
     >/dev/null 2>&1; echo $?)"
janein "Quittung landet in analyzed-scopes" "ja" \
  "$(python "$STW" "$P2" --quittung --skill mind-rules --geprueft 2 --stichprobe 3 \
     >/dev/null 2>&1; grep -q '^bestand=mind-rules:2/3' "$P2/.claude-mind/analyzed-scopes" \
     && echo ja || echo nein)"

rm -rf "$D" "$D2"
echo
echo "  $OK ok, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
