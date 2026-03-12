# TDO v11.2.2 — Text Density Optimizer Plugin

## Uebersicht

| Feature | Beschreibung |
|---------|-------------|
| Kompression | Dynamisch verlustfrei, waste-basiert |
| Fusion | 8-Stufen Multi-Agent Pipeline (9 Stages) |
| Verifikation | 5 Gates + CoVe + Self-Consistency |
| Modelle | 2x Opus, 7x Sonnet |

## Commands

| Command | Beschreibung |
|---------|-------------|
| `/tdo:compress` | Einzeldokument-Kompression (dynamisch, verlustfrei) |
| `/tdo:fuse-docs` | Multi-Dokument-Fusion (8-Stufen-Pipeline) |

## Pipeline-Stufen

1. **Parser** (sonnet) — Strukturextraktion aus Dokumenten in JSON
2. **Dedup** (sonnet) — Woertliche + semantische Deduplizierung, UNIQUE-Tagging
3. **Contradiction** (opus) — 6-Typ NLI-Widerspruchserkennung
4. **Merger** (sonnet) — Graph-of-Thoughts + DARE-Text + TDO-Kompression
5. **Architect** (sonnet) — Blueprint-Erstellung, Order Type Detection, Abschnitts-Autonomie
6. **Coherence** (sonnet) — Patchwork-Eliminierung, Ton-Harmonisierung, Blog-Formatierung
7. **Verification** (opus) — 5 Gates + CoVe + Self-Consistency
8a. **Cleaner** (sonnet) — Reines Dokument mit Kontexttitel, Executive Summary, TOC
8b. **Reporter** (sonnet) — Metriken, Source Coverage, Checkliste, Pipeline-Report

## Skills (5)

| Skill | Typ | Beschreibung |
|-------|-----|-------------|
| compress | User-facing | Einzeldokument-Kompression |
| fuse-docs | User-facing | Multi-Dokument-Fusion mit Orchestrierung |
| text-density-optimizer | Intern | 6-Stufen Compression Engine (CoD, Protected Registry) |
| dare-text-merger | Intern | DARE-Text Fusion (BASE + DELTAS + Reskalierung) |
| cove-verifier | Intern | Chain-of-Verification Fact-Check |

## Agents (10)

Alle Agents haben:
- `permissionMode: acceptEdits` — Keine Permission-Prompts
- `disallowedTools: Agent` — Kein Sub-Agent-Spawning
- `color` — Visuelle Identifikation

| Agent | Model | Color | Stufe |
|-------|-------|-------|-------|
| doc-parser-agent | sonnet | cyan | 1 |
| semantic-dedup-agent | sonnet | blue | 2 |
| contradiction-detector-agent | opus | red | 3 |
| graph-merger-agent | sonnet | green | 4 |
| doc-architect-agent | sonnet | magenta | 5 |
| coherence-agent | sonnet | blue | 6 |
| verification-agent | opus | yellow | 7 |
| doc-cleaner-agent | sonnet | green | 8a |
| doc-reporter-agent | sonnet | green | 8b |
| doc-fusion-orchestrator | opus | cyan | Protokoll |

## Output

- `[kontexttitel].md` — Reines Enddokument (Blog-Stil, ohne Tags, ohne Metriken)
- `stage-8-final.md` — Enddokument mit Kompressionsmetriken
- `stage-8-report.md` — Pipeline-Report (Source Coverage, Widerspruchsindex, Metriken, Checkliste)

## Version

v11.2.2 (2026-03-12)
