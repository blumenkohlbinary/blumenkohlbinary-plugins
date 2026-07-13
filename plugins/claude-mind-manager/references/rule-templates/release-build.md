---
description: Versionierung + Build-Disziplin für diese Python-Release-App (tools/version.py)
globs: ["build.py", "*.spec", "**/*.py", "pyproject.toml", "VERSION"]
---

# Versionierung & Build — Python-Release-App

Dieses Projekt hat `tools/version.py` (von claude-mind-manager installiert). **Nutze es**
für jede Versions-Änderung — Manifeste (pyproject.toml / package.json / *.csproj) von Hand
zu editieren führt zu Versions-Drift.

## Versions-Workflow

```bash
python tools/version.py show                 # aktueller Stand (stable + dev.N + Manifest-Drift)
python tools/version.py bump patch           # Feature/Fix fertig -> Patch hoch (auch minor|major)
python tools/version.py dev                  # Dev-Build: Counter +1, druckt X.Y.Z-dev.N
python tools/version.py sync                 # Manifeste angleichen (WARN bei Dissens)
python tools/version.py release minor --tag --changelog   # Release: bump+sync+git-Tag+Changelog
```

**Regeln:**
- **Nach Feature-Fertigstellung** `version.py bump`. **Vor einem Release** `version.py release`.
- **Nie aus einer `-dev`-Version bumpen** — `version.py` strippt den Suffix automatisch, also
  immer über das Tool gehen, nie Manifest von Hand hochzählen.
- **Single-Source-of-Truth:** Praezedenz `VERSION` > `pyproject.toml` > `package.json` > `*.csproj`.
  Bei Dissens meldet `sync` WARN und verlangt `--force` — erst prüfen welche Version stimmt.
- **dev.N-Counter** lebt in `.claude-mind/build_counter` (Nicht-VCS). Wird nur bei `version.py dev`
  hochgezählt (ein Fehlbuild verbrennt keine Nummer) und bei `bump`/`release` resettet.
- Git-Tag-Format exakt `vX.Y.Z` (opt-in via `--tag`) — sonst gruppiert `update_changelog.py` nicht.

## Python-Desktop-Build-Disziplin (falls PyInstaller/Freeze im Spiel)

- **Nie `pyinstaller App.spec` direkt** in einen `dist/` mit Benutzerdaten bauen — erst in einen
  Temp-Ordner bauen, dann selektiv EXE + `_internal/` kopieren (Benutzerdaten NIE anfassen).
- **Lazy-Import-Falle:** dynamisch importierte Module landen nicht automatisch im Bundle —
  `hiddenimports=[...]` bzw. `collect_all('paket')` in der `.spec` pflegen, sonst
  `ModuleNotFoundError` erst zur Laufzeit der EXE.
- **Immer im venv bauen** (`.venv/Scripts/python`), nie im System-Python.
- **Windows-Quirks:** Text-Dateien mit `encoding='utf-8'` schreiben (cp1252-`UnicodeEncodeError`
  bei Umlauten/Pfeilen); `upx=False` wenn UPX Antiviren-Fehlalarme auslöst.
- **Test-Gate vor Release:** `.backuprc BACKUP_TEST_CMD` grün, sonst kein Release-Bump.
