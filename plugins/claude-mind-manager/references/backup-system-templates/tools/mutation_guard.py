#!/usr/bin/env python3
"""mutation_guard.py - Pre-Mutation Safety-Checks fuer Backup-Operationen.

Installiert von claude-mind-manager v3.3.0 (mind-files Skill).
Adaptiert aus Zustellplan-App (build.py), generisch fuer beliebige Projekte.

3 Patterns:
1. User-Data-Fingerprint  - Hash der Ziel-Files vor/nach Mutation (Race-Detect)
2. Symlink-Check          - Verhindert cp/mv ueber Symlinks (TOCTOU-Schutz)
3. Test-Gate              - Vor jeder Mutation: BACKUP_TEST_CMD muss true sein

CLI:
    python tools/mutation_guard.py fingerprint <path>
        Liste {file: sha256} aller Files unter path (rekursiv)

    python tools/mutation_guard.py check-symlinks <path>
        Findet Symlinks unter path (FAIL bei Treffer)

    python tools/mutation_guard.py test-gate
        Fuehrt $BACKUP_TEST_CMD aus (default leer = skip).
        Exit 0 = OK, sonst FAIL.

    python tools/mutation_guard.py guarded-op <path>
        Komplett-Check: fingerprint + check-symlinks + test-gate
        Exit 0 = sicher fuer Mutation, sonst FAIL mit Begruendung

Defaults:
    BACKUP_TEST_CMD env-var: leer = skip Test-Gate (sicher), sonst Shell-Cmd
    Beispiel: BACKUP_TEST_CMD="pytest -q"  -> python tools/mutation_guard.py test-gate

__version__ = 1.0.0
"""
from __future__ import annotations
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path


__version__ = "1.0.0"

BACKUP_TEST_CMD = os.environ.get("BACKUP_TEST_CMD", "")
BACKUP_TEST_TIMEOUT = int(os.environ.get("BACKUP_TEST_TIMEOUT", "300"))  # 5 min default


def _sha256_file(path: Path, block_size: int = 65536) -> str:
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while chunk := f.read(block_size):
            h.update(chunk)
    return h.hexdigest()


# =========================================================================
# 1. User-Data-Fingerprint
# =========================================================================

def fingerprint(path: Path) -> dict:
    """Erzeugt {relative_path: sha256} dict aller Files unter path.

    Skipped Symlinks (separate Verantwortung von check_no_symlinks).
    Skipped Files die nicht lesbar sind.

    Use: vor Mutation aufrufen, nach Mutation erneut + vergleichen.
         Diff = unerwartete Veraenderungen (z.B. Race-Condition).
    """
    path = Path(path).resolve()
    if not path.exists():
        return {}

    result = {}
    if path.is_file():
        try:
            result[path.name] = _sha256_file(path)
        except OSError:
            pass
        return result

    for p in path.rglob('*'):
        if not p.is_file():
            continue
        if p.is_symlink():
            continue
        try:
            rel = p.relative_to(path).as_posix()
            result[rel] = _sha256_file(p)
        except (OSError, ValueError):
            continue

    return result


def fingerprint_diff(before: dict, after: dict) -> dict:
    """Vergleicht zwei Fingerprints.

    Returns: dict mit {added, removed, modified, unchanged_count}
    """
    before_keys = set(before.keys())
    after_keys = set(after.keys())

    added = sorted(after_keys - before_keys)
    removed = sorted(before_keys - after_keys)
    modified = sorted(k for k in (before_keys & after_keys) if before[k] != after[k])
    unchanged_count = len((before_keys & after_keys)) - len(modified)

    return {
        "added": added,
        "removed": removed,
        "modified": modified,
        "unchanged_count": unchanged_count,
    }


# =========================================================================
# 2. Symlink-Check
# =========================================================================

def check_no_symlinks(path: Path) -> list[Path]:
    """Findet alle Symlinks unter path. Leere Liste = OK.

    Schuetzt vor TOCTOU bei cp/mv:
    Wenn ein User-Daten-File ein Symlink ist, koennte cp den Link
    folgen und das LINK-TARGET ueberschreiben statt der erwarteten Datei.
    """
    path = Path(path)
    if not path.exists():
        return []

    symlinks = []
    if path.is_symlink():
        symlinks.append(path)
        return symlinks

    if path.is_file():
        return []

    for p in path.rglob('*'):
        if p.is_symlink():
            symlinks.append(p)

    return symlinks


# =========================================================================
# 3. Test-Gate
# =========================================================================

def test_gate() -> tuple[bool, str]:
    """Fuehrt BACKUP_TEST_CMD aus. Returns (ok, message).

    Wenn BACKUP_TEST_CMD leer: (True, "skipped — no BACKUP_TEST_CMD configured")
    Wenn cmd exit 0: (True, "tests passed")
    Sonst: (False, "tests failed: <stderr-snippet>")

    SECURITY-NOTE (CWE-78 akzeptiert):
        Wir nutzen shell=True um shell-features (pipes, &&) im BACKUP_TEST_CMD
        zu erlauben (z.B. "pytest -q && coverage report"). Das bedeutet:
        WER .backuprc / Env-Var BACKUP_TEST_CMD kontrolliert, kann beliebigen
        Code ausfuehren. .backuprc sollte deshalb wie Source-Code behandelt
        werden — NIEMALS aus untrusted-Quelle committen oder editieren lassen.
        Bei kompromittiertem .backuprc ist RCE so plausibel wie bei einem
        kompromittierten conftest.py oder Makefile.
    """
    if not BACKUP_TEST_CMD:
        return True, "skipped (no BACKUP_TEST_CMD env-var set)"

    try:
        result = subprocess.run(
            BACKUP_TEST_CMD, shell=True,  # noqa: S602 — security: shell=True intentional, siehe docstring
            capture_output=True, text=True,
            timeout=BACKUP_TEST_TIMEOUT,
        )
        if result.returncode == 0:
            return True, f"tests passed (cmd: {BACKUP_TEST_CMD!r})"
        else:
            # Letzte 500 chars stderr fuer Diagnose
            err = (result.stderr or result.stdout or "")[-500:]
            return False, f"tests failed (exit {result.returncode}): {err}"
    except subprocess.TimeoutExpired:
        return False, f"tests timeout after {BACKUP_TEST_TIMEOUT}s (cmd: {BACKUP_TEST_CMD!r})"
    except (OSError, FileNotFoundError) as e:
        return False, f"tests could not run: {e}"


# =========================================================================
# Combined: guarded-op
# =========================================================================

def guarded_op(path: Path) -> int:
    """Komplett-Check vor einer Mutation. Returns exit-code."""
    path = Path(path).resolve()
    print(f"Mutation-Guard fuer: {path}")
    print()

    # 1. Symlinks
    symlinks = check_no_symlinks(path)
    if symlinks:
        print(f"  FAIL: {len(symlinks)} Symlink(s) gefunden:")
        for s in symlinks[:5]:
            try:
                target = s.readlink()
                print(f"    {s} -> {target}")
            except OSError:
                print(f"    {s} (Target nicht lesbar)")
        if len(symlinks) > 5:
            print(f"    ... {len(symlinks) - 5} weitere")
        print()
        print("Mutation BLOCKIERT — Symlinks koennten Link-Targets statt erwarteter Files ueberschreiben.")
        return 2
    print(f"  OK: keine Symlinks unter {path}")

    # 2. Fingerprint
    fp = fingerprint(path)
    print(f"  OK: Fingerprint berechnet ({len(fp)} files)")

    # 3. Test-Gate
    ok, msg = test_gate()
    if ok:
        print(f"  OK: Test-Gate ({msg})")
    else:
        print(f"  FAIL: Test-Gate — {msg}")
        return 3

    print()
    print("[OK] Sicher fuer Mutation.")
    return 0


# =========================================================================
# CLI
# =========================================================================

def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help", "help"):
        print(__doc__)
        return 0

    cmd = argv[1]

    if cmd == "fingerprint" and len(argv) >= 3:
        result = fingerprint(Path(argv[2]))
        # Output als JSON fuer leichte Weiterverarbeitung
        print(json.dumps(result, indent=2))
        return 0

    if cmd == "check-symlinks" and len(argv) >= 3:
        symlinks = check_no_symlinks(Path(argv[2]))
        if symlinks:
            print(f"FAIL: {len(symlinks)} Symlink(s):")
            for s in symlinks:
                print(f"  {s}")
            return 2
        print(f"OK: keine Symlinks unter {argv[2]}")
        return 0

    if cmd == "test-gate":
        ok, msg = test_gate()
        print(f"{'OK' if ok else 'FAIL'}: {msg}")
        return 0 if ok else 3

    if cmd == "guarded-op" and len(argv) >= 3:
        return guarded_op(Path(argv[2]))

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
