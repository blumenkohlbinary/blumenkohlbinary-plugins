# Token-Budget — gemessene Werte statt Faustzahlen

> **Stand des Inhalts: 21.08.2026.** Alle Zahlen unten sind an diesem Rechner gemessen, nicht
> aus der Community uebernommen. Wo etwas geschaetzt ist, steht es dabei.

## ⛔ Drei Behauptungen, die hier bis v5.6.0 standen — alle drei widerlegt

| Stand bis v5.6.0 | Gemessen 21.08.2026 |
|---|---|
| „No API, CLI command, or env var to query per-file token usage" | **Der Kontextstand ist auslesbar** — aus dem Transkript, siehe unten |
| „token counts are undocumented" (zum `transcript_path`) | **2 062 von 5 044 Zeilen tragen `usage`**, die letzte ist der aktuelle Stand |
| „Auto-compaction threshold: ~167K of 200K tokens … **not configurable**" | **Fenster und Schwelle sind beide einstellbar**, Formel unten |

**Die Lehre ueber diese Datei hinaus:** eine Referenz, die „nicht moeglich" sagt, wird nicht
nachgeprueft — sie beendet die Suche. Zwei Jahre lang hat niemand nachgesehen, ob im Transkript
Tokenzahlen stehen.

## Den Kontextstand messen

Die letzte Transkriptzeile mit einem `usage`-Objekt traegt den aktuellen Stand:

```
Kontext = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
```

`output_tokens` gehoert **nicht** dazu — die Antwort ist beim naechsten Aufruf bereits Teil
des Eingabekontexts und wuerde doppelt zaehlen.

Fertig in `hooks/lib.sh`: **`mind_kontext_tokens <transcript>`**.

⚠ **Keine Zahl ist KEINE Null.** Ist nichts lesbar, gibt die Funktion nichts aus und
Rueckgabewert 1. Wer hier 0 zurueckgaebe, meldete „Kontext leer" statt „unbekannt" — und jeder
Schwellwert-Ausloeser bliebe still, ohne dass es auffiele.

## Wann die Auto-Kompaktierung feuert

Aus der CLI-Binaerdatei hergeleitet, empirisch bestaetigt:

```
Ausloeser = min( Fenster − Fenster × 0,12 ,  Fenster × Prozent/100 ,  Fenster − 13000 )
```

| Stellschraube | Wo | Wirkung |
|---|---|---|
| `autoCompactWindow` | `~/.claude/settings.json` | **Fenstergroesse**, 100 000 – 1 000 000 |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `settings.json` → `env` | Prozentsatz, `0 < n ≤ 100` |
| `--autocompact` | CLI-Aufruf | wie `autoCompactWindow` |

**Beleg fuer die 12 %:** bei 1M-Fenster ohne Regler loeste **879 106** nicht aus, **880 984**
schon — die Schwelle liegt also bei 880 000 = 1M − 12 %.

⛔ **Der Unterschied, der einmal verwechselt wurde:** `autoCompactWindow: 700000` verkleinert
das **Fenster** (weniger Platz zum Arbeiten). `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` senkt nur den
**Ausloeser** und laesst das Fenster gross. Wer frueher kompaktieren will, nimmt den Prozentsatz.

## Der 800k-Ablauf dieses Rechners (v5.7.0)

```
800 000  ->  /mind-all wird gemahnt   (MIND_SYNC_AT_TOKENS,    prompt-submit.sh)
840 000  ->  /mind-all wird erzwungen (MIND_SYNC_FORCE_TOKENS, stop.sh)
850 000  ->  Kompaktierung            (PCT_OVERRIDE 85 bei 1M-Fenster)
```

**Warum der Sync VOR die Kompaktierung gehoert:** laeuft er danach, fuellt er den frisch
geleerten Kontext sofort wieder mit 40 000 – 60 000 Tokens. Davor gearbeitet, raeumt die
Kompaktierung hinterher auf.

**Die 50 000 Kopffreiheit sind knapp und bewusst so.** Kostet der Sync 60k, wird die Schwelle
waehrend des Laufs ueberschritten — das ist kein Fehler, sondern die gewollte Reihenfolge.
`pre-compact.sh` erzeugt dann dank `sync-stand` **keine** neue Schuld.

⛔ **Ausloesen laesst sich eine Kompaktierung nicht.** Drei unabhaengige Belege: die Hook-Doku
(PreCompact kann nur *verhindern*), die Werkzeugliste (`/compact` ist CLI-Befehl, kein Skill)
und die Binaerdatei. Steuerbar ist nur der **Zeitpunkt** ueber die Schwellen oben.

## Was ein `/mind-all`-Lauf kostet

**40 000 – 60 000 Tokens** (gemessen 20.08.2026). Die Spanne ist das Ergebnis, keine
Nachlaessigkeit: die drei vorgeschriebenen Schaetzer laufen bei deutschem Text um **38 %**
auseinander (42 424 · 42 822 · 31 086).

| Posten | Umfang |
|---|---|
| die 6 SKILL.md der Kette | 3 347 Zeilen |
| Referenzen, nur bei Bedarf | bis ~1 000 Zeilen |
| Agentenergebnisse im Hauptkontext | 6 × ~1–3k |

## Schaetzformeln — nur wo nicht gemessen werden kann

⚠ **Immer DREI Schaetzer ausweisen**, nie einen. Sie laufen bei deutschem Text um ein Drittel
auseinander, und welcher stimmt, ist unbekannt.

```
Zeichen / 4   ·   Bytes / 4   ·   Woerter × 1,4
```

| Quelle | Zeilen | Tokens | Rate |
|---|---|---|---|
| MEMORY.md | 200 | ~1 500 | 7,5 T/Zeile |
| CLAUDE.md unoptimiert | 200 | ~4 500 | 22,5 T/Zeile |
| CLAUDE.md optimiert | 200 | ~1 800 | 9 T/Zeile |
| 1 MCP-Server (Werkzeugdefinitionen) | — | ~14 000 | — |

## Schwellen fuer den Optimierer

| Datei | Grenze | Was dann |
|---|---|---|
| MEMORY.md | > 180 Zeilen **oder** > 22 KB | warnen (25-KB-Grenze ab CC 2.1.198) |
| CLAUDE.md | > 150 Zeilen | aufteilen ueber Rules |
| Rules gesamt | > 400 Zeilen | Befolgung faellt auf ~71 % (SFEIR) |

## Was eine Kompaktierung ueberlebt

1. **MEMORY.md** — wird jede Sitzung neu eingespielt
2. **CLAUDE.md** — immer geladen, per Definition kompaktierungsfest
3. **PreCompact-Hook** — rettet den Chat und schreibt den Arbeitsstand
4. **`<ts>_ARBEITSSTAND.json` + `UEBERGABE`** (v5.7.0) — wird nach der Kompaktierung in den
   Chat injiziert, unabhaengig davon, ob eine Sync-Schuld besteht

⚠ **Offen:** ob `exit 2` in PreCompact die Kompaktierung wirklich abbricht, ist **nicht
gemessen**. Die Doku sagt es; ein Versuch wuerde die laufende Sitzung kosten.
