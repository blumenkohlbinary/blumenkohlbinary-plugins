#!/usr/bin/env python3
"""backup_tools.py - Generic Backup-Integritaet + GFS-Retention.

Installiert von claude-mind-manager v3.3.0 (mind-files Skill).
Adaptiert aus Zustellplan-App (backup_tools.py), generisch fuer beliebige Projekte.

Funktionen:
1. write_manifest(backup_dir)       - Erzeugt MANIFEST.sha256 (SHA-256 aller Files)
2. verify_manifest(backup_dir)       - Verifiziert Backup gegen MANIFEST.sha256
3. verify_all(root)                  - Prueft alle Backups in einem Root
4. gfs_cleanup(root, dry_run=True)   - Grandfather-Father-Son-Retention

CLI:
    python tools/backup_tools.py manifest <pfad>           # Manifest erzeugen
    python tools/backup_tools.py verify <pfad>             # 1 Backup pruefen
    python tools/backup_tools.py verify-all <root>         # alle Backups pruefen
    python tools/backup_tools.py gfs <root> [--apply]      # GFS-Cleanup (default dry-run)
    python tools/backup_tools.py gfs <root> --apply --keep-daily 14 --keep-weekly 8 --keep-monthly 24

Defaults:
    Backup-Target: $BACKUP_TARGET oder .claude-mind/backups/ (relativ zu CWD)
    GFS-Retention: 7 daily / 4 weekly / 12 monthly

__version__ = 1.0.0
"""
from __future__ import annotations
import hashlib
import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

__version__ = "1.0.0"

MANIFEST_NAME = "MANIFEST.sha256"
TIMESTAMP_RE = re.compile(r'^(\d{8})_(\d{6})')  # YYYYMMDD_HHMMSS prefix

# Default-Target: env-var oder konventionelles Subdir
DEFAULT_TARGET = os.environ.get("BACKUP_TARGET", ".claude-mind/backups")


# =========================================================================
# SHA-256 Manifest
# =========================================================================

def _sha256_file(path: Path, block_size: int = 65536) -> str:
    """SHA-256 hex-digest einer Datei (block-weise gelesen)."""
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while chunk := f.read(block_size):
            h.update(chunk)
    return h.hexdigest()


def write_manifest(backup_dir: Path) -> dict:
    """Erzeugt MANIFEST.sha256 mit hashes aller Dateien rekursiv.

    Format pro Zeile: '<sha256>  <relativer-pfad>'
    Schliesst MANIFEST.sha256 selbst aus.
    """
    backup_dir = Path(backup_dir).resolve()
    if not backup_dir.exists() or not backup_dir.is_dir():
        raise FileNotFoundError(f"Backup-Verzeichnis fehlt: {backup_dir}")

    manifest_path = backup_dir / MANIFEST_NAME
    entries = []
    skipped = []  # Resilience-Fix: skipped files strukturiert zurueckgeben
    total_bytes = 0
    file_count = 0

    for p in sorted(backup_dir.rglob('*')):
        if not p.is_file():
            continue
        if p.name == MANIFEST_NAME:
            continue
        rel = p.relative_to(backup_dir).as_posix()
        try:
            digest = _sha256_file(p)
            size = p.stat().st_size
        except OSError as e:
            entries.append(f"# SKIPPED  {rel}  (OSError: {e})")
            skipped.append((rel, str(e)))
            continue
        entries.append(f"{digest}  {rel}")
        total_bytes += size
        file_count += 1

    header = [
        f"# Backup-Manifest fuer: {backup_dir}",
        f"# Erzeugt: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"# Dateien: {file_count}",
        f"# Skipped: {len(skipped)}",
        f"# Gesamtgroesse: {total_bytes / 1024 / 1024:.2f} MB",
        f"# Generator: backup_tools.py v{__version__}",
        "# Format: <sha256-hex>  <relativer-pfad>",
        "",
    ]
    manifest_path.write_text("\n".join(header + entries) + "\n", encoding="utf-8")
    return {
        "file_count": file_count,
        "total_bytes": total_bytes,
        "manifest_path": manifest_path,
        "skipped": skipped,
    }


def verify_manifest(backup_dir: Path, verbose: bool = False) -> dict:
    """Verifiziert ein Backup gegen sein MANIFEST.sha256."""
    backup_dir = Path(backup_dir).resolve()
    manifest_path = backup_dir / MANIFEST_NAME
    if not manifest_path.exists():
        return {"no_manifest": True, "backup_dir": backup_dir}

    expected = {}
    for line in manifest_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("  ", 1)
        if len(parts) != 2:
            continue
        digest, rel = parts
        expected[rel] = digest

    verified = []
    missing = []
    mismatched = []  # (rel, expected, actual)

    for rel, exp_digest in expected.items():
        full = backup_dir / rel
        if not full.exists():
            missing.append(rel)
            continue
        try:
            actual = _sha256_file(full)
        except OSError as e:
            mismatched.append((rel, exp_digest, f"OSError: {e}"))
            continue
        if actual != exp_digest:
            mismatched.append((rel, exp_digest, actual))
        else:
            verified.append(rel)

    # Extra-Files: existieren im Verzeichnis, aber nicht im Manifest
    extra = []
    for p in sorted(backup_dir.rglob('*')):
        if not p.is_file() or p.name == MANIFEST_NAME:
            continue
        rel = p.relative_to(backup_dir).as_posix()
        if rel not in expected:
            extra.append(rel)

    if verbose:
        print(f"Backup: {backup_dir}")
        print(f"  Manifest:    {manifest_path}")
        print(f"  Verifiziert: {len(verified)}")
        print(f"  Missing:     {len(missing)}")
        print(f"  Mismatched:  {len(mismatched)}")
        print(f"  Extra:       {len(extra)}")

    return {
        "verified": len(verified),
        "missing": missing,
        "mismatched": mismatched,
        "extra": extra,
        "manifest_path": manifest_path,
    }


def verify_all(root: Path, verbose: bool = True) -> dict:
    """Verifiziert alle Backups in einem Root-Verzeichnis."""
    root = Path(root).resolve()
    if not root.exists():
        return {"total": 0, "ok": 0, "with_issues": 0, "no_manifest": 0}

    total = 0
    ok = 0
    with_issues = 0
    no_manifest_count = 0

    for sub in sorted(root.iterdir()):
        if not sub.is_dir():
            continue
        total += 1
        result = verify_manifest(sub, verbose=False)
        if result.get("no_manifest"):
            no_manifest_count += 1
            if verbose:
                print(f"  NO-MANIFEST  {sub.name}")
            continue
        issues = len(result["missing"]) + len(result["mismatched"])
        if issues == 0:
            ok += 1
            if verbose:
                print(f"  OK           {sub.name}  ({result['verified']} files)")
        else:
            with_issues += 1
            if verbose:
                print(f"  ISSUES ({issues}) {sub.name}  "
                      f"(missing={len(result['missing'])} mismatched={len(result['mismatched'])})")

    return {"total": total, "ok": ok, "with_issues": with_issues,
            "no_manifest": no_manifest_count}


# =========================================================================
# GFS-Retention
# =========================================================================

def _parse_backup_timestamp(name: str) -> datetime | None:
    """Extrahiert Timestamp aus Verzeichnisname (YYYYMMDD_HHMMSS prefix)."""
    m = TIMESTAMP_RE.match(name)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1) + m.group(2), '%Y%m%d%H%M%S')
    except ValueError as e:
        # Resilience-Fix: WARN-Log statt silent skip (sonst orphan-Backups akkumulieren)
        print(f"WARNING: Malformed backup timestamp '{name}': {e} — "
              f"excluded from GFS retention (wird NIE auto-geloescht)", file=sys.stderr)
        return None


def _classify_for_gfs(backups_with_ts, now: datetime,
                     keep_daily: int = 7, keep_weekly: int = 4,
                     keep_monthly: int = 12) -> dict:
    """Klassifiziert Backups nach GFS-Regeln (keep/delete)."""
    keep_set = set()
    reasons = {}

    sorted_desc = sorted(backups_with_ts, key=lambda x: x[1], reverse=True)

    # 1. Tages-Backups
    daily_kept = {}
    for path, ts in sorted_desc:
        day = ts.date()
        if (now.date() - day).days >= keep_daily:
            break
        if day not in daily_kept:
            daily_kept[day] = path
            keep_set.add(path)
            reasons[path] = f"daily ({day})"

    # 2. Wochen-Backups
    weekly_kept = {}
    for path, ts in sorted_desc:
        iso = ts.isocalendar()
        week_key = (iso[0], iso[1])
        weeks_ago = (now.date() - ts.date()).days // 7
        if weeks_ago >= keep_weekly:
            break
        if week_key not in weekly_kept:
            weekly_kept[week_key] = path
            if path not in keep_set:
                keep_set.add(path)
                reasons[path] = f"weekly (KW {iso[1]}/{iso[0]})"

    # 3. Monats-Backups
    monthly_kept = {}
    for path, ts in sorted_desc:
        month_key = (ts.year, ts.month)
        months_ago = (now.year - ts.year) * 12 + (now.month - ts.month)
        if months_ago >= keep_monthly:
            break
        if month_key not in monthly_kept:
            monthly_kept[month_key] = path
            if path not in keep_set:
                keep_set.add(path)
                reasons[path] = f"monthly ({ts.year}-{ts.month:02d})"

    delete = [p for p, _ in backups_with_ts if p not in keep_set]
    return {"keep": list(keep_set), "delete": delete, "reasons": reasons}


def gfs_cleanup(root: Path, dry_run: bool = True,
                keep_daily: int = 7, keep_weekly: int = 4,
                keep_monthly: int = 12) -> dict:
    """Grandfather-Father-Son-Retention auf Backup-Root."""
    root = Path(root).resolve()
    if not root.exists():
        return {"keep": [], "delete": [], "reasons": {},
                "dry_run": dry_run, "freed_bytes": 0, "error": "root not found"}

    backups_with_ts = []
    for sub in root.iterdir():
        if not sub.is_dir():
            continue
        ts = _parse_backup_timestamp(sub.name)
        if ts is not None:
            backups_with_ts.append((sub, ts))

    now = datetime.now()
    classified = _classify_for_gfs(
        backups_with_ts, now, keep_daily, keep_weekly, keep_monthly,
    )

    # Resilience-Fix: freed_bytes nur bei erfolgreichem Delete zaehlen
    # (war Bug: freed += size BEVOR rmtree() — failed deletes wurden faelschlich gezaehlt)
    def _dir_size(p):
        try:
            return sum((Path(r) / f).stat().st_size
                       for r, _, fs in os.walk(p) for f in fs)
        except OSError:
            return 0

    freed = 0
    failed_deletes = []
    for p in classified["delete"]:
        size = _dir_size(p)
        if not dry_run:
            try:
                shutil.rmtree(p)
                freed += size  # nur AFTER success
            except OSError as e:
                failed_deletes.append((p.name, str(e)))
                print(f"  FAIL delete {p.name}: {e}", file=sys.stderr)
        else:
            freed += size  # dry-run: would-free

    classified["dry_run"] = dry_run
    classified["freed_bytes"] = freed
    classified["failed_deletes"] = failed_deletes
    return classified


# =========================================================================
# CLI
# =========================================================================

def _print_help():
    print(__doc__.split('\n\n')[1] if '\n\n' in __doc__ else __doc__)


def _validate_cli_path(user_path: str, must_exist: bool = True) -> Path | None:
    """Security-Check CWE-22 fuer CLI-Path-Args.

    Akzeptiert absolute Pfade (User-Verantwortung) ABER warnt wenn ausserhalb
    BACKUP_TARGET-Root. Verhindert dass User versehentlich z.B. `gfs /etc --apply`
    aufruft und alles loescht.

    Returns Path object oder None bei Validierung-Fehler.
    """
    try:
        resolved = Path(user_path).resolve()
    except (OSError, ValueError) as e:
        print(f"FEHLER: Ungueltiger Pfad '{user_path}': {e}", file=sys.stderr)
        return None

    if must_exist and not resolved.exists():
        print(f"FEHLER: Pfad existiert nicht: {resolved}", file=sys.stderr)
        return None

    # Sanity-Check: WARN wenn Pfad NICHT unter erwartetem Backup-Root liegt
    expected_root = Path(DEFAULT_TARGET)
    if not expected_root.is_absolute():
        expected_root = Path.cwd() / expected_root
    try:
        expected_root = expected_root.resolve()
        resolved.relative_to(expected_root)
        # OK: innerhalb Backup-Root
    except (ValueError, OSError):
        # Ausserhalb — WARN aber nicht blockieren (User kann externe Backup-Dirs haben)
        print(f"WARNING: Pfad ausserhalb $BACKUP_TARGET ({expected_root})", file=sys.stderr)
        print(f"         Operiere trotzdem auf: {resolved}", file=sys.stderr)
        print(f"         (User-Verantwortung — bitte sicherstellen dass das gewollt ist)", file=sys.stderr)

    return resolved


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        _print_help()
        return 1

    cmd = argv[1]

    if cmd in ("-h", "--help", "help"):
        _print_help()
        return 0

    if cmd == "manifest" and len(argv) >= 3:
        validated = _validate_cli_path(argv[2], must_exist=True)
        if validated is None:
            return 4
        result = write_manifest(validated)
        print(f"OK: {result['file_count']} Dateien, "
              f"{result['total_bytes'] / 1024 / 1024:.2f} MB -> {result['manifest_path']}")
        return 0

    if cmd == "verify" and len(argv) >= 3:
        validated = _validate_cli_path(argv[2], must_exist=True)
        if validated is None:
            return 4
        result = verify_manifest(validated, verbose=True)
        if result.get("no_manifest"):
            print(f"FEHLER: kein MANIFEST.sha256 in {argv[2]}", file=sys.stderr)
            return 2
        ok = not (result["missing"] or result["mismatched"])
        return 0 if ok else 3

    if cmd == "verify-all" and len(argv) >= 3:
        validated = _validate_cli_path(argv[2], must_exist=True)
        if validated is None:
            return 4
        result = verify_all(validated)
        print(f"\nGesamt: {result['ok']} OK, {result['with_issues']} mit Issues, "
              f"{result['no_manifest']} ohne Manifest (von {result['total']})")
        return 0 if result['with_issues'] == 0 else 3

    if cmd == "gfs" and len(argv) >= 3:
        validated = _validate_cli_path(argv[2], must_exist=True)
        if validated is None:
            return 4
        apply = "--apply" in argv
        # Optional: --keep-daily N --keep-weekly N --keep-monthly N
        def _get_int(flag, default):
            if flag in argv:
                idx = argv.index(flag)
                if idx + 1 < len(argv):
                    try:
                        return int(argv[idx + 1])
                    except ValueError:
                        pass
            return default
        kd = _get_int("--keep-daily", 7)
        kw = _get_int("--keep-weekly", 4)
        km = _get_int("--keep-monthly", 12)

        result = gfs_cleanup(validated, dry_run=not apply,
                             keep_daily=kd, keep_weekly=kw, keep_monthly=km)
        mode = "APPLY" if apply else "DRY-RUN"
        print(f"\n=== GFS-Retention [{mode}] keep={kd}d/{kw}w/{km}m ===")
        print(f"Behalten: {len(result['keep'])} Backups")
        for p in sorted(result['keep'], key=lambda x: x.name):
            reason = result['reasons'].get(p, "?")
            print(f"  KEEP  {p.name}  [{reason}]")
        print(f"\nLoeschen: {len(result['delete'])} Backups")
        for p in sorted(result['delete'], key=lambda x: x.name):
            print(f"  {'DEL' if apply else 'WOULD-DEL'}   {p.name}")
        print(f"\nSpeicher freigegeben{' (dry-run)' if not apply else ''}: "
              f"{result['freed_bytes'] / 1024 / 1024:.1f} MB")
        return 0

    _print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
