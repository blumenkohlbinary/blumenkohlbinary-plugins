#!/usr/bin/env python3
"""version.py -- generisches Versionierungs-Tool (stdlib-only, Python 3.8+).

Adaptiert das Versions-Modell von Zustellplan build.py, ENTKOPPELT von
PyInstaller/EXE (keine Snapshots, kein _internal-Hashing, keine VERSIONINFO):

- Single-Source-of-Truth mit Fallback-Kette (VERSION -> pyproject -> package.json -> *.csproj)
- "nie aus einer -dev-Version bumpen"-Guard (Pre-Release wird vor dem Bump gestrippt)
- dev.N-Build-Counter in einer Nicht-VCS-Textdatei; wird NUR bei erfolgreichem
  `dev`-Aufruf hochgezaehlt (nicht bei einem Fehlbuild verbrannt) und bei Stable-Release resettet
- `sync` ueber alle gefundenen Manifeste; bei Versions-DISSENS -> WARN + `--force` verlangen,
  NIE still ueberschreiben oder downgraden
- `bump major|minor|patch`, optional `--tag` (Git-Tag vX.Y.Z, opt-in)
- `release` = bump + sync + optional Tag + optional Changelog

Kein Netzwerk, keine Dependencies.

CLI:
    python tools/version.py show
    python tools/version.py bump [major|minor|patch]   (default: patch)
    python tools/version.py dev                          (dev.N-Counter +1, druckt Dev-Version)
    python tools/version.py sync [--force]
    python tools/version.py release [major|minor|patch] [--tag] [--changelog]
Gemeinsame Option: --root <dir>  (default: aktuelles Verzeichnis)
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
import sys

SEMVER_RE = re.compile(r"(\d+)\.(\d+)\.(\d+)")
COUNTER_REL = os.path.join(".claude-mind", "build_counter")


# ============================================================
# Datei-I/O (context-managed + atomarer Write)
# ============================================================

def _read_text(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def _write_text(path: str, text: str):
    """Atomarer Write: erst in .tmp, dann os.replace -> nie halb-geschriebene Datei
    (Crash/Disk-Full lassen das Original unangetastet)."""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


# ============================================================
# Version-Arithmetik
# ============================================================

def strip_prerelease(version: str) -> str:
    """Entfernt '-dev', '-dev.3', '-alpha', '-rc1' etc. '1.0.1-dev.3' -> '1.0.1'."""
    return version.split("-")[0].strip()


def bump(version: str, part: str = "patch") -> str:
    """Erhoeht major|minor|patch um 1. Strippt Pre-Release VOR dem Bump.

    '1.2.5' patch -> '1.2.6' | '1.2.5' minor -> '1.3.0' | '1.2.5' major -> '2.0.0'
    '1.0.1-dev.3' patch -> '1.0.2'  (dev-Suffix abgestrippt -> nie aus -dev bumpen)
    """
    if not version or not version.strip():
        raise ValueError(f"Version darf nicht leer sein: {version!r}")
    clean = strip_prerelease(version)
    parts = clean.split(".")
    if len(parts) != 3:
        raise ValueError(f"Version muss Format X.Y.Z haben: {version!r}")
    try:
        major, minor, patch = (int(p) for p in parts)
    except ValueError as e:
        raise ValueError(f"Version-Teile muessen Zahlen sein: {version!r}") from e
    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    if part == "patch":
        return f"{major}.{minor}.{patch + 1}"
    raise ValueError(f"part muss major|minor|patch sein: {part!r}")


def _cmp(a: str, b: str) -> int:
    """Vergleicht zwei Stable-Versionen. -1 wenn a<b, 0 gleich, 1 wenn a>b."""
    ta = tuple(int(x) for x in strip_prerelease(a).split("."))
    tb = tuple(int(x) for x in strip_prerelease(b).split("."))
    return (ta > tb) - (ta < tb)


# ============================================================
# Manifest-Reader/Writer (jeweils: (path, read()->ver|None, write(ver)))
# ============================================================

def _read_version_file(root):
    p = os.path.join(root, "VERSION")
    if os.path.isfile(p):
        m = SEMVER_RE.search(_read_text(p))
        if m:
            return m.group(0)
    return None


def _write_version_file(root, version):
    _write_text(os.path.join(root, "VERSION"), version + "\n")


def _read_pyproject(root):
    p = os.path.join(root, "pyproject.toml")
    if os.path.isfile(p):
        m = re.search(r"\[project\][^\[]*?\nversion\s*=\s*[\"']([^\"']+)[\"']",
                      _read_text(p), flags=re.DOTALL)
        if m:
            return m.group(1)
    return None


def _write_pyproject(root, version):
    p = os.path.join(root, "pyproject.toml")
    if not os.path.isfile(p):
        return
    text = _read_text(p)
    new = re.sub(r"(\[project\][^\[]*?\nversion\s*=\s*)[\"'][^\"']*[\"']",
                 rf'\1"{version}"', text, count=1, flags=re.DOTALL)
    if new != text:
        _write_text(p, new)


def _read_package_json(root):
    p = os.path.join(root, "package.json")
    if os.path.isfile(p):
        m = re.search(r'"version"\s*:\s*"([^"]+)"', _read_text(p))
        if m:
            return m.group(1)
    return None


def _write_package_json(root, version):
    p = os.path.join(root, "package.json")
    if not os.path.isfile(p):
        return
    text = _read_text(p)
    new = re.sub(r'("version"\s*:\s*)"[^"]*"', rf'\1"{version}"', text, count=1)
    if new != text:
        _write_text(p, new)


def _csproj_paths(root):
    return sorted(glob.glob(os.path.join(root, "**", "*.csproj"), recursive=True))


def _read_csproj(root):
    for p in _csproj_paths(root):
        m = re.search(r"<Version>([^<]+)</Version>", _read_text(p))
        if m:
            return m.group(1)
    return None


def _write_csproj(root, version):
    for p in _csproj_paths(root):
        text = _read_text(p)
        new = re.sub(r"(<Version>)[^<]*(</Version>)", rf"\g<1>{version}\g<2>",
                     text, count=1)
        if new != text:
            _write_text(p, new)


# Reihenfolge = Fallback-/Praezedenz-Kette der Source-of-Truth
MANIFESTS = [
    ("VERSION",       _read_version_file,  _write_version_file),
    ("pyproject.toml", _read_pyproject,    _write_pyproject),
    ("package.json",  _read_package_json,  _write_package_json),
    ("*.csproj",      _read_csproj,        _write_csproj),
]


def read_stable_version(root: str) -> str:
    """Erste vorhandene Manifest-Version der Praezedenz-Kette, IMMER ohne -dev.

    Fallback-Literal '0.1.0' wenn kein Manifest existiert.
    """
    for _name, reader, _writer in MANIFESTS:
        v = reader(root)
        if v:
            return strip_prerelease(v)
    return "0.1.0"


def collect_versions(root: str):
    """{manifest_name: version} fuer alle vorhandenen Manifeste (gestrippt)."""
    out = {}
    for name, reader, _writer in MANIFESTS:
        v = reader(root)
        if v:
            out[name] = strip_prerelease(v)
    return out


def write_all(root: str, version: str):
    """Schreibt `version` in VERSION-Datei (immer) + alle vorhandenen Manifeste."""
    _write_version_file(root, version)  # kanonische Source-of-Truth immer setzen
    for name, reader, writer in MANIFESTS:
        if name == "VERSION":
            continue
        if reader(root) is not None:
            writer(root, version)


# ============================================================
# dev.N-Build-Counter (Nicht-VCS-Textdatei)
# ============================================================

def _counter_path(root):
    return os.path.join(root, COUNTER_REL)


def read_counter(root: str) -> int:
    p = _counter_path(root)
    if not os.path.isfile(p):
        return 0
    try:
        return int(_read_text(p).strip())
    except (ValueError, OSError) as e:
        # NICHT still auf 0 zuruecksetzen — das wuerde die Build-Historie verlieren.
        # Warnen, damit der Nutzer die korrupte Datei bemerkt (und ggf. loescht).
        print(f"WARN: Build-Counter '{p}' korrupt/unlesbar ({e}) - als 0 behandelt.",
              file=sys.stderr)
        return 0


def increment_counter(root: str) -> int:
    new_val = read_counter(root) + 1
    p = _counter_path(root)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    _write_text(p, str(new_val))  # atomar -> Crash mid-write laesst alte Zahl intakt
    return new_val


def reset_counter(root: str):
    p = _counter_path(root)
    if os.path.isfile(p):
        os.remove(p)


# ============================================================
# Commands
# ============================================================

def cmd_show(root, _args):
    stable = read_stable_version(root)
    counter = read_counter(root)
    print(f"stable: {stable}")
    if counter > 0:
        print(f"dev:    {bump(stable)}-dev.{counter}")
    versions = collect_versions(root)
    if versions:
        print("manifeste:")
        for name, v in versions.items():
            flag = "" if v == stable else "  <-- weicht ab!"
            print(f"  {name:16} {v}{flag}")
    return 0


def cmd_bump(root, args):
    current = read_stable_version(root)
    new = bump(current, args.part)
    write_all(root, new)
    reset_counter(root)  # neuer Stable -> Dev-Counter zurueck
    print(f"bump {args.part}: {current} -> {new}")
    others = [n for n, r, _ in MANIFESTS if n != "VERSION" and r(root) is not None]
    targets = "VERSION" + (" + " + ", ".join(others) if others else "")
    print(f"  geschrieben in: {targets}")
    return 0


def cmd_dev(root, _args):
    # Counter NUR hier hochzaehlen -> ein Fehlbuild, der diesen Command nicht
    # erreicht, verbrennt keine Nummer.
    counter = increment_counter(root)
    stable = read_stable_version(root)
    print(f"{bump(stable)}-dev.{counter}")
    return 0


def cmd_sync(root, args):
    versions = collect_versions(root)
    if not versions:
        print("Keine Manifeste gefunden - nichts zu synchronisieren.", file=sys.stderr)
        return 1
    distinct = set(versions.values())
    target = read_stable_version(root)  # Praezedenz-Kette bestimmt Ziel
    if len(distinct) == 1:
        print(f"Alle Manifeste bereits synchron auf {target}.")
        return 0
    # DISSENS: mehrere verschiedene Versionen im Projekt
    print("WARN: Manifeste sind NICHT synchron:", file=sys.stderr)
    for name, v in versions.items():
        print(f"  {name:16} {v}", file=sys.stderr)
    if not args.force:
        print(f"\nZiel waere '{target}' (hoechste Praezedenz). NICHT ueberschrieben -"
              f" das koennte ein Downgrade verbergen.\n"
              f"Version pruefen, dann mit  python tools/version.py sync --force  erzwingen.",
              file=sys.stderr)
        return 2
    write_all(root, target)
    print(f"--force: alle Manifeste auf {target} gesetzt.")
    return 0


def cmd_release(root, args):
    rc = cmd_bump(root, args)
    if rc != 0:
        return rc
    new = read_stable_version(root)
    if args.tag:
        tag = f"v{new}"
        try:
            subprocess.run(["git", "tag", tag], cwd=root, check=True)
            print(f"  git tag {tag}")
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f"WARN: git tag fehlgeschlagen ({e}) - Tag manuell setzen.", file=sys.stderr)
    if args.changelog:
        cl = os.path.join(root, "tools", "update_changelog.py")
        if os.path.isfile(cl):
            try:
                subprocess.run([sys.executable, cl], cwd=root, check=True)
                print("  CHANGELOG.md aktualisiert")
            except subprocess.CalledProcessError as e:
                print(f"WARN: update_changelog.py fehlgeschlagen ({e}).", file=sys.stderr)
        else:
            print("WARN: tools/update_changelog.py nicht gefunden - Changelog uebersprungen.",
                  file=sys.stderr)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generisches Versionierungs-Tool")
    parser.add_argument("--root", default=".", help="Projekt-Root (default: .)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("show", help="Aktuelle Version(en) anzeigen")

    p_bump = sub.add_parser("bump", help="Version erhoehen")
    p_bump.add_argument("part", nargs="?", default="patch",
                        choices=["major", "minor", "patch"])

    sub.add_parser("dev", help="Dev-Build-Counter +1, Dev-Version drucken")

    p_sync = sub.add_parser("sync", help="Alle Manifeste auf Source-of-Truth angleichen")
    p_sync.add_argument("--force", action="store_true",
                        help="Dissens erzwungen ueberschreiben (kann Downgrade sein!)")

    p_rel = sub.add_parser("release", help="bump + sync + optional tag/changelog")
    p_rel.add_argument("part", nargs="?", default="patch",
                       choices=["major", "minor", "patch"])
    p_rel.add_argument("--tag", action="store_true", help="Git-Tag vX.Y.Z setzen")
    p_rel.add_argument("--changelog", action="store_true",
                       help="tools/update_changelog.py nach dem Bump laufen lassen")

    args = parser.parse_args(argv)
    root = os.path.abspath(args.root)
    dispatch = {"show": cmd_show, "bump": cmd_bump, "dev": cmd_dev,
                "sync": cmd_sync, "release": cmd_release}
    try:
        return dispatch[args.cmd](root, args)
    except ValueError as e:
        print(f"FEHLER: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
