#!/usr/bin/env bash
# CLEANER-DOKU (v5.21.0) — drei Aussagen, die falsch waren.
#
# L2  `SKILL.md:305` sagte „NIE kuerzen" — ohne Nutzer-Zuschreibung und im
#     direkten Widerspruch zum REBUILD-Auftrag vom 24.08.2026 („Formuliere
#     diese Regeln so kurz wie moeglich … niemals dauerhaft loeschen").
#     Kuerzen war mit LOESCHEN verwechselt worden.
#
# L3  Die SKILL.md warb mit „hoeren sie an einem Modellwechsel auf?".
#     Das Wort `Modell` kam in `cleaner_belege.py` NULL MAL vor.
#     ⛔ Eine dokumentierte Faehigkeit, die es nicht gibt, ist schlimmer als
#        eine fehlende: man verlaesst sich darauf.
#
# L10 KEIN Cleaner-Werkzeug protokollierte, und /mind-cleaner meldete nichts
#     an MIND_DEBUG_DIR — waehrend /mind-all es tut. Die zwei Werkzeugfehler
#     vom 25.08. waeren nie in der Wiederholungserkennung gelandet.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_cleaner_doku.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
S="$CLAUDE_PLUGIN_ROOT/skills/mind-cleaner/SKILL.md"
A="$CLAUDE_PLUGIN_ROOT/references/cleaner_audit.py"
OK=0; ROT=0
janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

echo "=== CLEANER-DOKU ==="
echo "--- L2 · Kuerzen ist erlaubt, Loeschen nicht ---"

grep -q "NIE LÖSCHEN" "$S" && A1=ja || A1=nein
janein "die Hard Constraint sagt NIE LOESCHEN" ja "$A1"

# ⛔ Die alte Fassung darf nur noch als ZITAT der Ruecknahme vorkommen,
#    nicht mehr als geltende Regel.
grep -q '^- ⛔ \*\*NIE kürzen' "$S" && A1=ja || A1=nein
janein "NIE kuerzen ist KEINE geltende Regel mehr" nein "$A1"
grep -q "Bis v5.20.1 stand hier" "$S" && A1=ja || A1=nein
janein "und die Ruecknahme ist dokumentiert" ja "$A1"

# ⭐ Die Lockerung gilt NUR fuer --rebuild. Stuende sie unbegrenzt in den
#    Hard Constraints, duerfte auch --umzug Saetze aus lebenden Dateien nehmen.
grep -q "Kürzen gilt NUR für \`--rebuild\`" "$S" && A1=ja || A1=nein
janein "die Lockerung ist auf --rebuild begrenzt" ja "$A1"

# und der Auftrag steht woertlich dabei
grep -q "niemals dauerhaft löschen" "$S" && A1=ja || A1=nein
janein "der Nutzer-Auftrag steht woertlich dabei" ja "$A1"

echo "--- L3 · die Modell-Behauptung ist zurueckgezogen ---"

grep -q "| \`Debug/index.jsonl\` | datierte Verstöße — \*\*hören sie an einem Modellwechsel" "$S" \
  && A1=ja || A1=nein
janein "die Behauptung steht NICHT mehr in der Belegtabelle" nein "$A1"
grep -q "Modell-Alterung ist NICHT eingebaut" "$S" && A1=ja || A1=nein
janein "die Ruecknahme steht da" ja "$A1"
grep -q "Trennschärfe heute: null" "$S" && A1=ja || A1=nein
janein "mit der Messung, die sie begruendet" ja "$A1"

# ⛔ Und der Audit fuehrt sie als NICHT GEPRUEFT — sonst waere sie nur
#    verschwunden statt ausgewiesen.
grep -q "Schwaeche AELTERER Modelle" "$A" && A1=ja || A1=nein
janein "das Audit weist sie als ungeprueft aus" ja "$A1"

echo "--- L10 · Protokollierung ist Pflicht ---"

grep -q "Step 8: Protokollieren" "$S" && A1=ja || A1=nein
janein "es gibt einen Protokoll-Schritt" ja "$A1"
grep -q "mind_debug_write" "$S" && A1=ja || A1=nein
janein "er nennt mind_debug_write" ja "$A1"

# ⭐ Der wichtigere Teil: auch das SCHWEIGEN wird protokolliert.
grep -qi "Lauf, der nichts findet, protokolliert das ebenfalls" "$S" && A1=ja || A1=nein
janein "auch ein stiller Lauf protokolliert" ja "$A1"
grep -q "\[Protokoll\]" "$S" && A1=ja || A1=nein
janein "und der Self-Check hat eine Protokoll-Zeile" ja "$A1"

echo "--- GEGENKONTROLLE ---"
# Ohne diese Probe waere jeder Treffer oben auch mit einer leeren Datei gruen.
grep -q "Diese Zeile gibt es garantiert nirgends xyzzy" "$S" && A1=ja || A1=nein
janein "ein erfundener Text wird NICHT gefunden" nein "$A1"
[ -s "$S" ] && A1=ja || A1=nein
janein "die SKILL.md ist nicht leer" ja "$A1"

echo
echo "  gruen: $OK   rot: $ROT"
[ "$ROT" -eq 0 ] || exit 1
