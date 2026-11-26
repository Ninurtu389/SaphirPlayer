class AppStrings {
  AppStrings._();

  static const String appTitle = 'SaphirPlayer';
  static const String homeTab = 'Start';
  static const String libraryTab = 'Bibliothek';
  static const String settingsTab = 'Einstellungen';

  static const String portableModeLabel = 'Portabler Ordner';
  static const String nasPathLabel = 'NAS-Quellpfad';
  static const String nasFoldersTitle = 'Quellordner (NAS & Lokal)';
  static const String nasPathHint = r'\\NAS\Serien oder D:\Filme';
  static const String addFolderButton = 'Ordner hinzufuegen';
  static const String removeFolderTooltip = 'Ordner entfernen';
  static const String noFoldersConfigured =
      'Noch kein Quellordner hinterlegt. Fuege mindestens einen Ordner hinzu.';
  static const String folderAddedStatus = 'Quellordner hinzugefuegt';
  static const String folderDuplicateStatus =
      'Dieser Quellordner ist bereits vorhanden';
  static const String folderRemovedStatus = 'Quellordner entfernt';
  static const String effectModeLabel = 'Effekt-Modus';
  static const String effectGlassLabel = 'Glas (Blur & Animation)';
  static const String effectLeanLabel = 'Schlank (4 GB RAM / Ohne Blur)';
  static const String perDeviceEffectLabel =
      'Effekt-Modus nur fuer dieses Geraet speichern';
  static const String saveSettingsButton = 'Speichern';
  static const String savedStatus = 'Einstellungen gespeichert';

  static const String scanButton = 'Bibliothek scannen';
  static const String scanningStatus = 'Scan laeuft...';
  static const String scanPausedStatus = 'Scan pausiert (Wiedergabe aktiv)';
  static const String nasOfflineStatus =
      'NAS nicht erreichbar – lokaler Index aktiv';
  static const String seriesCountLabel = 'Serien';
  static const String moviesCountLabel = 'Filme';

  static const String continueWatchingTitle = 'Weiterschauen';
  static const String rediscoverTitle = 'Schon lange nicht mehr gesehen';
  static const String recentlyAddedTitle = 'Zuletzt hinzugefuegt';
  static const String randomPickButton = 'Was soll ich schauen?';
  static const String resumeButton = 'Fortsetzen';
  static const String openSeriesButton = 'Zur Serie';
  static const String searchHint = 'Serien, Folgen oder Filme suchen...';
  static const String emptyHomeMessage =
      'Noch keine Eintraege vorhanden. NAS-Pfad pruefen und scannen.';
  static const String seasonPrefix = 'Staffel';
  static const String episodePrefix = 'Folge';
  static const String watchedBadge = 'Gesehen';
  static const String remainingMinutesSuffix = 'Min. uebrig';
  static const String backButton = 'Zurueck';
  static const String toggleWatchedAction = 'Gesehen umschalten';

  static const String playerPlayTooltip = 'Wiedergabe (Leertaste)';
  static const String playerPauseTooltip = 'Pause (Leertaste)';
  static const String playerSeekBackTooltip = '10 Sek. zurueck (Pfeil links)';
  static const String playerSeekForwardTooltip = '10 Sek. vor (Pfeil rechts)';
  static const String playerPrevEpisodeTooltip =
      'Vorherige Folge (X-Maustaste Zurueck)';
  static const String playerNextEpisodeTooltip =
      'Naechste Folge (X-Maustaste Vorwaerts)';
  static const String playerAudioTrackTooltip = 'Tonspur';
  static const String playerSubtitleTrackTooltip = 'Untertitel';
  static const String playerSubtitleOffLabel = 'Aus';
  static const String playerFullscreenTooltip = 'Vollbild (Doppelklick)';
  static const String playerCloseTooltip = 'Player beenden (Esc)';
  static const String playerFileMissingError =
      'Videodatei auf dem NAS nicht erreichbar.';
  static const String libraryOverviewTitle = 'Serien & Filme';
  static const String filterAllLabel = 'Alle';
  static const String filterSeriesLabel = 'Serien';
  static const String filterMoviesLabel = 'Filme';
  static const String emptyLibraryMessage =
      'Keine passenden Serien oder Filme gefunden.';
  static const String seriesTypeBadge = 'Serie';
  static const String movieTypeBadge = 'Film';
  static const String playNowButton = 'Abspielen';
  static const String seriesProgressLabel = 'Gesamtfortschritt';

  static const String autoNextTitle = 'Naechste Folge';
  static const String autoNextPlayNowButton = 'Jetzt starten';
  static const String autoNextCancelButton = 'Abbrechen';
  static const String autoNextSecondsSuffix = 'Sek.';

  static const String cacheSectionTitle = 'Thumbnail-Cache';
  static const String cacheSizeLabel = 'Belegter Speicher';
  static const String clearCacheButton = 'Cache leeren';
  static const String cacheClearedStatus = 'Thumbnail-Cache geleert';
  static const String syncNowButton = 'Sync abgleichen';
  static const String syncCompletedStatus = 'Fortschritt synchronisiert';
}
