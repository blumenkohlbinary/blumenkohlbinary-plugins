# CLAUDE.md — zweite Bewertungsrubrik (Anthropic)

Quelle: `claude-md-management` (Anthropic-offiziell), Dateien `quality-criteria.md` und
`update-guidelines.md`.

⚠ **Das ist NICHT dieselbe Rubrik wie `quality-scoring-guide.md`.** Beide vergeben 100 Punkte,
gewichten aber anders. **Wer „100 Punkte" sagt, muss dazusagen welche.**

**Belegt, warum beide gefahren werden:** dieselbe Datei ergab **54** (hier) und **67** (eigene
Rubrik); nach dem Umbau **95** und **91**. Dieselben Defekte, andere Gewichte — eine Rubrik
allein haette die Haelfte nicht gefunden.

---

## Die sechs Kategorien

| Kategorie | Punkte | Volle Punktzahl bei |
|---|---|---|
| Commands/Workflows | 20 | Build, Test, Lint, Deploy dokumentiert · Entwicklungs-Workflow klar · uebliche Operationen erfasst |
| Architecture Clarity | 20 | Verzeichnisse erklaert · Modulbeziehungen · Einstiegspunkte · Datenfluss |
| Non-Obvious Patterns | 15 | Gotchas · bekannte Fehler · Workarounds · „warum wir es so machen" |
| Conciseness | 15 | kein Fuellmaterial · jede Zeile traegt · keine Redundanz zu Code-Kommentaren |
| Currency | 15 | Befehle laufen wie dokumentiert · Dateiverweise stimmen · Tech-Stack aktuell |
| Actionability | 15 | Befehle kopierbar · Schritte konkret · Pfade echt |

Abstufung je Kategorie: volle Punktzahl · „meist vorhanden, kleine Luecken" · „Grundlage da" ·
„vage/unvollstaendig" · 0.

⛔ **Diese Rubrik enthaelt KEINE Notenskala.** Das Quelldokument sagt nur „Calculate total and
assign grade" ohne Zuordnung. **Wer daraus eine Note macht, erfindet die Skala.** Am 2026-08-18
wurde so „54 = F" gemeldet — nach der einzigen dokumentierten Skala (`quality-scoring-guide.md`)
waeren 54 ein **C**.

## Bewertungsprozess (5 Schritte)

1. Datei vollstaendig lesen
2. **Gegen die Codebasis pruefen** — Befehle ausfuehren (gedanklich oder echt), Existenz der
   referenzierten Dateien pruefen, Architekturbeschreibung verifizieren
3. Je Kriterium bewerten
4. Summe bilden
5. Konkrete Verbesserungen vorschlagen

## Red Flags

- Befehle, die fehlschlagen wuerden (falsche Pfade, fehlende Abhaengigkeiten)
- Verweise auf geloeschte Dateien oder Ordner
- Veraltete Tech-Versionen
- Unangepasste Template-Kopien
- Generische, nicht projektspezifische Ratschlaege
- Nie erledigte `TODO`s
- **Doppelte Information ueber mehrere Dateien hinweg**

---

# `update-guidelines.md` — was hinzugefuegt wird und was nicht

> **„The context window is precious — every line must earn its place."**

## Was HINZUGEHOERT (5)

1. **Entdeckte Commands/Workflows** — erspart der naechsten Sitzung die Suche
2. **Gotchas und nicht offensichtliche Muster** — verhindert wiederholte Fehlersuche
3. **Package Relationships** — Initialisierungs- und Importreihenfolge, die man dem Code nicht
   ansieht („`auth` braucht initialisiertes `crypto`; Reihenfolge in `src/bootstrap.ts` zaehlt")
4. **Testing Approaches That Worked** — welches Vorgehen sich bewaehrt hat
5. **Configuration Quirks** — umgebungsspezifisch („`NEXT_PUBLIC_*` muss zur Buildzeit gesetzt
   sein, nicht zur Laufzeit")

## Was NICHT (4)

| Anti-Pattern | Warum |
|---|---|
| Offensichtliche Code-Info | Der Klassenname sagt es bereits |
| Generische Best Practices | Universeller Rat, nicht projektspezifisch |
| **One-Off Fixes** | *„We fixed a bug in commit abc123 … Won't recur; clutters the file."* |
| Ausschweifende Erklaerungen | Statt drei Absaetzen ueber JWT: `Auth: JWT mit HS256, Token im Authorization-Header` |

## Diff-Format fuer Aenderungsvorschlaege

Datei benennen → Sektion benennen → Aenderung als `diff`-Block → **„Why this helps"** in einem
Satz. Ohne die Begruendung ist ein Vorschlag nicht bewertbar.

## Validierungs-Checkliste

- [ ] Jede Ergaenzung ist projektspezifisch
- [ ] Kein generischer Rat, keine offensichtliche Info
- [ ] Befehle sind getestet und laufen
- [ ] Dateipfade stimmen
- [ ] **„Would a new Claude session find this helpful?"**
- [ ] **„Is this the most concise way to express the info?"**

Die letzten beiden Fragen stehen in keiner anderen Referenzdatei dieses Plugins.
