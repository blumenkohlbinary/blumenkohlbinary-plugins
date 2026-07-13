---
description: Projekt-Backup-System nutzen vor riskanten Datei-Operationen (tools/backup_tools.py + rollback.py)
globs: ["**/*"]
---

# Backup-System dieses Projekts nutzen

Dieses Projekt hat ein installiertes Backup-System unter `tools/` (von claude-mind-manager
installiert). **Nutze es** — es liegt nicht zur Zierde da.

## Wann (Trigger)

VOR jeder riskanten Operation an Projekt-eigenen Dateien:
- Löschen / Überschreiben / Verschieben mehrerer Dateien
- Mass-Edit / Refactoring über viele Files
- vor einer Migration die Datenformate ändert

## Wie

```bash
# 1. Snapshot des betroffenen Verzeichnisses (Timestamp-Prefix) + Integritäts-Manifest
cp -r <dir> ".claude-mind/backups/$(date +%Y%m%d_%H%M%S)_pre-<was>/"
python tools/backup_tools.py manifest ".claude-mind/backups/<snapshot>"

# 2. Später verifizieren dass ein Backup intakt ist
python tools/backup_tools.py verify ".claude-mind/backups/<snapshot>"

# 3. Restore (macht automatisch Pre-Rollback-Snapshot des aktuellen Stands)
python tools/rollback.py list
python tools/rollback.py restore <snapshot-name>

# 4. Alte Backups aufräumen — GFS-Retention, DEFAULT dry-run
python tools/backup_tools.py gfs .claude-mind/backups            # zeigt Plan
python tools/backup_tools.py gfs .claude-mind/backups --apply    # führt aus
```

## Regeln

- GFS-Cleanup ist **default `--dry-run`** — Löschen NUR mit `--apply`.
- Vor jedem `restore` macht `rollback.py` einen **Pre-Rollback-Snapshot** → du kannst jeden Rollback rückgängig machen.
- Details: `docs/BACKUP_USAGE.md`.

## Zwei Backup-Schichten — kein Widerspruch

Es gibt ZWEI Ebenen, die sich **ergänzen**:
- **Global** (`~/.claude/rules/backup-before-delete.md`, falls vorhanden): ad-hoc Sicherheitsnetz,
  das Claude vor Löschungen ganz allgemein nach `C:\CD\KOHLEKTIV\_claude_backups\{ts}\` sichert.
- **Projekt-lokal (dieses Tool):** strukturiertes System für die **Projekt-eigenen** Dateien —
  GFS-Retention + SHA-256-Integritäts-Manifest + Rollback, nach `.claude-mind/backups/`.

Beide dürfen greifen. Die globale Regel ersetzt NICHT die Integritäts-/Rollback-Fähigkeit dieses Tools.
