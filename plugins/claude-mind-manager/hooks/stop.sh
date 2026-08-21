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

# v5.4.1: belegt, DASS der Hook lief — sonst ist "Hook feuerte nicht" nicht
# von "Hook stieg still aus" zu unterscheiden.
_slog DEBUG "aufgerufen"

# ===== v5.7.0: Zwang an der TOKEN-Schwelle ==================================
# ⛔ stop.sh sourct lib.sh bewusst NICHT im Kopf — es ist der einzige Hook mit Zwangswirkung
#    und soll auch dann noch laufen, wenn lib.sh kaputt ist. Deshalb hier: GEGUARDET sourcen,
#    und wenn die Funktion fehlt, faellt nur diese Erweiterung aus. Der Schuld-Zwang darunter
#    bleibt in jedem Fall funktionsfaehig.
_TOKZWANG="nein"
_FSCHWELLE="${MIND_SYNC_FORCE_TOKENS:-0}"
if [ "$_FSCHWELLE" -gt 0 ] 2>/dev/null && [ -n "$CLAUDE_PLUGIN_ROOT" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" ] && command -v jq >/dev/null 2>&1; then
  # v5.7.6: dieselbe Aufloesung wie unten fuer PROJ. Vorher las dieser Block NUR .cwd,
  # waehrend PROJ CLAUDE_PROJECT_DIR bevorzugt. Weichen beide ab, suchte der Token-Zwang
  # sync-stand am falschen Ort — und feuerte, obwohl der Sync laengst gelaufen war.
  _PROJ="${CLAUDE_PROJECT_DIR:-}"
  [ -z "$_PROJ" ] && _PROJ=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  _TP=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  _STAND="$_PROJ/.claude-mind/rescued/sync-stand"
  # v5.11.0: kein `! -f "$_STAND"` mehr -- siehe mind_sync_frisch in lib.sh.
  # Ein Merker, dessen Verbraucher nie laeuft, war eine Dauersperre; gemessen
  # 21.08.2026 schwieg der Zwang bei 950 000 Tokens vollkommen korrekt.
  if [ -n "$_TP" ]; then
    # shellcheck disable=SC1091
    . "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" 2>/dev/null
    if command -v mind_kontext_tokens >/dev/null 2>&1 || type mind_kontext_tokens >/dev/null 2>&1; then
      _TOK=$(mind_kontext_tokens "$_TP" 2>/dev/null) || _TOK=""
      if [ -n "$_TOK" ] && [ "$_TOK" -ge "$_FSCHWELLE" ] 2>/dev/null \
         && ! mind_sync_frisch "$_STAND" "$_TOK"; then
        _TOKZWANG="ja"
        _slog INFO "Token-Zwang: $_TOK >= $_FSCHWELLE, sync-stand verbraucht"
      fi
    else
      _slog WARN "mind_kontext_tokens fehlt -> Token-Zwang faellt aus (Schuld-Zwang bleibt)"
    fi
  fi
fi


# --- Bremse 2: ohne jq kein Schleifenschutz -> gar nicht erst blocken ---
# v5.4.1: JEDER Ausstieg wird protokolliert. Vorher schwieg dieser Hook in drei Faellen
# vollstaendig — und ein Hook, der schweigt weil er soll, war von einem, der schweigt weil
# er kaputt ist, nicht zu unterscheiden. Genau daran scheiterte am 19.08.2026 die Frage
# "warum hat er kein /mind-all gemacht?": blocks=0, keine Log-Zeile, drei Kandidaten,
# keiner ausschliessbar. v5.3.1 hatte diesen Fix den zwei anderen Hooks schon gegeben.
if ! command -v jq >/dev/null 2>&1; then
  _slog WARN "kein jq -> kein Schleifenschutz, deshalb KEIN Block (Schuld bleibt offen)"
  exit 0
fi

# --- Bremse 1: Schleifenschutz ZUERST ---
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ]; then
  _slog INFO "still: stop_hook_active=true (erzwungene Fortsetzung laeuft bereits)"
  exit 0
fi

PROJ="${CLAUDE_PROJECT_DIR:-}"
[ -z "$PROJ" ] && PROJ=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJ" ] && PROJ="$(pwd)"

# --- v5.7.5: COMPACT-FAELLIG — der Sync ist durch, die Kompaktierung steht aus ---
# Nutzerwunsch: nach /mind-all soll KOMPAKTIERT werden, bevor weitergearbeitet wird. Sonst
# wandert der Sync-Ertrag (40-60k) in das naechste Kontextfenster.
#
# ⛔ Was dieser Block NICHT kann: kompaktieren. Es gibt kein Werkzeug dafuer, weder im Hook
#    noch beim Assistenten. Was er kann: erzwingen, dass die Bitte an den Menschen als
#    LETZTER Satz der Antwort steht statt in einem Bericht vergraben. Mehr ist ehrlich nicht
#    drin, und der Text sagt das auch.
CFA="$PROJ/.claude-mind/rescued/COMPACT-FAELLIG"
if [ -f "$CFA" ]; then
  _CB=$(grep -m1 '^blocks=' "$CFA" 2>/dev/null | cut -d= -f2-)
  case "$_CB" in ''|*[!0-9]*) _CB=0 ;; esac
  _CMAX="${MIND_COMPACT_MAX_BLOCKS:-2}"
  case "$_CMAX" in ''|*[!0-9]*) _CMAX=2 ;; esac
  if [ "$_CB" -ge "$_CMAX" ] 2>/dev/null; then
    # Notausgang. Wer nicht kompaktieren WILL, darf nicht festgenagelt werden — und ein
    # Zwang, den niemand aufloesen kann, waere genau das.
    _slog INFO "COMPACT-FAELLIG: Notausgang nach $_CB Blockaden -> Merker entfernt"
    rm -f "$CFA" 2>/dev/null
  else
    _CT=$(grep -m1 '^tokens=' "$CFA" 2>/dev/null | cut -d= -f2-)
    # ⛔ WER NICHT ZAEHLEN KANN, BLOCKT NICHT. (v5.7.6, adversarische Pruefung)
    #    Die erste Fassung erhoehte den Zaehler "so gut es geht" und blockte in jedem Fall.
    #    Schlug das Schreiben fehl — schreibgeschuetztes Verzeichnis, volle Platte, oder
    #    schlicht `grep -v` mit Rueckgabe 1, wenn NUR eine blocks=-Zeile in der Datei steht —
    #    las der naechste Aufruf denselben alten Wert und blockte erneut mit derselben
    #    Nummer. Der Notausgang war damit unerreichbar: eine Endlosschleife, die nur von
    #    Hand aufzuloesen war. Der Fehler hatte drei Gesichter und EINE Ursache — der
    #    Notausgang hing am Erfolg des Schreibens.
    #
    #    Deshalb jetzt: schreiben, ZURUECKLESEN, und nur blocken, wenn der neue Wert wirklich
    #    in der Datei steht. Sonst faellt der Merker weg und der Zwang entfaellt. Ein
    #    entfallener Zwang kostet eine Kompaktierung; ein unaufloesbarer kostet die Sitzung.
    _CNEU=$((_CB + 1))
    _CTMP="${CFA}.tmp.$$"
    _CSCHREIB="nein"
    # Befehlsgruppe statt if-grep: der Rueckgabewert ist der von printf, nicht der von grep.
    if { grep -v '^blocks=' "$CFA" 2>/dev/null; printf 'blocks=%s\n' "$_CNEU"; } \
         > "$_CTMP" 2>/dev/null && [ -s "$_CTMP" ] && mv -f "$_CTMP" "$CFA" 2>/dev/null \
       && [ "$(grep -m1 '^blocks=' "$CFA" 2>/dev/null | cut -d= -f2-)" = "$_CNEU" ]; then
      _CSCHREIB="ja"
    fi
    rm -f "$_CTMP" 2>/dev/null
    if [ "$_CSCHREIB" = "nein" ]; then
      _slog WARN "COMPACT-FAELLIG: Zaehler nicht zurueckschreibbar -> Merker entfernt, KEIN Block"
      rm -f "$CFA" 2>/dev/null
      exit 0
    fi
    _slog INFO "block (COMPACT-FAELLIG #$_CNEU/$_CMAX, Kontext beim Sync: ${_CT:-?})"
    jq -nc --arg r "[Mind Manager] /mind-all ist durch (Kontext beim Sync: ${_CT:-unbekannt}).

Der Sync hat 40-60k Tokens gekostet. Am guenstigsten waere jetzt ein /compact — dann
raeumt die Kompaktierung den Sync-Ertrag gleich mit auf, statt ihn ins naechste Fenster
zu tragen.

⚠ Das ist eine EMPFEHLUNG, kein Zwang. Die Arbeit kann normal weitergehen; Claude
kompaktiert bei etwa 1 Mio Tokens ohnehin von sich aus.

Erwaehne den Vorschlag einmal am Ende der Antwort und mach dann weiter. Auslosen kann
ihn weder ein Hook noch der Assistent — nur der Mensch tippt /compact." \
      '{decision:"block", reason:$r}'
    exit 0
  fi
fi

OPEN="$PROJ/.claude-mind/rescued/OPEN"

# --- SCHNELLPFAD: keine Schuld -> still, aber nachweisbar ---
if [ ! -f "$OPEN" ]; then
  # v5.7.0: KEINE Schuld, aber die Token-Schwelle ist ueberschritten und in diesem Zyklus
  # lief noch kein Sync. Dann wird trotzdem geblockt — der Sync soll VOR die Kompaktierung,
  # nicht danach. Der Text nennt die Zahl, damit die Aufforderung nachpruefbar ist.
  if [ "$_TOKZWANG" = "ja" ]; then
    _slog INFO "block (Token-Schwelle, keine Schuld): $_TOK >= $_FSCHWELLE"
    jq -nc --arg r "[Mind Manager] Kontext bei $_TOK Tokens — guter Zeitpunkt fuer /mind-all.

⚠ Das Fenster ist NICHT voll und die Arbeit muss nicht abgebrochen werden. Es geht
allein um die REIHENFOLGE: laeuft der Sync erst nach einer Kompaktierung, fuellt er den
frisch geleerten Kontext sofort wieder mit 40-60k Tokens. Davor gelaufen, raeumt die
Kompaktierung hinterher auf.

Also: /mind-all ausfuehren und danach normal weiterarbeiten. Ist es hier nicht
ausfuehrbar, sage kurz warum — und arbeite weiter." \
      '{decision:"block", reason:$r}'
    exit 0
  fi
  _slog INFO "still: keine offene Schuld (PROJ=$PROJ)"
  exit 0
fi

RESCUE_PATH=$(grep -m1 '^path='        "$OPEN" 2>/dev/null | cut -d= -f2-)
RESUME_FILE=$(grep -m1 '^resume='      "$OPEN" 2>/dev/null | cut -d= -f2-)
RESCUE_N=$(grep    -m1 '^events='      "$OPEN" 2>/dev/null | cut -d= -f2-)
COMPACTIONS=$(grep -m1 '^compactions=' "$OPEN" 2>/dev/null | cut -d= -f2-)
BLOCKS=$(grep      -m1 '^blocks='      "$OPEN" 2>/dev/null | cut -d= -f2-)
case "$BLOCKS" in ''|*[!0-9]*) BLOCKS=0 ;; esac

# Schuld zeigt ins Leere (Rettung wegrotiert)? Aufraeumen statt blocken.
# v5.4.1: OPEN kann MEHRERE Rettungen nennen — eine je Kompaktierung ohne Sync.
# Tote Zeiger fliegen EINZELN raus; OPEN verschwindet nur, wenn KEINE Rettung mehr da ist.
# Vorher loeschte eine einzige wegrotierte Datei die Schuld fuer alle.
_ALIVE=$(grep '^path=' "$OPEN" 2>/dev/null | cut -d= -f2- | while IFS= read -r _p; do
           [ -n "$_p" ] && [ -f "$_p" ] && echo "$_p"; done)
RESCUE_ANZ=$(printf '%s\n' "$_ALIVE" | grep -c . 2>/dev/null)
case "$RESCUE_ANZ" in ''|*[!0-9]*) RESCUE_ANZ=0 ;; esac
if [ "$RESCUE_ANZ" -eq 0 ]; then
  _slog INFO "OPEN nannte nur tote Rettungen -> entfernt"
  rm -f "$OPEN" "${OPEN}.seen-"* 2>/dev/null
  exit 0
fi
_ROH=$(grep -c '^path=' "$OPEN" 2>/dev/null); case "$_ROH" in ''|*[!0-9]*) _ROH=0 ;; esac
if [ "$RESCUE_ANZ" -ne "$_ROH" ]; then
  _T="${OPEN}.tmp.$$"
  { grep -v -E '^(path|resume)=' "$OPEN" 2>/dev/null
    printf '%s\n' "$_ALIVE" | sed 's|^|path=|'
    grep '^resume=' "$OPEN" 2>/dev/null | cut -d= -f2- | while IFS= read -r _r; do
      [ -n "$_r" ] && [ -f "$_r" ] && echo "resume=$_r"; done
  } > "$_T" 2>/dev/null && mv -f "$_T" "$OPEN" 2>/dev/null || rm -f "$_T" 2>/dev/null
  _slog INFO "$((_ROH - RESCUE_ANZ)) tote Rettungszeiger entfernt, $RESCUE_ANZ verbleiben"
fi
RESCUE_PATH=$(printf '%s\n' "$_ALIVE" | tail -1)   # die JUENGSTE ist die Leitrettung


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

# v5.4.1: alle offenen Rettungen auflisten, nicht nur die juengste
OFFENE_LISTE=$(printf '%s\n' "$_ALIVE" | while IFS= read -r _p; do
                 [ -n "$_p" ] && echo "    - $_p"; done)

REASON="[Mind Manager] Der Context-Sync steht noch aus.${NACHHOL}

⛔ REIHENFOLGE: /mind-all ZUERST — ohne Ausnahme. Der Auftrag ist woertlich in der
RESUME-Datei gesichert und kommt im Sync-Bericht mit der FORTSETZUNG-Zeile zurueck. Der Sync
dauert Minuten; ihn zu verschieben kostet den Inhalt der Rettung, sobald die naechste
Kompaktierung kommt. 'Ich mache zuerst den Auftrag fertig' ist ab v5.4.1 KEIN zulaessiger
Grund mehr.

Fuehre JETZT /mind-all aus. Der Knowledge-Sync MUSS die geretteten Sitzungsdaten als Quelle
nehmen und im Bericht 'Session-Quelle: gerettet <pfad>' ausweisen:
  Offene Rettungen: ${RESCUE_ANZ:-1} — ALLE einspeisen, aelteste zuerst:
${OFFENE_LISTE}
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
