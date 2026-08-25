#!/usr/bin/env bash
# CODE-KANDIDATEN (v5.21.0) — L1 aus PLAN-mind-cleaner-vollstaendig.md
#
# Nutzer-Szenario 1 vom 24.08.2026, praezisiert am 25.08.:
#   "sachen die die ki selber herleiten kann z.b zustellplan app wenn es im code
#    schon gut beschrieben ist braucht man dafuer kein extra dokument ...
#    dann muss die ki entscheiden wuerdest du das VERSTEHEN ohne diese rule"
#
# ⛔ WAS BEWUSST NICHT GEBAUT WURDE: ein Werkzeug, das URTEILT. Der Plan-Review
#    hat den Entwurf `cleaner_code.py` zerlegt — er misst "kommt der Bezeichner
#    vor", nicht "verstehe ich es ohne die Regel".
#
# ⛔ DAS GEGENBEISPIEL, das jede Zusicherung hier traegt: `calculate_km`.
#    Die km-Dynamik der Zustellplan-App verschwand still bei einem Umbau, GENAU
#    WEIL nur der Code sie trug und keine Regel das Warum festhielt. Ein
#    Werkzeug mit der Regel "steht im Code -> Regel weg" haette genau diesen
#    Verlust EMPFOHLEN. Deshalb pruefen die Faelle unten KANDIDATENMENGEN,
#    niemals Urteile.
#
# ⛔ WINDOWS-PFADE: python bekommt IMMER cygpath -w.
#
# Aufruf:  CLAUDE_PLUGIN_ROOT=<paket> bash tests/test_code_kandidaten.sh
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
import cleaner_aussagen as A

regel = sys.argv[2]
baum = sys.argv[3]
was = sys.argv[4]

txt = open(regel, encoding="utf-8", errors="replace").read()
aus, _ = A.zerlege(txt)
k = A.code_kandidaten(aus, baum, regeldatei=regel)

if was == "anzahl":
    print(len(k))
elif was == "dateien":
    # welche Quelldateien tauchen ueberhaupt auf?
    s = set()
    for tr in k.values():
        for d, _z, _s, _m in tr:
            s.add(os.path.basename(d))
    print(",".join(sorted(s)))
elif was == "kein-urteil":
    # ⛔ Die Rueckgabe darf KEIN Urteilsfeld tragen.
    verboten = ("ueberfluessig", "redundant", "kann weg", "loeschen", "unnoetig")
    roh = repr(k).lower()
    print("sauber" if not any(v in roh for v in verboten) else "URTEIL-GEFUNDEN")
elif was == "bericht":
    import io
    import contextlib
    puf = io.StringIO()
    with contextlib.redirect_stdout(puf):
        A.code_bericht(aus, k, baum)
    print(puf.getvalue())
PYEOF

lauf() { python "$(cygpath -w "$D/h.py")" "$RW" "$(cygpath -w "$1")" "$(cygpath -w "$2")" "$3" 2>&1 | tr -d '\r'; }

echo "=============================================================================="
echo "  L1 — Code-Kandidaten VORLEGEN, nicht urteilen"
echo "=============================================================================="

# ---------------------------------------------------------------- Quellbaum
B="$D/baum"
mkdir -p "$B/hooks" "$B/node_modules/fremd" "$B/__pycache__"
cat > "$B/hooks/stop.sh" <<'CODEEOF'
#!/usr/bin/env bash
# Der Stop-Hook blockt, solange OPEN liegt.
OPEN="$RESCUE_DIR/OPEN"
if [ -f "$OPEN" ] && [ "$MIND_STOP_MAX_BLOCKS" -gt 0 ]; then
  echo '{"decision":"block"}'
fi
CODEEOF
cat > "$B/hooks/lib.sh" <<'CODEEOF'
#!/usr/bin/env bash
mind_sync_voll() {
  # MIND_SYNC_DELTA entscheidet, ab wann ein sync-stand als verbraucht gilt.
  grep -m1 '^umfang=' "$1"
}
CODEEOF
# ⛔ Fremder Code und Kopien duerfen NICHT durchsucht werden.
echo 'OPEN MIND_STOP_MAX_BLOCKS decision block' > "$B/node_modules/fremd/x.js"
echo 'OPEN MIND_STOP_MAX_BLOCKS' > "$B/__pycache__/y.py"
# Eine .md im Quellbaum ist KEIN Code.
echo 'OPEN und MIND_STOP_MAX_BLOCKS stehen hier auch.' > "$B/LIESMICH.md"

# ---------------------------------------------------------------- Fixtures
# 1) Regel, die den Code spiegelt
cat > "$D/spiegel.md" <<'MDEOF'
# Stop-Hook

Der Hook blockt, solange `OPEN` liegt und `MIND_STOP_MAX_BLOCKS` groesser 0 ist.

`mind_sync_voll` liest `umfang=` aus dem Merker.
MDEOF

# 2) Regel, die nur das WARUM sagt — keine Bezeichner aus dem Code
cat > "$D/warum.md" <<'MDEOF'
# Warum es diese Regel gibt

Eine Pruefung, die ihren Gegenstand knapp verfehlt, ist gefaehrlicher als gar
keine: sie erzeugt ein gruenes Ergebnis, auf das sich danach jeder verlaesst.

Wer nur Fehlalarme wegdreht, dreht am Ende das Signal weg.
MDEOF

# 3) Regel, die eine ANDERE Quelldatei spiegelt
# ⛔ Muss NICHT-LEER und VERSCHIEDEN von (1) sein. Die erste Fassung dieser
#    Sammlung nahm hier einen zweiten Nullfall — dann waren "drei Mengen" in
#    Wahrheit zwei, und die Zusicherung war gruen ohne zu messen.
cat > "$D/andere.md" <<'MDEOF'
# Die Bibliothek

`mind_sync_voll` liest `MIND_SYNC_DELTA` und entscheidet ueber den Teilsync.
MDEOF

# 4) Regel mit genau EINER geteilten Marke — unter der Schwelle
cat > "$D/einzeln.md" <<'MDEOF'
# Einzelne Marke

Der Wert `MIND_STOP_MAX_BLOCKS` ist ein Notausgang und keine Ration.
MDEOF

echo
echo "  --- drei Fixtures, drei verschiedene Kandidatenmengen ---"
M1=$(lauf "$D/spiegel.md" "$B" dateien)
M2=$(lauf "$D/warum.md"   "$B" dateien)
M3=$(lauf "$D/andere.md"  "$B" dateien)
A3=$(lauf "$D/einzeln.md" "$B" anzahl)
echo "       spiegel=[$M1]  warum=[$M2]  andere=[$M3]"
janein "Regel, die stop.sh spiegelt -> stop.sh" stop.sh "$M1"
janein "Regel, die nur das WARUM sagt -> leere Menge" "" "$M2"
janein "Regel, die lib.sh spiegelt -> lib.sh" lib.sh "$M3"
# ⛔ Die eigentliche Forderung des Plans: DREI Mengen, PAARWEISE verschieden.
#    Zweimal die leere Menge waere gruen und wertlos.
janein "drei paarweise VERSCHIEDENE Mengen" ja \
       "$([ "$M1" != "$M2" ] && [ "$M1" != "$M3" ] && [ "$M2" != "$M3" ] && echo ja || echo nein)"
janein "eine einzelne geteilte Marke -> keine (Schwelle)" 0 "$A3"

echo
echo "  --- was NICHT durchsucht wird ---"
DAT=$(lauf "$D/spiegel.md" "$B" dateien)
echo "       gefunden in: $DAT"
case "$DAT" in *x.js*) janein "node_modules bleibt aussen vor" ja nein ;;
               *) janein "node_modules bleibt aussen vor" ja ja ;; esac
case "$DAT" in *y.py*) janein "__pycache__ bleibt aussen vor" ja nein ;;
               *) janein "__pycache__ bleibt aussen vor" ja ja ;; esac
case "$DAT" in *LIESMICH*) janein "eine .md ist kein Code" ja nein ;;
               *) janein "eine .md ist kein Code" ja ja ;; esac
case "$DAT" in *stop.sh*) janein "der echte Hook wird gefunden" ja ja ;;
               *) janein "der echte Hook wird gefunden" ja nein ;; esac

echo
echo "  --- die Regeldatei findet sich nicht selbst ---"
# Regel als .py-Datei IM Quellbaum: ohne Ausschluss wuerde sie sich selbst melden
cp "$D/spiegel.md" "$B/selbst.py"
S=$(python "$(cygpath -w "$D/h.py")" "$RW" "$(cygpath -w "$B/selbst.py")" "$(cygpath -w "$B")" dateien 2>&1 | tr -d '\r')
case "$S" in *selbst.py*) janein "eigene Datei ausgeschlossen" ja nein ;;
             *) janein "eigene Datei ausgeschlossen" ja ja ;; esac
rm -f "$B/selbst.py"

echo
echo "  --- ⛔ KEIN URTEIL, und das ist die Kernzusicherung ---"
janein "Rueckgabe traegt kein Urteilsfeld" sauber "$(lauf "$D/spiegel.md" "$B" kein-urteil)"
BER=$(lauf "$D/spiegel.md" "$B" bericht)
case "$BER" in *"KEIN URTEIL"*) janein "Bericht sagt ausdruecklich: kein Urteil" ja ja ;;
               *) janein "Bericht sagt ausdruecklich: kein Urteil" ja nein ;; esac
case "$BER" in *"WUERDEST DU DAS AUCH OHNE DIESE REGEL VERSTEHEN"*)
                 janein "Bericht stellt die Nutzer-Frage woertlich" ja ja ;;
               *) janein "Bericht stellt die Nutzer-Frage woertlich" ja nein ;; esac
case "$BER" in *calculate_km*) janein "Bericht nennt das calculate_km-Gegenbeispiel" ja ja ;;
               *) janein "Bericht nennt das calculate_km-Gegenbeispiel" ja nein ;; esac
case "$BER" in *"Code sagt WAS"*) janein "Bericht trennt WAS von WARUM" ja ja ;;
               *) janein "Bericht trennt WAS von WARUM" ja nein ;; esac

echo
echo "  --- leerer Befund ist KEINE Entwarnung ---"
BER2=$(lauf "$D/warum.md" "$B" bericht)
case "$BER2" in *"heisst NICHT"*) janein "0 Kandidaten wird nicht als 'alles noetig' gelesen" ja ja ;;
                *) janein "0 Kandidaten wird nicht als 'alles noetig' gelesen" ja nein ;; esac

rm -rf "$D"
echo
echo "=============================================================================="
echo "  $OK ok, $ROT rot"
echo "=============================================================================="
[ "$ROT" -eq 0 ]
