---
description: Prüft den Flutter-Build und die Analyse für SaphirPlayer, kontrolliert Git-Änderungen und bereitet einen sauberen Conventional Commit auf Deutsch vor.
---

Führe die folgenden Schritte der Reihe nach aus:

1. **Analyse & Build-Prüfung (Flutter / Windows):**
   - Führe im Projektverzeichnis von **SaphirPlayer** `flutter analyze` und (falls vorhanden) `flutter test` aus.
   - **Abbruchbedingung:** Falls `flutter analyze` Fehler oder Warnungen meldet oder Tests fehlschlagen, brich den Workflow sofort ab, zeige die Meldungen an und erstelle **keinen** Commit.

2. **Änderungen, Portabilität & Sicherheit prüfen:**
   - Führe `git status` und `git diff` aus, um alle geänderten und neuen Dateien zu erfassen.
   - Prüfe, ob versehentlich lokale Datenbankdateien (`data/`), Cache-Dateien (`cache/`), `portable.flag`, `progress_sync.json`, sensible Zugangsdaten oder Build-Artefakte (`build/`) zur Aufnahme bereitstehen. Falls ja, warne sofort und schlage eine Ergänzung für die `.gitignore` vor.
   - Prüfe kurz, ob die Regeln aus `AGENTS.md` (Trennung von UI und Logik, keine Inline-Strings/Magic-Numbers im UI-Code) eingehalten wurden.

3. **Commit-Nachricht formulieren & lokal committen:**
   - Erstelle eine prägnante Commit-Nachricht nach dem **Conventional Commits**-Schema (englisches Präfix wie `feat:`, `fix:`, `refactor:`, `ui:`, `docs:`, `chore:`, `perf:` + deutsche Beschreibung im Imperativ unter 70 Zeichen, ohne Punkt am Ende).
   - Stage die sauberen Änderungen mit `git add` und erstelle den lokalen Commit mit `git commit -m "..."`.

4. **Abschluss & Push-Abfrage:**
   - Zeige die verwendete Commit-Nachricht und die betroffenen Dateien kurz an.
   - Führe `git push` **nicht** automatisch aus, sondern frage am Ende ausdrücklich, ob dieser Stand jetzt auf GitHub hochgeladen werden soll.