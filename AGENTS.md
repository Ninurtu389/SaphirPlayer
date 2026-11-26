# AGENTS.md – Projektrichtlinien für SaphirPlayer

## 1. Projektvision & Zielbild
**SaphirPlayer** ist ein lokaler, serverloser Streaming-Videoplayer im Stil moderner Streaming-Dienste (Netflix, Disney+, Apple TV+) für eigene Serien und Filme auf einem NAS.
- **Kein 24/7-Server:** Alle Medien bleiben unverändert auf dem NAS (SMB / Netzlaufwerk / UNC-Pfad). Die App arbeitet mit einem lokalen SQLite-Index und einem dateibasierten Multi-Geräte-Sync (`progress_sync.json`).
- **Portabler Betrieb:** Wenn neben der `.exe` eine `portable.flag` oder ein `data/`-Ordner liegt, werden Datenbank, Einstellungen und Thumbnail-Cache relativ zum Programmordner gespeichert (lauffähig direkt aus einem NAS-Ordner).
- **Ziel-Hardware:** Läuft sowohl auf leistungsstarken Windows-11-Laptops als auch ruckelfrei auf einem Windows-11-Tablet-Laptop mit **4 GB RAM** (und bleibt perspektivisch kompatibel mit Android).

---

## 2. Verpflichtende Architektur- & Code-Regeln
Jeder Agent muss diese Regeln strikt einhalten:

1. **Strikte Trennung von UI und Logik:**
   - UI-Dateien (`*_view.dart`, Widgets) enthalten **ausschließlich deklarativen Layout-Code**.
   - Berechnungen, Dateisystem-Scans, SQLite-Abfragen, State-Änderungen und Validierungen gehören ausnahmslos in Controller (`*_controller.dart`) oder Services (`*_service.dart`).
2. **Keine Inline-Werte im UI-Code:**
   - Alle Strings, Magic Numbers, Abstände (Paddings/Margins), Radien, Größen, Schwellenwerte und Farben müssen in dedizierten Token-Dateien unter `lib/core/constants/` (`AppColors`, `AppSpacing`, `AppStrings`) oder im Theme (`AppTheme`) definiert werden.
3. **Anti-Halluzinations-Regel:**
   - Erfinde keine Hilfsfunktionen, Klassen, Methoden, SQL-Spalten, JSON-Felder, Packages, UI-Tokens (`AppColors`, `AppSpacing`, `AppStrings`) oder Konstanten, die nicht nachweislich im Projekt existieren oder in der aktuellen Aufgabe sauber eingeführt werden.
   - Wenn dir zur Bewertung einer Abhängigkeit, eines Imports, eines Datenbankschemas oder eines Widgets der Inhalt einer Datei (z. B. `lib/core/storage/database_service.dart`, `lib/features/shell/shell_view.dart` oder `pubspec.yaml`) fehlt, stoppe und fordere genau diese Datei an, statt zu raten.
4. **Code-Ausgabe & Snippets:**
   - Niemals Platzhalter-Kommentare wie `// ... rest of code ...` einfügen.
   - Änderungen an bestehenden Dateien immer vollständig oder in klar getrennten, kopierbaren Codeblöcken pro Datei liefern und über jedem Codeblock angeben, um welche Datei es sich handelt und ob es eine neue oder aktualisierte Datei ist.
5. **Assets & Icons:**
   - In `pubspec.yaml` unter `flutter:` muss zwingend `uses-material-design: true` gesetzt sein, damit Icons unter Windows korrekt gerendert werden (keine Platzhalter-Rechtecke).

---

## 3. UI- & Design-Richtlinien (Streaming-Ästhetik)
Die Oberfläche soll hochwertig, aufgeräumt und sofort als moderner Video-Streaming-Client erkennbar sein:
- **Farbwelt:** Tiefes OLED-Schwarz (`#070A0F`) als Basis, dunkles Anthrazit (`#101622`) für Karten/Leisten und **Saphirblau** (`#1D6FE5` / `#4B9BFF`) für Fokus-Rahmen, Fortschrittsbalken und primäre Aktionen.
- **Inhalte im Fokus:** Große 16:9-Vorschaubilder (Episoden-Thumbs) und Poster-Karten mit weichen Farbverläufen, klaren Typografie-Hierarchien und sichtbaren Fortschrittsbalken. Keine technischen Rohdaten oder Debug-Texte auf der Startseite.
- **Umschaltbarer Effekt-Modus (`EffectMode`):**
  - `EffectMode.glass`: Dezente Unschärfe (`BackdropFilter`), weiche Hover-Skalierung, sanfte Einblendungen und Glow-Rahmen.
  - `EffectMode.lean`: Optimiert für 4 GB RAM – kein Echtzeit-Blur, kein Animations-Overhead, halbtransparente dunkle Flächen mit klaren Konturen.
  - Dieser Modus muss in den Einstellungen umschaltbar und pro Gerät (`Platform.localHostname`) speicherbar sein.
- **Moderne Navigation:** Schlanke, integrierte Fensterleiste (`WindowTitleBar` ohne System-Rahmen) und eine kompakte Navigation mit klaren Icons und Beschriftungen.

---

## 4. Kernfunktionen & Bedienkonzept
- **Startseite (Home-Hub):**
  - Hero-Banner oben (mit Hintergrundbild/Verlauf, Serientitel, aktueller Episode, Fortschritt und direktem „Fortsetzen“-Button).
  - Horizontale Karussells („Rails“): *Weiterschauen*, *Schon lange nicht mehr gesehen* (konfigurierbar, Standard > 60 Tage) und *Zuletzt hinzugefügt*.
  - Live-Suche und Zufalls-Button („Was soll ich schauen?“).
- **Serien-Detailansicht:**
  - Kopfbereich mit Banner/Poster, Serienbeschreibung (`.nfo` / `info.json`), Gesamtfortschritt, Staffel-Auswahl und Episodenliste mit 16:9-Vorschaubildern, Laufzeit, Fortschrittsbalken und „Gesehen“-Toggle.
- **Videoplayer (`media_kit` / `libmpv`):**
  - Hardware-Dekodierung (`enableHardwareAcceleration: true`) aktiv.
  - Auto-Hide für Mauszeiger und HUD nach 2 Sekunden Inaktivität.
  - **Tastatur & Maus:**
    - `Leertaste`: Play / Pause
    - `Pfeil links / rechts`: 10 Sekunden vor / zurück
    - **X-Maustasten (4. & 5. Maustaste / Daumentasten):** `kForwardMouseButton` = nächste Folge, `kBackMouseButton` = vorherige Folge (System-Zurück-Navigation muss abgefangen werden)
    - `Doppelklick`: Vollbild an/aus
    - `Mausrad`: Lautstärke regeln
  - **Automatisierung:** Fortschritt alle 5 Sekunden speichern, ab 92 % Laufzeit als „Gesehen“ werten, Auto-Next-Karte mit Countdown vor Episodenende einblenden und Audio-/Untertitelspur pro Serie merken.

---

## 5. Performance- & 4-GB-RAM-Schutzregeln
- **Hintergrund-Isolates:** Dateisystem-Scans laufen in einem separaten Isolate (`Isolate.run`), damit die UI nie einfriert.
- **Scan-Pause bei Wiedergabe:** Sobald ein Video startet, pausieren NAS-Scans und Thumbnail-Generierung sofort.
- **Bild-Cache:** Thumbnails werden auf maximal `320x180 px` skaliert im Cache abgelegt und beim Rendern mit `cacheWidth` / `cacheHeight` begrenzt.

---

## 6. Verzeichnisstruktur
```text
lib/
├── main.dart
├── core/
│   ├── constants/      # AppColors, AppSpacing, AppStrings
│   ├── controllers/    # LibraryController, SettingsController
│   ├── storage/        # PortablePaths, DatabaseService, ProgressSyncService
│   └── theme/          # AppTheme, EffectMode
├── features/
│   ├── home/           # HomeController, HomeView
│   ├── library/        # LibraryModels, MetadataReader, SeriesDetailView
│   ├── player/         # PlaybackSession, SaphirPlayerController, SaphirPlayerView
│   ├── scanner/        # MediaParser, NasScannerService, ThumbnailGeneratorService
│   └── shell/          # ShellController, ShellView
└── widgets/            # WindowTitleBar, SurfacePanel, MediaTile
```

7. Arbeitsweise & Strukturierter Prüfbericht für Coding-Agents
- Vor Änderungen bestehende Dateien prüfen, fehlende Dateien anfordern statt zu raten und keinen bestehenden Code unabsichtlich löschen.
- Nach jeder Änderung flutter analyze ausführen und sicherstellen, dass keine Fehler oder Warnungen verbleiben.
- Änderungen in kleinen, logischen Schritten umsetzen und bestehende Token-Klassen (AppColors, AppSpacing, AppStrings) konsequent erweitern statt neue Konstanten oder Strings in Widgets zu verstreuen.
- Strukturierter Prüfbericht: Dokumentiere das Ergebnis deiner Kontrolle nach Code-Änderungen zwingend in dieser Reihenfolge:
- Kritische Bugs & Sicherheitslücken (inkl. Dateiname & Zeilenbereich)
- Toter Code & Redundanzen (ungenutzte Variablen, Methoden, Konstanten oder Regeln)
- Durchgeführte Korrekturen (kurze Begründung pro Änderung)
- Offene Risiken außerhalb des Scopes (nur Meldung, keine Änderung)

