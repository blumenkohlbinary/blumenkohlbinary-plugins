#!/bin/bash
# Claude Mind Manager — Stop Hook (NEU v5.2.1)
#
# DER EINZIGE HOOK, DER ETWAS ERZWINGEN KANN.
# Alle anderen koennen nur Kontext einspeisen — und eingespeister Text kann uebergangen werden,
# weil der Turn danach einfach endet. Genau das ist am 2026-08-16 passiert: die Ankuendigung kam
# an, der laufende Auftrag hatte Vorrang, der Turn war vorbei, die Schuld verschwand.
# Stop akzeptiert {"decision":"block","reason":"..."} (references/hooks-api-reference.md:47) —
# der Turn kann dann NICHT enden und die Begruendung steht am Anfang des naechsten.
#
# ⚠ EHRLICH: Auch das startet keinen Skill. Es erzwingt, dass es einen weiteren Turn GIBT und
# dass der Auftrag darin ganz oben steht. Das ist Befolgung, keine Mechanik. Kein Hook der API
# kann einen Skill ausfuehren.
#
# Nutzer-Entscheidung 2026-08-16: "er soll bei jedem compact mind all machen".
# Deshalb wird WIEDERHOLT geblockt, bis die Schuld beglichen ist — nicht einmal pro Sitzung.
#
# DREI BREMSEN, in dieser Reihenfolge:
#   1. stop_hook_active  -> laeuft bereits eine erzwungene Fortsetzung, sofort raus.
#      Das ist die vorgeschriebene Schleifenbremse der API und steht bewusst als ERSTES.
#   2. kein jq           -> ohne verlaessliches Auslesen von stop_hook_active gibt es keinen
#      Schleifenschutz. Dann wird NICHT geblockt. Lieber kein Zwang als eine Endlosschleife.
#   3. blocks >= MAX     -> Notausgang gegen ein dauerhaft scheiterndes /mind-all, damit die
#      Sitzung nicht festgenagelt wird. KEINE Ration: bei Erfolg verschwindet OPEN ohnehin.
#
# Im Normalfall (keine offene Schuld) gibt dieser Hook NICHTS aus und endet mit 0.

INPUT=$(cat 2>/dev/null)

MIND_LOG_FILE="/tmp/mind-manager.log"
_slog() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1 stop: ${*:2}" >> "$MIND_LOG_FILE" 2>/dev/null; }

# --- Bremse 2: ohne jq kein Schleifenschutz -> gar nicht erst blocken ---
command -v jq >/dev/null 2>&1 || exit 0

# --- Bremse 1: Schleifenschutz ZUERST ---
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ]; then
  exit 0
fi

PROJ="${CLAUDE_PROJECT_DIR:-}"
[ -z "$PROJ" ] && PROJ=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJ" ] && PROJ="$(pwd)"

OPEN="$PROJ/.claude-mind/rescued/OPEN"

# --- SCHNELLPFAD: keine Schuld -> absolut still ---
[ -f "$OPEN" ] || exit 0

RESCUE_PATH=$(grep -m1 '^path='        "$OPEN" 2>/dev/null | cut -d= -f2-)
RESUME_FILE=$(grep -m1 '^resume='      "$OPEN" 2>/dev/null | cut -d= -f2-)
RESCUE_N=$(grep    -m1 '^events='      "$OPEN" 2>/dev/null | cut -d= -f2-)
COMPACTIONS=$(grep -m1 '^compactions=' "$OPEN" 2>/dev/null | cut -d= -f2-)
BLOCKS=$(grep      -m1 '^blocks='      "$OPEN" 2>/dev/null | cut -d= -f2-)
case "$BLOCKS" in ''|*[!0-9]*) BLOCKS=0 ;; esac

# Schuld zeigt ins Leere (Rettung wegrotiert)? Aufraeumen statt blocken.
if [ -z "$RESCUE_PATH" ] || [ ! -f "$RESCUE_PATH" ]; then
  rm -f "$OPEN" "${OPEN}.seen-"* 2>/dev/null
  _slog INFO "OPEN zeigte ins Leere -> entfernt, kein Block"
  exit 0
fi

# --- Bremse 3: Notausgang ---
MAX="${MIND_STOP_MAX_BLOCKS:-3}"
if [ "$BLOCKS" -ge "$MAX" ] 2>/dev/null; then
  _slog WARN "Notausgang: ${BLOCKS} Blockaden ohne erfolgreichen Sync — gebe auf, Schuld bleibt offen ($OPEN)"
  exit 0
fi

# Zaehler hochschreiben. KEIN sed -i (bricht auf Windows/Git-Bash bei Mehrzeiligem);
# stattdessen Zeile herausfiltern und neu anhaengen, dann atomar ersetzen.
TMP="${OPEN}.tmp.$$"
if grep -v '^blocks=' "$OPEN" > "$TMP" 2>/dev/null; then
  echo "blocks=$((BLOCKS + 1))" >> "$TMP"
  mv -f "$TMP" "$OPEN" 2>/dev/null || rm -f "$TMP" 2>/dev/null
else
  rm -f "$TMP" 2>/dev/null
fi

RESUME_TXT=""
[ -n "$RESUME_FILE" ] && [ -f "$RESUME_FILE" ] && RESUME_TXT=$(sed -n '/^## /,$p' "$RESUME_FILE" | head -30)

NACHHOL=""
if [ -n "$COMPACTIONS" ] && [ "$COMPACTIONS" -gt 1 ] 2>/dev/null; then
  NACHHOL=" Es sind bereits ${COMPACTIONS} Kompaktierungen seit dem letzten Sync aufgelaufen."
fi

REASON="[Mind Manager] Der Context-Sync steht noch aus.${NACHHOL}

Fuehre JETZT /mind-all aus. Der Knowledge-Sync MUSS die geretteten Sitzungsdaten als Quelle
nehmen und im Bericht 'Session-Quelle: gerettet <pfad>' ausweisen:
  Rettung: ${RESCUE_PATH}   (${RESCUE_N:-?} Beitraege)
  Auftrag: ${RESUME_FILE:-(keiner gesichert)}

⛔ Die Rettungsdatei NIE im Hauptkontext lesen (kein Read, kein cat) — sie ist mehrere hundert
KB gross und wuerde den Kontext sofort wieder fuellen, was die naechste Kompaktierung ausloest
und damit diese Schuld erneut erzeugt. Erlaubt: Pfad an einen Subagenten uebergeben, und
zaehlende Aufrufe (grep -c, wc).

Am Ende schreibt /mind-all pflichtgemaess nach listeverbesserungen.md (Probleme dieses Laufs,
Verbesserungsvorschlaege, Nicht-angewendetes) und gibt den unterbrochenen Auftrag mit der
'⏭ FORTSETZUNG'-Zeile zurueck — /mind-all ist nie ein Auftragsende.

--- WORAN GEARBEITET WURDE (aus dem Protokoll gezogen) ---
${RESUME_TXT:-(kein Auftrags-Merker vorhanden)}
--- Ende Auftrags-Merker ---

Sollte /mind-all hier nicht ausfuehrbar sein, sage das ausdruecklich und nenne den Grund —
schweigend uebergehen ist keine Option, die Schuld bleibt sonst offen."

_slog INFO "block #$((BLOCKS + 1)) — Sync steht aus ($RESCUE_PATH)"

jq -nc --arg r "$REASON" '{decision:"block", reason:$r}'
exit 0
