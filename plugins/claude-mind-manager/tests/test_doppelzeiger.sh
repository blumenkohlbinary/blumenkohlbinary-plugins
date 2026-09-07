#!/usr/bin/env bash
# v5.39.0 / ZIEL 3: der Doppelzeiger ist ein GATE, kein Hinweis mehr.
#
# ⛔ WARUM. Bis v5.38.0 stand der Command als HINWEIS im Umzugs-Gate, mit der
#    Begruendung "der Pfad traegt (4/4)". Das stimmt und reicht nicht:
#      Pfad     4 von 4 gefolgt  -> ZUVERLAESSIG, aber niemand ruft ihn freiwillig
#      Command  20 % ohne Hook   -> BEQUEM, aber unzuverlaessig
#    Erst beide zusammen bringen die zwei Messungen zusammen.
#
# ⭐ Die Bauform stammt vom Nutzer und steht FUENFMAL in seinen globalen Regeln.
#    Das Plugin hat sie fuenfmal gesehen und nie gelernt — Klasse `sichtbarkeit`.
#
# ⭐ POSITIV- UND NEGATIVKONTROLLE STEHEN NEBENEINANDER. Ein Gate, das immer
#    bricht, besteht sonst jede Probe der Form "es muss brechen".
set -u
R="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
U="$R/references/cleaner_umzug.py"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
GRUEN=0; ROT=0
pruef() { if [ "$2" = "$3" ]; then GRUEN=$((GRUEN+1)); echo "  [ok ] $1"
  else ROT=$((ROT+1)); echo "  [ROT] $1 (erwartet '$2', war '$3')"; fi; }
hat() { case "$3" in *"$2"*) GRUEN=$((GRUEN+1)); echo "  [ok ] $1";;
  *) ROT=$((ROT+1)); echo "  [ROT] $1 — '$2' fehlt";; esac; }

SK="$TMP/skills/beispiel"; mkdir -p "$SK"
cat > "$TMP/alt.md" <<'MD'
# Beispiel
⛔ NIE ohne Sicherung loeschen.
Die Herleitung: gemessen am 21.08.2026 lagen dort 32 MB.
Der Aufruf lautet `python tools/rollback.py list`.
MD
cat > "$SK/SKILL.md" <<'MD'
---
name: beispiel
description: Ein Beispiel-Command fuer den Prueflauf des Doppelzeiger-Gates, lang genug fuer die Beschreibungsgrenze.
---
# Beispiel — Volltext
Die Herleitung: gemessen am 21.08.2026 lagen dort 32 MB.
Der Aufruf lautet `python tools/rollback.py list`.
MD

# --- Kurz-Rule A: nennt PFAD und COMMAND (der Doppelzeiger) ----------------
cat > "$TMP/kurz-beide.md" <<MD
---
name: beispiel
description: Die Leitplanke zum Beispiel, kurz gehalten und mit beiden Zeigern versehen.
---
# Beispiel — die Leitplanke
⛔ NIE ohne Sicherung loeschen.

> Alles Weitere steht im Command \`/beispiel\`.
> Wird er nicht angeboten: \`$SK/SKILL.md\` direkt lesen.
MD

# --- Kurz-Rule B: nennt NUR den Pfad (der alte Zustand) --------------------
cat > "$TMP/kurz-nur-pfad.md" <<MD
---
name: beispiel
description: Die Leitplanke zum Beispiel, kurz gehalten, aber ohne den Command-Namen.
---
# Beispiel — die Leitplanke
⛔ NIE ohne Sicherung loeschen.

> Alles Weitere: \`$SK/SKILL.md\` direkt lesen.
MD

lauf() { python "$U" --alt "$TMP/alt.md" --kurz "$1" --skill "$SK/SKILL.md" 2>&1; }

echo "=== 1) ⭐ POSITIVKONTROLLE: beide Zeiger -> Gate haelt ==="
A=$(lauf "$TMP/kurz-beide.md"); RC_A=$?
hat "DOPPELZEIGER wird als Gate gefuehrt" "DOPPELZEIGER" "$A"
hat "   ... und es haelt" "OK    DOPPELZEIGER" "$A"
pruef "Rueckgabe 0" 0 "$RC_A"

echo
echo "=== 2) ⭐ NEGATIVKONTROLLE: nur der Pfad -> Gate BRICHT ==="
B=$(lauf "$TMP/kurz-nur-pfad.md"); RC_B=$?
hat "BRUCH wird gemeldet" "BRUCH DOPPELZEIGER" "$B"
hat "   ... und der Text sagt WARUM" "nur gelesen, wenn jemand ihn sucht" "$B"
hat "   ... und der Lauf sagt NICHT UMZIEHEN" "NICHT UMZIEHEN" "$B"
pruef "Rueckgabe 1" 1 "$RC_B"

echo
echo "=== 3) ⛔ Der Unterschied ist ECHT, nicht nur ein Etikett ==="
# Bis v5.38.0 hiess das Gate "HINWEIS COMMAND" und wurde in der Auswertung
# uebersprungen (n.startswith("HINWEIS")). Es konnte den Lauf NIE brechen.
pruef "beide Rueckgaben unterscheiden sich" "0 1" "$RC_A $RC_B"
case "$A$B" in *"HINWEIS COMMAND"*) ROT=$((ROT+1));
  echo "  [ROT] das alte Etikett HINWEIS COMMAND steht noch da" ;;
  *) GRUEN=$((GRUEN+1)); echo "  [ok ] das alte Etikett HINWEIS COMMAND ist weg" ;; esac

echo
echo "=== 4) Der PFAD bleibt das staerkere Gate ==="
hat "PFAD wird weiterhin eigenstaendig geprueft" "PFAD" "$A"

echo
echo "  $GRUEN gruen · $ROT rot"
[ "$ROT" -eq 0 ]
