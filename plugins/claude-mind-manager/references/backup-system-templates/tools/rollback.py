#!/usr/bin/env python3
"""rollback.py - Generic Snapshot-Restore mit Pre-Rollback-Safety.

Installiert von claude-mind-manager v3.3.0 (mind-files Skill).
Adaptiert aus Zustellplan-App (rollback.py), generisch fuer beliebige Projekte.

Pattern:
1. List verfuegbare Snapshots in $BACKUP_TARGET (default .claude-mind/backups/)
2. Vor jedem Restore: aktuellen Stand als pre-rollback-Snapshot sichern
3. Restore: Datei(en) aus Snapshot zurueckkopieren

CLI:
    python tools/rollback.py list
        Listet alle verfuegbaren Snapshots

    python tools/rollback.py info <snapshot>
        Zeigt Inhalt eines Snapshots

    python tools/rollback.py restore <snapshot> [<target_path>]
        Restore (default: alle Files aus Snapshot zurueck ins Projekt-Root)
        Mit <target_path>: nur diese Datei/dieses Verzeichnis restoren

    python tools/rollback.py restore <snapshot> --dry-run
        Zeigt was passieren wuerde, ohne zu schreiben

Defaults:
    Backup-Target: $BACKUP_TARGET oder .claude-mind/backups/ (relativ zu CWD)
    Pre-Rollback: <BACKUP_TARGET>/pre-rollback_<timestamp>/

__version__ = 1.0.0
"""
from __future__ import annotations
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

__version__ = "1.0.0"

DEFAULT_TARGET = os.environ.get("BACKUP_TARGET", ".claude-mind/backups")
PROJECT_ROOT = Path.cwd()


def get_backup_root() -> Path:
    """Resolved Backup-Root (absolut)."""
    target = Path(DEFAULT_TARGET)
    if not target.is_absolute():
        target = PROJECT_ROOT / target
    return target.resolve()


def _safe_join(base: Path, untrusted: str) -> Path | None:
    """Safe path-join mit Path-Traversal-Check (Security-Fix CWE-22).

    Verhindert dass untrusted_name aus base ausbricht via '../' oder absolute Pfade.
    Returns None wenn Traversal-Versuch erkannt.
    """
    base = base.resolve()
    joined = (base / untrusted).resolve()
    try:
        joined.relative_to(base)  # raised ValueError wenn ausserhalb base
        return joined
    except ValueError:
        return None


def list_snapshots() -> int:
    """Listet alle Snapshots im Backup-Root."""
    root = get_backup_root()
    if not root.exists():
        print(f"Backup-Root existiert nicht: {root}")
        print(f"Setze $BACKUP_TARGET oder lege das Verzeichnis an.")
        return 1

    snapshots = sorted([p for p in root.iterdir() if p.is_dir()],
                       key=lambda p: p.stat().st_mtime, reverse=True)

    if not snapshots:
        print(f"Keine Snapshots in {root}")
        return 0

    print(f"Verfuegbare Snapshots in {root}:\n")
    for s in snapshots:
        mtime = datetime.fromtimestamp(s.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        # File-Count + Total-Size
        file_count = 0
        total_size = 0
        for r, _, fs in os.walk(s):
            for f in fs:
                fp = Path(r) / f
                try:
                    total_size += fp.stat().st_size
                    file_count += 1
                except OSError:
                    pass
        size_mb = total_size / 1024 / 1024
        print(f"  {s.name}")
        print(f"    Erstellt: {mtime}")
        print(f"    Files:    {file_count} ({size_mb:.1f} MB)")
        # Hinweis auf MANIFEST.sha256
        manifest = s / "MANIFEST.sha256"
        if manifest.exists():
            print(f"    Manifest: vorhanden (verify mit `backup_tools.py verify {s}`)")
        print()

    return 0


def snapshot_info(snapshot_name: str) -> int:
    """Zeigt Details eines Snapshots."""
    root = get_backup_root()
    # Security-Fix CWE-22: Path-Traversal-Check
    snap = _safe_join(root, snapshot_name)
    if snap is None:
        print(f"FEHLER: '{snapshot_name}' ausserhalb Backup-Root", file=sys.stderr)
        return 2
    if not snap.exists() or not snap.is_dir():
        print(f"Snapshot nicht gefunden: {snap}", file=sys.stderr)
        return 1

    print(f"Snapshot: {snap}")
    mtime = datetime.fromtimestamp(snap.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
    print(f"  Erstellt: {mtime}")
    print()
    print("Inhalt:")
    for p in sorted(snap.rglob('*')):
        if p.is_file():
            rel = p.relative_to(snap).as_posix()
            try:
                size = p.stat().st_size
                print(f"  {size:>10} bytes  {rel}")
            except OSError:
                print(f"  {'?':>10}        {rel}")
    return 0


def restore(snapshot_name: str, target_path: str | None = None,
            dry_run: bool = False) -> int:
    """Restore aus Snapshot. Sichert vorher aktuellen Stand."""
    root = get_backup_root()
    # Security-Fix CWE-22: Path-Traversal-Check fuer snapshot_name
    snap = _safe_join(root, snapshot_name)
    if snap is None:
        print(f"FEHLER: snapshot_name '{snapshot_name}' ausserhalb Backup-Root", file=sys.stderr)
        return 2
    if not snap.exists() or not snap.is_dir():
        print(f"Snapshot nicht gefunden: {snap}", file=sys.stderr)
        print(f"Hinweis: `python tools/rollback.py list` zeigt alle Snapshots", file=sys.stderr)
        return 1

    # Pre-Rollback-Backup: aktuellen Stand der zu restorten Files sichern
    pre_ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    pre_dir = root / f"{pre_ts}_pre-rollback-from-{snapshot_name[:40]}"

    files_to_restore = []
    if target_path:
        # Security-Fix CWE-22: Path-Traversal-Check fuer target_path innerhalb snap
        src = _safe_join(snap, target_path)
        if src is None:
            print(f"FEHLER: target_path '{target_path}' ausserhalb Snapshot", file=sys.stderr)
            return 2
        if not src.exists():
            print(f"FEHLER: {target_path} existiert nicht im Snapshot", file=sys.stderr)
            return 2
        files_to_restore.append(target_path)
    else:
        # Alle Files aus Snapshot (außer MANIFEST.sha256)
        for p in snap.rglob('*'):
            if p.is_file() and p.name != "MANIFEST.sha256":
                files_to_restore.append(p.relative_to(snap).as_posix())

    if not files_to_restore:
        print("Nichts zu restoren — Snapshot leer?")
        return 0

    # Pre-Rollback-Sicherung
    if not dry_run:
        pre_dir.mkdir(parents=True, exist_ok=True)
    saved_count = 0
    for rel in files_to_restore:
        current = PROJECT_ROOT / rel
        if current.exists() and current.is_file():
            if not dry_run:
                pre_target = pre_dir / rel
                pre_target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(current, pre_target)
            saved_count += 1

    if not dry_run and saved_count > 0:
        print(f"Pre-Rollback gesichert: {saved_count} files -> {pre_dir.name}")
    elif dry_run:
        print(f"[DRY-RUN] Wuerde {saved_count} aktuelle files sichern -> {pre_dir.name}")

    # Restore aus Snapshot
    restored = 0
    for rel in files_to_restore:
        src = snap / rel
        dst = PROJECT_ROOT / rel
        if dry_run:
            print(f"  [DRY-RUN] {src} -> {dst}")
            restored += 1
            continue
        try:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            restored += 1
        except OSError as e:
            print(f"  FAIL {rel}: {e}", file=sys.stderr)

    # Resilience-Fix: exit-code reflektiert partial failure (war: immer 0)
    failed_count = len(files_to_restore) - restored
    print(f"\n{'[DRY-RUN] ' if dry_run else ''}Restore: {restored}/{len(files_to_restore)} files")

    if not dry_run:
        if failed_count > 0:
            print(f"[PARTIAL] Restore unvollstaendig: {failed_count} Files failed", file=sys.stderr)
            print(f"          Pre-Rollback verfuegbar: {pre_dir.name}")
            return 4  # partial-failure exit code
        print(f"\n[OK] Restore abgeschlossen aus Snapshot: {snapshot_name}")
        print(f"     Pre-Rollback verfuegbar: {pre_dir.name}")
        print(f"     Re-Rollback moeglich via: python tools/rollback.py restore {pre_dir.name}")

    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help", "help"):
        print(__doc__)
        return 0

    cmd = argv[1]

    if cmd == "list":
        return list_snapshots()

    if cmd == "info" and len(argv) >= 3:
        return snapshot_info(argv[2])

    if cmd == "restore" and len(argv) >= 3:
        snapshot = argv[2]
        target = None
        dry_run = "--dry-run" in argv
        # Optional: target_path als 3. Arg (vor --dry-run)
        if len(argv) >= 4 and not argv[3].startswith("--"):
            target = argv[3]
        return restore(snapshot, target, dry_run)

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
