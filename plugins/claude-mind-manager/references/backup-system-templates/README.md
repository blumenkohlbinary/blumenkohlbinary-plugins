# Backup-System Templates

Templates fuer ein **plugin-unabhaengiges** Projekt-internes Backup-System.
Installiert von `claude-mind-manager` (mind-files Skill) ins Projekt.

Adaptiert aus der Zustellplan-App (`C:\CD\KOHLEKTIV\APP - Zustellplan`), generisch
fuer beliebige Projekte. Nach Installation **kein Plugin-Bezug mehr** — Tools
laufen autonom im Projekt.

## Files (werden ins Projekt installiert)

| Datei | Patterns | Zweck |
|---|---|---|
| `tools/backup_tools.py` | GFS-Retention + SHA-256-Manifest | Backups verwalten/verifizieren |
| `tools/rollback.py` | Pre-Restore-Snapshot + Restore | Backups zurueckspielen |
| `tools/mutation_guard.py` | Fingerprint + Symlink-Schutz + Test-Gate | Pre-Mutation-Safety |
| `tools/update_changelog.py` | Conventional-Commits -> CHANGELOG.md | Auto-Changelog |
| `docs/BACKUP_USAGE.md` | User-Doku | Wie verwenden? |
| `.backupignore` | Default-Excludes | node_modules, __pycache__, etc. |
| `.backuprc` | Test-Cmd + GFS-Overrides | Projekt-spezifische Defaults |

## Installations-Layout im Projekt

```
<projekt>/
├── tools/
│   ├── backup_tools.py
│   ├── rollback.py
│   ├── mutation_guard.py
│   └── update_changelog.py
├── docs/
│   └── BACKUP_USAGE.md
├── .backupignore                  # Default Patterns (von mind-files generiert)
├── .backuprc                      # BACKUP_TEST_CMD etc. (projekt-spezifisch)
└── .claude-mind/
    └── backups/                   # Backup-Snapshots (mit Timestamps)
        ├── 20260530_143245_pre-edit-claude-md/
        │   ├── CLAUDE.md
        │   └── MANIFEST.sha256
        └── 20260530_144501_pre-rollback-from-20260530_140000/
            ├── ...
```

## Wichtig

- **Plugin-unabhaengig:** Tools brauchen Python, KEIN claude-mind-manager Plugin
- **Generisch:** Keine projekt-spezifischen Hardcodes
- **Env-Vars optional:** `BACKUP_TARGET`, `BACKUP_TEST_CMD`, `BACKUP_TEST_TIMEOUT`
- **Sicher per Default:** GFS dry-run by default, test-gate skipped wenn cmd leer

## Adaption-Notes (Zustellplan -> generisch)

| Original | Generic |
|---|---|
| `UNSTABLE = ROOT / "dist" / "unstable"` | `$BACKUP_TARGET` env-var (default `.claude-mind/backups/`) |
| `Zustellplan.exe` hardcoded | KEIN Hardcode — Tools arbeiten mit beliebigen Files |
| `pytest` hardcoded in `run_tests_or_abort` | `$BACKUP_TEST_CMD` (default leer = skip), `.backuprc` per Tech-Stack |
| `__init__.py` Coupled-File Logic | nicht uebernommen — projekt-spezifisch |

## Mind-Files Installer-Verhalten

`/mind-files` schlaegt das Backup-System in jedem Projekt vor (User-Direktive H).
Bei User-OK:
1. Templates aus `references/backup-system-templates/` ins Projekt schreiben
2. `.backuprc` generieren mit project-scanner-Detection (`pytest`/`npm test`/etc.)
3. `.backupignore` generieren mit Standard-Defaults
4. `mkdir -p .claude-mind/backups/`
5. User-Hinweis: "Backup-System installiert — Doku in `docs/BACKUP_USAGE.md`"
