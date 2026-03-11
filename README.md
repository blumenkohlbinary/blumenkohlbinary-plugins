# blumenkohlbinary-plugins — Claude Code Plugin Marketplace

Personal plugin marketplace for Claude Code.

## Plugins

### TDO v11.2 — Text Density Optimizer

Verlustfreie Dokumentkompression und Multi-Dokument-Fusion.

**Features:**
- `/tdo:compress` — Einzeldokument-Kompression (45-55%, verlustfrei)
- `/tdo:fuse-docs` — Multi-Dokument-Fusion mit 8-Stufen-Pipeline

**Architektur:**
- 5 Skills (text-density-optimizer, compress, fuse-docs, dare-text-merger, cove-verifier)
- 9 Agents (8 Pipeline-Stufen + 1 Orchestrator)
- Modelle: 2x Opus (Contradiction + Verification), 4x Sonnet, 2x Haiku
- Flache Orchestrierung (Nesting-Tiefe 1)
- Dateibasierte Kommunikation via `.tdo-pipeline/`

**Qualitaetssicherung:**
- 5-Gate-Verifikation (Faktisch, Strukturell, Qualitaet, Source Coverage, Reconstruction)
- Chain-of-Verification (CoVe) Fact-Check
- Self-Consistency-Check (3 Versionen, 20+ Fakten)
- Protected Registry (Zahlen, Daten, Zitate zeichenidentisch)
- UNIQUE-Tag Schutz fuer dokumentspezifische Inhalte
- Konflikt-Hierarchie: Datum > Autoritaet > Spezifizitaet > Konsens

## Installation

```bash
# 1. Marketplace registrieren
/plugin marketplace add https://github.com/blumenkohlbinary/blumenkohlbinary-plugins.git

# 2. TDO Plugin installieren
/plugin install tdo@blumenkohlbinary-plugins
```

Danach in **Anpassen** > **Plugins** aktivieren/deaktivieren.

## Nutzung

```
/tdo:compress @dokument.md
/tdo:fuse-docs @doc1.md @doc2.md @doc3.md
```

## Lizenz

MIT
