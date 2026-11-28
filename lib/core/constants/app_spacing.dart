class AppSpacing {
  AppSpacing._();

  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;

  static const double defaultWindowWidth = 1280.0;
  static const double defaultWindowHeight = 800.0;
  static const double minWindowWidth = 800.0;
  static const double minWindowHeight = 500.0;

  static const double titleBarHeight = 34.0;
  static const double windowControlWidth = 34.0;
  static const double windowControlHeight = 26.0;
  static const double windowControlIconSize = 14.0;
  static const double windowMaximizeIconSize = 12.0;
  static const double windowRestoreIconSize = 10.0;
  static const double titleBarSearchHeight = 26.0;
  static const double titleBarLogoDotSize = 7.0;
  static const double titleBarSearchFontSize = 13.0;
  static const double navRailWidth = 84.0;
  static const double navItemHeight = 56.0;
  static const double navIndicatorWidth = 3.0;
  static const double navIndicatorHeight = 24.0;

  static const double blurSigmaGlass = 12.0;
  static const double progressBarHeight = 4.0;
  static const double heroProgressWidth = 280.0;
  static const double heroGlowRadius = 0.9;
  static const double seriesHeaderGlowRadius = 1.0;

  static const int heroCacheWidth = 1280;
  static const int heroCacheHeight = 720;
  static const double thumbWidth = 320.0;
  static const double thumbHeight = 180.0;
  static const double tileCardWidth = 264.0;
  static const double tileCardHeight = 148.0;
  static const double tileRailHeight = 184.0;
  static const double tileRemoveButtonSize = 26.0;
  static const double libraryGridMaxExtent = 280.0;

  static const double tileHoverScale = 1.04;
  static const double tileRestScale = 1.0;
  static const double tileHoverElevationBlur = 18.0;
  static const double tileBorderWidthHover = 1.5;
  static const int hoverAnimationMs = 180;
  static const int hudFadeAnimationMs = 220;

  static const double heroBannerHeight = 360.0;
  static const double heroContentMaxWidth = 620.0;
  static const double searchBarExpandedWidth = 460.0;
  static const double railArrowButtonSize = 40.0;
  static const double railScrollStep = 540.0;
  static const double scrollEdgeTolerance = 0.5;

  static const double statsBarMaxHeight = 110.0;
  static const double statsBarWidth = 28.0;
  static const int statsTopListLimit = 5;
  static const double statsMaxWidth = 1040.0;
  static const int statsKpiColumnsWide = 4;
  static const int statsKpiColumnsMedium = 2;
  static const int statsKpiColumnsNarrow = 1;

  static const double seriesDetailHeaderHeight = 280.0;
  static const double episodeThumbWidth = 216.0;
  static const double episodeThumbHeight = 122.0;
  static const double seasonTabIndicatorHeight = 3.0;

  static const double maxSettingsWidth = 760.0;
  static const double settingsTwoColumnBreakpoint = 820.0;
  static const double settingsCompactRowBreakpoint = 420.0;
  static const double settingsIconBadgeSize = 36.0;
  static const double dividerThickness = 1.0;
  static const double railSpacing = 14.0;
  static const double iconSizeSm = 16.0;
  static const double iconSizeMd = 20.0;
  static const double iconSizeLg = 28.0;
  static const double iconSizeXl = 40.0;
  static const double monogramFontSize = 42.0;
  static const double monogramLetterSpacing = 2.0;
  static const double heroMonogramFontSize = 96.0;
  static const double heroMonogramLetterSpacing = 4.0;

  static const int staleDaysDefault = 60;
  static const double thumbnailSeekRatio = 0.15;
  static const int thumbnailMinSeekSeconds = 300;
  static const int ffmpegTimeoutSeconds = 10;
  static const int ffprobeTimeoutSeconds = 5;
  static const int mkvTagHeaderMaxScanBytes = 262144;
  static const int executableProbeTimeoutSeconds = 2;
  static const int thumbnailShortVideoSeekSeconds = 1;
  static const int thumbnailShortVideoThresholdSeconds = 30;
  static const int thumbnailOpenTimeoutSeconds = 8;
  static const int thumbnailSeekWaitTimeoutMs = 6000;
  static const int thumbnailFrameSettleMs = 450;
  static const int millisecondsPerSecond = 1000;
  static const int secondsPerMinute = 60;
  static const int secondsPerHour = 3600;
  static const int maxPlayerDurationSeconds = 359999;
  static const int millisecondsPerMinute = 60000;
  static const int millisecondsPerDay = 86400000;
  static const int bytesPerMegabyte = 1048576;
  static const double completedThresholdRatio = 0.92;
  static const int maxThumbnailsPerScan = 40;

  static const int seekStepSeconds = 10;
  static const double volumeStep = 5.0;
  static const double volumeMin = 0.0;
  static const double volumeMax = 100.0;
  static const int hudAutoHideSeconds = 2;
  static const double hudSliderWidth = 110.0;
  static const double compactPlayerBreakpoint = 560.0;
  static const double playerTopHudHeight = 96.0;
  static const double playerBottomHudHeight = 144.0;
  static const double playerSeekThumbRadius = 6.0;
  static const double playerSeekThumbRadiusHover = 9.0;
  static const double playerSeekTrackHeight = 4.0;
  static const List<double> playbackSpeeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  static const int progressSaveIntervalSeconds = 5;
  static const int autoNextLeadSeconds = 12;
  static const double autoNextCardWidth = 340.0;
  static const double autoNextBottomWithHud = 152.0;

  static const double subtitleScaleMin = 0.6;
  static const double subtitleScaleMax = 2.0;
  static const double subtitleScaleDefault = 1.0;
  static const int subtitleScaleDivisions = 14;
  static const int subtitlePositionMin = 50;
  static const int subtitlePositionMax = 100;
  static const int subtitlePositionDefault = 100;
  static const int subtitlePositionDivisions = 10;
  static const double subtitleBgOpacityMin = 0.0;
  static const double subtitleBgOpacityMax = 0.85;
  static const double subtitleBgOpacityDefault = 0.0;
  static const int subtitleBgOpacityDivisions = 17;

  static const double volumeBoostMax = 150.0;
  static const int seekStepLongSeconds = 60;
  static const int delayStepMs = 100;
  static const int delayMinMs = -5000;
  static const int delayMaxMs = 5000;
  static const int introSkipWindowSeconds = 300;
  static const int defaultIntroSkipSeconds = 85;
  static const List<int> introSkipPresets = [60, 85, 90, 120];
  static const int osdDurationMs = 1200;
  static const int diagnosticsPollSeconds = 1;
  static const int sleepTimer30Minutes = 30;
  static const int sleepTimer60Minutes = 60;
  static const int sleepTimerTickSeconds = 30;
  static const int searchDebounceMs = 180;
  static const int statusBannerAutoHideSeconds = 4;
  static const double introDismissIconSize = 16.0;
  static const double sliderHorizontalTrackInset = 24.0;

  static const double miniPlayerWidth = 480.0;
  static const double miniPlayerHeight = 270.0;
  static const double miniPlayerMinWidth = 320.0;
  static const double miniPlayerMinHeight = 180.0;
  static const double episodeDrawerWidth = 320.0;
  static const double shortcutSheetMaxWidth = 560.0;
  static const double shortcutSheetMaxHeight = 480.0;
  static const double shortcutKeyBadgeMinWidth = 96.0;
  static const double diagnosticsOverlayMaxWidth = 280.0;
  static const double osdMaxWidth = 280.0;
  static const double subtitleStyleDialogWidth = 360.0;
  static const double seekBarHeight = 36.0;
  static const double seekHoverTooltipOffsetY = 44.0;
  static const double seekHoverTooltipMaxWidth = 220.0;
  static const double chapterMarkerWidth = 2.0;
  static const double chapterMarkerHeight = 10.0;
  static const double bookmarkMarkerRadius = 4.5;
  static const double compactTopHudBreakpoint = 560.0;
  static const double miniPlayerDragBarHeight = 32.0;
  static const double badgePaddingH = 8.0;
  static const double badgePaddingV = 3.0;
  static const double borderWidthThin = 1.0;
  static const double opacityVisible = 1.0;
  static const double opacityHidden = 0.0;
  static const double zero = 0.0;
  static const double halfFactor = 0.5;
  static const double drawerMaxWidthFraction = 0.85;
  static const double drawerBottomOffset = 152.0;
  static const double osdTopOffset = 72.0;
  static const double diagnosticsTopOffset = 76.0;
  static const double sleepBadgeFontSize = 11.0;
  static const double shortcutKeyFontSize = 12.0;
  static const double diagnosticsFontSize = 12.0;

  static const int shutdownPlayerDisposeTimeoutMs = 2000;
  static const int shutdownScanStopTimeoutMs = 1500;
  static const int shutdownSyncTimeoutMs = 2500;
  static const int shutdownNativeDrainDelayMs = 250;
  static const int shutdownWindowDestroyTimeoutMs = 1000;

  static const int scanDeleteGuardMinEntries = 10;
  static const double scanDeleteGuardMaxRatio = 0.85;
  static const int scanIsolateShutdownGraceMs = 250;

  static const int thumbnailMaxRetryAttempts = 3;
  static const int thumbnailRetryBaseSeconds = 30;
  static const int thumbnailQueueBatchDelayMs = 250;
}
