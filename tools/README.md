# tools/ — Werkzeuge rund um die Plugin-Installation

## `_sync_plugin_registry.py`

Repariert Claude Codes Plugin-Registry nach einem manuellen Cache-Umbau und raeumt alte
Versionsverzeichnisse auf.

```bash
python tools/_sync_plugin_registry.py <marktplatz> <plugin> <version> <klon-verzeichnis>
```

⛔ **Diese Kopie ist die kanonische Quelle.** Gearbeitet wird mit dem Exemplar unter
`C:\CD\KOHLEKTIV\_sync_plugin_registry.py` — dorthin ruft es die
`update-claude-marketplace.bat`. Nach einer Aenderung hier ausrollen:

```bash
cp tools/_sync_plugin_registry.py "C:/CD/KOHLEKTIV/_sync_plugin_registry.py"
```

**Warum es hier liegt:** Bis zum 19.08.2026 lag das Skript in **keiner** Versionskontrolle.
An dem Tag loeschte es die Plugin-Version, auf der eine laufende Claude-Code-Sitzung stand —
alle ihre Hooks waeren lautlos gestorben. Ein Werkzeug, das `shutil.rmtree` aufruft und
nirgends versioniert ist, hat keine Rueckfallebene.

## Was der Aufraeumer schuetzt

| Regel | Wirkung |
|---|---|
| die aktive Version | nie geloescht |
| jede vor ≤ `PROTECT_HOURS` (168) abgeloeste | nie geloescht — `.sync-protect.json` neben den Versionsverzeichnissen |
| die `KEEP_VERSIONS` (2) **hoechsten** Versionsnummern | nie geloescht |
| alles, was nicht wie eine Version heisst | nie angefasst |
| Vorgaengerversion nicht bestimmbar | raeumt **gar nicht** auf |
| `ver` enthaelt `..` | raeumt **gar nicht** auf |

`MIND_SYNC_PROTECT_HOURS` setzt die Schonfrist (1 bis 8760; unsinnige Werte fallen auf 168
zurueck, statt das Skript abstuerzen zu lassen).

## Prueffaelle

Sie liegen **nicht** im Repo, weil sie eine Sandbox mit eigenem `USERPROFILE` bauen und
plattformgebunden sind. Wer den Aufraeumer aendert, baut sie neu — und faehrt sie **zuerst
gegen einen absichtlich beschaedigten Stand**: bleibt der gruen, misst die Pruefung nichts.
