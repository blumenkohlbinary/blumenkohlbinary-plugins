#!/usr/bin/env bash
# AGENT-QUITTUNG: ERWARTUNGSZAHL UND WIEDERHOLUNG (v5.21.2)
#
# Zwei Befunde aus dem 26.08.2026, beide gemessen, beide im plan.md als B1/B2.
#
# B1 ⛔ `Pc Forschung` meldete `DISPATCH=0`, obwohl VIER Agenten liefen.
#    `mind_agent_dispatch` ist eine PROSA-Anweisung in mind-update/SKILL.md, die
#    ein Modell abtippen muss. Ein Bash-Aufruf kann keinen Agenten STARTEN — die
#    Quittung ist also nicht vollstaendig automatisierbar. Ihr FEHLEN ist es:
#    mit einer Erwartungszahl laesst sich "nie dispatcht" von "dispatcht, aber
#    nie quittiert" wenigstens als ZWEIFEL benennen, statt es zu behaupten.
#
# B2 ⛔ Ein zweiter, engerer Dispatch lieferte ein Ergebnis; die Bilanz blieb bei
#    LEER=1. Der Bereich war geprueft, das Instrument konnte es nicht sagen.
#    ⭐ BEWUSST NICHT am selben Tag geaendert, an dem der Befund entstand — das
#       waere gewesen, das Instrument anzupassen, damit der eigene Lauf besteht
#       (messung-vor-glauben.md §2). Deshalb ein eigener, spaeterer Schritt.
#    ⚠ Der Verlauf bleibt SICHTBAR. Ein gestorbener Agent darf nicht spurlos
#      verschwinden — das ist der Zweck der ganzen Quittung.
#
# ⛔ NEUE DATEI. tests/test_quittung.sh bleibt unangetastet und muss weiter
#    gruen sein: seine Kopfzeilen-Zusicherungen ("DISPATCH=4 ERGEBNIS=4 LEER=0
#    STUMM=0") sind der Grund, warum das Format hier NICHT erweitert wurde.
#    Alles Neue steht auf eigenen Zeilen.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_quittung_erwartet.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
. "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh"
OK=0; ROT=0
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P"

pruefe() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — ist '$2', soll '$3'"; ROT=$((ROT+1)); fi; }

echo "=============================================================================="
echo "  B1 — die Erwartungszahl macht den Zweifel sagbar"
echo "=============================================================================="

# --- 1) vier geplant, KEINER quittiert -------------------------------------
mind_agent_quittung_start "$P" 4
AUS=$(mind_agent_bilanz "$P"); RC=$?
pruefe "0 von 4 -> Rueckgabe 2" "$RC" "2"
pruefe "ERWARTET steht in der Ausgabe" "$(echo "$AUS" | grep -c 'ERWARTET=4')" "1"
pruefe "nennt beide Moeglichkeiten" \
       "$(echo "$AUS" | grep -c 'NICHT unterscheidbar')" "1"
# ⛔ Der alte Satz muss BLEIBEN — test_quittung.sh:83 zaehlt ihn.
pruefe "alter Satz bleibt erhalten" \
       "$(echo "$AUS" | grep -c 'Fan-out hat nicht stattgefunden')" "1"

# --- 2) vier geplant, zwei quittiert ---------------------------------------
mind_agent_quittung_start "$P" 4
for b in claude-md memory; do
  mind_agent_dispatch "$b" "$P"; mind_agent_ergebnis "$b" 4096 "$P"
done
AUS=$(mind_agent_bilanz "$P"); RC=$?
pruefe "2 von 4 -> Rueckgabe 1" "$RC" "1"
pruefe "sagt 'nur 2 von 4'" "$(echo "$AUS" | grep -c 'nur 2 von 4')" "1"
# ⭐ DAS ist der Creator-Fall vom 24.08.2026: zwei dispatcht, beide mit Ergebnis.
#    Vorher ergab das Rueckgabe 0 — "alles gut" — und der Lauf galt als vollstaendig.
pruefe "und NICHT mehr Rueckgabe 0" "$([ "$RC" = 0 ] && echo doch || echo nein)" "nein"

# --- 3) vier geplant, vier sauber ------------------------------------------
mind_agent_quittung_start "$P" 4
for b in claude-md memory rules custom-context; do
  mind_agent_dispatch "$b" "$P"; mind_agent_ergebnis "$b" 4096 "$P"
done
AUS=$(mind_agent_bilanz "$P"); RC=$?
pruefe "4 von 4 -> Rueckgabe 0" "$RC" "0"
pruefe "Kopfzeile UNVERAENDERT" "$(echo "$AUS" | head -1)" \
       "DISPATCH=4 ERGEBNIS=4 LEER=0 STUMM=0"

# --- 4) ⛔ NEGATIVKONTROLLE: ohne Erwartungszahl aendert sich NICHTS --------
#     Jeder Bestand ohne $2 muss sich exakt wie vorher verhalten.
mind_agent_quittung_start "$P"
AUS=$(mind_agent_bilanz "$P"); RC=$?
pruefe "ohne Erwartungszahl -> weiterhin Rueckgabe 2" "$RC" "2"
pruefe "und KEINE ERWARTET-Zeile" "$(echo "$AUS" | grep -c 'ERWARTET=')" "0"
pruefe "und KEIN Zweifels-Satz" "$(echo "$AUS" | grep -c 'NICHT unterscheidbar')" "0"

echo
echo "=============================================================================="
echo "  B2 — je Bereich zaehlt der LETZTE Eintrag"
echo "=============================================================================="

# --- 5) leer, dann erfolgreich wiederholt ----------------------------------
mind_agent_quittung_start "$P" 1
mind_agent_dispatch "custom-context" "$P"; mind_agent_ergebnis "custom-context" 0 "$P"
mind_agent_dispatch "custom-context" "$P"; mind_agent_ergebnis "custom-context" 2400 "$P"
AUS=$(mind_agent_bilanz "$P"); RC=$?
pruefe "leer -> voll: Rueckgabe 0" "$RC" "0"
pruefe "LEER=0" "$(echo "$AUS" | head -1 | grep -c 'LEER=0')" "1"
# ⚠ Der Verlauf bleibt sichtbar — sonst verschwindet der tote Agent spurlos.
pruefe "WIEDERHOLT wird gemeldet" "$(echo "$AUS" | grep -c 'WIEDERHOLT: custom-context')" "1"
pruefe "nennt beide Groessen" "$(echo "$AUS" | grep -c 'erst 0 Byte, dann 2400')" "1"
pruefe "NICHT als UNGEPRUEFT" "$(echo "$AUS" | grep -c 'UNGEPRUEFT: custom-context')" "0"

# --- 6) ⛔ die Gegenrichtung: voll, dann leer -------------------------------
#     Der LETZTE zaehlt. Wer zuletzt nichts lieferte, ist ungeprueft.
mind_agent_quittung_start "$P" 1
mind_agent_dispatch "rules" "$P"; mind_agent_ergebnis "rules" 2400 "$P"
mind_agent_dispatch "rules" "$P"; mind_agent_ergebnis "rules" 0 "$P"
AUS=$(mind_agent_bilanz "$P"); RC=$?
pruefe "voll -> leer: Rueckgabe 1" "$RC" "1"
pruefe "und als UNGEPRUEFT gemeldet" "$(echo "$AUS" | grep -c 'UNGEPRUEFT: rules')" "1"

# --- 7) zweimal leer -------------------------------------------------------
mind_agent_quittung_start "$P" 1
mind_agent_dispatch "memory" "$P"; mind_agent_ergebnis "memory" 0 "$P"
mind_agent_dispatch "memory" "$P"; mind_agent_ergebnis "memory" 0 "$P"
AUS=$(mind_agent_bilanz "$P"); RC=$?
pruefe "zweimal leer -> Rueckgabe 1" "$RC" "1"
pruefe "LEER=1, nicht 2 (Bereiche, nicht Zeilen)" \
       "$(echo "$AUS" | head -1 | grep -c 'LEER=1')" "1"
pruefe "keine WIEDERHOLT-Meldung" "$(echo "$AUS" | grep -c 'WIEDERHOLT:')" "0"

# --- 8) ⛔ NEGATIVKONTROLLE: ein sauberer Bereich meldet NIE eine Wiederholung
mind_agent_quittung_start "$P" 2
mind_agent_dispatch "claude-md" "$P"; mind_agent_ergebnis "claude-md" 4096 "$P"
mind_agent_dispatch "memory" "$P";    mind_agent_ergebnis "memory" 800 "$P"
AUS=$(mind_agent_bilanz "$P"); RC=$?
pruefe "zwei saubere Bereiche -> Rueckgabe 0" "$RC" "0"
pruefe "keine WIEDERHOLT-Zeile" "$(echo "$AUS" | grep -c 'WIEDERHOLT')" "0"
pruefe "keine UNGEPRUEFT-Zeile" "$(echo "$AUS" | grep -c 'UNGEPRUEFT')" "0"

# --- 9) doppelter Dispatch zaehlt den Bereich nur EINMAL --------------------
#     Sonst meldete "einmal wiederholt" faelschlich DISPATCH=2 von 1 erwartet.
pruefe "DISPATCH zaehlt Bereiche, nicht Aufrufe" \
       "$(mind_agent_bilanz "$P" | head -1 | sed -n 's/DISPATCH=\([0-9]*\).*/\1/p')" "2"

echo
echo "=============================================================================="
echo "  ⛔ RATSCHE — die Aufrufer muessen die Zahl auch UEBERGEBEN"
echo "=============================================================================="
# ⛔ v5.21.2 gab der Funktion den Parameter und liess BEIDE Aufrufer unveraendert.
#    Die Quittung verhielt sich damit exakt wie vorher — der Fix war HALB.
#    Woertlich der v5.7.1-Fall ("es sammelte `_wurzel_py` und benutzte es nie")
#    und derselbe Halbfix wie bei classify_path am selben Tag: die Funktion war
#    richtig, der Aufrufer benutzte sie nicht.
#    Gefunden hat es erst der `Pc Forschung`-Lauf um 23:02, der denselben Befund
#    zum ZWEITEN Mal unveraendert meldete.
#
# ⚠ Diese Faelle sind STRIKT ADDITIV — sie koennen die Sammlung nur strenger
#   machen, nie milder. Deshalb stehen sie hier statt in einer vierten Datei:
#   sie gehoeren thematisch zur Erwartungszahl.
for s in mind-all mind-update; do
  F="$CLAUDE_PLUGIN_ROOT/skills/$s/SKILL.md"
  if [ -f "$F" ]; then
    # Ein Aufruf OHNE folgende Zahl ist der Rueckfall.
    N=$(grep -cE 'mind_agent_quittung_start "\$PROJ"[[:space:]]*$' "$F")
    pruefe "$s uebergibt die Erwartungszahl" "$N" "0"
    M=$(grep -cE 'mind_agent_quittung_start "\$PROJ" [0-9]+' "$F")
    pruefe "$s: Aufruf MIT Zahl vorhanden" "$([ "$M" -ge 1 ] && echo ja || echo nein)" "ja"
  else
    pruefe "$s/SKILL.md gefunden" "fehlt" "vorhanden"
  fi
done

echo
echo "=============================================================================="
echo "  $OK ok, $ROT rot"
echo "=============================================================================="
[ "$ROT" -eq 0 ]
