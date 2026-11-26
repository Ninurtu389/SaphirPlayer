---
trigger: always_on
---

# Git & Commit-Richtlinien für SaphirPlayer

Halte dich bei allen Git-Operationen in **SaphirPlayer** strikt an folgende Regeln:

1. **Keine automatischen Commits während der Arbeit:** Führe niemals selbstständig `git commit` oder `git push` aus, während du Code, UI-Tokens, Scanner, Player oder Sync-Logik bearbeitest oder umbaust. Warte immer, bis der jeweilige Meilenstein bzw. die Aufgabe abgeschlossen ist und ausdrücklich dazu aufgefordert wird.
2. **Format für Commit-Nachrichten (Conventional Commits):**
   - Verwende ein englisches Typ-Präfix (`feat:`, `fix:`, `refactor:`, `ui:`, `docs:`, `chore:`, `perf:`, `test:`), optional mit Bereich in Klammern (z. B. `feat(player):`, `ui(home):`, `fix(scanner):`, `chore(portable):`).
   - Schreibe die Beschreibung dahinter auf **Deutsch** im Imperativ (z. B. `feat(player): X-Maustasten fuer Folgenwechsel ergaenzt`).
   - Halte die erste Zeile unter 70 Zeichen und setze keinen Punkt ans Ende.
   - Ergänze bei größeren Änderungen nach einer Leerzeile eine kurze Stichpunktliste mit den wichtigsten Details.
3. **Schutz portabler und lokaler Artefakte:**
   - Achte darauf, dass lokale Datenbanken (`data/`), Thumbnail-Caches (`cache/`), `portable.flag`, `progress_sync.json` und Flutter-Build-Ordner (`build/`, `.dart_tool/`) nicht versehentlich committet werden.
4. **Freigabe vor dem Upload (`git push`):**
   - Führe `git push` **niemals** ohne ausdrückliche Bestätigung aus.
   - Wenn um einen Commit gebeten wird, schlage zuerst die genaue Commit-Nachricht vor (oder erstelle nur den lokalen Commit) und frage anschließend aktiv, ob der Stand jetzt auf GitHub gepusht werden soll.