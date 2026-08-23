#!/bin/bash
# Claude Mind Manager — UserPromptSubmit Hook (v5.1.0, umgebaut v5.2.1)
#
# Zweck: Solange eine Sync-Schuld offen ist, EINMAL PRO SITZUNG darauf hinweisen, dass ein
# vollstaendiger Chat gerettet wurde und /mind-all ihn als Quelle nehmen soll.
#
# Warum UserPromptSubmit und nicht PostCompact/SessionStart:
#   - PostCompact ist command-only -> kann KEINEN Kontext einspeisen.
#   - Eine Auto-Kompaktierung beendet die Session NICHT -> es feuert kein SessionStart.
#   - Der naechste Beruehrungspunkt ist die naechste Nachricht des Nutzers. Genau hier.
#
# ⛔ AENDERUNG v5.2.1 — der Merker wird NICHT MEHR VERBRAUCHT.
# Bis v5.2.0 hiess der Merker PENDING und wurde beim ANKUENDIGEN in PENDING.announced
# umbenannt. Damit war die Schuld nach einer einzigen Ankuendigung fuer immer unsichtbar:
# belegt am 2026-08-16 — Ankuendigung kam an, der laufende Auftrag hatte Vorrang (so will es
# v5.2.0), und 417 KB geretteter Chat blieben liegen, die nie jemand eingespeist hat.
# Jetzt: OPEN ist die SCHULD und bleibt, bis der Sync wirklich lief. Angekuendigt wird einmal
# pro Sitzung (OPEN.seen-<session_id>) — in jeder neuen Sitzung also wieder.
# Erzwungen wird der Sync von hooks/stop.sh; dieser Hook informiert nur.
#
# EHRLICHE GRENZE: Ein Hook kann keinen Skill STARTEN. Das hier ist ein eingespeister Auftrag
# an der sichtbarsten Stelle (Kopf des naechsten Turns) — kein Automatismus.
#
# WICHTIG: Dieser Hook laeuft bei JEDER Nachricht. Im Normalfall gibt er NICHTS aus.
# Ein Hook, der staendig redet, wird ignoriert oder abgeschaltet.

# stdin defensiv konsumieren (der Aufrufer pipet JSON herein)
INPUT=$(cat 2>/dev/null)

# --- Protokoll (NEU v5.3.1) ---------------------------------------------------
# Eigener Logger statt lib.sh: dieser Hook laeuft bei JEDER Nachricht und soll schlank
# bleiben — ein `source lib.sh` je Tastendruck waere Startkosten fuer nichts. Gleiches
# Muster wie hooks/stop.sh.
#
# WARUM ueberhaupt (gemessen 2026-08-17): Dieser Hook und session-start.sh hatten zusammen
# NULL Log-Aufrufe. Auf die Frage "der Compact lief, warum ist nichts passiert?" liess sich
# nicht beantworten, ob, wann und von welchem Hook die Schuld gemeldet wurde — erschliessbar
# war es nur ueber den Zeitstempel von OPEN.seen-<sid>. Das Log, das die Frage beantworten
# sollte, schwieg.
MIND_LOG_FILE="/tmp/mind-manager.log"
_slog() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1 prompt-submit: ${*:2}" >> "$MIND_LOG_FILE" 2>/dev/null; }

# Projekt-Dir: env-Var bevorzugt (dokumentiert), sonst aus dem JSON, sonst CWD
PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ] && command -v jq >/dev/null 2>&1; then
  PROJ=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
fi
[ -z "$PROJ" ] && PROJ="$(pwd)"

OPEN="$PROJ/.claude-mind/rescued/OPEN"

# ===== v5.7.0: Uebergabe nach der Kompaktierung =============================
# Bis v5.6.0 hing JEDE Meldung an der Sync-SCHULD. Laeuft der Sync kuenftig VOR der
# Kompaktierung, gibt es keine Schuld — und damit haette hier niemand mehr ein Wort gesagt,
# genau in dem Moment, in dem der Kontext leer ist und die Uebergabe am noetigsten waere.
UEBERGABE="$PROJ/.claude-mind/rescued/UEBERGABE"
if [ -f "$UEBERGABE" ]; then
  _AS=$(grep -m1 '^arbeitsstand=' "$UEBERGABE" 2>/dev/null | cut -d= -f2-)
  _RS=$(grep -m1 '^resume='       "$UEBERGABE" 2>/dev/null | cut -d= -f2-)
  _TXT=""
  if [ -n "$_AS" ] && [ -s "$_AS" ] && [ -n "$CLAUDE_PLUGIN_ROOT" ]; then
    _PY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)
    [ -n "$_PY" ] && _TXT=$("$_PY" "$CLAUDE_PLUGIN_ROOT/references/arbeitsstand_render.py" \
                            "$_AS" 2>/dev/null)
  fi
  _AUF=""
  [ -n "$_RS" ] && [ -f "$_RS" ] && _AUF=$(sed -n "/^## /,\$p" "$_RS" | head -30)
  rm -f "$UEBERGABE" 2>/dev/null
  if [ -n "$_TXT" ] || [ -n "$_AUF" ]; then
    _slog INFO "Arbeitsstand nach Kompaktierung uebergeben"
    _MSGU="[Mind Manager] Der Kontext wurde gerade kompaktiert. Hier ist der Arbeitsstand
von unmittelbar davor — er ersetzt das, was aus dem Fenster gefallen ist.

$_TXT

--- WORAN GEARBEITET WURDE ---
$_AUF
--- Ende ---

Die Arbeit oben WIEDER AUFNEHMEN. Der Sync ist erledigt; es steht nichts aus."
    if command -v jq >/dev/null 2>&1; then
      jq -nc --arg ctx "$_MSGU" \
        '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
    else
      echo "$_MSGU"
    fi
    exit 0
  fi
fi

# ===== v5.7.0: Sync-Ausloeser an der TOKEN-Schwelle =========================
# ⛔ Reihenfolge-Umkehr gegenueber v5.6.0. Vorher: kompaktieren, DANACH /mind-all erzwingen —
#    der Lauf fuellte den frisch geleerten Kontext mit 40-60k Tokens wieder auf.
#    Jetzt: bei 800k synchronisieren, DANACH kompaktieren lassen (Nutzer-Entscheidung 21.08.2026).
# ⚠ Vorgabe 0 = AUS. Ohne gesetzte Schwelle aendert sich fuer andere Projekte nichts.
# --- v5.7.5: Kompaktierung steht aus (Rueckfallnetz zum Stop-Hook) ---
# Der Stop-Hook hat einen Notausgang nach MIND_COMPACT_MAX_BLOCKS. Danach schweigt er.
# Diese Zeile bleibt — sie kostet nichts und haelt die faellige Kompaktierung sichtbar.
# --- v5.9.3: der NOTFALL-Block ist ENTFERNT ---
#
# ⛔ Er stand auf einer Annahme, die nie geprueft wurde: dass mit
#    `autoCompactEnabled: false` GAR NICHTS mehr auffaengt. Daraus wurden Saetze wie
#    "endet die Sitzung OHNE Rettung, OHNE gesicherten Auftrag und OHNE Arbeitsstand".
#
#    Belegt war das nie. Gemessen wurde nur: zwischen 833k und 895k kam keine
#    Kompaktierung. Was bei ~1 Mio geschieht, sagt diese Messung NICHT — dort war die
#    Sitzung nie. Laut Nutzer (21.08.2026) kompaktiert Claude dort von sich aus.
#
# ⛔ DER SCHADEN WAR REAL UND WIEDERHOLTE SICH IN JEDEM CHAT. Nutzer woertlich:
#    "Bei in jedem Chat behauptet der Tokens Fenster ist voll. Das stimmt nicht."
#    Am selben Tag hat derselbe Text dazu gefuehrt, bei 880k die Arbeit einzustellen,
#    obwohl 120k Luft waren — und die Begruendung als "gemessen" auszugeben.
#
# ⭐ DIE LEHRE, DIE UEBER DIESEN BLOCK HINAUSGEHT: Ein Hook, der zu Vorsicht mahnt,
#    unterliegt derselben Belegpflicht wie jede andere Aussage. Eine Warnung ohne
#    Beleg ist NICHT die sichere Seite — sie ist eine unbelegte Behauptung, die bei
#    jedem einzelnen Lauf erneut Schaden anrichtet.
#
# `MIND_NOTFALL_TOKENS` wird nicht mehr gelesen. Die Variable darf in settings.json
# stehen bleiben; sie tut nichts mehr.

_CFA="$PROJ/.claude-mind/rescued/COMPACT-FAELLIG"
if [ -f "$_CFA" ]; then
  _CFT=$(grep -m1 '^ts=' "$_CFA" 2>/dev/null | cut -d= -f2-)
  # ⛔ Als JSON ausgeben und AUSSTEIGEN — nicht per echo weiterlaufen. (v5.7.6)
  #    Die erste Fassung schrieb Klartext und lief weiter; kam danach die OPEN-Erinnerung
  #    als JSON, standen Klartext UND JSON im selben stdout eines einzigen Hook-Aufrufs.
  #    Das ist kein gueltiges JSON mehr, und der strukturierte additionalContext wirkt
  #    dann nur noch als literaler Text. Der UEBERGABE-Block darueber macht es seit jeher
  #    richtig; nur dieser scherte aus.
  _MSGC="[Mind Manager] Kompaktierung steht aus: /mind-all lief um ${_CFT:-?}, seither wurde
nicht kompaktiert. Den Nutzer bitten, /compact zu tippen — der Sync-Ertrag von 40-60k
Tokens wandert sonst in das naechste Kontextfenster.

Eine Kompaktierung ist NICHT ausloesbar: weder aus einem Hook noch vom Assistenten.
Nur der Mensch kann /compact eingeben."
  _slog INFO "COMPACT-FAELLIG gemeldet (seit ${_CFT:-?})"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ctx "$_MSGC" \
      '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
  else
    echo "$_MSGC"
  fi
  exit 0
fi

_SCHWELLE="${MIND_SYNC_AT_TOKENS:-0}"
_STAND="$PROJ/.claude-mind/rescued/sync-stand"
# v5.11.0: die Existenz von sync-stand schaltet NICHT mehr dauerhaft stumm.
# Sein einziger Verbraucher (pre-compact.sh) feuert seit autoCompactEnabled=false
# nur noch bei handgetipptem /compact -- ein Merker konnte damit ewig liegen.
# Geprueft wird jetzt der ZUWACHS seit dem Sync, s. mind_sync_frisch in lib.sh.
if [ ! -f "$OPEN" ] && [ "$_SCHWELLE" -gt 0 ] 2>/dev/null; then
  _TP=""
  command -v jq >/dev/null 2>&1 && _TP=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -n "$_TP" ] && [ -n "$CLAUDE_PLUGIN_ROOT" ] && [ -f "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" ]; then
    # shellcheck disable=SC1091
    . "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" 2>/dev/null
    _TOK=$(mind_kontext_tokens "$_TP" 2>/dev/null) || _TOK=""
    # ⚠ KEINE Zahl ist KEINE Null — ohne Messung wird NICHT gemahnt.
    if [ -n "$_TOK" ] && [ "$_TOK" -ge "$_SCHWELLE" ] 2>/dev/null \
       && ! mind_sync_frisch "$_STAND" "$_TOK"; then
      _slog INFO "Token-Schwelle erreicht ($_TOK >= $_SCHWELLE) -> Sync angemahnt"
      _MSGT="[Mind Manager] Kontext bei $_TOK Tokens (Erinnerungsschwelle $_SCHWELLE).

Ein guter Zeitpunkt fuer /mind-all — VOR der naechsten Kompaktierung, damit der Sync den
frisch geleerten Kontext nicht sofort wieder mit 40-60k fuellt.

⚠ Das Fenster ist NICHT voll. Kein Grund, Arbeit abzubrechen oder zu kuerzen."
      if command -v jq >/dev/null 2>&1; then
        jq -nc --arg ctx "$_MSGT" \
          '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
      else
        echo "$_MSGT"
      fi
      exit 0
    fi
  fi
fi

# --- F6: Arbeitsmengen-Ausloeser (NEU v5.14.0) -----------------------------
# Beide Ausloeser oben messen den KONTEXT und faengen bei jedem Neustart wieder
# bei null an. Belegt (Palvedo, 21.08.2026): 11 Commits und 12 h ohne Netz.
# Hier wird ARBEIT gezaehlt, nicht Fuellstand.
#
# ⛔ NUR MAHNUNG, kein Zwang. Ein stop.sh-Block auf Commit-Basis wuerde in einem
#    Repo mit vielen kleinen Commits die Sitzung festnageln -- und ein Zwang, den
#    der Blockierte nicht aufloesen kann, ist eine Falle (Lehre aus
#    MIND_COMPACT_MAX_BLOCKS).
_CSCHWELLE="${MIND_SYNC_AT_COMMITS:-0}"
_CSTAND="$PROJ/.claude-mind/rescued/sync-stand"
[ -f "$_CSTAND" ] || _CSTAND="$PROJ/.claude-mind/rescued/commit-stand"
if [ ! -f "$OPEN" ] && [ "$_CSCHWELLE" -gt 0 ] 2>/dev/null && [ -d "$PROJ/.git" ]; then
  if [ -n "$CLAUDE_PLUGIN_ROOT" ] && [ -f "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" ]; then
    # shellcheck disable=SC1091
    . "$CLAUDE_PLUGIN_ROOT/hooks/lib.sh" 2>/dev/null
    if [ ! -f "$_CSTAND" ]; then
      # ⚠ ERSTE BEOBACHTUNG SETZT NUR DEN NULLPUNKT. Ohne Referenz waere jede
      #   Zahl erfunden -- und eine erfundene Mahnung beim ersten Prompt einer
      #   frischen Installation ist genau das, was Mahnungen entwertet.
      mkdir -p "$(dirname "$_CSTAND")" 2>/dev/null
      : > "$_CSTAND" 2>/dev/null
      _slog INFO "Commit-Nullpunkt gesetzt: $_CSTAND"
    else
      _CN=$(mind_commits_seit "$PROJ" "$_CSTAND" 2>/dev/null) || _CN=""
      if [ -n "$_CN" ] && [ "$_CN" -ge "$_CSCHWELLE" ] 2>/dev/null; then
        _slog INFO "Commit-Schwelle erreicht ($_CN >= $_CSCHWELLE) -> Sync angemahnt"
        _MSGK="[Mind Manager] $_CN Commits seit dem letzten Sync (Schwelle $_CSCHWELLE).

Der Kontext ist noch klein — genau deshalb greift die Token-Mahnung hier nicht. Nach einem
Neustart faengt sie wieder bei null an, waehrend die Arbeit weiterlaeuft.

Ein /mind-all traegt diese Arbeit in die Context-Dateien. Danach ist der Zaehler zurueck."
        if command -v jq >/dev/null 2>&1; then
          jq -nc --arg ctx "$_MSGK" \
            '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
        else
          echo "$_MSGK"
        fi
        # Nullpunkt versetzen, sonst mahnt es ab jetzt bei JEDEM Prompt.
        : > "$PROJ/.claude-mind/rescued/commit-stand" 2>/dev/null
        exit 0
      fi
    fi
  fi
fi


# --- SCHNELLPFAD: keine Schuld -> absolut still, sofort raus ---
[ -f "$OPEN" ] || exit 0

# --- Sitzungs-Sperre: einmal pro Sitzung ankuendigen, nicht einmal ueberhaupt ---
SID=""
command -v jq >/dev/null 2>&1 && SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && SID="nosession"
SEEN="${OPEN}.seen-${SID}"
# ⛔ v5.5.1 — WARUM DIE SPERRE NICHT MEHR "EINMAL UND NIE WIEDER" IST.
#
# Gemessen 20.08.2026 im Projekt "APP - Palvedo" (Plugin v5.5.0, die JEDEN Stop-Aufruf
# protokolliert): nach einer Kompaktierung mit `trigger: manual` gibt es **keinen einzigen**
# Eintritts-Log des Stop-Hooks. Er wurde nicht still beendet — er lief GAR NICHT.
# Nach `trigger: auto` laeuft er dagegen (belegt am selben Tag: 01:16 -> 01:25).
# Vier bekannte Faelle, alle konsistent.
#
# FOLGE: Bei einem manuellen /compact gibt es nur EINE Meldung (aus session-start) — und
# danach Stille, weil dieser Hook sich selbst stummschaltet. Der Zwang (`decision:block`)
# kann nur vom Stop-Hook kommen; dieser hier kann nicht blocken. Er ist damit die EINZIGE
# verbliebene Stimme — und schwieg ausgerechnet dann.
#
# Jetzt: wiederholte Erinnerung mit ABSTAND statt Dauerschweigen. Der Zaehler steht in der
# seen-Datei. Nicht bei jeder Nachricht (das waere Laerm), aber auch nicht nur einmal.
# Der Eintrag "still" bleibt erhalten — er ist weiter der wichtigere der beiden, weil sonst
# "schweigt bewusst" und "ist tot" wieder gleich aussehen (Fehlersuche 17.08.2026).
_N=0
[ -f "$SEEN" ] && _N=$(cat "$SEEN" 2>/dev/null)
case "$_N" in ''|*[!0-9]*) _N=0 ;; esac
_C=$(grep -m1 '^compactions=' "$OPEN" 2>/dev/null | cut -d= -f2-)
case "$_C" in ''|*[!0-9]*) _C=1 ;; esac
# Je mehr Kompaktierungen verschleppt wurden, desto kuerzer der Abstand.
_JEDE="${MIND_REMIND_EVERY:-5}"
[ "$_C" -ge 2 ] 2>/dev/null && _JEDE=3
[ "$_C" -ge 4 ] 2>/dev/null && _JEDE=2

if [ "$_N" -gt 0 ] && [ $(( _N % _JEDE )) -ne 0 ]; then
  echo "$((_N + 1))" > "$SEEN" 2>/dev/null
  _slog INFO "still: Schuld besteht, naechste Erinnerung in $(( _JEDE - (_N % _JEDE) )) Nachricht(en) (n=$_N, sid=$SID)"
  exit 0
fi
[ "$_N" -gt 0 ] && _slog INFO "ERNEUTE Erinnerung (n=$_N, alle $_JEDE Nachrichten, compactions=$_C)"

RESCUE_PATH=$(grep -m1 '^path='        "$OPEN" 2>/dev/null | cut -d= -f2-)
RESUME_FILE=$(grep -m1 '^resume='      "$OPEN" 2>/dev/null | cut -d= -f2-)
RESCUE_N=$(grep    -m1 '^events='      "$OPEN" 2>/dev/null | cut -d= -f2-)
RESCUE_TS=$(grep   -m1 '^ts='          "$OPEN" 2>/dev/null | cut -d= -f2-)
COMPACTIONS=$(grep -m1 '^compactions=' "$OPEN" 2>/dev/null | cut -d= -f2-)

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


# Sperre VOR der Ausgabe setzen: bricht danach etwas ab, gibt es lieber keine zweite
# Ankuendigung in DIESER Nachricht als eine Endlosschleife.
# v5.5.1: ZAEHLER statt leerer Datei — er steuert den Abstand der Wiederholungen.
echo "$((_N + 1))" > "$SEEN" 2>/dev/null

# Gesicherten Auftrag mitgeben — er ueberlebt die Kompaktierung damit im Kontext,
# unabhaengig davon wie gut die automatische Zusammenfassung war.
RESUME_TXT=""
[ -n "$RESUME_FILE" ] && [ -f "$RESUME_FILE" ] && RESUME_TXT=$(sed -n '/^## /,$p' "$RESUME_FILE" | head -40)

NACHHOL=""
if [ -n "$COMPACTIONS" ] && [ "$COMPACTIONS" -gt 1 ] 2>/dev/null; then
  NACHHOL="
  ⚠ ${COMPACTIONS} Kompaktierungen seit dem letzten Sync — er wurde also schon einmal verschleppt."
fi

MSG="[Mind Manager] Es liegt eine OFFENE Sync-Schuld vor. Der VOLLSTAENDIGE Chat vor der
Kompaktierung wurde gerettet:
  Datei:      ${RESCUE_PATH}
  Beitraege:  ${RESCUE_N:-?}   (gerettet ${RESCUE_TS:-?})
  Auftrags-Merker: ${RESUME_FILE:-(keiner)}${NACHHOL}

--- WORAN GEARBEITET WURDE (aus dem Protokoll gezogen, nicht erinnert) ---
${RESUME_TXT:-(kein Auftrags-Merker vorhanden)}
--- Ende Auftrags-Merker ---

REIHENFOLGE: /mind-all ZUERST — ohne Ausnahme. Der Auftrag ist woertlich in
<ts>_RESUME.md gesichert und kommt im Sync-Bericht mit der Zeile 'FORTSETZUNG' zurueck.
Der Sync dauert Minuten; ihn zu verschieben kostet den Inhalt der Rettung, sobald die
naechste Kompaktierung kommt. 'Ich mache zuerst den Auftrag fertig' ist ab v5.4.1
KEIN zulaessiger Grund mehr.
1. Laeuft der Auftrag oben noch? -> WEITERARBEITEN. Kontextknappheit ist kein Abbruchgrund.
2. Ist der Auftrag durch (oder lief keiner)? -> /mind-all ausfuehren; der Knowledge-Sync MUSS
   die Rettungsdatei als Session-Quelle nehmen und im Bericht 'Session-Quelle: gerettet <pfad>'
   ausweisen.
3. Nach dem Sync: den Auftrag oben WIEDER AUFNEHMEN und das ausdruecklich sagen.
   /mind-all ist nie ein Auftragsende.

⛔ Die Rettungsdatei NIE im Hauptkontext lesen (kein Read, kein cat) — sie ist mehrere hundert
KB gross und wuerde den frisch geleerten Kontext sofort wieder fuellen. Erlaubt sind nur:
Pfad an einen Subagenten uebergeben, und zaehlende Aufrufe (grep -c, wc).

Die Schuld bleibt bestehen, bis /mind-all gelaufen ist — sie verfaellt nicht mit dieser Meldung."

# JSON-Ausgabe (Context Injection ist fuer UserPromptSubmit dokumentiert).
# Ohne jq: plain-text stdout wirkt laut Referenz ebenfalls als Kontext.
_slog INFO "Schuld gemeldet (events=${RESCUE_N:-?}, compactions=${COMPACTIONS:-?}, sid=$SID) -> $RESCUE_PATH"
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ctx "$MSG" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
else
  echo "$MSG"
fi

exit 0
