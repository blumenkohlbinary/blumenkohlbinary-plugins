#!/usr/bin/env bash
# ARCHIV JE SATZ (v5.21.0) — Kuerzen heisst Verschieben, nicht Loeschen.
#
# ⛔ WAS VORHER FEHLTE, gefunden im Plan-Review am 25.08.2026:
#    `archiviere()` liest eine Datei und schreibt ihre MARKEN nach
#    `archiviert-marken.json`. Kein `copy`, kein `move` — es gab ueberhaupt
#    keinen Ort, an den etwas archiviert wurde. Der Schritt "Archiv anlegen"
#    war nicht ausfuehrbar.
#
# ⛔ UND DER KORNFEHLER: `archiviere()` arbeitet je DATEI, --rebuild je SATZ.
#    `pruefe()` schliesst `e["datei"]` von der Suche aus. Originalpfad ->
#    Ratsche dauerhaft blind (die Datei lebt ja weiter). Archivpfad -> jede in
#    der Kurzfassung VERBLIEBENE Marke meldet Wiederauferstehung. Beide falsch.
#
# ⛔ Der Nutzer-Auftrag vom 24.08.2026 lautet woertlich:
#    "verschiebe alles andere in einen archive-Ordner (niemals dauerhaft loeschen)".
#
# ⛔ WINDOWS-PFADE: python bekommt IMMER cygpath -w.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_archiv.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
command -v cygpath >/dev/null 2>&1 || { echo "cygpath fehlt" >&2; exit 2; }
RW=$(cygpath -w "$CLAUDE_PLUGIN_ROOT/references")
OK=0; ROT=0
D=$(mktemp -d); DW=$(cygpath -w "$D")

janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

# Helfer als DATEI — keine Anfuehrungszeichen-Hoelle, keine Backtick-Substitution.
cat > "$D/h.py" <<'PYEOF'
import os
import sys
sys.path.insert(0, sys.argv[1])
sys.stdout.reconfigure(encoding="utf-8", newline="")
import cleaner_ratsche as R

proj = sys.argv[2]
was = sys.argv[3]

if was == "vorhanden":
    print("ja" if callable(getattr(R, "archiviere_saetze", None))
          and callable(getattr(R, "entarchiviere", None)) else "nein")

elif was == "archiviere":
    # Ein Satz mit einer Marke wandert weg, ein zweiter mit EIGENER Marke bleibt.
    quelle = os.path.join(proj, ".claude", "rules", "regel.md")
    weg = ["Der Regler `WEG_TOKENS` stand auf 940000 und ist entfallen."]
    rest = "# Regel\n\nDer Regler `BLEIBT_TOKENS` gilt weiter.\n"
    e = R.archiviere_saetze(proj, quelle, weg, "im Code entfallen", rest=rest)
    open(quelle, "w", encoding="utf-8", newline="\n").write(rest)
    print("%s|%s" % (",".join(e["marken"]), e.get("korn", "?")))

elif was == "archivort":
    print(R.archiv_datei(proj, os.path.join(proj, ".claude", "rules", "regel.md")))

elif was == "laedt":
    # Laedt der Archivort mit? Das entscheidet ueber den ganzen Zweck.
    dl = R.geladene_dateien(proj, nur_projekt=True)
    a = R.archiv_datei(proj, os.path.join(proj, ".claude", "rules", "regel.md"))
    print("ja" if any(os.path.abspath(x) == os.path.abspath(a) for x in dl) else "nein")

elif was == "pruefe":
    auf, n = R.pruefe(proj, nur_projekt=True)
    if auf is None:
        print("NICHT-MESSBAR")
    else:
        print("%d|%s" % (len(auf), ",".join(sorted(m for m, _e, _w in auf))))

elif was == "zurueck":
    # Die archivierte Marke kehrt in eine LADENDE Datei zurueck.
    p = os.path.join(proj, ".claude", "rules", "regel.md")
    t = open(p, encoding="utf-8").read()
    open(p, "w", encoding="utf-8", newline="\n").write(
        t + "\nDoch wieder: `WEG_TOKENS` steht auf 940000.\n")
    print("ok")

elif was == "entarchiviere":
    e, grund = R.entarchiviere(proj, int(sys.argv[4]))
    print("ok" if e else ("FEHLER:" + grund))
PYEOF

h() { python "$DW\\h.py" "$RW" "$DW\\proj" "$@" 2>&1; }

mkdir -p "$D/proj/.claude/rules"
printf '# Regel\n\nDer Regler `WEG_TOKENS` stand auf 940000 und ist entfallen.\nDer Regler `BLEIBT_TOKENS` gilt weiter.\n' \
  > "$D/proj/.claude/rules/regel.md"
printf '# P\n' > "$D/proj/CLAUDE.md"

echo "=== ARCHIV JE SATZ ==="

# --- 1 · die Funktionen existieren ---------------------------------------
janein "archiviere_saetze + entarchiviere vorhanden" ja "$(h vorhanden)"

# --- 2 ⭐ der Archivort liegt AUSSERHALB jedes Ladepfads -----------------
#     Ein Archiv unter rules/ waere der 267-von-920-Fall: ein Ordner,
#     angelegt UM zu kuerzen, der den Bestand verdoppelt.
ORT=$(h archivort)
printf '%s' "$ORT" | grep -q "archiv" && A=ja || A=nein
janein "Archivort heisst archiv/" ja "$A"
printf '%s' "$ORT" | grep -qE "rules[\\/]" && A=ja || A=nein
janein "Archivort liegt NICHT unter rules/" nein "$A"

# --- 3 · archivieren --------------------------------------------------------
AUS=$(h archiviere)
M="${AUS%%|*}"; K="${AUS##*|}"
janein "Korn ist 'satz', nicht 'datei'" satz "$K"

# ⭐ NUR die Marke des verschobenen Satzes — nicht die der bleibenden
printf '%s' "$M" | grep -q "WEG_TOKENS" && A=ja || A=nein
janein "Marke des verschobenen Satzes erfasst" ja "$A"
printf '%s' "$M" | grep -q "BLEIBT_TOKENS" && A=ja || A=nein
janein "Marke des BLEIBENDEN Satzes NICHT erfasst" nein "$A"

# --- 4 · das Archiv existiert und traegt den Satz --------------------------
[ -f "$ORT" ] && A=ja || A=nein
janein "Archivdatei wurde geschrieben" ja "$A"
grep -q "WEG_TOKENS" "$ORT" 2>/dev/null && A=ja || A=nein
janein "der verschobene Satz steht drin" ja "$A"
grep -qi "niemals dauerhaft" "$ORT" 2>/dev/null && A=ja || A=nein
janein "der Kopf nennt den Auftrag" ja "$A"

# --- 5 ⭐ und es LAEDT nicht mit -----------------------------------------
janein "das Archiv laedt NICHT mit" nein "$(h laedt)"

# --- 6 · die Ratsche ist jetzt MESSBAR (vorher rc=2) ----------------------
AUS=$(h pruefe)
printf '%s' "$AUS" | grep -q "NICHT-MESSBAR" && A=ja || A=nein
janein "Ratsche ist messbar geworden" nein "$A"
janein "und meldet (noch) keine Wiederauferstehung" "0|" "$AUS"

# --- 7 ⭐ POSITIVKONTROLLE: die Marke kehrt zurueck -> Befund -------------
#     Ohne diesen Fall waere "0 Auferstehungen" von einem stummen Werkzeug
#     nicht zu unterscheiden.
h zurueck >/dev/null
AUS=$(h pruefe)
printf '%s' "$AUS" | grep -q "^1|WEG_TOKENS" && A=ja || A=nein
janein "zurueckgekehrte Marke -> genau 1 Befund" ja "$A"

# --- 8 · entarchivieren nimmt den Wachposten weg --------------------------
janein "entarchivieren gelingt" ok "$(h entarchiviere 0)"
AUS=$(h pruefe)
printf '%s' "$AUS" | grep -q "^0|" && A=ja || A=nein
janein "danach kein Befund mehr" ja "$A"

# --- 9 · GEGENKONTROLLE: die Archivdatei bleibt --------------------------
#     Geloescht wird NIE etwas — das ist der Kern des Auftrags.
[ -f "$ORT" ] && A=ja || A=nein
janein "Archivdatei bleibt nach dem Entarchivieren" ja "$A"

# --- 10 · GEGENKONTROLLE: ungueltiger Index bricht ab ---------------------
printf '%s' "$(h entarchiviere 99)" | grep -q "FEHLER" && A=ja || A=nein
janein "Index ausserhalb -> Fehler statt stiller Erfolg" ja "$A"

rm -rf "$D"
echo
echo "  gruen: $OK   rot: $ROT"
[ "$ROT" -eq 0 ] || exit 1
