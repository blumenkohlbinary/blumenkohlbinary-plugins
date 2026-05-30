# Backup-System — Verwendungs-Doku

Installiert von **claude-mind-manager** (mind-files Skill). Nach Installation
plugin-unabhaengig — laeuft autonom in diesem Projekt.

## Quick Start

```bash
# 1. Backup erstellen (manuell, beliebiges Verzeichnis)
cp -r CLAUDE.md .claude-mind/backups/$(date +%Y%m%d_%H%M%S)_pre-edit/

# 2. Manifest erzeugen (SHA-256 Hashes aller Files im Backup)
python tools/backup_tools.py manifest .claude-mind/backups/<timestamp>_pre-edit/

# 3. Spaeter: verifizieren ob Backup intakt ist
python tools/backup_tools.py verify .claude-mind/backups/<timestamp>_pre-edit/

# 4. Restore (mit automatischem Pre-Rollback-Snapshot)
python tools/rollback.py list                          # alle Snapshots
python tools/rollback.py restore <snapshot-name>       # restore all files
python tools/rollback.py restore <snapshot-name> CLAUDE.md --dry-run  # nur ein File, trocken
```

## Tool-Uebersicht

### `tools/backup_tools.py` — Manifest + GFS-Retention

| Command | Zweck |
|---|---|
| `manifest <dir>` | SHA-256-Manifest erzeugen |
| `verify <dir>` | Backup gegen Manifest pruefen |
| `verify-all <root>` | Alle Backups in Root pruefen |
| `gfs <root>` | GFS-Retention DRY-RUN (default) |
| `gfs <root> --apply` | GFS-Retention AUSFUEHREN |
| `gfs <root> --apply --keep-daily 14 --keep-weekly 8 --keep-monthly 24` | Custom Retention |

**GFS-Default:** 7 daily / 4 weekly / 12 monthly. Aelteste Backups werden geloescht.
Verzeichnis-Namen mit Prefix `YYYYMMDD_HHMMSS_*` werden erkannt.

### `tools/rollback.py` — Snapshot-Restore

| Command | Zweck |
|---|---|
| `list` | Alle Snapshots listen (mit Mtime, File-Count, Size) |
| `info <snapshot>` | Inhalt eines Snapshots |
| `restore <snapshot>` | Alle Files aus Snapshot zurueckspielen (mit Pre-Rollback-Backup) |
| `restore <snapshot> <path>` | Nur 1 File/Dir restoren |
| `restore <snapshot> --dry-run` | Zeigt was passieren wuerde |

**Pre-Rollback-Pattern:** Vor jedem Restore wird der **aktuelle** Stand der zu
restorenden Files als neuer Snapshot gesichert (Pattern aus Zustellplan-App).
So kannst du jeden Rollback selbst rueckgaengig machen.

### `tools/mutation_guard.py` — Pre-Mutation Safety

| Command | Zweck |
|---|---|
| `fingerprint <path>` | SHA-256-Liste aller Files (Vorher/Nachher-Vergleich) |
| `check-symlinks <path>` | Findet Symlinks (TOCTOU-Schutz) |
| `test-gate` | Fuehrt `$BACKUP_TEST_CMD` aus |
| `guarded-op <path>` | Komplett-Check: Symlinks + Fingerprint + Test-Gate |

**Use-Case:** Vor riskanten Operationen (z.B. Massen-Edit von Source-Files):

```bash
# 1. Backup + Fingerprint VOR Mutation
cp -r src/ .claude-mind/backups/$(date +%Y%m%d_%H%M%S)_pre-mass-edit/src/
python tools/mutation_guard.py fingerprint src/ > /tmp/fp_before.json

# 2. Mutation durchfuehren (z.B. Refactoring)
... refactoring commands ...

# 3. Fingerprint NACH Mutation + Diff
python tools/mutation_guard.py fingerprint src/ > /tmp/fp_after.json
diff /tmp/fp_before.json /tmp/fp_after.json
```

**Test-Gate Pattern:** In `.backuprc` setzen:
```bash
export BACKUP_TEST_CMD="pytest -q"       # Python-Projekt
export BACKUP_TEST_CMD="npm test"         # Node-Projekt
export BACKUP_TEST_CMD="cargo test"       # Rust-Projekt
export BACKUP_TEST_TIMEOUT=600            # 10 min (default 300)
```

Dann vor riskanten Operationen:
```bash
source .backuprc
python tools/mutation_guard.py test-gate  # exit 0 = OK
```

### `tools/update_changelog.py` — Auto-CHANGELOG

| Command | Zweck |
|---|---|
| `update_changelog.py` | Schreibt `CHANGELOG.md` aus Conventional-Commits |
| `--print` | Druckt nach stdout statt File |
| `--since v1.0.0` | Nur seit Tag X |
| `--output FILE` | Custom output-Pfad |

**Conventional-Commits-Pattern:** `<type>(<scope>)!: <subject>`

Erkannte Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`,
`chore`, `style`, `revert`, `release`.

Generierte Sections: Features, Bug Fixes, Performance, Refactoring, etc.
Breaking-Changes (mit `!` oder `BREAKING CHANGE:` im body) immer oben.

## Konfiguration via Env-Vars

| Variable | Default | Zweck |
|---|---|---|
| `BACKUP_TARGET` | `.claude-mind/backups/` | Wohin Backups (relativ zu CWD) |
| `BACKUP_TEST_CMD` | leer | Shell-Cmd fuer Test-Gate (leer = skip) |
| `BACKUP_TEST_TIMEOUT` | `300` | Test-Cmd Timeout in Sekunden |

Persistente Defaults in **`.backuprc`** (im Projekt-Root):
```bash
# .backuprc - automatisch generiert von claude-mind-manager
export BACKUP_TEST_CMD="pytest -q"      # je nach Projekt-Typ
export BACKUP_TARGET=".claude-mind/backups"
```

`source .backuprc` vor Tool-Aufrufen, oder in `.bashrc`/`.zshrc`/`fish_config`.

## Integration mit `.backupignore`

Aehnlich `.gitignore` — wird **noch nicht** automatisch von `backup_tools.py`
gelesen (TODO future). Aktuell nur Dokumentation:

```
# .backupignore - Files die NICHT in Backups landen sollen
node_modules/
__pycache__/
.venv/
.git/
dist/
build/
*.pyc
.DS_Store
```

Wenn du Backups manuell mit `cp -r` machst: nutze `rsync --exclude-from=.backupignore`.

## Voraussetzungen

- **Python 3.8+** (alle Tools)
- **Git** (nur `update_changelog.py`)
- KEIN externes Package — nur stdlib (`hashlib`, `pathlib`, `subprocess`, etc.)

## Wenn etwas nicht funktioniert

1. `python tools/backup_tools.py --help` — Zeigt CLI-Optionen
2. Tools laufen mit `python3` ODER `python` — beides probieren
3. Bei `Permission denied`: pruefe ob `BACKUP_TARGET` schreibbar ist
4. Bei `FileNotFoundError`: pruefe ob `.claude-mind/backups/` existiert (`mkdir -p`)

## Updates

Dieses Backup-System wurde von **claude-mind-manager v3.3.0** installiert.
Bei Update des Plugins kann es passieren dass neue Versionen der Tools angeboten werden.
`/mind-files` erkennt `__version__` Strings in den Tools und fragt ob auf neue Version
geupdatet werden soll.

**Wenn du Tools manuell veraendert hast:** Updates ablehnen, sonst gehen Anpassungen verloren.
