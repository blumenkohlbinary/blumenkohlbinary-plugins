---
name: doc-fusion-orchestrator
description: "Protokoll-Referenz fuer 8-stufige Multi-Dokument-Fusion. Wird via @-Include vom /fuse-docs Skill geladen."
model: opus
tools: Read, Write, Glob, Grep
maxTurns: 50
skills:
  - text-density-optimizer
disallowedTools: Agent
permissionMode: acceptEdits
color: cyan
---

# Document Fusion Orchestrator — Protokoll-Referenz

Dieses Dokument enthaelt das vollstaendige 8-Stufen-Orchestrierungs-Protokoll fuer die Multi-Dokument-Fusion. Es wird vom `/tdo:fuse-docs` Skill via `@`-Include in die Hauptkonversation eingebettet.

**WICHTIG:** Die Orchestrierung laeuft in der Hauptkonversation (Tiefe 0). Sub-Agents werden bei Tiefe 1 dispatcht. Der Orchestrator selbst ist KEINE Sub-Agent-Instanz, sondern ein Protokoll-Dokument.

## Architektur-Uebersicht

```
Hauptkonversation (Tiefe 0)
  │ Orchestrierungsprotokoll (dieses Dokument)
  │
  ├→ Stage 1:  doc-parser-agent        (Tiefe 1, sonnet)
  ├→ Stage 2:  semantic-dedup-agent     (Tiefe 1, sonnet)
  ├→ Stage 3:  contradiction-detector   (Tiefe 1, opus)
  ├→ Stage 4:  graph-merger-agent       (Tiefe 1, sonnet)
  ├→ Stage 5:  doc-architect-agent      (Tiefe 1, sonnet)
  ├→ Stage 6:  coherence-agent          (Tiefe 1, sonnet)
  ├→ Stage 7:  verification-agent       (Tiefe 1, opus)
  ├→ Stage 8a: doc-cleaner-agent        (Tiefe 1, sonnet)
  └→ Stage 8b: doc-reporter-agent       (Tiefe 1, sonnet)
```

## Pipeline-Verzeichnis initialisieren

Vor Stage 1, erstelle die Pipeline-Struktur:

```
.tdo-pipeline/
├── input/              ← Quelldokumente hierhin kopieren
├── stage-1-parsed/     ← wird von doc-parser-agent gefuellt
├── pipeline-state.json ← Status-Tracking
```

### Initiale pipeline-state.json

```json
{
  "current_stage": 0,
  "status": "INITIALIZED",
  "documents": [],
  "start_time": "[ISO-Timestamp]",
  "attempts": {}
}
```

## 8-Stufen-Dispatch-Protokoll

### Vor JEDER Stufe: Re-Anchoring

1. Lies `.tdo-pipeline/pipeline-state.json`
2. Pruefe: Vorherige Stufe abgeschlossen? Status OK?
3. Falls FAIL: Error Recovery anwenden (siehe @skills/fuse-docs/references/error-recovery.md)
4. Falls OK: Naechste Stufe dispatchen

---

### Stage 1 — Document Parser
**Agent:** `doc-parser-agent` (sonnet, maxTurns: 10)
**Prompt:** "Lies alle Dokumente aus .tdo-pipeline/input/ und erstelle strukturierte JSON-Parses in .tdo-pipeline/stage-1-parsed/. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
**Output:** `.tdo-pipeline/stage-1-parsed/doc-N.json`

### Stage 2 — Semantic Dedup
**Agent:** `semantic-dedup-agent` (sonnet, maxTurns: 15)
**Prompt:** "Lies die geparsten Dokumente aus .tdo-pipeline/stage-1-parsed/ und erstelle einen deduplizierten Content mit [UNIQUE:Dn] Tags in .tdo-pipeline/stage-2-deduped.md. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
**Output:** `.tdo-pipeline/stage-2-deduped.md`

### Stage 3 — Contradiction Detection
**Agent:** `contradiction-detector-agent` (opus, maxTurns: 15)
**Prompt:** "Lies den deduplizierten Content aus .tdo-pipeline/stage-2-deduped.md und die Originale aus .tdo-pipeline/stage-1-parsed/. Erstelle einen vollstaendigen Widerspruchsbericht in .tdo-pipeline/stage-3-contradictions.md. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
**Output:** `.tdo-pipeline/stage-3-contradictions.md`

### Stage 4 — Graph Merger
**Agent:** `graph-merger-agent` (sonnet, maxTurns: 20)
**Prompt:** "Lies den deduplizierten Content (.tdo-pipeline/stage-2-deduped.md) und den Widerspruchsbericht (.tdo-pipeline/stage-3-contradictions.md). Fuehre Graph-of-Thoughts Merging und TDO-Kompression (--pipeline Modus) durch. Schreibe nach .tdo-pipeline/stage-4-merged.md und .tdo-pipeline/protected-registry.json. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
**Output:** `stage-4-merged.md` + `protected-registry.json`

### Stage 5 — Document Architecture
**Agent:** `doc-architect-agent` (sonnet, maxTurns: 10)
**Prompt:** "Lies den fusionierten Content (.tdo-pipeline/stage-4-merged.md) und den Widerspruchsbericht (.tdo-pipeline/stage-3-contradictions.md). Erstelle einen detaillierten Blueprint in .tdo-pipeline/stage-5-blueprint.md. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
**Output:** `.tdo-pipeline/stage-5-blueprint.md`

### Stage 6 — Coherence
**Agent:** `coherence-agent` (sonnet, maxTurns: 15)
**Prompt:** "Lies den fusionierten Content (.tdo-pipeline/stage-4-merged.md) und den Blueprint (.tdo-pipeline/stage-5-blueprint.md). Erstelle ein kohaerentes Dokument in .tdo-pipeline/stage-6-coherent.md. Nutze auch stage-2-deduped.md und protected-registry.json. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
**Output:** `.tdo-pipeline/stage-6-coherent.md`

### Stage 7 — Verification
**Agent:** `verification-agent` (opus, maxTurns: 20)
**Prompt:** "Lies das kohaerente Dokument (.tdo-pipeline/stage-6-coherent.md) und verifiziere es gegen alle Originale (.tdo-pipeline/stage-1-parsed/*.json) und die Protected Registry (.tdo-pipeline/protected-registry.json). Fuehre alle 5 Gates, CoVe-Check und Self-Consistency-Check durch. Schreibe nach .tdo-pipeline/stage-7-verification.md. Wende notwendige Patches direkt an. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
**Output:** `.tdo-pipeline/stage-7-verification.md`

### Stage 8a — Document Cleaning
**Agent:** `doc-cleaner-agent` (sonnet, maxTurns: 10)
**Prompt:** "Lies das verifizierte Dokument (.tdo-pipeline/stage-6-coherent.md) und den Verifikationsbericht (.tdo-pipeline/stage-7-verification.md). Erstelle ein reines, professionelles Dokument mit Kontexttitel, Executive Summary und TOC in .tdo-pipeline/[kontexttitel].md. Bereinige alle Pipeline-Tags. Schreibe den Kontexttitel in pipeline-state.json. Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
**Output:** `.tdo-pipeline/[kontexttitel].md`

### Stage 8b — Report & Metrics
**Agent:** `doc-reporter-agent` (sonnet, maxTurns: 10)
**Prompt:** "Lies das reine Dokument (Pfad aus pipeline-state.json → kontexttitel), den Verifikationsbericht und alle Pipeline-Artefakte. Erstelle stage-8-final.md (Dokument + Metriken) und stage-8-report.md (Pipeline-Report mit Source Coverage, Widerspruchsindex, Checkliste). Befolge dein Agent-Protokoll vollstaendig. Gib nur eine kurze Statusmeldung zurueck."
**Output:** `stage-8-final.md` + `stage-8-report.md`

---

## Error Recovery

Siehe @skills/fuse-docs/references/error-recovery.md fuer vollstaendige Error Recovery Logik, Severity-basierte Recovery, Retry-Logik und Recovery-Aktionen pro Stage.

## Standalone-Nutzung

Dieser Agent kann auch standalone aufgerufen werden (ohne /tdo:fuse-docs Skill). In diesem Fall:
- Laeuft in der Hauptkonversation
- Kann KEINE Sub-Agents dispatchen (weil er selbst bei Tiefe 1 ist)
- Fuehrt alle 8 Stufen INTERN aus (ohne Agent-Tool)
- Geeignet fuer kleinere Fusionen (2-3 kurze Dokumente)

## Monitoring-Output

```
=== TDO v11.2.2 Document Fusion Pipeline ===
Dokumente: [N]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[✅] Stage 1:  Parsing         — [N] docs, [N] sections
[✅] Stage 2:  Dedup           — [N] duplicates, [N] unique
[✅] Stage 3:  Contradictions  — B1:[N] B2:[N] B3:[N]
[🔄] Stage 4:  Merging         — in progress...
[⏳] Stage 5-7                 — pending
[⏳] Stage 8a: Cleaning        — pending
[⏳] Stage 8b: Report          — pending
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
