#!/usr/bin/env bash
# REBUILD — KUERZEN DURCH VERSCHIEBEN (v5.21.0), L11 aus
# PLAN-mind-cleaner-vollstaendig.md
#
# Dein AUDIT/REBUILD-Auftrag vom 24.08.2026, woertlich:
#   "Behalte nur die Regeln, bei denen du ohne sie tatsaechlich Fehler machen
#    wuerdest. Formuliere diese Regeln so kurz wie moeglich und verschiebe
#    alles andere in einen archive-Ordner (NIEMALS DAUERHAFT LOESCHEN)."
#
# ⛔ DIE SKILL.md SAGTE BIS v5.20.2 "NIE kuerzen" — meine Zeile, nicht deine,
#    und sie setzte KUERZEN mit LOESCHEN gleich.
#
# ⛔ DAS ERHALTUNGS-GATE AUS cleaner_umzug TAUGT HIER NICHT: es zaehlt Zeilen,
#    und ein Archiv mit Kopf und Datum hat IMMER mehr Zeilen als das Entnommene.
#    Es ist trivial gruen. Hier gilt SATZ-IDENTITAET, gefahren VOR dem Schreiben.
#
# ⛔ DREI SPERREN, DIE KEIN GATE ERSETZEN KANN (alle drei sind VERTAUSCHUNG,
#    nicht VERLUST — kein Satz geht verloren, alle Gates bleiben gruen):
#      Ueberschrift · Tabellenzeile · Rueckbezug im Folgesatz
#    Sie stehen im Modul-Selbsttest; hier wird die CLI geprueft.
#
# ⛔ WINDOWS-PFADE: python bekommt IMMER cygpath -w.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_rebuild.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
command -v cygpath >/dev/null 2>&1 || { echo "cygpath fehlt" >&2; exit 2; }
RB=$(cygpath -w "$CLAUDE_PLUGIN_ROOT/references/cleaner_rebuild.py")
RW=$(cygpath -w "$CLAUDE_PLUGIN_ROOT/references")
OK=0; ROT=0
D=$(mktemp -d)

janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

echo "=============================================================================="
echo "  L11 — kuerzen heisst verschieben, und die Freigabe ist dreistufig"
echo "=============================================================================="

P="$D/p"; R="$P/.claude/rules"
mkdir -p "$R"
mach_regel() {
  cat > "$1" <<'MDEOF'
---
description: Eine Testregel mit Geboten und Belegen zum Verschieben
---
# Testregel

- ALWAYS `tools/backup_tools.py verify` vor dem Restore aufrufen.

- Gemessen 2026-08-01: 12 von 14 Laeufen scheiterten an `xargs` und Leerzeichen.

- Belegt mit 8 Pruefungen in `tests/test_x.sh`, vier davon zuerst rot.

- NEVER `git add -A` im Plugin-Repo aufrufen.

- Gemessen 2026-08-16: 73 Prozent eines Snapshots waren globale Regeln.
MDEOF
}
mach_regel "$R/t.md"
VORHER=$(cksum < "$R/t.md")
BYTES_VORHER=$(wc -c < "$R/t.md")
PW=$(cygpath -w "$P")

echo
echo "  --- Freigabe: die Sperren ---"
python "$RB" --bereich "$PW" "$(cygpath -w "$R/t.md")" --anwenden > /dev/null 2>&1
janein "--anwenden ohne --auto bricht ab (rc=2)" 2 "$?"

cp "$R/t.md" "$R/zwei.md"
python "$RB" --bereich "$PW" "$(cygpath -w "$R/t.md")" "$(cygpath -w "$R/zwei.md")" --auto > /dev/null 2>&1
janein "zwei Dateien in einem Lauf brechen ab (rc=2)" 2 "$?"
rm -f "$R/zwei.md"

python "$RB" --bereich "$D/gibt-es-nicht" "$(cygpath -w "$R/t.md")" --auto > /dev/null 2>&1
janein "toter Projektpfad bricht ab (rc=2)" 2 "$?"

echo
echo "  --- Vorschlag schreibt NICHTS ---"
AUS=$(python "$RB" --bereich "$PW" "$(cygpath -w "$R/t.md")" --auto 2>&1 | tr -d '\r')
janein "Datei nach dem Vorschlag byte-gleich" "$VORHER" "$(cksum < "$R/t.md")"
case "$AUS" in *"Nichts geschrieben"*) janein "und sagt das auch" ja ja ;;
               *) janein "und sagt das auch" ja nein ;; esac
case "$AUS" in *"alle vier Gates halten"*) janein "die vier Gates laufen VOR dem Schreiben" ja ja ;;
               *) janein "die vier Gates laufen VOR dem Schreiben" ja nein ;; esac
janein "kein Archiv angelegt" nein "$([ -e "$P/.claude/archiv" ] && echo ja || echo nein)"

echo
echo "  --- anwenden ---"
python "$RB" --bereich "$PW" "$(cygpath -w "$R/t.md")" --auto --anwenden > /dev/null 2>&1
janein "Lauf meldet Erfolg (rc=0)" 0 "$?"
janein "die Regel ist jetzt anders" ja \
       "$([ "$(cksum < "$R/t.md")" != "$VORHER" ] && echo ja || echo nein)"
# ⛔ Die erste Fassung dieser Zeile lautete `&& echo ja || echo ja` — eine
#    Zusicherung, die NICHT SCHEITERN KANN. Genau das, was
#    messung-vor-glauben.md §1 verbietet. Jetzt gegen die gemessene Byte-Zahl.
janein "die Regel ist KUERZER als vorher" ja \
       "$([ "$(wc -c < "$R/t.md")" -lt "$BYTES_VORHER" ] && echo ja || echo nein)"
janein "das Archiv existiert" ja \
       "$([ -f "$P/.claude/archiv/t.archiv.md" ] && echo ja || echo nein)"

# ⛔ DER ORT IST DER GANZE PUNKT: `geladene_dateien()` ist rekursiv. Ein Archiv
#    unter `.claude/rules/` wuerde WEITER MITLADEN — genau der 267-von-920-Fall.
janein "das Archiv liegt NICHT unter rules/" nein \
       "$(find "$R" -name '*archiv*' | grep -qc . && echo ja || echo nein)"

echo
echo "  --- nichts verloren, nichts erfunden ---"
cat > "$D/pruef.py" <<'PYEOF'
import io
import os
import re
import sys
sys.path.insert(0, sys.argv[1])
sys.stdout.reconfigure(encoding="utf-8", newline="")
import cleaner_aussagen as A


def saetze(p):
    t = io.open(p, encoding="utf-8", errors="replace", newline="").read()
    if t.startswith("---"):
        m = re.match(r"^---\r?\n.*?\r?\n---\r?\n", t, re.S)
        if m:
            t = t[len(m.group(0)):]
    return set(re.sub(r"\s+", " ", s).strip() for s in A.zerlege(t)[0])


alt = saetze(sys.argv[2])
kurz = saetze(sys.argv[3])
arch = saetze(sys.argv[4])
was = sys.argv[5]
if was == "fehlt":
    print(len(alt - kurz - arch))
elif was == "doppelt":
    print(len(kurz & arch))
elif was == "gewandert":
    print(len(alt & arch))
PYEOF
cp "$R/t.md" "$D/nachher.md"
mach_regel "$D/original.md"
PP="$(cygpath -w "$D/pruef.py")"
O="$(cygpath -w "$D/original.md")"; K="$(cygpath -w "$D/nachher.md")"
A="$(cygpath -w "$P/.claude/archiv/t.archiv.md")"
janein "kein Satz verloren" 0 "$(python "$PP" "$RW" "$O" "$K" "$A" fehlt | tr -d '\r')"
janein "kein Satz in BEIDEN (verschoben, nicht kopiert)" 0 \
       "$(python "$PP" "$RW" "$O" "$K" "$A" doppelt | tr -d '\r')"
janein "es ist wirklich etwas gewandert" ja \
       "$([ "$(python "$PP" "$RW" "$O" "$K" "$A" gewandert | tr -d '\r')" -gt 0 ] && echo ja || echo nein)"

echo
echo "  --- der Zeiger nennt den PFAD, nicht den Namen ---"
# Lehre aus cleaner_umzug Gate 3: Pfad 4 von 4 gelesen, Skill-NAME 20-84 %.
janein "Kurzfassung nennt den Archivpfad woertlich" 1 \
       "$(grep -c '\.claude/archiv/t\.archiv\.md' "$R/t.md")"

echo
echo "  --- Rueckweg ---"
janein "das Archiv nennt den Rueckweg" 1 \
       "$(grep -c 'entarchiviere' "$P/.claude/archiv/t.archiv.md")"
janein "die Ratsche hat den Eintrag" ja \
       "$([ -f "$P/.claude-mind/archiviert-marken.json" ] && echo ja || echo nein)"

echo
echo "  --- Zeilenenden bleiben ---"
mkdir -p "$D/q/.claude/rules"
python - "$D/q/.claude/rules/c.md" <<'PYEOF'
import io
import sys
io.open(sys.argv[1], "w", encoding="utf-8", newline="").write(
    "# C\r\n\r\n- ALWAYS pruefen.\r\n\r\n"
    "- Gemessen 2026-08-01: 12 von 14 Laeufen scheiterten.\r\n\r\n"
    "- NEVER loeschen.\r\n")
PYEOF
python "$RB" --bereich "$(cygpath -w "$D/q")" "$(cygpath -w "$D/q/.claude/rules/c.md")" --auto --anwenden > /dev/null 2>&1
CR=$(python -c "import sys;b=open(sys.argv[1],'rb').read();print(b.count(b'\r\n'))" "$D/q/.claude/rules/c.md" | tr -d '\r')
janein "CRLF-Datei bleibt CRLF" ja "$([ "$CR" -gt 0 ] 2>/dev/null && echo ja || echo nein)"

rm -rf "$D"
echo
echo "=============================================================================="
echo "  $OK ok, $ROT rot"
echo "=============================================================================="
[ "$ROT" -eq 0 ]
