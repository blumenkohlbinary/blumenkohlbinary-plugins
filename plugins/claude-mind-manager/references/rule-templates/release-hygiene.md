---
description: Release-Hygiene — Conventional Commits + Changelog + Versions-Sync
globs: ["**/*"]
---

# Release-Hygiene

## Conventional Commits (Pflicht-Format)

`<type>(<scope>)!: <subject>`

- **type** (fixes Set): `feat` `fix` `refactor` `perf` `test` `docs` `build` `chore` `style` `revert` `release`
- **subject**: imperativ, klein, KEIN Punkt am Ende
- **Body**: erklärt **Was + Warum**, NICHT Wie. Breaking Changes: `!` nach type ODER `BREAKING CHANGE:` im Footer.
- **Staging**: `git add <konkrete files>` — **NIE `git add -A`/`.`** (staged versehentlich Fremdes).
- Mehrzeilige Messages via Heredoc (`git commit -m "$(cat <<'EOF' … EOF)"`).

**Wann committen:** Feature/Phase fertig · User sagt "ok/commit" · vor Release · nach Migration.

## Changelog (aus Git-Historie generiert)

Dieses Projekt generiert `CHANGELOG.md` aus den Commits via `tools/update_changelog.py`:

```bash
python tools/update_changelog.py            # schreibt CHANGELOG.md
python tools/update_changelog.py --print    # dry-run (stdout)
python tools/update_changelog.py --since v1.0.2
```

## Vier load-bearing Warnungen (der eigentliche Wert dieser Regel)

1. **Changelog-Generierung ist MANUELL.** NIEMALS in eine Build-/Commit-Pipeline hängen —
   das erzeugt eine Endlos-Commit-Schleife (Changelog-Commit → triggert Build → neuer Changelog-Commit …).
2. **Tag-Format muss exakt `vMAJOR.MINOR.PATCH` sein** (z.B. `v1.0.5`). Weicht es ab, kann
   `update_changelog.py` die Commits nicht nach Version gruppieren — der Changelog wird still falsch.
3. **Version hat EINE Source-of-Truth** mit definierter Fallback-Kette. Bei mehreren Manifesten
   (pyproject.toml / package.json / *.csproj): **synchron halten** — Drift ist der häufigste Bug.
4. **dev.N-Build-Counter** (falls verwendet) lebt in einer **Nicht-VCS-Textdatei** und wird bei
   einem **fehlgeschlagenen/abgebrochenen Build NICHT hochgezählt** (keine "verbrannte" Nummer).

## Version bumpen

<!-- ECOSYSTEM-ADAPTER: von mind-files aus project-scanner-Detection gefüllt.
     Python-Release-App → siehe release-build.md (tools/version.py).
     Node → `npm version patch` (bumpt package.json + Git-Tag).
     .NET → `<Version>` in *.csproj editieren.
     Danach: alle Manifeste synchron + `python tools/update_changelog.py`. -->
