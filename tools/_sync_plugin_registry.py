#!/usr/bin/env python3
"""Sync Claude Code's plugin registry after a MANUAL cache rebuild.

Called by update-claude-marketplace.bat once per rebuilt plugin.

Why this exists (the orphaning bug):
  The .bat rebuilds  cache\\<mkt>\\<plugin>\\<NEWVER>\\  and deletes the old version
  directory. But Claude Code's  installed_plugins.json  still records the plugin at the
  OLD version path -> on startup Claude Code cannot find it there -> marks it orphaned
  (writes .orphaned_at) -> plugin invisible/not activatable.

This resyncs everything the cache rebuild desynced:
  1. installed_plugins.json : entry <plugin>@<mkt> -> version, installPath, gitCommitSha, lastUpdated
  2. .install-manifests\\<plugin>@<mkt>.json : regenerated (sha256 of cache files, NO .orphaned_at)
  3. deletes any leftover .orphaned_at marker in the new cache dir

Safe: atomic writes, touches only the one plugin's entry, idempotent, never aborts the .bat
(errors -> WARN + continue). stdlib only. ASCII-only output (Windows cp1252 console safe).

Usage:
  python _sync_plugin_registry.py <MARKETPLACE> <PLUGIN> <VERSION> <MARKETPLACE_CLONE_DIR>
"""
import sys, os, json, hashlib, subprocess, datetime, shutil, time

# Wie viele Versionsverzeichnisse je Plugin stehen bleiben.
# WARUM ueberhaupt welche: Eine LAUFENDE Claude-Code-Sitzung haelt CLAUDE_PLUGIN_ROOT auf das
# Verzeichnis, das beim Sitzungsstart aktuell war. Wird das geloescht, sind die Hook-Skripte weg
# und alle Hooks sterben lautlos - ein Skript kann sich nicht selbst wiederbeleben.
KEEP_VERSIONS = 2

# Wie lange eine ABGELOESTE Version zusaetzlich geschuetzt bleibt (Stunden).
# Eine Claude-Code-Sitzung laeuft Stunden bis Tage, nie Wochen. 7 Tage sind grosszuegig
# und kosten nur Plattenplatz; zu kurz kostet die Hooks einer laufenden Sitzung.
#
# ⛔ NICHT `.isdigit()` nehmen: '²'.isdigit() ist True, int('²') wirft ValueError.
#    Gemessen 19.08.2026 - mit MIND_SYNC_PROTECT_HOURS='²' brach das Skript beim IMPORT ab
#    (rc=1), also ausserhalb des try/except um main(), und damit genau entgegen der Zusage
#    im Docstring ("never aborts the .bat"). Untergrenze 1, weil 0 den Schutz auf den
#    setzenden Lauf verkuerzt - dasselbe Ein-Lauf-Verhalten wie der Fehler, der hier
#    behoben wurde.
def _protect_hours():
    try:
        v = int(os.environ.get("MIND_SYNC_PROTECT_HOURS", "168"))
    except Exception:
        return 168
    return max(1, min(v, 24 * 365))


PROTECT_HOURS = _protect_hours()

PROTECT_FILE = ".sync-protect.json"


def _atomic_write(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def _vkey(name):
    """Sortierschluessel nach VERSIONSNUMMER, nicht nach mtime.

    mtime sagt, wann ein Verzeichnis zuletzt angefasst wurde - nicht, welche Version
    aktuell ist. Am 19.08.2026 hatte 5.3.0 eine juengere mtime als 5.3.1 und ueberlebte
    deshalb, waehrend 5.3.1 (die Version der laufenden Sitzung) geloescht wurde.

    '5.10.0' > '5.9.0' - genau das kann ein Zeichenkettenvergleich nicht.
    """
    out = []
    for teil in name.replace("_", ".").replace("-", ".").split("."):
        ziffern = ""
        for ch in teil:
            if not ch.isdigit():
                break
            ziffern += ch
        out.append(int(ziffern) if ziffern else 0)
    # Auf feste Laenge bringen: sonst gilt [5,4] < [5,4,0], obwohl "5.4" und "5.4.0"
    # dieselbe Version meinen - die kuerzer benannte fiele frueher aus den Top-KEEP_VERSIONS.
    while len(out) < 4:
        out.append(0)
    return out[:4]


def _sieht_aus_wie_version(name):
    """Nur Verzeichnisse loeschen, die wie eine Version aussehen.

    Ein fremdes Verzeichnis im Plugin-Cache (Sicherung, Notizen) darf dieser Aufraeumer
    nicht anfassen - er kennt seinen Inhalt nicht.
    """
    return bool(name) and name[0].isdigit() and all(
        c.isdigit() or c in "._-+abcdefghijklmnopqrstuvwxyz" for c in name.lower())


def main(argv):
    if len(argv) < 5:
        print("  [sync] usage: <marketplace> <plugin> <version> <marketplace_clone_dir>")
        return 0  # never fail the .bat on a usage slip
    mkt, plugin, ver, clone = argv[1], argv[2], argv[3], argv[4]
    home = os.environ.get("USERPROFILE") or os.path.expanduser("~")
    plugins = os.path.join(home, ".claude", "plugins")
    cache_ver = os.path.join(plugins, "cache", mkt, plugin, ver)
    ip_path = os.path.join(plugins, "installed_plugins.json")
    man_path = os.path.join(plugins, ".install-manifests", plugin + "@" + mkt + ".json")
    plugin_id = plugin + "@" + mkt

    if not os.path.isdir(cache_ver):
        print("  [sync] SKIP " + plugin_id + ": cache dir missing")
        return 0

    now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")

    # git SHA of the marketplace clone (best-effort)
    sha = ""
    try:
        sha = subprocess.check_output(["git", "-C", clone, "rev-parse", "HEAD"],
                                      text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        pass

    # 1. installed_plugins.json -- the load-bearing fix (this is what prevents orphaning)
    prev_ver = None   # Version VOR diesem Update -> die zeigt eine laufende Sitzung an
    if os.path.isfile(ip_path):
        try:
            d = json.load(open(ip_path, encoding="utf-8"))
            entries = d.get("plugins", {}).get(plugin_id)
            if isinstance(entries, list) and entries and isinstance(entries[0], dict):
                e = entries[0]
                prev_ver = e.get("version")
                changed = (e.get("version") != ver or e.get("installPath") != cache_ver)
                e["version"] = ver
                e["installPath"] = cache_ver
                if sha:
                    e["gitCommitSha"] = sha
                e["lastUpdated"] = now
                _atomic_write(ip_path, json.dumps(d, indent=2, ensure_ascii=False))
                print("  [sync] installed_plugins.json: " + plugin_id + " -> v" + ver
                      + ("" if changed else " (already current)"))
            else:
                print("  [sync] " + plugin_id + " not user-installed (not in registry) - registry skip")
        except Exception as ex:
            print("  [sync] WARN installed_plugins.json: " + str(ex))

    # 2. install-manifest -- regenerate to match the new cache (no orphan state)
    try:
        files = {}
        for root, _dirs, fns in os.walk(cache_ver):
            for fn in fns:
                full = os.path.join(root, fn)
                rel = os.path.relpath(full, cache_ver)
                if rel == ".orphaned_at":
                    continue
                with open(full, "rb") as fh:
                    files[rel.replace("/", "\\")] = hashlib.sha256(fh.read()).hexdigest()
        created = None
        if os.path.isfile(man_path):
            try:
                created = json.load(open(man_path, encoding="utf-8")).get("createdAt")
            except Exception:
                pass
        manifest = {"pluginId": plugin_id,
                    "createdAt": created or now,
                    "files": dict(sorted(files.items()))}
        os.makedirs(os.path.dirname(man_path), exist_ok=True)
        _atomic_write(man_path, json.dumps(manifest, indent=2, ensure_ascii=False))
        print("  [sync] manifest regenerated: " + str(len(files)) + " files")
    except Exception as ex:
        print("  [sync] WARN manifest: " + str(ex))

    # 3. delete leftover orphan marker
    marker = os.path.join(cache_ver, ".orphaned_at")
    if os.path.exists(marker):
        try:
            os.remove(marker)
            print("  [sync] removed .orphaned_at")
        except Exception as ex:
            print("  [sync] WARN marker: " + str(ex))

    # 4. Alte Versionsverzeichnisse aufraeumen -- ERSETZT das "rmdir /s /q" der .bat.
    #    Die .bat loeschte frueher ALLE Versionen auf einen Schlag und schrieb die neue neu.
    #    Lief dabei eine Sitzung, starben deren Hooks lautlos (ihr CLAUDE_PLUGIN_ROOT zeigte
    #    auf das geloeschte Verzeichnis). Hier wird stattdessen GEZIELT geraeumt:
    #      - die neue Version:                    nie
    #      - jede vor <= PROTECT_HOURS abgeloeste: nie (darauf zeigt eine laufende Sitzung)
    #      - die KEEP_VERSIONS hoechsten:         nie
    #      - was nicht wie eine Version aussieht: nie (Fremdinhalt, den wir nicht kennen)
    #      - alles andere:                        weg
    #    Zwei Abbruchbedingungen VOR dem ersten Loeschen (beide melden und kehren zurueck):
    #      - Vorgaengerversion nicht bestimmbar   -> gar nicht aufraeumen
    #      - plugin_root nicht dort, wo es sein soll (".." in `ver`) -> gar nicht aufraeumen
    #
    # ⛔ ZWEI FEHLER, beide am 19.08.2026 gemessen und mit repro_sync.py reproduziert.
    #    Sie sind UNABHAENGIG - jeder allein reicht, um die laufende Sitzung zu toeten:
    #
    #    (a) `protect = {ver, prev_ver}` hielt genau EINEN Durchlauf. Der erste Lauf schreibt
    #        die neue Version in installed_plugins.json; ab dem zweiten liest `prev_ver`
    #        deshalb die NEUE Version statt der abgeloesten. Ein Schutz, der von einem Zustand
    #        abhaengt, den der geschuetzte Vorgang selbst veraendert, haelt einen Durchlauf -
    #        und sieht dabei die ganze Zeit richtig aus. Deshalb steht der Schutz jetzt in
    #        einer eigenen Datei AUSSERHALB des Zustands, den dieser Lauf anfasst.
    #    (b) Sortierung nach mtime statt nach Versionsnummer. mtime sagt, wann kopiert wurde.
    #        5.3.0 war zufaellig juenger als 5.3.1 und ueberlebte an deren Stelle.
    #
    #    Gemessen (echte Ausgabe, vorher):  1. Lauf kept: 5.4.0, 5.3.0, 5.3.1
    #                                       2. Lauf kept: 5.4.0, 5.3.0   removed: 5.3.1  <-- Sitzung
    try:
        # ⛔ NICHT aufraeumen, wenn unbekannt ist WAS registriert war. `prev_ver` bleibt None,
        #    wenn installed_plugins.json fehlt, unlesbar ist oder das Plugin nicht enthaelt -
        #    dann weiss dieser Lauf nicht, auf welche Version eine offene Sitzung zeigt.
        #    Nichts loeschen kostet Plattenplatz; falsch loeschen kostet die Hooks.
        if prev_ver is None:
            print("  [sync] prune uebersprungen: Vorgaengerversion nicht bestimmbar "
                  "(installed_plugins.json fehlt/unlesbar/kein Eintrag)")
            return 0

        plugin_root = os.path.normpath(os.path.dirname(cache_ver))
        # Containment: plugin_root MUSS unter <plugins>/cache/<mkt>/<plugin> liegen. Ohne das
        # kann ein `ver` mit ".." aus argv den Aufraeumer eine Ebene hoeher setzen - dirname()
        # ist rein textuell, os.listdir() loest die ".." danach wirklich auf.
        erwartet = os.path.normpath(os.path.join(plugins, "cache", mkt, plugin))
        if os.path.normcase(plugin_root) != os.path.normcase(erwartet):
            print("  [sync] prune uebersprungen: unerwartetes Verzeichnis " + plugin_root)
            return 0
        pfile = os.path.join(plugin_root, PROTECT_FILE)

        # --- Schutzliste laden (fehlertolerant: lieber zu viel schuetzen als zu wenig) ---
        prot = {}
        if os.path.isfile(pfile):
            try:
                geladen = json.load(open(pfile, encoding="utf-8"))
                if isinstance(geladen, dict):
                    prot = {k: v for k, v in geladen.items() if isinstance(v, (int, float))}
                else:
                    # Gueltiges JSON, aber kein Objekt -> lief vorher STILL ins Leere und
                    # loeschte bei jedem Lauf alle Schutzeintraege.
                    print("  [sync] WARN protect-file ist kein Objekt ("
                          + type(geladen).__name__ + ") - Schutzliste wird neu aufgebaut")
            except Exception as ex:
                print("  [sync] WARN protect-file unlesbar, wird neu angelegt: " + str(ex))

        jetzt = time.time()
        prot.pop(ver, None)                      # die aktive Version braucht keinen Ablauf
        if prev_ver and prev_ver != ver:
            # Nur setzen, wenn noch nicht vorhanden - sonst stellt jeder Lauf die Uhr neu
            # und der Eintrag altert nie. Genau so entsteht ein Schutz, der ewig haelt.
            prot.setdefault(prev_ver, jetzt)
        grenze = PROTECT_HOURS * 3600
        abgelaufen = [k for k, t in prot.items() if jetzt - t > grenze]
        for k in abgelaufen:
            prot.pop(k, None)

        alle = [x for x in os.listdir(plugin_root)
                if os.path.isdir(os.path.join(plugin_root, x))]
        fremd = [x for x in alle if not _sieht_aus_wie_version(x)]
        dirs = [x for x in alle if _sieht_aus_wie_version(x)]
        dirs.sort(key=_vkey, reverse=True)       # (b): Versionsnummer, nicht mtime

        # Vergleich case-INsensitiv: Windows-Pfade sind es, Python-Mengen nicht. Wird ein
        # Verzeichnis als "5.4.0-Beta" angelegt und "5.4.0-beta" uebergeben (beide Schritte
        # von Hand), erkennt ein case-sensitiver Vergleich die AKTIVE Version nicht als
        # geschuetzt und loescht sie.
        protect = set([ver]) | set(prot.keys())  # (a): aus der Datei, nicht aus dem Zustand
        keep_cf = {x.casefold() for x in list(dirs[:KEEP_VERSIONS]) + list(protect)}
        removed = []
        for x in dirs:
            if x.casefold() in keep_cf:
                continue
            voll = os.path.join(plugin_root, x)
            try:
                # Junction/Symlink nie durchlaufen. Gemessen: shutil.rmtree wirft hier
                # ohnehin OSError statt in das Ziel zu rekursieren - der Befund war insofern
                # entwarnt. Der Vorabtest macht aus dem Fehlerfall eine klare Meldung.
                if os.path.islink(voll) or os.path.ismount(voll):
                    print("  [sync] uebersprungen (Verweis, kein echtes Verzeichnis): " + x)
                    continue
                shutil.rmtree(voll)
                removed.append(x)
            except Exception as ex:
                print("  [sync] WARN prune " + x + ": " + str(ex))

        # Schutzliste zurueckschreiben - MIT Merge gegen den Stand auf Platte.
        # _atomic_write macht nur das Schreiben atomar, nicht den Lese-Aendere-Schreibe-Zyklus.
        # Laufen zwei Sync-Aufrufe ueberlappend, wuerde ein blindes Ueberschreiben den frisch
        # gesetzten Schutzeintrag des anderen Laufs verwerfen. Der Merge nimmt beim selben
        # Schluessel den AELTEREN Zeitstempel - der laeuft frueher ab und horten tut niemand.
        vorhanden = {x.casefold(): x for x in set(dirs) - set(removed)}
        prot = {k: v for k, v in prot.items() if k.casefold() in vorhanden}
        try:
            if os.path.isfile(pfile):
                try:
                    # ⛔ NICHT `fremd` nennen - das ist oben die Liste der Nicht-Versions-
                    #    Verzeichnisse. Die Kollision liess den Inhalt der Schutzdatei als
                    #    "nicht angefasst (keine Versionsnamen)" erscheinen (19.08.2026).
                    auf_platte = json.load(open(pfile, encoding="utf-8"))
                    if isinstance(auf_platte, dict):
                        for k, v in auf_platte.items():
                            if isinstance(v, (int, float)) and k.casefold() in vorhanden:
                                prot[k] = min(prot[k], v) if k in prot else v
                except Exception:
                    pass
            _atomic_write(pfile, json.dumps(prot, indent=2))
        except Exception as ex:
            print("  [sync] WARN protect-file nicht schreibbar: " + str(ex))

        kept = [x for x in dirs if x.casefold() in keep_cf]
        zeile = "  [sync] versions kept: " + ", ".join(kept)
        zeile += ("  removed: " + ", ".join(removed)) if removed else "  removed: none"
        if prot:
            zeile += "  (geschuetzt bis " + str(PROTECT_HOURS) + "h: " + ", ".join(sorted(prot)) + ")"
        print(zeile)
        if fremd:
            print("  [sync] nicht angefasst (keine Versionsnamen): " + ", ".join(sorted(fremd)))
    except Exception as ex:
        print("  [sync] WARN prune: " + str(ex))

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as ex:   # never break the .bat
        print("  [sync] WARN: " + str(ex))
        sys.exit(0)
