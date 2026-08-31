#!/usr/bin/env bash
# PostToolUse auf ExitPlanMode — merkt sich, dass ein OFFIZIELLER Plan laeuft.
#
# Nutzer-Auftrag 31.08.2026: "wenn er einen plan abarbeitet soll er kein mind
# all machen bis der plan durch ist — aber nur bei einem offiziellen plan im
# planmodus, plan.md".
#
# ⭐ DER AUSLOESER IST MECHANISCH. `ExitPlanMode` feuert genau dann, wenn der
#    Nutzer einen Plan FREIGIBT — nicht, wenn irgendwo eine `plan.md`
#    herumliegt. Gemessen 31.08.2026: in diesem Projekt liegen 10 Plan-Dateien,
#    KEINE mit Checkboxen. "Datei existiert" haette den Sync fuer immer
#    stillgelegt, "offene Checkbox" haette nie gefeuert.
#
# ⛔ DASS `ExitPlanMode` HIER ANKOMMT, IST NICHT BELEGT. Die Hook-Referenz
#    nennt `tool_name` als Feld von PostToolUse, aber nicht diesen Tool-Namen.
#    Deshalb protokolliert dieser Hook JEDEN Aufruf mit dem gesehenen Namen —
#    nach dem ersten Planmodus steht im Log, ob er je gefeuert hat.
#    ⚠ Ein Hook, der schweigt weil er soll, und einer, der schweigt weil er nie
#      gerufen wird, sind sonst nicht zu unterscheiden (v5.3.1).
#
# ⛔ HANDWEG, falls er nie feuert:
#      touch "<projekt>/.claude-mind/PLAN-AKTIV"
#      printf 'ts=%s\nplan=plan.md\n' "$(date +%s)" > .../PLAN-AKTIV
#
# ⛔ FAIL-OPEN. Dieser Hook darf nichts blockieren und nichts abbrechen. Er
#    schreibt einen Merker; geht das schief, laeuft alles wie bisher weiter.
set -u

INPUT=$(cat 2>/dev/null || echo '{}')

_LOG="${MIND_LOG_FILE:-/tmp/mind-manager.log}"
_slog() { printf '[%s] %s plan-modus: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" \
          >> "$_LOG" 2>/dev/null; }

if ! command -v jq >/dev/null 2>&1; then
  _slog WARN "kein jq — Merker nicht gesetzt, Ablauf unveraendert"
  exit 0
fi

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
PROJ="${CLAUDE_PROJECT_DIR:-}"
[ -z "$PROJ" ] && PROJ=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJ" ] && PROJ="$(pwd)"

# ⚠ Der Matcher in hooks.json filtert schon; die zweite Pruefung hier ist
#   Absicht. Faellt der Matcher aus oder aendert Claude Code seine Semantik,
#   setzt dieser Hook sonst bei JEDEM Werkzeugaufruf eine Plan-Pause — und
#   legte damit den Sync dauerhaft still. Das waere schlimmer als gar keine
#   Pause.
case "$TOOL" in
  ExitPlanMode|exit_plan_mode) : ;;
  *)
    _slog INFO "still: tool_name='$TOOL' ist nicht ExitPlanMode"
    exit 0 ;;
esac

# Welcher Plan? Nur zur Anzeige — die Pause haengt NICHT daran.
PLAN=""
[ -f "$PROJ/plan.md" ] && PLAN="plan.md"

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" 2>/dev/null
fi

if command -v mind_plan_merken >/dev/null 2>&1; then
  if mind_plan_merken "$PROJ" "$PLAN"; then
    _slog INFO "Plan-Pause gesetzt (plan='${PLAN:-unbekannt}', proj=$PROJ)"
  else
    _slog WARN "Plan-Pause NICHT gesetzt (Schreibfehler) — Ablauf unveraendert"
  fi
else
  # lib.sh unerreichbar: den Merker trotzdem schreiben, gleiche Form.
  mkdir -p "$PROJ/.claude-mind" 2>/dev/null \
    && printf 'ts=%s\nplan=%s\n' "$(date +%s)" "$PLAN" \
       > "$PROJ/.claude-mind/PLAN-AKTIV" 2>/dev/null \
    && _slog INFO "Plan-Pause gesetzt (ohne lib.sh)" \
    || _slog WARN "Plan-Pause NICHT gesetzt (lib.sh fehlt UND Schreibfehler)"
fi

exit 0
