#!/usr/bin/env bash
# VORSCHLAGSMODUS von cleaner_rebuild (v5.29.0) — er war TOT.
#
# ⛔ DER DEFEKT, am Code gefunden (`cleaner_rebuild.py:160`):
#
#       darf = auto and k in AUTO_KLASSEN and not _bleibt_immer(s)
#
#    `darf` verlangt `auto`. OHNE `--auto` ist `wandert` deshalb IMMER leer,
#    `baue()` gibt "nichts zu verschieben" zurueck, und `rebuild()` bricht ab.
#    Der Modus konnte per Konstruktion NICHTS vorschlagen — waehrend der Skill
#    verspricht: "Ohne --auto ist der Lauf ein Vorschlag, und die Auswahl der
#    Saetze gehoert dir."
#
# ⭐ WIE ER AUFFIEL — und warum kein Selbsttest ihn fand:
#    Der Selbsttest fuhr `einteilen(..., auto=True)` (Zeilen 434/476/482/488)
#    und war deshalb immer gruen. Aufgefallen ist es erst im ECHTEN Lauf, an
#    einem WIDERSPRUCH ZWISCHEN ZWEI WERKZEUGEN: `cleaner_aussagen` meldete
#    fuer dieselbe Datei **37 Belege** und woertlich "genau der Fall, fuer den
#    es den Umzug gibt" — `cleaner_rebuild` sagte "nichts zu verschieben".
#    ⛔ Ein Werkzeug, das schweigt, und eines, das nichts zu sagen hat, sind
#      von aussen gleich. Nur die zweite Meinung hat es getrennt.
#
# ⭐ FALL 4 IST DER WICHTIGSTE: der Vorschlag darf NICHTS SCHREIBEN. Ein
#    Vorschlagsmodus, der schreibt, waere schlimmer als einer, der schweigt.
#
# ⛔ WAS DIESE SAMMLUNG NICHT PRUEFT: ob die vorgeschlagenen Saetze die
#    RICHTIGEN sind. Gemessen am echten Bestand waren unter 18 Kandidaten
#    mindestens vier TRAGENDE Aussagen (u.a. "Keine Zahl ist KEINE Null" —
#    eine Fail-safe-Regel, kein Beleg). Das ist VERTAUSCHUNG, nicht Verlust:
#    alle vier Gates halten, und die Datei waere schlechter. Deshalb bleibt
#    die menschliche Auswahl Pflicht — der Vorschlag macht sie moeglich, er
#    ersetzt sie nicht.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_rebuild_vorschlag.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
RB="$CLAUDE_PLUGIN_ROOT/references/cleaner_rebuild.py"
[ -f "$RB" ] || { echo "fehlt: $RB" >&2; exit 2; }
command -v cygpath >/dev/null 2>&1 && W=cygpath || W=echo
w() { if [ "$W" = cygpath ]; then cygpath -w "$1"; else echo "$1"; fi; }
RBW="$(w "$RB")"

OK=0; ROT=0
janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P/.claude/rules"

# Eine Datei mit BEIDEM: Geboten (bleiben) und Belegen (waeren verschiebbar).
cat > "$P/.claude/rules/probe.md" <<'MDEOF'
---
description: Probe fuer den Vorschlagsmodus mit Geboten und Belegen gemischt
globs: ["**/*"]
---

# Probe

⛔ **NIE `rm -rf` auf `dist/` anwenden.** Das ist das Gebot und bleibt.

⛔ **NIE `git push` ohne `git pull --rebase`.** Auch das bleibt.

Gemessen am 21.08.2026: die Rotation loeschte 0 von 7 Dateien, weil `xargs`
an Leerzeichen zerlegt. Der Pfad heisst `Plugin - Entwicklung`.

**Belegt mit 26 Pruefungen**, darunter der Fall "Transkript ohne `usage`" —
keine Zahl ist KEINE Null, sonst schwiege der Notfall bei kaputter Messung.

Bis v5.4.0 schrieb `pre-compact.sh` den Merker mit `>` und einer `path=`-Zeile.
Belegt: `20260816-194132_chat.md`, 412 KB, nie eingespeist.
MDEOF

echo "== 1/5  OHNE --auto muss der Vorschlag KOMMEN (der tote Modus) =="
AUS=$(python "$RBW" --bereich "$(w "$P")" "$(w "$P/.claude/rules/probe.md")" 2>&1)
janein "⭐ Vorschlag erscheint (frueher: 'nichts zu verschieben')" "1" \
       "$(printf '%s' "$AUS" | grep -c 'VORSCHLAG')"
janein "⛔ und NICHT mehr 'nichts zu verschieben'" "0" \
       "$(printf '%s' "$AUS" | grep -c 'nichts zu verschieben')"
janein "er nennt eine Kandidatenzahl" "1" \
       "$(printf '%s' "$AUS" | grep -c 'waeren mit --auto verschiebbar')"
janein "er listet mindestens einen Satz mit Klasse" "1" \
       "$(printf '%s' "$AUS" | grep -cE '^ +[0-9]+ \[beleg' | head -1 | \
          awk '{print ($1>0)?1:0}')"
janein "Rueckgabe 0 (Vorschlag ist kein Fehler)" "0" \
       "$(python "$RBW" --bereich "$(w "$P")" "$(w "$P/.claude/rules/probe.md")" \
          >/dev/null 2>&1; echo $?)"

echo "== 2/5  ⭐ Er sagt, dass die AUSWAHL beim Menschen bleibt =="
janein "⭐ warnt vor VERTAUSCHUNG durch --auto" "1" \
       "$(printf '%s' "$AUS" | grep -c 'VERTAUSCHUNG, nicht Verlust')"
janein "sagt woertlich: die Auswahl gehoert dir" "1" \
       "$(printf '%s' "$AUS" | grep -c 'Auswahl gehoert dir')"

echo "== 3/5  Eine Datei OHNE Belege meldet weiterhin ehrlich 'nichts' =="
mkdir -p "$P/nur"
cat > "$P/nur/gebote.md" <<'MDEOF'
---
description: Nur Gebote, kein einziger Beleg — hier gibt es nichts zu verschieben
globs: ["**/*"]
---

# Nur Gebote

⛔ **NIE loeschen ohne Sicherung.**

⛔ **IMMER `git pull --rebase` vor `git push`.**
MDEOF
AUS2=$(python "$RBW" --bereich "$(w "$P")" "$(w "$P/nur/gebote.md")" 2>&1)
janein "⛔ ohne Belege bleibt es bei 'nichts zu verschieben'" "1" \
       "$(printf '%s' "$AUS2" | grep -c 'nichts zu verschieben')"
janein "kein falscher Vorschlag" "0" "$(printf '%s' "$AUS2" | grep -c 'VORSCHLAG')"
janein "Rueckgabe 1 (nichts zu tun)" "1" \
       "$(python "$RBW" --bereich "$(w "$P")" "$(w "$P/nur/gebote.md")" \
          >/dev/null 2>&1; echo $?)"

echo "== 4/5  ⭐ DER VORSCHLAG SCHREIBT NICHTS =="
VOR="$(find "$P" -type f | sort | xargs md5sum 2>/dev/null | md5sum)"
python "$RBW" --bereich "$(w "$P")" "$(w "$P/.claude/rules/probe.md")" >/dev/null 2>&1
python "$RBW" --bereich "$(w "$P")" "$(w "$P/nur/gebote.md")" >/dev/null 2>&1
NACH="$(find "$P" -type f | sort | xargs md5sum 2>/dev/null | md5sum)"
janein "⭐ Dateibestand byte-gleich nach zwei Vorschlaegen" "$VOR" "$NACH"
janein "⛔ kein Archiv angelegt" "0" \
       "$(ls -1 "$P/.claude/archiv" 2>/dev/null | wc -l)"

echo "== 5/5  --auto bleibt UNVERAENDERT (die Reparatur ist reine Anzeige) =="
AUS3=$(python "$RBW" --bereich "$(w "$P")" "$(w "$P/.claude/rules/probe.md")" --auto 2>&1)
janein "--auto zeigt weiterhin den REBUILD-Kopf" "1" \
       "$(printf '%s' "$AUS3" | grep -c 'REBUILD')"
janein "--auto zeigt NICHT den Vorschlagskopf" "0" \
       "$(printf '%s' "$AUS3" | grep -c 'VORSCHLAG')"
janein "--auto ohne --anwenden schreibt ebenfalls nichts" "$VOR" \
       "$(find "$P" -type f | sort | xargs md5sum 2>/dev/null | md5sum)"
janein "Selbsttest des Werkzeugs unveraendert gruen" "0" \
       "$(python "$RBW" --selbsttest >/dev/null 2>&1; echo $?)"

echo
echo "  $OK gruen, $ROT rot"
[ "$ROT" -eq 0 ] || exit 1
exit 0
