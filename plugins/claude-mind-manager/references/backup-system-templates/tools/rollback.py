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
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

__version__ = "1.0.0"

DEFAULT_TARGET = os.environ.get("BACKUP_TARGET", ".claude-mind/backups")
PROJECT_ROOT = Path.cwd()


HOME = Path(os.path.expanduser("~"))


def wurzeln() -> list:
    """Alle Orte, an denen Snapshots liegen koennen.

    ⛔ ZWEI ABLAGEN, und rollback.py kannte bis v5.20.1 nur EINE:
       `mind_snapshot` (hooks/lib.sh) schreibt nach `.claude-mind/snapshots`,
       das Backup-System nach `.claude-mind/backups`. `rollback.py list` fand
       die Snapshots des Plugins damit **gar nicht** — der Rueckweg existierte
       nur auf dem Papier. Gefunden im Plan-Review am 25.08.2026.

    ⚠ Ist BACKUP_TARGET ausdruecklich gesetzt, gilt NUR dieser Ort — eine
      bewusste Wahl wird nicht heimlich erweitert.
    """
    aus = []
    t = Path(DEFAULT_TARGET)
    aus.append(t if t.is_absolute() else PROJECT_ROOT / t)
    if "BACKUP_TARGET" not in os.environ:
        aus.append(PROJECT_ROOT / ".claude-mind" / "snapshots")
    return [p.resolve() for p in aus]


def get_backup_root() -> Path:
    """Der ERSTE Ort — bleibt fuer Aufrufer, die genau einen erwarten."""
    return wurzeln()[0]


def finde_snapshot(name: str):
    """Snapshot in ALLEN Wurzeln suchen. -> (pfad, wurzel) oder (None, None)."""
    for w in wurzeln():
        if not w.exists():
            continue
        p = _safe_join(w, name)
        if p is not None and p.is_dir():
            return p, w
    return None, None


def _slug(win_pfad: str) -> str:
    """Spiegelbild von hash_project_dir() aus hooks/lib.sh (Regel ab v5.7.0).

    ⛔ NICHT nachgebaut: dieselbe Formel steht in references/slug_regression.py
       und ist dort gegen 12 Vektoren geprueft — einschliesslich des `&`-Falls,
       der Memory einst in den Fallback schickte.
    """
    return re.sub(r"^-*", "", re.sub(r"[^A-Za-z0-9]", "-", win_pfad))


def ziel_fuer(rel: str):
    """Snapshot-Zweig -> echter Zielort. -> (Path, "") oder (None, grund).

    ⛔ Ein Snapshot hat VIER Zweige (rules/, global/, memory/, project/), und
       KEINER liegt unter <projekt>/<zweig>/. Bis v5.20.1 schrieb restore()
       stumpf `PROJECT_ROOT / rel` — `rules/hooks.md` landete damit in
       <projekt>/rules/hooks.md statt in <projekt>/.claude/rules/hooks.md.
       **Nur die blanke CLAUDE.md kam richtig an.**

    ⭐ Die Zuordnung stand die ganze Zeit dokumentiert, in
       skills/mind-all/SKILL.md Step 3 ("Restore (Ziele liegen NICHT alle im
       Projekt!)"). Sie war nur nie implementiert.
    """
    r = rel.replace("\\", "/")
    if r == "dot-claude-CLAUDE.md":
        return PROJECT_ROOT / ".claude" / "CLAUDE.md", ""
    if r == "global/CLAUDE.md":
        return HOME / ".claude" / "CLAUDE.md", ""
    if r.startswith("global/rules/"):
        return HOME / ".claude" / "rules" / r[len("global/rules/"):], ""
    if r.startswith("rules/"):
        return PROJECT_ROOT / ".claude" / "rules" / r[len("rules/"):], ""
    if r.startswith("project/"):
        return PROJECT_ROOT / r[len("project/"):], ""
    if r.startswith("memory/"):
        # ⛔ get_memory_dir faellt bei Slug-Mismatch auf das NEUESTE FREMDE
        #    Projekt zurueck (lib.sh). mind_snapshot sichert dagegen ab, indem
        #    es den Pfad nur nimmt, wenn GENAU DIESES Verzeichnis existiert —
        #    derselbe Schutz gilt hier. Lieber nicht restaurieren als in ein
        #    fremdes Projekt schreiben.
        d = HOME / ".claude" / "projects" / _slug(str(PROJECT_ROOT)) / "memory"
        if not d.is_dir():
            return None, "memory uebersprungen: %s existiert nicht" % d
        return d / r[len("memory/"):], ""
    if r == "CLAUDE.md":
        return PROJECT_ROOT / "CLAUDE.md", ""
    return PROJECT_ROOT / r, ""          # unbekannter Zweig: wie bisher


def _erlaubt(ziel: Path) -> bool:
    """Schreiben nur unter die Projektwurzel oder unter ~/.claude.

    Der Traversal-Schutz von `_safe_join` reichte, solange alles ins Projekt
    ging. Seit ziel_fuer() auch nach ~/.claude schreibt, braucht es zwei
    erlaubte Wurzeln — und weiterhin KEINE dritte.
    """
    z = ziel.resolve()
    for w in (PROJECT_ROOT.resolve(), (HOME / ".claude").resolve()):
        try:
            z.relative_to(w)
            return True
        except ValueError:
            continue
    return False


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
    """Listet alle Snapshots aus ALLEN Wurzeln (backups/ UND snapshots/)."""
    orte = [w for w in wurzeln() if w.exists()]
    if not orte:
        print("Keine Snapshot-Ablage gefunden. Gesucht in:")
        for w in wurzeln():
            print(f"  {w}")
        print("Setze $BACKUP_TARGET oder lege eines der Verzeichnisse an.")
        return 1

    snapshots = []
    for w in orte:
        snapshots += [p for p in w.iterdir() if p.is_dir()]
    snapshots.sort(key=lambda p: p.stat().st_mtime, reverse=True)

    if not snapshots:
        print("Keine Snapshots in: " + " · ".join(str(w) for w in orte))
        return 0

    print("Verfuegbare Snapshots in " + " · ".join(str(w) for w in orte) + ":\n")
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
    # Security-Fix CWE-22: Path-Traversal-Check steckt in finde_snapshot()
    snap, _root = finde_snapshot(snapshot_name)
    if snap is None:
        print(f"Snapshot nicht gefunden: {snapshot_name}", file=sys.stderr)
        for w in wurzeln():
            print(f"  gesucht in: {w}", file=sys.stderr)
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
    snap, root = finde_snapshot(snapshot_name)
    if snap is None:
        print(f"Snapshot nicht gefunden: {snapshot_name}", file=sys.stderr)
        for w in wurzeln():
            print(f"  gesucht in: {w}", file=sys.stderr)
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
        # ⛔ NICHT PROJECT_ROOT / rel — siehe ziel_fuer(). Wer hier den falschen
        #    Ort sichert, sichert eine Datei, die gar nicht ueberschrieben wird,
        #    und laesst die echte ungesichert.
        current, _grund = ziel_fuer(rel)
        if current is not None and current.exists() and current.is_file():
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
    uebersprungen = 0
    for rel in files_to_restore:
        src = snap / rel
        dst, grund = ziel_fuer(rel)
        if dst is None:
            # z.B. memory/, dessen Zielverzeichnis nicht existiert
            print(f"  UEBERSPRUNGEN {rel}: {grund}")
            uebersprungen += 1
            continue
        if not _erlaubt(dst):
            print(f"  ABGEWIESEN {rel}: Ziel ausserhalb Projekt und ~/.claude "
                  f"({dst})", file=sys.stderr)
            uebersprungen += 1
            continue
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
    if uebersprungen:
        print(f"  {uebersprungen} Datei(en) uebersprungen — s. Meldungen oben.")

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
