class AppStrings {
  AppStrings._();

  static const String appTitle = 'SaphirPlayer';
  static const String homeTab = 'Start';
  static const String libraryTab = 'Bibliothek';
  static const String statsTab = 'Statistiken';
  static const String settingsTab = 'Einstellungen';

  static const String windowMinimizeTooltip = 'Minimieren';
  static const String windowMaximizeTooltip = 'Maximieren';
  static const String windowRestoreTooltip = 'Wiederherstellen';
  static const String windowCloseTooltip = 'Schließen';

  static const String nasPathLabel = 'NAS-Quellpfad';
  static const String nasPathHint = r'\\NAS\Serien oder D:\Filme';
  static const String addFolderButton = 'Ordner hinzufügen';
  static const String removeFolderTooltip = 'Ordner entfernen';
  static const String noFoldersConfigured =
      'Noch kein Quellordner hinterlegt. Füge mindestens einen Ordner hinzu.';
  static const String folderAddedStatus = 'Quellordner hinzugefügt';
  static const String folderDuplicateStatus =
      'Dieser Quellordner ist bereits vorhanden';
  static const String folderRemovedStatus = 'Quellordner entfernt';
  static const String effectGlassLabel = 'Glas (Blur & Animation)';
  static const String effectLeanLabel = 'Schlank (4 GB RAM / Ohne Blur)';
  static const String perDeviceEffectLabel =
      'Effekt-Modus nur für dieses Gerät speichern';
  static const String saveSettingsButton = 'Speichern';
  static const String savedStatus = 'Einstellungen gespeichert';

  static const String settingsMediaSectionTitle = 'Medienquellen & NAS';
  static const String settingsMediaSectionDesc =
      'Verwalte lokale und Netzwerk-Ordner (SMB/UNC) für deine Serien und Filme.';
  static const String settingsAppearanceSectionTitle =
      'Darstellung & Performance (4 GB RAM)';
  static const String settingsAppearanceSectionDesc =
      'Passe visuelle Effekte an die Leistung dieses Geräts an.';
  static const String settingsEffectGlassDesc =
      'Weiche Hover-Skalierung, dezente Unschärfe und sanfte Übergänge.';
  static const String settingsEffectLeanDesc =
      'Ohne Echtzeit-Blur und Zoom-Animationen – ideal für 4 GB RAM.';
  static const String settingsPerDeviceDesc =
      'Speichert den Effekt-Modus getrennt nach Rechnername.';
  static const String settingsSyncSectionTitle = 'Synchronisation & Cache';
  static const String settingsSyncSectionDesc =
      'Fortschritte manuell abgleichen oder zwischengespeicherte Vorschaubilder bereinigen.';
  static const String settingsPageSubtitle =
      'Medienquellen, Wiedergabe, Darstellung und lokalen Cache verwalten.';
  static const String settingsSyncActionTitle = 'Fortschritt synchronisieren';
  static const String settingsSyncActionDesc =
      'Gleicht den Wiedergabestand über progress_sync.json auf dem NAS ab.';
  static const String settingsCacheActionDesc =
      'Zwischengespeicherte Vorschaubilder freigeben.';
  static const String settingsDangerZoneTitle = 'Gefahrenbereich';
  static const String settingsDangerZoneDesc =
      'Löscht alle lokalen Seriendaten, Fortschritte und Einstellungen unwiderruflich.';

  static const String scanButton = 'Bibliothek scannen';
  static const String scanningStatus = 'Scan läuft...';
  static const String scanPausedStatus = 'Scan pausiert (Wiedergabe aktiv)';
  static const String nasOfflineStatus =
      'NAS nicht erreichbar – lokaler Index aktiv';
  static const String seriesCountLabel = 'Serien';
  static const String moviesCountLabel = 'Filme';
  static const String episodesCountLabel = 'Episoden';

  static const String continueWatchingTitle = 'Weiterschauen';
  static const String rediscoverTitle = 'Schon lange nicht mehr gesehen';
  static const String recentlyAddedTitle = 'Zuletzt hinzugefügt';
  static const String randomPickShortButton = 'Zufälliger Vorschlag';
  static const String resumeButton = 'Fortsetzen';
  static const String detailsButton = 'Details';
  static const String searchHint = 'Serien, Folgen oder Filme suchen...';
  static const String emptyHomeMessage =
      'Noch keine Einträge vorhanden. NAS-Pfad prüfen und scannen.';
  static const String seasonPrefix = 'Staffel';
  static const String episodeFallbackPrefix = 'Folge';
  static const String watchedBadge = 'Gesehen';
  static const String remainingMinutesSuffix = 'Min. übrig';
  static const String backButton = 'Zurück';
  static const String toggleWatchedAction = 'Gesehen umschalten';
  static const String playEpisodeOneButton = 'Folge 1 abspielen';

  static const String scrollLeftTooltip = 'Nach links scrollen';
  static const String scrollRightTooltip = 'Nach rechts scrollen';

  static const String playerPlayTooltip = 'Wiedergabe (Leertaste)';
  static const String playerPauseTooltip = 'Pause (Leertaste)';
  static const String playerSeekBackTooltip = '10 Sek. zurück (Pfeil links)';
  static const String playerSeekForwardTooltip = '10 Sek. vor (Pfeil rechts)';
  static const String playerPrevEpisodeTooltip =
      'Vorherige Folge (X-Maustaste Zurück)';
  static const String playerNextEpisodeTooltip =
      'Nächste Folge (X-Maustaste Vorwärts)';
  static const String playerAudioTrackTooltip = 'Tonspur';
  static const String playerSubtitleTrackTooltip = 'Untertitel';
  static const String playerSubtitleOffLabel = 'Aus';
  static const String playerTrackPrefix = 'Spur';
  static const String playerSubtitleTrackPrefix = 'Untertitel';
  static const String playerSpeedTooltip = 'Wiedergabegeschwindigkeit';
  static const String playerMuteTooltip = 'Stummschalten';
  static const String playerUnmuteTooltip = 'Ton aktivieren';
  static const String playerFullscreenTooltip = 'Vollbild (Doppelklick)';
  static const String playerCloseTooltip = 'Player beenden (Esc)';
  static const String playerFileMissingError =
      'Videodatei auf dem NAS nicht erreichbar.';
  static const String playerPlaybackError =
      'Wiedergabe fehlgeschlagen. Videoformat oder Codec wird nicht unterstützt.';
  static const String playerEmptyFileError =
      'Videodatei ist leer oder beschädigt.';

  static const String libraryOverviewTitle = 'Serien & Filme';
  static const String filterAllLabel = 'Alle';
  static const String filterSeriesLabel = 'Serien';
  static const String filterMoviesLabel = 'Filme';
  static const String emptyLibraryMessage =
      'Keine passenden Serien oder Filme gefunden.';
  static const String seriesTypeBadge = 'Serie';
  static const String movieTypeBadge = 'Film';
  static const String playNowButton = 'Abspielen';

  static const String autoNextTitle = 'Nächste Folge';
  static const String autoNextPlayNowButton = 'Jetzt starten';
  static const String autoNextCancelButton = 'Abbrechen';
  static const String autoNextSecondsSuffix = 'Sek.';

  static const String cacheSectionTitle = 'Thumbnail-Cache';
  static const String megabytesUnit = 'MB';
  static const String clearCacheButton = 'Cache leeren';
  static const String cacheClearedStatus = 'Thumbnail-Cache geleert';
  static const String syncNowButton = 'Sync abgleichen';
  static const String syncCompletedStatus = 'Fortschritt synchronisiert';
  static const String pickFolderDialogTitle = 'Medienordner auswählen';
  static const String resetDatabaseButton = 'Datenbank zurücksetzen';
  static const String resetDatabaseConfirmTitle = 'Datenbank zurücksetzen?';
  static const String resetDatabaseConfirmMessage =
      'Alle eingelesenen Serien, Filme, Fortschritte und Einstellungen werden unwiderruflich aus der lokalen Datenbank gelöscht.';
  static const String resetDatabaseConfirmAction = 'Zurücksetzen';
  static const String cancelAction = 'Abbrechen';
  static const String databaseResetStatus = 'Datenbank wurde zurückgesetzt';
  static const String clearSearchTooltip = 'Suche leeren';

  static const String statsPageTitle = 'Statistiken';
  static const String statsTotalWatchtimeTitle = 'Gesamte Watchtime';
  static const String statsSeriesWatchtimeLabel = 'Serien';
  static const String statsMoviesWatchtimeLabel = 'Filme';
  static const String statsTopDayTitle = 'Aktivster Tag';
  static const String statsTopWeekdayTitle = 'Aktivster Wochentag';
  static const String statsStreakTitle = 'Watch-Streak';
  static const String statsStreakDaysSuffix = 'Tage';
  static const String statsStreakBestPrefix = 'Rekord:';
  static const String statsCompletedTitle = 'Abgeschlossen';
  static const String statsWeekdayChartTitle = 'Watchtime nach Wochentag';
  static const String statsTopSeriesTitle = 'Meistgesehene Serien';
  static const String statsTopMoviesTitle = 'Meistgesehene Filme';
  static const String statsEmptyMessage =
      'Noch keine Wiedergabedaten vorhanden. Starte eine Folge oder einen Film, um Statistiken zu sammeln.';
  static const String statsNoDataDash = '–';
  static const String statsHoursShort = 'Std.';
  static const String statsMinutesShort = 'Min.';
  static const String statsDaysShort = 'Tage';
  static const String statsPlaysSuffix = '× geschaut';
  static const List<String> statsWeekdayLabels = [
    'Mo',
    'Di',
    'Mi',
    'Do',
    'Fr',
    'Sa',
    'So',
  ];
  static const List<String> statsWeekdayFullNames = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  static const String settingsHwdecLabel =
      'Hardware-Dekodierung (pro Gerät)';
  static const String settingsHwdecDesc =
      'Nutzt GPU-Beschleunigung für flüssige Wiedergabe (wird beim nächsten Player-Start aktiv).';
  static const String settingsSubtitlesSectionTitle = 'Untertitel & Sprache';
  static const String settingsSubtitlesSectionDesc =
      'Standardverhalten, bevorzugte Sprache und Darstellung für neue Videos.';
  static const String settingsSubtitlesDefaultLabel =
      'Untertitel standardmäßig aktivieren';
  static const String settingsSubtitlesDefaultDesc =
      'Gespeicherte Serien-Präferenzen haben stets Vorrang.';
  static const String settingsSubtitleLanguageLabel =
      'Bevorzugte Untertitel-Sprache';
  static const String subtitleLangCodeDe = 'de';
  static const String subtitleLangCodeEn = 'en';
  static const String subtitleLangCodeAuto = 'auto';
  static const String subtitleLangDe = 'Deutsch';
  static const String subtitleLangEn = 'Englisch';
  static const String subtitleLangAuto = 'Automatisch / Original';
  static const String subtitleScaleLabel = 'Schriftgröße';
  static const String subtitlePositionLabel = 'Vertikale Position';
  static const String subtitleBgOpacityLabel = 'Hintergrund-Kontrast';
  static const String percentSymbol = '%';
  static const String timesSymbol = '×';

  static const String playerNightModeLabel = 'Nachtmodus (Dialog-Boost)';
  static const String playerVolumeBoostLabel = 'Lautstärke-Boost (150 %)';
  static const String playerAudioDelayLabel = 'Audio-Sync';
  static const String playerSubtitleDelayLabel = 'Untertitel-Sync';
  static const String playerDelayMinusLabel = '-100 ms';
  static const String playerDelayPlusLabel = '+100 ms';
  static const String playerDelayResetLabel = 'Reset';
  static const String playerDelayUnitMs = 'ms';
  static const String playerLoadExternalSubLabel =
      'Externe Datei laden (.srt/.ass/.vtt)';
  static const String playerPickSubtitleDialogTitle =
      'Untertiteldatei auswählen';
  static const String playerSubtitleStyleLabel = 'Untertitel-Styling';
  static const String playerSubtitleStyleTitle = 'Untertitel-Darstellung';
  static const String playerAspectModeTooltip = 'Seitenverhältnis / Zoom (A)';
  static const String aspectOriginalLabel = 'Original';
  static const String aspectFillCropLabel = 'Füllen / Crop';
  static const String aspect16x9Label = '16:9';
  static const String aspect21x9Label = '21:9';

  static const String playerChapterPrefix = 'Kapitel';
  static const String playerIntroSkipButton = 'Intro überspringen';
  static const String playerIntroSkipSettingsTooltip =
      'Intro-Dauer für Serie festlegen';
  static const String playerIntroSkipSecondsSuffix = 'Sek.';
  static const String playerBookmarkTooltip = 'Lesezeichen setzen (B)';
  static const String playerBookmarkAddedOsd = 'Lesezeichen gespeichert';
  static const String playerBookmarkDeletedOsd = 'Lesezeichen entfernt';
  static const String playerBookmarkListTitle = 'Szenen-Lesezeichen';
  static const String playerNoBookmarksLabel = 'Keine Lesezeichen';
  static const String playerScreenshotTooltip = 'Screenshot speichern (S)';
  static const String playerScreenshotSavedOsd = 'Screenshot gespeichert';
  static const String playerScreenshotFailedOsd =
      'Screenshot fehlgeschlagen';
  static const String playerFinishTimePrefix = 'Fertig um';
  static const String playerTimeToggleTooltip =
      'Anzeige wechseln (Gesamt / Rest / Endzeit)';

  static const String playerEpisodeDrawerTooltip = 'Episodenliste (E)';
  static const String playerEpisodeDrawerTitle = 'Episoden';
  static const String playerMiniPlayerTooltip = 'Mini-Player (Always on Top)';
  static const String playerMiniPlayerExitTooltip = 'Zurück zur Normalansicht';
  static const String playerSleepTimerTooltip = 'Sleep-Timer';
  static const String sleepTimerOffLabel = 'Aus';
  static const String sleepTimerEndOfEpisodeLabel = 'Nach dieser Folge';
  static const String sleepTimer30MinLabel = '30 Min.';
  static const String sleepTimer60MinLabel = '60 Min.';
  static const String sleepTimerTriggeredOsd = 'Sleep-Timer abgelaufen';
  static const String sleepTimerBadgeEndOfEp = 'Ende Folge';
  static const String playerDiagnosticsTooltip = 'Diagnose (I)';
  static const String playerDiagnosticsTitle = 'Stats for Nerds';
  static const String diagVideoCodecLabel = 'Video-Codec';
  static const String diagAudioCodecLabel = 'Audio-Codec';
  static const String diagResolutionLabel = 'Auflösung';
  static const String diagFpsLabel = 'FPS';
  static const String diagHwdecLabel = 'HW-Decoder';
  static const String diagUnknownValue = '–';
  static const String playerShortcutsTooltip = 'Tastenkürzel (?)';
  static const String playerShortcutsTitle = 'Tastenkürzel';
  static const String playerCloseOverlayAction = 'Schließen';

  static const String osdMuteOn = 'Stumm';
  static const String osdMuteOff = 'Ton an';
  static const String osdNightModeOn = 'Nachtmodus an';
  static const String osdNightModeOff = 'Nachtmodus aus';
  static const String osdVolumeBoostOn = 'Boost 150 % an';
  static const String osdVolumeBoostOff = 'Boost aus';
  static const String osdFrameStepForward = 'Einzelbild vor';
  static const String osdFrameStepBack = 'Einzelbild zurück';
  static const String osdExternalSubLoaded = 'Untertitel geladen';
  static const String osdSleepTimerSetPrefix = 'Sleep-Timer:';
  static const String osdSleepTimerOff = 'Sleep-Timer aus';

  static const List<(String, String)> playerShortcutEntries = [
    ('Leertaste', 'Wiedergabe / Pause'),
    ('← / →', '10 Sek. zurück / vor'),
    ('Shift + ← / →', '60 Sek. zurück / vor'),
    ('↑ / ↓ / Mausrad', 'Lautstärke regeln'),
    ('F / Doppelklick', 'Vollbild umschalten'),
    ('M', 'Stummschalten'),
    ('N / P / X-Tasten', 'Nächste / Vorherige Folge'),
    ('. / ,', 'Einzelbild vorwärts / rückwärts'),
    ('A', 'Seitenverhältnis / Zoom'),
    ('B', 'Lesezeichen setzen'),
    ('S', 'Screenshot speichern'),
    ('E', 'Episodenliste umschalten'),
    ('I', 'Diagnose-Overlay'),
    ('? / H', 'Tastenkürzel anzeigen'),
    ('Esc', 'Overlay schließen / Player beenden'),
  ];
}
