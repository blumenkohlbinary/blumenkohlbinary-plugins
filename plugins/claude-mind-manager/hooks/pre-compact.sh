#!/bin/bash
# Claude Mind Manager — PreCompact Hook
# Backs up MEMORY.md + CLAUDE.md before compaction. Transcript: POINTER only (v5.0.0),
# keine Kopie mehr — sie wuchs auf 32 MB/Workspace und wurde per rclone hochgeladen.
# Keeps last N backups (default 5) to prevent unbounded growth.

source "$(dirname "$0")/lib.sh"
mind_init "pre-compact"

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"')

# Lebenszeichen (v5.2.1) — macht einen spaeteren stillen Hook-Tod nachweisbar
mind_heartbeat "$PROJECT_DIR" "PreCompact/${TRIGGER}"

# --- Create backup (OHNE Transkript-Kopie, v5.0.0) ---
# Frueher: create_backup "$PROJECT_DIR" "$TRANSCRIPT_PATH" -> kopierte das VOLLE Transkript in
# den Projektordner. Gemessen 2026-08-15: 32 MB in EINEM Workspace (Einzeldateien 4-7 MB), bei
# 3 vorgehaltenen Staenden bis ~60 MB — und unter C:\CD\KOHLEKTIV laedt rclone das nach Z: hoch.
# Das Transkript ist unveraenderlich und liegt ohnehin unter ~/.claude/projects/<slug>/.
# Deshalb: nur noch ZEIGER statt Kopie.
BACKED_UP=$(create_backup "$PROJECT_DIR" "" 2>/dev/null)

# --- Transkript-Zeiger statt Kopie ---
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  POINTER_DIR="${MIND_BACKUP_DIR:-$PROJECT_DIR/.claude-mind/backups}"
  mkdir -p "$POINTER_DIR" 2>/dev/null
  {
    echo "# Transkript-Zeiger (v5.0.0 — keine Kopie, Datei liegt unveraendert am Originalort)"
    echo "ts=$(date +%Y%m%d-%H%M%S)  trigger=${TRIGGER}"
    echo "path=$TRANSCRIPT_PATH"
    echo "size_bytes=$(wc -c < "$TRANSCRIPT_PATH" 2>/dev/null)"
    echo "sha256=$(sha256sum "$TRANSCRIPT_PATH" 2>/dev/null | cut -d' ' -f1)"
  } > "$POINTER_DIR/transcript-pointer.txt" 2>/dev/null
fi

# --- VOLL-RETTUNG des Gespraechs (NEU v5.1.0) ---
# Warum hier: PreCompact feuert genau am Auto-Kompaktierungs-Schwellwert (Standard ~850K).
# Gleich danach ist der Gespraechsverlauf im Live-Kontext weg. Das Transkript auf Platte bleibt
# zwar vollstaendig, ist aber zu gross zum Lesen (12 MB Roh-JSONL). Der reine Gespraechs-Anteil
# sind ~350-400 KB — genau das retten wir, lesbar und ungekuerzt.
# Das ist der DETERMINISTISCHE Teil: er haengt an keiner Entscheidung eines Modells.
RESCUE_DIR="$PROJECT_DIR/.claude-mind/rescued"
RESCUE_KEEP="${MIND_RESCUE_KEEP_COUNT:-3}"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  SAMPLER="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/references/session_sampler.py"
  if [ -f "$SAMPLER" ]; then
    mkdir -p "$RESCUE_DIR" 2>/dev/null
    RTS=$(date +%Y%m%d-%H%M%S)
    RESCUE_FILE="$RESCUE_DIR/${RTS}_chat.md"
    # Python-Pfad (venv bevorzugt, wie im Skill)
    if [ -x ".venv/Scripts/python.exe" ]; then RPY=".venv/Scripts/python.exe"
    elif command -v python3 >/dev/null 2>&1; then RPY="python3"
    else RPY="python"; fi
    # cygpath fuer Windows-Pfade, sonst direkt
    if command -v cygpath >/dev/null 2>&1; then
      RS_WIN=$(cygpath -w "$SAMPLER"); RT_WIN=$(cygpath -w "$TRANSCRIPT_PATH"); RO_WIN=$(cygpath -w "$RESCUE_FILE")
    else
      RS_WIN="$SAMPLER"; RT_WIN="$TRANSCRIPT_PATH"; RO_WIN="$RESCUE_FILE"
    fi
    if RESCUE_OUT=$("$RPY" "$RS_WIN" --full "$RT_WIN" "$RO_WIN" 2>&1) && [ -s "$RESCUE_FILE" ]; then
      RESCUE_N=$(echo "$RESCUE_OUT" | grep -oE '[0-9]+ Beitraege' | grep -oE '[0-9]+' | head -1)

      # --- Auftrags-Sicherung (v5.2.0; ab v5.2.1 MIT ZEITSTEMPEL) ---
      # Der laufende Auftrag wird HERAUSGEZOGEN, bevor er wegkompaktiert wird — deterministisch
      # aus dem Transkript, nicht aus dem Gedaechtnis eines Modells.
      # v5.2.1: frueher fester Name "RESUME.md" — die NAECHSTE Kompaktierung ueberschrieb damit
      # den Auftragstext der vorigen. Zwei Kompaktierungen vor einem Sync und der aeltere Auftrag
      # war weg. Jetzt zeitgestempelt; OPEN zeigt auf die richtige Datei.
      RESUME_FILE="$RESCUE_DIR/${RTS}_RESUME.md"
      if command -v cygpath >/dev/null 2>&1; then RR_WIN=$(cygpath -w "$RESUME_FILE"); else RR_WIN="$RESUME_FILE"; fi
      if "$RPY" "$RS_WIN" --orders "$RT_WIN" "$RR_WIN" >/dev/null 2>&1 && [ -s "$RESUME_FILE" ]; then
        mind_log "orders saved -> $RESUME_FILE"
        echo "[Mind Manager] Auftrag gesichert: ${RESUME_FILE##*/}"
      else
        mind_log WARN "Auftrags-Sicherung fehlgeschlagen (Chat-Rettung ist trotzdem da)"
        rm -f "$RESUME_FILE" 2>/dev/null
        RESUME_FILE=""
      fi

      # --- ARBEITSSTAND (NEU v5.6.0) ---
      # Vier Kategorien aus dem Transkript: Entscheidungen, Bugs, geaenderte Dateien,
      # Constraints. BEWUSST eine eigene Datei und NICHT in RESUME.md:
      # Die Erinnerungs-Hooks kappen RESUME.md mit `sed -n '/^## /,$p' | head -30`
      # (prompt-submit.sh:96,133 · session-start.sh:121 · stop.sh:117 · mind-all:96).
      # Vier zusaetzliche Kategorien fielen dort aus dem Fenster — technisch gruen,
      # Zweck verfehlt, ohne Fehlermeldung. Die Kappung ist RICHTIG: eine Erinnerung
      # soll kurz sein. Der ausfuehrliche Stand gehoert dorthin, wo er ganz gelesen
      # wird (/mind-all Step 0).
      #
      # ⛔ FAIL-OPEN, wie bei --orders: schlaegt das fehl, laeuft der Hook WEITER.
      #    pre-compact.sh ist der einzige Hook, der den Chat rettet. Ein Fehlschlag
      #    der Anreicherung darf die Rettung niemals gefaehrden.
      ARBEITSSTAND_FILE="$RESCUE_DIR/${RTS}_ARBEITSSTAND.json"
      if command -v cygpath >/dev/null 2>&1; then RA_WIN=$(cygpath -w "$ARBEITSSTAND_FILE"); else RA_WIN="$ARBEITSSTAND_FILE"; fi
      if "$RPY" "$RS_WIN" --arbeitsstand "$RT_WIN" "$RA_WIN" - >/dev/null 2>&1 && [ -s "$ARBEITSSTAND_FILE" ]; then
        mind_log "arbeitsstand saved -> $ARBEITSSTAND_FILE"
        echo "[Mind Manager] Arbeitsstand gesichert: ${ARBEITSSTAND_FILE##*/}"
      else
        mind_log WARN "Arbeitsstand fehlgeschlagen (Chat-Rettung und Auftrag sind trotzdem da)"
        rm -f "$ARBEITSSTAND_FILE" 2>/dev/null
        ARBEITSSTAND_FILE=""
      fi

      # --- v5.7.0: UEBERGABE-Merker, IMMER ---
      # Er haengt bewusst NICHT an der Schuld. Laeuft der Sync vor der Kompaktierung, gibt es
      # keine Schuld — und ohne diesen Merker saehe der frisch geleerte Kontext gar nichts.
      # Fail-open wie --orders: schlaegt es fehl, laeuft der Hook weiter.
      {
        printf 'ts=%s\n' "$TS"
        [ -n "$ARBEITSSTAND_FILE" ] && printf 'arbeitsstand=%s\n' "$ARBEITSSTAND_FILE"
        [ -n "$RESUME_FILE" ] && printf 'resume=%s\n' "$RESUME_FILE"
      } > "$RESCUE_DIR/UEBERGABE" 2>/dev/null \
        || mind_log WARN "UEBERGABE-Merker nicht schreibbar (Rettung ist davon unberuehrt)"

      # --- v5.7.0: lief in diesem Zyklus schon ein Sync? ---
      # Dann entsteht KEINE neue Schuld — der Sync ist ja erledigt, die Kompaktierung ist
      # seine Folge und nicht sein Ausloeser. Der Merker wird hier verbraucht und stellt damit
      # den 800k-Ausloeser fuer den naechsten Zyklus automatisch wieder scharf.
      SYNC_LIEF_SCHON="nein"
      if [ -f "$RESCUE_DIR/sync-stand" ]; then
        SYNC_LIEF_SCHON="ja"
        rm -f "$RESCUE_DIR/sync-stand" 2>/dev/null
        mind_log "Sync lief vor dieser Kompaktierung -> keine neue Schuld"
      fi
      # v5.7.5: Die Kompaktierung ist da — die Faelligkeit ist damit erledigt. Ohne diese
      # Zeile bliebe der Merker liegen und der Stop-Hook wuerde nach der Kompaktierung
      # weiter blocken: ein Zwang ohne Gegenstand.
      #
      # ⛔ Beim Einbau ist die mind_log-Zeile darueber versehentlich HIERHER gerutscht.
      #    Das Verhalten blieb richtig — SYNC_LIEF_SCHON sass weiter im richtigen Block —
      #    aber das Protokoll haette ab dann eine ANDERE Bedingung gemeldet als die, die es
      #    nennt. Gefunden beim Nachlesen der Verschachtelung: `bash -n` sagt nur
      #    "syntaktisch gueltig", nie "logisch richtig". Deshalb prueft test_precompact.sh
      #    diese Zeile jetzt ausdruecklich.
      # (Die Entfernung steht bewusst NICHT hier, sondern ganz am Ende des Hooks —
      #  siehe dort. Dieser Zweig laeuft nur, wenn die Chat-Rettung GELUNGEN ist.)
      :


      # --- SCHULD-Merker OPEN (NEU v5.2.1 — loest PENDING ab) ---
      # WARUM die Umbenennung mehr ist als ein neuer Name: PENDING wurde beim ANKUENDIGEN
      # geloescht (prompt-submit.sh/session-start.sh benannten es in .announced um), nicht beim
      # ERLEDIGEN. Belegt am 2026-08-16: Ankuendigung kam an, der laufende Auftrag hatte Vorrang
      # (so will es v5.2.0) — und damit war die Sync-Schuld fuer immer unsichtbar. 417 KB
      # geretteter Chat lagen da, die nie jemand eingespeist hat.
      # OPEN wird NUR entfernt, wenn der Sync wirklich lief (/mind-all bzw. /mind-update mit
      # Rettungsquelle) oder wenn die Rettungsdatei nachweislich weg ist.
      # ⛔ v5.4.1: path= und resume= werden ANGEHAENGT, nicht ersetzt.
      # Vorher stand hier genau EINE path=-Zeile. Kam eine zweite Kompaktierung vor dem
      # Sync, zeigte der Merker nur noch auf die neue Rettung — die aeltere lag als Datei
      # da, war aber als Quelle unerreichbar, weil alle Leser `grep -m1 '^path='` nahmen.
      # Belegt im eigenen Projekt: 20260816-194132_chat.md, 412 KB, nie eingespeist.
      PREV_C=0
      PREV_PATHS=""; PREV_RESUMES=""; PREV_ARB=""
      if [ -f "$RESCUE_DIR/OPEN" ]; then
        PREV_C=$(grep -m1 '^compactions=' "$RESCUE_DIR/OPEN" 2>/dev/null | cut -d= -f2-)
        case "$PREV_C" in ''|*[!0-9]*) PREV_C=0 ;; esac
        # Nur uebernehmen, was es noch GIBT — ein toter Zeiger soll die Liste nicht belasten.
        OLD_P=$(grep '^path='   "$RESCUE_DIR/OPEN" 2>/dev/null | cut -d= -f2-)
        OLD_R=$(grep '^resume=' "$RESCUE_DIR/OPEN" 2>/dev/null | cut -d= -f2-)
        OLD_A=$(grep '^arbeitsstand=' "$RESCUE_DIR/OPEN" 2>/dev/null | cut -d= -f2-)
        while IFS= read -r _p; do
          [ -n "$_p" ] && [ -f "$_p" ] && PREV_PATHS="${PREV_PATHS}path=${_p}
"
        done <<EOF
$OLD_P
EOF
        while IFS= read -r _r; do
          [ -n "$_r" ] && [ -f "$_r" ] && PREV_RESUMES="${PREV_RESUMES}resume=${_r}
"
        done <<EOF
$OLD_R
EOF
        while IFS= read -r _a; do
          [ -n "$_a" ] && [ -f "$_a" ] && PREV_ARB="${PREV_ARB}arbeitsstand=${_a}
"
        done <<EOF
$OLD_A
EOF
      fi
      # ⛔ v5.7.0: KEINE neue Schuld, wenn der Sync VOR dieser Kompaktierung lief.
      #    Ab v5.7.0 ist genau das der Normalfall: /mind-all laeuft bei 800k, die
      #    Kompaktierung ist seine FOLGE und nicht sein Ausloeser. Eine Schuld waere hier
      #    schlicht falsch — sie wuerde den naechsten Turn blockieren, obwohl nichts aussteht.
      #    Rettung, Auftrags-Merker und UEBERGABE entstehen trotzdem; nur der ZWANG entfaellt.
      if [ "$SYNC_LIEF_SCHON" = "ja" ]; then
        mind_log "keine Schuld angelegt (Sync lief vor dieser Kompaktierung)"
      else
        {
          printf '%s' "$PREV_PATHS"            # aeltere zuerst -> chronologisch
          echo "path=$RESCUE_FILE"
          printf '%s' "$PREV_RESUMES"
          echo "resume=$RESUME_FILE"
          printf '%s' "$PREV_ARB"
          echo "arbeitsstand=$ARBEITSSTAND_FILE"
          echo "events=${RESCUE_N:-?}"
          echo "ts=$RTS"
          echo "trigger=$TRIGGER"
          echo "compactions=$((PREV_C + 1))"   # seit dem letzten erfolgreichen Sync
          echo "blocks=0"                       # Stop-Hook-Notausgang, s. hooks/stop.sh
        } > "$RESCUE_DIR/OPEN" 2>/dev/null
        # Neue Rettung -> in JEDER Sitzung neu ankuendigen, Notausgang-Zaehler auf 0
        rm -f "$RESCUE_DIR/OPEN.seen-"* 2>/dev/null
      fi
      # Altlasten aus v5.1.0/v5.2.0 wegraeumen (sonst redet niemand mehr ueber sie)
      rm -f "$RESCUE_DIR/PENDING" "$RESCUE_DIR/PENDING.announced" "$RESCUE_DIR/RESUME.md" \
            "$RESCUE_DIR/RESUME.done.md" 2>/dev/null

      mind_log "chat rescued: ${RESCUE_N:-?} Beitraege -> $RESCUE_FILE (compactions seit Sync: $((PREV_C + 1)))"
      echo "[Mind Manager] Chat gerettet: ${RESCUE_N:-?} Beitraege -> ${RESCUE_FILE##*/}"
      if [ "$PREV_C" -gt 0 ]; then
        echo "[Mind Manager] ACHTUNG: $((PREV_C + 1)) Kompaktierungen seit dem letzten /mind-all — Sync steht aus."
      fi
      # Rotation (KEIN xargs — Pfade enthalten Leerzeichen). RESUME-Dateien mitrotieren;
      # *_RESUME.done.md faellt nicht unter das Muster und bleibt als Beleg liegen.
      # ⛔ v5.4.1: was im OPEN steht, wird NIE rotiert.
      # Vorher loeschte KEEP=3 ab der vierten Kompaktierung ohne Sync die aelteste Rettung —
      # also genau den Beleg, der noch eingespeist werden musste. Geschuetzte Dateien zaehlen
      # nicht gegen KEEP; wer nie synct, sammelt an. Das ist gewollt: Platte ist billiger als
      # verlorene Arbeit, und die Warnung unten wird mit jeder Kompaktierung lauter.
      GESCHUETZT=$(grep -E '^(path|resume|arbeitsstand)=' "$RESCUE_DIR/OPEN" 2>/dev/null | cut -d= -f2-)
      for pat in '*_chat.md' '*_RESUME.md' '*_ARBEITSSTAND.json'; do
        ls -t "$RESCUE_DIR"/$pat 2>/dev/null | tail -n +$((RESCUE_KEEP + 1)) | while IFS= read -r f; do
          [ -n "$f" ] && [ -f "$f" ] || continue
          case "
$GESCHUETZT
" in *"
$f
"*) continue ;; esac
          rm -f "$f"
        done
      done
    else
      # Rettung fehlgeschlagen: KEIN PENDING-Merker (lieber keine Marke als eine ins Leere).
      # Der Hook laeuft trotzdem weiter — die Backups sind wichtiger als der Extrakt.
      mind_log WARN "chat rescue fehlgeschlagen: ${RESCUE_OUT:0:200}"
      echo "[Mind Manager] WARN: Chat-Rettung fehlgeschlagen (Backups sind trotzdem da)"
      rm -f "$RESCUE_FILE" 2>/dev/null
    fi
  else
    mind_log WARN "session_sampler.py nicht gefunden: $SAMPLER"
  fi
fi

# --- v5.7.6: COMPACT-FAELLIG verbrauchen — UNBEDINGT, ausserhalb jedes Erfolgspfads ---
# Die Kompaktierung LAEUFT gerade; damit ist die Faelligkeit erledigt, ganz gleich ob die
# Chat-Rettung geklappt hat.
#
# ⛔ In v5.7.5 stand diese Entfernung INNERHALB des Erfolgspfads der Rettung
#    (`if RESCUE_OUT=$(…) && [ -s "$RESCUE_FILE" ]`). Scheiterte die Rettung — kein
#    Transkriptpfad, Sampler nicht gefunden, Python-Fehler — blieb der Merker liegen, und
#    stop.sh blockte danach fuer eine Kompaktierung, die bereits gelaufen war. Genau der
#    "Zwang ohne Gegenstand", den der Kommentar dort zu verhindern versprach.
#    Gefunden von der adversarischen Pruefung, nicht von den Tests: die pruefen den
#    Normalfall, und im Normalfall gelingt die Rettung.
if [ -n "$RESCUE_DIR" ] && [ -f "$RESCUE_DIR/COMPACT-FAELLIG" ]; then
  mind_log INFO "COMPACT-FAELLIG erledigt (Kompaktierung laeuft)"
  rm -f "$RESCUE_DIR/COMPACT-FAELLIG" 2>/dev/null
fi

# --- Report ---
if [ -n "$BACKED_UP" ] && [ "$BACKED_UP" -gt 0 ]; then
  mind_log "pre-compact backup: ${BACKED_UP} files (trigger: ${TRIGGER})"
  echo "[Mind Manager] Pre-compact backup: ${BACKED_UP} file(s) saved (trigger: ${TRIGGER})"
else
  mind_log "Pre-compact backup failed or no files to back up (trigger: ${TRIGGER})"
  echo "[Mind Manager] Pre-compact: no files backed up (trigger: ${TRIGGER})"
fi

exit 0
