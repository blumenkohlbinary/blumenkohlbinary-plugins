#!/usr/bin/env bash
# NEUN ABLAGEN STATT VIER (v5.21.0) — L4 aus PLAN-mind-cleaner-vollstaendig.md
#
# ⛔ WAS VORHER FEHLTE: dein AUDIT-Prompt vom 24.08.2026 nennt woertlich
#    "CLAUDE.md, Rules-Dateien, Skills, Hooks und Memory", Szenario 2 nennt
#    "memory lokal, memory global". `ablagen()` deckte VIER ab — Skills, Memory
#    und die Ahnen-CLAUDE.md wurden NIE verglichen.
#
# ⛔ FREMDPROJEKT-SCHUTZ: `get_memory_dir` in lib.sh faellt bei Slug-Mismatch auf
#    das NEUESTE FREMDE Projekt zurueck (lib.sh:545-548). `mind_snapshot` sichert
#    seit v5.2.1 dagegen ab. `ablagen()` tat es nicht — dieselbe Luecke, andere
#    Ebene. Marken aus einem fremden Projekt waeren als Duplikate gemeldet worden.
#
# ⛔ GATE AUF DIE DICT-SCHLUESSEL, nicht auf die Bildschirmausgabe.
#    (messung-vor-glauben.md §1: "Die Kontrolle prueft den MECHANISMUS, nicht die
#    DARSTELLUNG" — dreimal am 21.08.2026 an genau diesem Fehler gescheitert.)
#
# ⛔ WINDOWS-PFADE: python bekommt IMMER cygpath -w.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_ablagen.sh
set -u
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { echo "CLAUDE_PLUGIN_ROOT fehlt" >&2; exit 2; }
command -v cygpath >/dev/null 2>&1 || { echo "cygpath fehlt" >&2; exit 2; }
RW=$(cygpath -w "$CLAUDE_PLUGIN_ROOT/references")
OK=0; ROT=0
D=$(mktemp -d)

janein() { if [ "$2" = "$3" ]; then echo "  [ok ] $1"; OK=$((OK+1))
           else echo "  [ROT] $1 — erwartet '$2', bekommen '$3'"; ROT=$((ROT+1)); fi; }

cat > "$D/h.py" <<'PYEOF'
import os
import sys
sys.path.insert(0, sys.argv[1])
sys.stdout.reconfigure(encoding="utf-8", newline="")
import cleaner_duplikate as C

heim = sys.argv[2]
proj = sys.argv[3]
was = sys.argv[4]
os.environ["HOME"] = heim
os.environ["USERPROFILE"] = heim

if was == "schluessel":
    print(" ".join(sorted(C.ablagen(proj).keys())))
elif was == "nur-projekt":
    # ⛔ Existiert heute als Zusicherung NIRGENDS — deshalb hier.
    print(len([k for k in C.ablagen(proj, "projekt") if k.startswith("g:")]))
elif was == "nur-global":
    print(len([k for k in C.ablagen(proj, "global") if k.startswith("p:")]))
elif was == "memory-da":
    print(1 if C._memory_dir(heim, proj) else 0)
elif was == "memory-fremd":
    # Slug passt NICHT -> darf NICHT in ein fremdes Projekt zeigen
    print(C._memory_dir(heim, proj) or "LEER")
elif was == "memory-ohne-projekt":
    print(C._memory_dir(heim) or "LEER")
elif was == "wurzel-ist-ordner":
    w = C.ablage_wurzeln(proj)
    print(sum(1 for v in w.values() if os.path.isfile(v)))
elif was == "wurzel-schluessel":
    print(" ".join(sorted(C.ablage_wurzeln(proj).keys())))
elif was == "wurzel-nur-projekt":
    print(" ".join(sorted(C.ablage_wurzeln(proj, "projekt").keys())))
elif was == "ahnen":
    print(len(C._ahnen(proj)))
elif was == "ahnen-namen":
    print(" ".join(sorted(os.path.basename(p) for p in C._ahnen(proj))))
elif was == "zaehle":
    a = C.ablagen(proj)
    print(" ".join("%s=%d" % (k, len(v)) for k, v in sorted(a.items())))
PYEOF
HW=""
lauf() { python "$(cygpath -w "$D/h.py")" "$RW" "$1" "$2" "$3" 2>&1 | tr -d '\r'; }

echo "=============================================================================="
echo "  L4 — neun Ablagen, mit Fremdprojekt-Schutz"
echo "=============================================================================="

# ---------------------------------------------------------------- Aufbau
H="$D/heim"; P="$D/proj"
mkdir -p "$H/.claude/rules" "$H/.claude/skills/ein-skill" "$P/.claude/rules" "$P/.claude/skills/a"
echo "# g" > "$H/.claude/CLAUDE.md"
echo "# gr" > "$H/.claude/rules/eine.md"
echo "# gs" > "$H/.claude/skills/ein-skill/SKILL.md"
echo "# p" > "$P/CLAUDE.md"
echo "# pr" > "$P/.claude/rules/eine.md"
echo "# ps" > "$P/.claude/skills/a/SKILL.md"
HWIN=$(cygpath -w "$H"); PWIN=$(cygpath -w "$P")

# Memory-Verzeichnis unter dem RICHTIGEN Slug anlegen
SLUG=$(printf '%s' "$PWIN" | sed 's/[^A-Za-z0-9]/-/g' | sed 's/^-*//')
mkdir -p "$H/.claude/projects/$SLUG/memory"
echo "# m" > "$H/.claude/projects/$SLUG/memory/MEMORY.md"

echo
echo "  --- die Schluessel des Dicts (nicht die Bildschirmausgabe) ---"
K=$(lauf "$HWIN" "$PWIN" schluessel)
for want in "g:CLAUDE.md" "g:rules" "g:skills" "p:CLAUDE.md" "p:rules" "p:skills" "p:memory" "ahnen"; do
  case " $K " in *" $want "*) janein "Ablage $want vorhanden" ja ja ;;
                 *) janein "Ablage $want vorhanden" ja nein ;; esac
done
janein "genau acht Ablagen" 8 "$(printf '%s' "$K" | wc -w | tr -d ' ')"
# ⛔ NEGATIVFALL: g:memory war in der ersten L4-Fassung dabei und konnte per
#    Konstruktion NIE eine Datei enthalten (lib.sh:372 bildet den Memory-Pfad
#    immer aus dem Projekt-Slug). Diese Zeile verhindert die Rueckkehr.
case " $K " in *" g:memory "*) janein "KEIN totes g:memory" nein ja ;;
               *) janein "KEIN totes g:memory" nein nein ;; esac

echo
echo "  --- Bereichsgrenze ---"
janein "--nur projekt liest NICHTS Globales" 0 "$(lauf "$HWIN" "$PWIN" nur-projekt)"
janein "--nur global liest NICHTS Projekteigenes" 0 "$(lauf "$HWIN" "$PWIN" nur-global)"
janein "wurzeln: projekt-Bereich ohne g:" "p:memory p:rules p:skills" "$(lauf "$HWIN" "$PWIN" wurzel-nur-projekt)"

echo
echo "  --- Fremdprojekt-Schutz (das eigentliche Risiko) ---"
janein "Memory wird gefunden, wenn der Slug passt" 1 "$(lauf "$HWIN" "$PWIN" memory-da)"
FREMD="$D/anderes"; mkdir -p "$FREMD"
janein "Slug-Mismatch -> LEER, nicht fremdes Projekt" LEER "$(lauf "$HWIN" "$(cygpath -w "$FREMD")" memory-fremd)"
janein "ohne Projektangabe -> LEER" LEER "$(lauf "$HWIN" "$PWIN" memory-ohne-projekt)"

echo
echo "  --- ablage_wurzeln liefert ORDNER, nicht Dateien ---"
janein "keine Datei unter den Wurzeln" 0 "$(lauf "$HWIN" "$PWIN" wurzel-ist-ordner)"
janein "fuenf Wurzeln (die CLAUDE.md sind keine)" "g:rules g:skills p:memory p:rules p:skills" "$(lauf "$HWIN" "$PWIN" wurzel-schluessel)"

echo
echo "  --- Ahnen: nur AUFWAERTS, nie seitwaerts ---"
echo "# ahn" > "$D/CLAUDE.md"
echo "# lokal" > "$D/.claude.local.md"
mkdir -p "$D/nachbar"; echo "# nachbar" > "$D/nachbar/CLAUDE.md"
janein "zwei Ahnen im Elternordner" 2 "$(lauf "$HWIN" "$PWIN" ahnen)"
janein "der Nachbar ist NICHT dabei" ".claude.local.md CLAUDE.md" "$(lauf "$HWIN" "$PWIN" ahnen-namen)"

echo
echo "  --- Rekursion: Unterordner zaehlen mit (V4) ---"
mkdir -p "$P/.claude/rules/tief/tiefer"
echo "# t" > "$P/.claude/rules/tief/tiefer/versteckt.md"
Z=$(lauf "$HWIN" "$PWIN" zaehle)
case "$Z" in *"p:rules=2"*) janein "Datei in rules/tief/tiefer/ wird gezaehlt" ja ja ;;
              *) janein "Datei in rules/tief/tiefer/ wird gezaehlt" ja "nein ($Z)" ;; esac
case "$Z" in *"p:skills=1"*) janein "SKILL.md im Unterordner wird gezaehlt" ja ja ;;
              *) janein "SKILL.md im Unterordner wird gezaehlt" ja "nein ($Z)" ;; esac

echo
echo "  --- CLI: --bereich heisst an zwei Stellen zwei Dinge (25.08.2026) ---"
# SKILL.md:22 verspricht dem Nutzer `--bereich global|projekt|alles`,
# SKILL.md:48 ruft `--bereich "$PROJ" --nur projekt`. Wer die dokumentierte
# Form eintippt, setzte den PROJEKTPFAD auf die Zeichenkette "projekt" — und
# die Ausgabe zeigte dann `p:rules 0`, was wie ein Befund ueber das Projekt
# aussieht statt wie ein Bedienfehler. Klasse `instrument-misst-nichts`.
CD_PY="$CLAUDE_PLUGIN_ROOT/references/cleaner_duplikate.py"
CD_W=$(cygpath -w "$CD_PY")

AUS=$(python "$CD_W" --bereich "$PWIN" 2>&1 | tr -d '')
KOPFZAHL=$(printf '%s
' "$AUS" | grep -o 'ueber [0-9]* Ablagen' | grep -o '[0-9]*')
LISTZAHL=$(printf '%s
' "$AUS" | grep -cE '^  (g|p):|^  ahnen ')
janein "Kopfzeile zaehlt, was sie auflistet" "$KOPFZAHL" "$LISTZAHL"

AUS2=$(CLAUDE_PROJECT_DIR="$PWIN" python "$CD_W" --bereich projekt 2>&1 | tr -d '')
case "$AUS2" in *"als BEREICH verstanden"*) janein "Bereichswort an der Pfadstelle wird erkannt" ja ja ;;
                *) janein "Bereichswort an der Pfadstelle wird erkannt" ja nein ;; esac
janein "und liest dann NICHTS Globales" 0 "$(printf '%s
' "$AUS2" | grep -cE '^  g:')"

# ⛔ Rueckgabewert OHNE Pipe messen — eine Pipe verschluckt ihn.
python "$CD_W" --bereich "$D/gibt-es-nicht" > /dev/null 2>&1
janein "toter Projektpfad bricht ab (rc=2)" 2 "$?"

rm -rf "$D"
echo
echo "=============================================================================="
echo "  $OK ok, $ROT rot"
echo "=============================================================================="
[ "$ROT" -eq 0 ]
