---
name: fuse-docs
description: "Multi-Dokument-Fusion via 8-Stufen-Pipeline. Nutze wenn der User 'fusioniere', 'merge Dokumente', 'fasse zusammen', 'fuse-docs' sagt. Verlustfreie Fusion."
argument-hint: "[dateipfade oder @mentions]"
context: inherit
allowed-tools: Read, Write, Glob, Grep, Agent
---

# /fuse-docs — Multi-Dokument-Fusion

Fusioniere mehrere Dokumente zu einem einzigen, super-strukturierten Output mit maximaler Informationsdichte, null Verlust, Source Coverage und Widerspruchs-Annotationen.

**KRITISCH: Dieser Skill verwendet `context: inherit`.** Die Orchestrierung laeuft in der Hauptkonversation (Tiefe 0). Sub-Agents werden bei Tiefe 1 dispatcht. Dieses Design respektiert das Verschachtelungslimit von 1 Ebene.

## Input erkennen

Analysiere `$ARGUMENTS`:

1. **Dateipfade angegeben** → Sammle alle referenzierten Dateien
2. **@mentions verwendet** → Lese die referenzierten Dateien
3. **Glob-Pattern** (z.B. `*.md`) → Suche passende Dateien
4. **Keine Argumente** → Frage: "Bitte Dateipfade oder @mentions angeben fuer die zu fusionierenden Dokumente."

## Edge Cases (vor Pipeline-Start)

- **1 Dokument** → Warnung: "Nur 1 Dokument erkannt. Verwende /tdo:compress fuer Einzeldokument-Kompression." Dann /tdo:compress ausfuehren.
- **>10 Dokumente** → Warnung: "Mehr als 10 Dokumente erkannt. Empfehlung: Fusioniere in 5er-Batches fuer optimale Ergebnisse. Trotzdem fortfahren?"
- **Leere/nicht lesbare Dateien** → Ueberspringe mit Warnung, restliche Dateien verarbeiten.
- **Binaerdateien** → Ueberspringe mit Warnung.

## Pipeline initialisieren

```
1. Erstelle .tdo-pipeline/input/ Verzeichnis
2. Kopiere alle Input-Dokumente nach .tdo-pipeline/input/
3. Erstelle .tdo-pipeline/pipeline-state.json mit Initialwerten
4. Zaehle und benenne Dokumente: D1, D2, D3, ...
```

## 8-Stufen-Pipeline ausfuehren

Folge dem Orchestrierungsprotokoll aus @agents/doc-fusion-orchestrator.md:

### Stage 1 — Parsing
Dispatche `doc-parser-agent` via Agent-Tool:
- Prompt: "Lies alle Dokumente aus .tdo-pipeline/input/ und erstelle strukturierte JSON-Parses in .tdo-pipeline/stage-1-parsed/. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
- Pruefe pipeline-state.json nach Abschluss

### Stage 2 — Deduplizierung
Dispatche `semantic-dedup-agent` via Agent-Tool:
- Prompt: "Lies die geparsten Dokumente aus .tdo-pipeline/stage-1-parsed/ und erstelle einen deduplizierten Content mit [UNIQUE:Dn] Tags in .tdo-pipeline/stage-2-deduped.md. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
- Pruefe pipeline-state.json

### Stage 3 — Widerspruchserkennung
Dispatche `contradiction-detector-agent` via Agent-Tool:
- Prompt: "Lies den deduplizierten Content aus .tdo-pipeline/stage-2-deduped.md und die Originale aus .tdo-pipeline/stage-1-parsed/. Erstelle einen vollstaendigen Widerspruchsbericht in .tdo-pipeline/stage-3-contradictions.md. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
- Pruefe pipeline-state.json

### Stage 4 — Graph Merging
Dispatche `graph-merger-agent` via Agent-Tool:
- Prompt: "Lies den deduplizierten Content (.tdo-pipeline/stage-2-deduped.md) und den Widerspruchsbericht (.tdo-pipeline/stage-3-contradictions.md). Fuehre Graph-of-Thoughts Merging und TDO-Kompression (--pipeline Modus) durch. Schreibe nach .tdo-pipeline/stage-4-merged.md und .tdo-pipeline/protected-registry.json. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
- Pruefe pipeline-state.json

### Stage 5 — Architektur
Dispatche `doc-architect-agent` via Agent-Tool:
- Prompt: "Lies den fusionierten Content (.tdo-pipeline/stage-4-merged.md) und den Widerspruchsbericht (.tdo-pipeline/stage-3-contradictions.md). Erstelle einen detaillierten Blueprint in .tdo-pipeline/stage-5-blueprint.md. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
- Pruefe pipeline-state.json

### Stage 6 — Kohaerenz
Dispatche `coherence-agent` via Agent-Tool:
- Prompt: "Lies den fusionierten Content (.tdo-pipeline/stage-4-merged.md) und den Blueprint (.tdo-pipeline/stage-5-blueprint.md). Erstelle ein kohaerentes Dokument in .tdo-pipeline/stage-6-coherent.md. Nutze auch stage-2-deduped.md und protected-registry.json. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
- Pruefe pipeline-state.json

### Stage 7 — Verifikation
Dispatche `verification-agent` via Agent-Tool:
- Prompt: "Lies das kohaerente Dokument (.tdo-pipeline/stage-6-coherent.md) und verifiziere es gegen alle Originale (.tdo-pipeline/stage-1-parsed/*.json) und die Protected Registry (.tdo-pipeline/protected-registry.json). Fuehre alle 5 Gates, CoVe-Check und Self-Consistency-Check durch. Schreibe nach .tdo-pipeline/stage-7-verification.md. Wende notwendige Patches direkt an. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
- Pruefe pipeline-state.json

### Stage 8a — Document Cleaning
Dispatche `doc-cleaner-agent` via Agent-Tool:
- Prompt: "Lies das verifizierte Dokument (.tdo-pipeline/stage-6-coherent.md) und den Verifikationsbericht (.tdo-pipeline/stage-7-verification.md). Erstelle ein reines, professionelles Dokument mit Kontexttitel, Executive Summary und TOC in .tdo-pipeline/[kontexttitel].md. Bereinige alle Pipeline-Tags. Schreibe den Kontexttitel in pipeline-state.json. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
- Pruefe pipeline-state.json

### Stage 8b — Report & Metrics
Dispatche `doc-reporter-agent` via Agent-Tool:
- Prompt: "Lies das reine Dokument (Pfad aus pipeline-state.json → kontexttitel), den Verifikationsbericht und alle Pipeline-Artefakte. Erstelle stage-8-final.md (Dokument + Metriken) und stage-8-report.md (Pipeline-Report mit Source Coverage, Widerspruchsindex, Checkliste). Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
- Pruefe pipeline-state.json

## Error Recovery (nach jeder Stage)

Nach jeder Stage, pruefe pipeline-state.json. Details siehe @skills/fuse-docs/references/error-recovery.md

```
IF status == "OK":     → Naechste Stage dispatchen
ELIF status == "FAIL": → Error Recovery anwenden (max 3 Retries)
```

## Finales Ergebnis ausgeben

Nach Stage 8b (status: COMPLETE):

1. Lies `kontexttitel` aus `.tdo-pipeline/pipeline-state.json`
2. Teile dem User mit:
   - Reines Dokument: `.tdo-pipeline/[kontexttitel].md`
   - Pipeline-Output mit Metriken: `.tdo-pipeline/stage-8-final.md`
   - Pipeline-Report: `.tdo-pipeline/stage-8-report.md`
3. Gib NICHT den Dokumentinhalt im Chat aus — nur die Dateipfade
4. Frage: "Pipeline-Artefakte in .tdo-pipeline/ beibehalten oder loeschen?"

## Monitoring-Output

Gib nach jeder Stage ein Status-Update aus:

```
=== TDO v11.2.2 Document Fusion Pipeline ===
Dokumente: [N]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[✅] Stage 1:  Parsing         — [Status]
[✅] Stage 2:  Dedup           — [Status]
[🔄] Stage 3:  Contradictions  — in progress...
[⏳] Stage 4-7                 — pending
[⏳] Stage 8a: Cleaning        — pending
[⏳] Stage 8b: Report          — pending
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
