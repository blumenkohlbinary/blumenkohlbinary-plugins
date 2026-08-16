---
description: Projekt-Backup-System nutzen vor riskanten Datei-Operationen (tools/backup_tools.py + tools/rollback.py + tools/mutation_guard.py)
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

## `tools/mutation_guard.py` — Sicherheits-Checks VOR der Mutation

Ergänzt die Backups um drei Prüfungen, die *vor* dem Eingriff laufen. Nutze sie, wenn ein
Schritt fremde Daten anfassen könnte oder über Symlinks laufen kann:

```bash
# 1. Fingerabdruck vor/nach der Mutation — erkennt, ob ein LAUFENDES Programm dazwischenschreibt
python tools/mutation_guard.py fingerprint <pfad> > /tmp/fp_before.json
#   ... Mutation ...
python tools/mutation_guard.py fingerprint <pfad> > /tmp/fp_after.json

# 2. Symlink-Pruefung — verhindert, dass cp/mv ueber einen Symlink aus dem Projekt herausschreibt
python tools/mutation_guard.py check-symlinks <pfad>

# 3. Test-Gate — fuehrt BACKUP_TEST_CMD aus, exit 0 = weitermachen erlaubt
python tools/mutation_guard.py test-gate
```

⚠ **`test-gate` startet `BACKUP_TEST_CMD` mit `shell=True`** (bewusst, damit Pipes und `&&` im
Kommando funktionieren). Das heißt: **`.backuprc` ist ausführbarer Code.** Nie eine `.backuprc`
aus fremder Quelle übernehmen, ohne sie gelesen zu haben. Ist `BACKUP_TEST_CMD` leer, wird das
Gate übersprungen — der Normalfall in Projekten ohne Tests.

> **Warum dieser Abschnitt existiert:** Bis v5.2.1 installierte der Backup-Installer drei Tools,
> aber diese Rule beschrieb nur zwei. `mutation_guard.py` war installiert, in
> `docs/BACKUP_USAGE.md` dokumentiert — und trotzdem **nicht glob-getriggert erreichbar**, also
> genau das „tote Tool", das die Kern-Invariante des Plugins verbietet. Aufgefallen erst, als
> `mind_check_tools_have_rules()` in v5.2.2 genau genug wurde, um es zu sehen.

## Zwei Backup-Schichten — kein Widerspruch

Es gibt ZWEI Ebenen, die sich **ergänzen**:
- **Global** (`~/.claude/rules/backup-before-delete.md`, falls vorhanden): ad-hoc Sicherheitsnetz,
  das Claude vor Löschungen ganz allgemein nach `C:\CD\KOHLEKTIV\_claude_backups\{ts}\` sichert.
- **Projekt-lokal (dieses Tool):** strukturiertes System für die **Projekt-eigenen** Dateien —
  GFS-Retention + SHA-256-Integritäts-Manifest + Rollback, nach `.claude-mind/backups/`.

Beide dürfen greifen. Die globale Regel ersetzt NICHT die Integritäts-/Rollback-Fähigkeit dieses Tools.
