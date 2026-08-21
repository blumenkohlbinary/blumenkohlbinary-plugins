#!/usr/bin/env bash
# COMPACT-FAELLIG (v5.7.5) — nach /mind-all ist die Kompaktierung faellig.
#
# Nutzerwunsch 21.08.2026: "er soll nach mind all erst den compact machen damit das andere
# context fenster nicht belastet wird". Bis v5.7.4 endete der Ablauf passiv mit "kommt von
# selbst" — was nur stimmt, wenn der Sync teuer genug ausfaellt.
#
# ⛔ Was hier NICHT geprueft wird, weil es nicht geht: dass tatsaechlich kompaktiert wird.
#    Weder Hook noch Assistent koennen /compact ausloesen. Geprueft wird, dass die Bitte
#    erzwungen wird und dass der Zwang wieder verschwindet.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_compact_faellig.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
H="$CLAUDE_PLUGIN_ROOT/hooks"
OK=0; ROT=0

janein() { # name erwartung(ja|nein) ist(ja|nein)
  if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
  else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi
}

neu_projekt() { # -> Pfad
  local d; d=$(mktemp -d); mkdir -p "$d/.claude-mind/rescued"; printf '%s' "$d"
}
marker() { # projekt [blocks]
  printf 'ts=2026-08-21 13:00:00\ntokens=772345\nblocks=%s\n' "${2:-0}" \
    > "$1/.claude-mind/rescued/COMPACT-FAELLIG"
}
stop_lauf() { # projekt [stop_hook_active]
  CLAUDE_PROJECT_DIR="$1" MIND_SYNC_FORCE_TOKENS=0 \
    printf '{"session_id":"s","transcript_path":"","stop_hook_active":%s,"cwd":"%s"}' \
      "${2:-false}" "$1" | CLAUDE_PROJECT_DIR="$1" MIND_SYNC_FORCE_TOKENS=0 bash "$H/stop.sh" 2>/dev/null
}

echo "=== COMPACT-FAELLIG ==="

# --- 1 · Merker da -> stop.sh blockt, und der Text nennt /compact ---------
P=$(neu_projekt); marker "$P"
O=$(stop_lauf "$P")
printf '%s' "$O" | grep -q '"decision"' && A=ja || A=nein
janein "Merker vorhanden -> Block" ja "$A"
printf '%s' "$O" | grep -q '/compact' && A=ja || A=nein
janein "Blocktext nennt /compact" ja "$A"
# Die Ehrlichkeit MUSS im Text stehen, sonst versucht der Assistent es selbst
printf '%s' "$O" | grep -qi 'NICHT ausloesbar\|nicht ausloesbar' && A=ja || A=nein
janein "Blocktext nennt die Grenze (nicht ausloesbar)" ja "$A"
rm -rf "$P"

# --- 2 · Der Zaehler wird hochgesetzt ------------------------------------
P=$(neu_projekt); marker "$P"
stop_lauf "$P" >/dev/null
B=$(grep -m1 '^blocks=' "$P/.claude-mind/rescued/COMPACT-FAELLIG" 2>/dev/null | cut -d= -f2-)
janein "Zaehler steht nach einem Block auf 1" 1 "${B:-fehlt}"
# und die uebrigen Felder ueberleben
grep -q '^tokens=772345' "$P/.claude-mind/rescued/COMPACT-FAELLIG" && A=ja || A=nein
janein "tokens= ueberlebt das Umschreiben" ja "$A"
rm -rf "$P"

# --- 3 · Notausgang: nach MIND_COMPACT_MAX_BLOCKS ist Schluss ------------
#     Ein Zwang, den niemand aufloesen kann, waere eine Falle.
P=$(neu_projekt); marker "$P" 2
O=$(MIND_COMPACT_MAX_BLOCKS=2 CLAUDE_PROJECT_DIR="$P" bash -c \
  'printf "{\"session_id\":\"s\",\"transcript_path\":\"\",\"stop_hook_active\":false,\"cwd\":\"$0\"}" "$1" | MIND_SYNC_FORCE_TOKENS=0 bash "$2/stop.sh"' \
  "$P" "$P" "$H" 2>/dev/null)
printf '%s' "$O" | grep -q '"decision"' && A=ja || A=nein
janein "Notausgang: kein Block mehr bei blocks>=max" nein "$A"
[ -f "$P/.claude-mind/rescued/COMPACT-FAELLIG" ] && A=ja || A=nein
janein "Notausgang entfernt den Merker" nein "$A"
rm -rf "$P"

# --- 4 · Kein Merker -> kein Block (kein Fehlalarm) ----------------------
P=$(neu_projekt)
O=$(stop_lauf "$P")
printf '%s' "$O" | grep -q 'COMPACT\|/compact' && A=ja || A=nein
janein "ohne Merker kein Kompaktierungs-Zwang" nein "$A"
rm -rf "$P"

# --- 5 · Schleifenschutz geht VOR ---------------------------------------
#     stop_hook_active=true muss auch mit Merker sofort aussteigen, sonst Endlosschleife.
P=$(neu_projekt); marker "$P"
O=$(stop_lauf "$P" true)
printf '%s' "$O" | grep -q '"decision"' && A=ja || A=nein
janein "stop_hook_active=true schlaegt den Merker" nein "$A"
rm -rf "$P"

# --- 6 · prompt-submit erinnert weiter -----------------------------------
P=$(neu_projekt); marker "$P"
O=$(printf '{"session_id":"s","transcript_path":"","prompt":"hi","cwd":"%s"}' "$P" \
    | CLAUDE_PROJECT_DIR="$P" MIND_SYNC_AT_TOKENS=0 bash "$H/prompt-submit.sh" 2>/dev/null)
printf '%s' "$O" | grep -q '/compact' && A=ja || A=nein
janein "prompt-submit nennt /compact" ja "$A"
rm -rf "$P"

# --- 7 · ohne Merker schweigt prompt-submit dazu -------------------------
P=$(neu_projekt)
O=$(printf '{"session_id":"s","transcript_path":"","prompt":"hi","cwd":"%s"}' "$P" \
    | CLAUDE_PROJECT_DIR="$P" MIND_SYNC_AT_TOKENS=0 bash "$H/prompt-submit.sh" 2>/dev/null)
printf '%s' "$O" | grep -q '/compact' && A=ja || A=nein
janein "ohne Merker schweigt prompt-submit" nein "$A"
rm -rf "$P"

# --- 8 · Merker OHNE blocks=-Zeile -> trotzdem blocken, Zaehler anlegen ---
#     Faellt der Zaehler weg (von Hand editiert, halb geschriebene Datei), darf der
#     Zwang nicht ausfallen — sonst waere Handarbeit ein stiller Notausgang.
P=$(neu_projekt)
printf 'ts=2026-08-21 13:00:00\n' > "$P/.claude-mind/rescued/COMPACT-FAELLIG"
O=$(stop_lauf "$P")
printf '%s' "$O" | grep -q '"decision"' && A=ja || A=nein
janein "Merker ohne blocks= blockt trotzdem" ja "$A"
B=$(grep -m1 '^blocks=' "$P/.claude-mind/rescued/COMPACT-FAELLIG" 2>/dev/null | cut -d= -f2-)
janein "und legt den Zaehler an" 1 "${B:-fehlt}"
rm -rf "$P"

# --- 9 · Pathologisch: Merker ist ein VERZEICHNIS -> nicht abstuerzen ----
#     stop.sh ist der einzige Hook mit Zwangswirkung. Ein Absturz hier ist teurer als
#     ein entfallener Zwang, deshalb muss er fail-open sein.
P=$(neu_projekt); mkdir -p "$P/.claude-mind/rescued/COMPACT-FAELLIG"
O=$(stop_lauf "$P"); R=$?
janein "Verzeichnis statt Datei: sauberer Rueckgabewert" 0 "$R"
rm -rf "$P"

# --- 10 · NEGATIVKONTROLLE, die scheitern KANN ---------------------------
#     Ein Stub, der auf JEDEN Fall blockt, muss an Fall 4 (kein Merker) durchfallen.
#     Damit ist belegt, dass Fall 4 wirklich zwischen "blockt" und "blockt nicht"
#     unterscheidet und nicht bloss immer gruen ist.
stub_blockt_immer() { printf '{"decision":"block","reason":"/compact"}'; }
O=$(stub_blockt_immer)
printf '%s' "$O" | grep -q '"decision"' && A=ja || A=nein
if [ "$A" = "ja" ]; then
  echo "  [ok ] Negativkontrolle: Dauer-Blocker faellt an Fall 4 durch"; OK=$((OK+1))
else
  echo "  [ROT] Negativkontrolle misst nichts — Fall 4 waere immer gruen"; ROT=$((ROT+1))
fi

# --- 11/12 · pre-compact verbraucht den Merker UND protokolliert richtig -------
#     Beim Einbau von v5.7.5 ist die mind_log-Zeile "Sync lief vor dieser Kompaktierung"
#     versehentlich aus dem sync-stand-Block in den COMPACT-FAELLIG-Block gerutscht. Das
#     Verhalten blieb richtig, das Protokoll haette ab dann die falsche Bedingung gemeldet.
#     `bash -n` sieht so etwas nie. Diese zwei Faelle sehen es.
transkript() { # datei
  : > "$1"
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    printf '{"type":"user","message":{"content":[{"type":"text","text":"Frage %s"}]}}\n' "$i" >> "$1"
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Antwort %s. Entscheidung: Weg A."}],"usage":{"input_tokens":2,"cache_read_input_tokens":1000,"cache_creation_input_tokens":3,"output_tokens":9}}}\n' "$i" >> "$1"
  done
}
precompact() { # projekt logdatei
  printf '{"hook_event_name":"PreCompact","cwd":"%s","session_id":"S1","transcript_path":"%s","trigger":"auto"}' \
    "$1" "$1/t.jsonl" \
    | CLAUDE_PROJECT_DIR="$1" MIND_LOG_FILE="$2" bash "$H/pre-compact.sh" >/dev/null 2>&1
}

P=$(neu_projekt); transkript "$P/t.jsonl"; marker "$P"
LG="$P/log.txt"; : > "$LG"
precompact "$P" "$LG"
[ -f "$P/.claude-mind/rescued/COMPACT-FAELLIG" ] && A=ja || A=nein
janein "pre-compact verbraucht COMPACT-FAELLIG" nein "$A"
rm -rf "$P"

P=$(neu_projekt); transkript "$P/t.jsonl"
# sync-stand da, COMPACT-FAELLIG NICHT — die Protokollzeile muss trotzdem kommen
printf 'ts=2026-08-21 13:00:00\n' > "$P/.claude-mind/rescued/sync-stand"
LG="$P/log.txt"; : > "$LG"
precompact "$P" "$LG"
grep -q 'Sync lief vor dieser Kompaktierung' "$LG" && A=ja || A=nein
janein "Protokollzeile haengt an sync-stand, nicht an COMPACT-FAELLIG" ja "$A"
rm -rf "$P"

echo
echo "=================================="
echo "  $OK bestanden, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
