#!/usr/bin/env bash
# Entscheidet, ob die PLAN-PAUSE gilt — aufrufbar OHNE `source`.
#
#   bash plan-pause.sh <projekt>   ->  0 = PAUSE GILT (schweigen)
#                                      1 = keine Pause (normal weiter)
#   Bei aktiver Pause steht die Begruendung auf stdout.
#
# ⛔ WARUM ES DIESE DATEI GIBT — der Fehler, den sie behebt, war LAUTLOS.
#    Die erste Fassung rief `mind_plan_pause` direkt in `stop.sh` und
#    `prompt-submit.sh` auf, abgesichert mit `command -v ... >/dev/null`.
#    Beides ging schief:
#      · `stop.sh` sourct `lib.sh` NUR im Token-Zweig (bewusst — es ist der
#        einzige Hook mit Zwangswirkung und soll auch mit kaputter lib.sh
#        laufen).
#      · `prompt-submit.sh` sourct sie GAR NICHT (bewusst — ein `source` je
#        Tastendruck waere Startkosten fuer nichts).
#    `command -v` war damit IMMER falsch, der Block wurde IMMER uebersprungen,
#    und der Waechter hat den Ausfall VERSCHLUCKT statt ihn zu melden.
#    ⭐ Gefunden hat es nur eine POSITIVKONTROLLE: "ohne Pause MUSS stop.sh
#      blocken". Der Test "mit Pause schweigt er" war gruen und wertlos —
#      er schwieg, weil die Pause nie ankam.
#
# ⛔ Die Logik steht EINMAL, in `lib.sh:mind_plan_pause`. Diese Datei ist eine
#    Huelle, kein Zweitbau (`werkzeuge-zuerst.md`).
#
# ⛔ FAIL-SAFE-RICHTUNG: alles Unklare heisst KEINE Pause (Rueckgabe 1). Eine
#    faelschlich ausbleibende Pause kostet eine Mahnung; eine faelschlich
#    geltende kostet die Rettungsdatei.
set -u

PROJ="${1:-}"
[ -n "$PROJ" ] || exit 1

_LOG="${MIND_LOG_FILE:-/tmp/mind-manager.log}"
_plog() { printf '[%s] %s plan-pause: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" \
          >> "$_LOG" 2>/dev/null; }

# Schnellausstieg ohne jede Ladearbeit: liegt kein Merker, gibt es nichts zu tun.
# ⚠ Das ist der Normalfall und darf nichts kosten.
[ -f "$PROJ/.claude-mind/PLAN-AKTIV" ] || exit 1

_LIB="${CLAUDE_PLUGIN_ROOT:-}/hooks/lib.sh"
if [ ! -f "$_LIB" ]; then
  # ⛔ NICHT still. Ein Merker liegt, aber die Entscheidung ist nicht treffbar —
  #    das ist ein Befund, kein Normalfall.
  _plog WARN "Merker liegt, aber lib.sh unerreichbar ($_LIB) — KEINE Pause"
  exit 1
fi
# shellcheck disable=SC1090
. "$_LIB" 2>/dev/null

if ! command -v mind_plan_pause >/dev/null 2>&1; then
  _plog WARN "lib.sh geladen, aber mind_plan_pause fehlt — KEINE Pause"
  exit 1
fi

mind_plan_pause "$PROJ"
