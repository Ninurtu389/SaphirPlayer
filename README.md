# SaphirPlayer

**SaphirPlayer** ist ein lokaler, serverloser Streaming-Videoplayer für eigene Serien und Filme auf einem NAS (SMB/UNC-Pfad) oder lokalen Laufwerken – im Stil moderner Streaming-Dienste, optimiert für Windows 11 sowie Geräte mit **4 GB RAM**.

---

## Kernfunktionen

- **Serverloser NAS- & Lokal-Betrieb:** Alle Mediendateien bleiben unverändert auf dem NAS oder lokalen Ordnern. Ein lokaler SQLite-Index (`sqlite3`) sorgt für schnelle Ladezeiten auch bei Offline-NAS.
- **Portabler Modus:** Liegt neben der ausführbaren Datei eine `portable.flag` oder ein `data/`-Ordner, werden Datenbank, Einstellungen und Thumbnail-Cache relativ zum Programmordner gespeichert.
- **Multi-Geräte-Sync:** Dateibasierter Fortschrittsabgleich über `progress_sync.json` (Zeitstempel-Merge pro `media_key`).
- **Home-Hub & Bibliothek:** Hero-Banner, horizontale Karussells (*Weiterschauen*, *Zuletzt hinzugefügt*, *Schon lange nicht mehr gesehen* > 60 Tage), globale Live-Suche, Filter (*Alle / Serien / Filme*) und Zufallsvorschlag.
- **Serien-Detailansicht:** Staffel-Tabs, Episodenliste mit 16:9-Vorschaubildern, Laufzeit, Fortschrittsbalken, „Gesehen“-Toggle sowie Metadaten aus `info.json` oder `tvshow.nfo`.
- **Videoplayer (`media_kit` / `libmpv`):**
  - Hardware-Dekodierung (`enableHardwareAcceleration: true`)
  - Auto-Hide für Mauszeiger und HUD nach 2 Sekunden Inaktivität
  - Steuerung: `Leertaste` (Play/Pause), `Pfeil links/rechts` (±10 Sek.), `Doppelklick` (Vollbild), `Mausrad` (Lautstärke), **X-Maustasten** (Vorwärts/Zurück für nächste/vorherige Folge), `Esc` (Beenden)
  - Automatisches Speichern alle 5 Sekunden, Abschluss ab 92 % Laufzeit, Auto-Next-Countdown-Karte sowie Merken von Audio- und Untertitelspuren pro Serie
  - Responsives HUD auch für schmale Fensterbreiten
- **Statistiken:** Gesamte Watchtime (Serien vs. Filme), aktivster Tag und Wochentag, Watch-Streak sowie Top-Serien/-Filme.
- **Umschaltbarer Effekt-Modus (`EffectMode`):**
  - `glass`: Dezenter Blur (`BackdropFilter`), Hover-Skalierung und Glow-Effekte
  - `lean`: Optimiert für 4 GB RAM ohne Echtzeit-Blur oder Zoom-Animationen (pro Gerät via Rechnername speicherbar)

---

## Projektstruktur

```text
lib/
├── main.dart
├── core/
│   ├── constants/      # AppColors, AppSpacing, AppStrings
│   ├── controllers/    # LibraryController, SettingsController
│   ├── services/       # LocalFileService, DesktopPlatformService
│   ├── storage/        # PortablePaths, DatabaseService, ProgressSyncService
│   ├── theme/          # AppTheme, EffectMode
│   └── utils/          # Formatters
├── features/
│   ├── home/           # HomeController, HomeView, widgets/
│   ├── library/        # LibraryModels, LibraryView, MetadataReader, SeriesDetailView, widgets/
│   ├── player/         # PlaybackSession, PlaybackPersistenceService, SaphirPlayerController, SaphirPlayerView, widgets/
│   ├── scanner/        # MediaParser, NasScanRepository, NasScannerService, ThumbnailGeneratorService
│   ├── shell/          # ShellController, ShellView, widgets/ (NavigationSidebar, SettingsView)
│   └── stats/          # StatsController, StatsModels, StatsView, widgets/
└── widgets/            # WindowTitleBar, SurfacePanel, MediaTile

test/
├── architecture/       # Automatisierte Architektur-, Token- & Layer-Trennungs-Tests
├── controllers/        # Bestehende Controller-Tests
├── database/           # Schema-, Constraint-, Last- & Sync-Tests
├── helpers/            # TestEnv, synthetische Medien-Fixtures, MockPlayer, DartSourceAnalyzer
├── integration/        # End-to-End User-Flow-Tests
├── media/              # Import-Pipeline-, Thumbnail- & Player-Controller-Tests
├── scanner/            # Bestehende Parser- & Metadaten-Tests
├── storage/            # Bestehende DB- & Sync-Tests
├── ui/                 # Bestehende UI-Interaktionstests
├── unit/               # Erweiterte Controller-, Parser- & Model-Unit-Tests
└── widget/             # Player-UI-, Screen-, UX- & Responsive-Tests (Desktop bis 390×844)
```

---

## Entwicklung & Tests

```bash
# Abhängigkeiten installieren
flutter pub get

# App unter Windows starten
flutter run -d windows

# Statische Analyse
flutter analyze --no-pub

# Vollständige Test-Suite inkl. Coverage ausführen
flutter test --coverage
```

Aktueller Qualitätsstand:
- `flutter analyze --no-pub`: **0 Probleme**
- `flutter test --coverage`: **104 / 104 Tests bestanden** (87,0 % Code-Coverage)
