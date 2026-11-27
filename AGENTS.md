
# AGENTS.md – Projektrichtlinien für SaphirPlayer

## 1. Projektvision & Zielbild
**SaphirPlayer** ist ein lokaler, serverloser Streaming-Videoplayer im Stil moderner Streaming-Dienste (Netflix, Disney+, Apple TV+) für eigene Serien und Filme auf einem NAS.
- **Kein 24/7-Server:** Alle Medien bleiben unverändert auf dem NAS (SMB / Netzlaufwerk / UNC-Pfad). Die App arbeitet mit einem lokalen SQLite-Index (`sqlite3`) und einem dateibasierten Multi-Geräte-Sync (`progress_sync.json`).
- **Portabler Betrieb:** Wenn neben der `.exe` eine `portable.flag` oder ein `data/`-Ordner liegt, werden Datenbank, Einstellungen, Thumbnail-Cache und Screenshots relativ zum Programmordner gespeichert (lauffähig direkt aus einem NAS-Ordner).
- **Ziel-Hardware:** Läuft sowohl auf leistungsstarken Windows-11-Laptops als auch ruckelfrei auf einem Windows-11-Tablet-Laptop mit **4 GB RAM** (und bleibt perspektivisch kompatibel mit Android).

---

## 2. Verpflichtende Architektur- & Code-Regeln
Jeder Agent muss diese Regeln strikt einhalten:

1. **Strikte Trennung von UI und Logik:**
   - UI-Dateien (`*_view.dart`, Widgets) enthalten **ausschließlich deklarativen Layout-Code**.
   - Berechnungen, Dateisystem-Scans, SQLite-Abfragen, Formatierungen, Timer, Plattform-Aufrufe (`window_manager`, `file_picker`), State-Änderungen und Validierungen gehören ausnahmslos in Controller (`*_controller.dart`), Services (`*_service.dart`, `*_bridge.dart`) oder `Formatters`.
2. **Keine Inline-Werte im UI-Code:**
   - Alle Strings, Magic Numbers, Abstände (Paddings/Margins), Radien, Größen, Schwellenwerte, Timer-Dauern und Farben müssen in dedizierten Token-Dateien unter `lib/core/constants/` (`AppColors`, `AppSpacing`, `AppStrings`) oder im Theme (`AppTheme`) definiert werden.
3. **Kapselung nativer `libmpv`- & Plattform-Zugriffe:**
   - Sämtliche direkten `NativePlayer`-Property- und Command-Aufrufe (`setProperty`, `getProperty`, `command` für Audio-Filter, Delay, Aspect-Ratio, Untertitel-Styling, Kapitel, Frame-Stepping, Diagnose) müssen über das injizierbare Interface `IMpvPropertyBridge` / `MpvPropertyBridge` laufen.
   - Kein direkter Zugriff auf `NativePlayer`, `window_manager` oder `file_picker` aus UI-Widgets oder direkt ungekapselt im Controller – damit bleiben alle Tests mit `MockPlayer` und `MockMpvPropertyBridge` ohne native DLLs ausführbar.
4. **Datenbank-Migrationen & Schema-Hygiene:**
   - Schema-Erweiterungen erfolgen ausschließlich über `PRAGMA user_version` und eine idempotente Migrationsmethode in `DatabaseService` (z. B. `v1 -> v2` für `series_preferences.intro_skip_seconds` und `media_bookmarks`), ohne Bestandsdaten zu verlieren.
   - Jede neue Tabelle muss ebenfalls in `DatabaseService.resetDatabase()` berücksichtigt werden.
5. **Anti-Halluzinations-Regel:**
   - Erfinde keine Hilfsfunktionen, Klassen, Methoden, SQL-Spalten, JSON-Felder, Packages, UI-Tokens (`AppColors`, `AppSpacing`, `AppStrings`) oder Konstanten, die nicht nachweislich im Projekt existieren oder in der aktuellen Aufgabe sauber eingeführt werden.
   - Wenn dir zur Bewertung einer Abhängigkeit, eines Imports, eines Datenbankschemas oder eines Widgets der Inhalt einer Datei (z. B. `lib/core/storage/database_service.dart`, `lib/features/shell/shell_view.dart` oder `pubspec.yaml`) fehlt, stoppe und fordere genau diese Datei an, statt zu raten.
6. **Code-Ausgabe & Snippets:**
   - Niemals Platzhalter-Kommentare wie `// ... rest of code ...` einfügen.
   - Änderungen an bestehenden Dateien immer vollständig oder in klar getrennten, kopierbaren Codeblöcken pro Datei liefern und über jedem Codeblock angeben, um welche Datei es sich handelt und ob es eine neue oder aktualisierte Datei ist.
7. **Assets & Icons:**
   - In `pubspec.yaml` unter `flutter:` muss zwingend `uses-material-design: true` gesetzt sein, damit Icons unter Windows korrekt gerendert werden (keine Platzhalter-Rechtecke).

---

## 3. UI- & Design-Richtlinien (Streaming-Ästhetik)
Die Oberfläche soll hochwertig, aufgeräumt und sofort als moderner Video-Streaming-Client erkennbar sein:
- **Farbwelt:** Tiefes OLED-Schwarz (`#080A0F`) als Basis, dunkles Anthrazit (`#10141D`) für Karten/Leisten und **Saphirblau** (`#1D6FE5` / `#4B9BFF`) für Fokus-Rahmen, Fortschrittsbalken, Lesezeichen-Marker und primäre Aktionen.
- **Inhalte im Fokus:** Große 16:9-Vorschaubilder (Episoden-Thumbs) und Poster-Karten mit weichen Farbverläufen, klaren Typografie-Hierarchien und sichtbaren Fortschrittsbalken. Keine technischen Rohdaten oder Debug-Texte auf der Startseite.
- **Umschaltbarer Effekt-Modus (`EffectMode`):**
  - `EffectMode.glass`: Dezente Unschärfe (`BackdropFilter`), weiche Hover-Skalierung, sanfte Einblendungen und Glow-Rahmen.
  - `EffectMode.lean`: Optimiert für 4 GB RAM – kein Echtzeit-Blur, kein Animations-Overhead, halbtransparente dunkle Flächen mit klaren Konturen.
  - Alle neuen In-Player-Overlays (Episoden-Drawer, Action-OSD, Intro-Skip-Button, Seekbar-Hover-Tooltip, Diagnose-Overlay, Shortcut-Cheat-Sheet) müssen zwingend `SurfacePanel` verwenden, damit `glass` und `lean` überall konsistent greifen.
  - Dieser Modus muss in den Einstellungen umschaltbar und pro Gerät (`DesktopPlatformService.localHostname`) speicherbar sein.
- **Moderne Navigation:** Schlanke, integrierte Fensterleiste (`WindowTitleBar` ohne System-Rahmen inkl. globaler Suche) und eine kompakte Seitenleiste (`NavigationSidebar`) für Start, Bibliothek, Statistiken und Einstellungen.

---

## 4. Kernfunktionen & Bedienkonzept
- **Startseite (Home-Hub) & Bibliothek:**
  - Hero-Banner oben (Hintergrundbild/Verlauf, Titel, aktuelle Episode, Fortschritt, „Fortsetzen“-Button, Zufallsvorschlag).
  - Horizontale Karussells (`MediaRail`): *Weiterschauen*, *Zuletzt hinzugefügt*, *Schon lange nicht mehr gesehen* (> 60 Tage), *Serien* und *Filme*.
  - Bibliothek mit Typ-Filter (*Alle / Serien / Filme*) und globaler Live-Suche.
- **Serien-Detailansicht & Statistiken:**
  - Kopfbereich mit Banner/Poster, Serienbeschreibung (`tvshow.nfo` / `info.json`), Gesamtfortschritt, Staffel-Tabs und Episodenliste mit 16:9-Vorschaubildern, Laufzeit, Fortschrittsbalken und „Gesehen“-Toggle.
  - Statistik-Ansicht mit Watchtime (Serien vs. Filme), aktivstem Tag/Wochentag, Watch-Streak und Top-Listen.
- **Globale Einstellungen (`SettingsController` / `SettingsView`):**
  - Medienquellen (Multi-Ordner SMB/UNC & lokal), Effekt-Modus (global oder pro Gerät), Cache- & Sync-Verwaltung.
  - **Untertitel & Sprache:** Global umschaltbar, ob Untertitel standardmäßig an oder aus sind, bevorzugte Sprache (z. B. `de`, `en`, `auto`) sowie globales Untertitel-Styling (Schriftgröße, vertikale Position, Hintergrund-Kontrast).
  - **Spur-Priorität:** Gespeicherte Serien-Präferenzen (`series_preferences`) haben stets Vorrang vor den globalen Untertitel-Defaults.
  - **Hardware-Dekodierung:** Pro Gerät (`hwdec_<localHostname>`) umschaltbar zwischen Hardware- und Software-Dekodierung.
- **Videoplayer (`media_kit` / `libmpv`):**
  - Auto-Hide für Mauszeiger und HUD nach 2 Sekunden Inaktivität; kompaktes **Action-OSD** für Kurzaktionen (Lautstärke, Seek, Speed, Screenshot, Lesezeichen, Aspect-Mode), ohne das gesamte HUD aufzureißen.
  - **Audio, Video & Untertitel:** Nachtmodus (Audio-Normalisierung via `dynaudnorm`), Lautstärke-Boost bis 150 %, Seitenverhältnis/Crop/Ultrawide-Zoom (`Original`, `Füllen/Crop`, `16:9`, `21:9`), Live-Sync (`audio-delay`, `sub-delay`), externes Untertitel-Nachladen (`.srt`/`.ass`/`.vtt`), Live-Diagnose-Overlay („Stats for Nerds“).
  - **Navigation, Seekbar & Komfort:** Seekbar-Hover-Zeitanzeige (inkl. Kapitelname), MKV-Kapitel-Marker, Szenen-Lesezeichen (`media_bookmarks`), 1-Klick-Screenshot, konfigurierbarer „Intro überspringen“-Button (pro Serie speicherbar), Restlaufzeit-/Endzeit-Toggle („Fertig um HH:MM“ inkl. `playbackSpeed`), In-Player Episoden-Drawer, Always-on-Top Mini-Player (PiP mit Fenster-Bounds-Wiederherstellung) und Sleep-Timer (*Nach dieser Folge*, *30 Min.*, *60 Min.*).
  - **Tastatur & Maus:**
    - `Leertaste`: Play / Pause
    - `Pfeil links / rechts`: ±10 Sek. (`Shift + Pfeil links / rechts`: ±60 Sek.)
    - `Pfeil hoch / runter` & `Mausrad`: Lautstärke regeln
    - `F` / `Doppelklick`: Vollbild an/aus
    - `M`: Stummschalten
    - `N` / `P` & **X-Maustasten** (`kForwardMouseButton` / `kBackMouseButton`): Nächste / vorherige Folge
    - `.` / `,`: Einzelbild vorwärts / rückwärts (`frame-step` / `frame-back-step`)
    - `A`: Seitenverhältnis/Zoom umschalten
    - `B`: Lesezeichen an aktueller Position setzen
    - `S`: 1-Klick-Screenshot speichern
    - `E`: In-Player Episoden-Drawer umschalten
    - `I`: Diagnose-Overlay („Stats for Nerds“) umschalten
    - `?` (oder `H`): Shortcut-Cheat-Sheet umschalten
    - `Esc`: Schließt zuerst offene Overlays, danach den Player
  - **Automatisierung:** Fortschritt alle 5 Sekunden speichern, ab 92 % Laufzeit als „Gesehen“ werten, Auto-Next-Karte mit Countdown (deaktiviert bei aktivem „Nach dieser Folge“-Sleep-Timer), Audio-/Untertitelspur und Intro-Skip pro Serie merken.

---

## 5. Performance- & 4-GB-RAM-Schutzregeln
- **Hintergrund-Isolates:** Dateisystem-Scans laufen in einem separaten Isolate (`Isolate.run`), damit die UI nie einfriert.
- **Scan-Pause bei Wiedergabe:** Sobald ein Video startet, pausieren NAS-Scans und Thumbnail-Generierung sofort.
- **Bild-Cache:** Thumbnails werden auf maximal `320x180 px` skaliert im Cache abgelegt und beim Rendern mit `cacheWidth` / `cacheHeight` begrenzt.
- **Timer-Disziplin:** Keine dauerhaft laufenden Polling-Timer bei geschlossenen Overlays. Der Diagnose-Timer („Stats for Nerds“) läuft ausschließlich bei geöffnetem Overlay und wird beim Schließen sowie in `stopAndClose()` / `dispose()` sofort beendet.
- **Leichtgewichtiges Rendering:** Kapitel- und Lesezeichen-Marker auf der Seekbar werden per `CustomPainter` statt über dynamische Widget-Bäume gezeichnet.

---

## 6. Verzeichnisstruktur
```
lib/
├── main.dart
├── core/
│   ├── constants/      # AppColors, AppSpacing, AppStrings
│   ├── controllers/    # LibraryController, SettingsController
│   ├── services/       # DesktopPlatformService, LocalFileService
│   ├── storage/        # PortablePaths, DatabaseService, ProgressSyncService
│   ├── theme/          # AppTheme, EffectMode
│   └── utils/          # Formatters
├── features/
│   ├── home/           # HomeController, HomeView, widgets/ (MediaRail)
│   ├── library/        # LibraryModels, LibraryView, MetadataReader, SeriesDetailView, widgets/ (EpisodeRow)
│   ├── player/         # PlayerModels, PlaybackSession, PlaybackPersistenceService, MpvPropertyBridge,
│   │                   # SaphirPlayerController, SaphirPlayerView, widgets/ (HUD, SeekBar, TrackMenus,
│   │                   # AutoNextCard, IntroSkipButton, ActionOsd, EpisodeDrawer, DiagnosticsOverlay, ShortcutSheet)
│   ├── scanner/        # MediaParser, NasScanRepository, NasScannerService, ThumbnailGeneratorService
│   ├── shell/          # ShellController, ShellView, widgets/ (NavigationSidebar, SettingsView)
│   └── stats/          # StatsController, StatsModels, StatsView, widgets/ (StatsCards)
└── widgets/            # WindowTitleBar, SurfacePanel, MediaTile

test/
├── architecture/       # Automatisierte Architektur-, Token- & Layer-Trennungs-Tests
├── controllers/        # Controller-Tests
├── database/           # Schema-, Migrations-, Constraint-, Last- & Sync-Tests
├── helpers/            # TestEnv, synthetische Fixtures, MockPlayer, MockMpvPropertyBridge
├── integration/        # End-to-End User-Flow-Tests
├── media/              # Import-Pipeline-, Thumbnail- & Player-Controller-Tests
├── scanner/            # Parser- & Metadaten-Tests
├── storage/            # DB- & Sync-Tests
├── ui/                 # UI-Interaktionstests
├── unit/               # Erweiterte Controller-, Formatierer-, Bridge- & Model-Unit-Tests
└── widget/             # Player-UI-, Overlay-, Shortcut- & Responsive-Tests (inkl. 480×270 PiP & 390×844)

```

---

## 7. Arbeitsweise & Strukturierter Prüfbericht für Coding-Agents

* Vor Änderungen bestehende Dateien prüfen, fehlende Dateien anfordern statt zu raten und keinen bestehenden Code unabsichtlich löschen.
* Nach jeder abgeschlossenen Phase bzw. Code-Änderung zwingend `flutter analyze --no-pub` (0 Fehler/Warnungen) und `flutter test` (inkl. `test/architecture/`) ausführen und verifizieren.
* Änderungen in kleinen, logischen Schritten umsetzen und bestehende Token-Klassen (`AppColors`, `AppSpacing`, `AppStrings`) konsequent erweitern statt neue Konstanten oder Strings in Widgets zu verstreuen.
* **Strukturierter Prüfbericht:** Dokumentiere das Ergebnis deiner Kontrolle nach Code-Änderungen zwingend in dieser Reihenfolge:
1. **Kritische Bugs & Sicherheitslücken** (inkl. Dateiname & Zeilenbereich)
2. **Toter Code & Redundanzen** (ungenutzte Variablen, Methoden, Konstanten oder Regeln)
3. **Durchgeführte Korrekturen** (kurze Begründung pro Änderung)
4. **Offene Risiken außerhalb des Scopes** (nur Meldung, keine Änderung)
