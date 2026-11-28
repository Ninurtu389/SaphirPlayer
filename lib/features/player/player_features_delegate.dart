import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/utils/formatters.dart';
import 'mpv_property_bridge.dart';
import 'playback_persistence_service.dart';
import 'playback_session.dart';
import 'player_models.dart';
import 'player_overlays_controller.dart';

/// Zustandsmatrix der Player-Features:
/// - Global persistent: SettingsController (Untertitel-Default, Sprache, Styling, HWDEC)
/// - Pro Serie persistent: series_preferences (Tonspur, Untertitelspur, Intro-Skip-Dauer)
/// - Pro Medium persistent: watch_progress, media_bookmarks, watch_history
/// - Pro Eintrag transient: Position, Dauer, Fehler, Tracks, Kapitel, Intro-Dismissal,
///   Auto-Next-Dismissal, Delays, aktives OSD, laufende Async-Reads
/// - Pro Session transient: Sleep-Timer, Playback-Speed, Aspect-Mode, Night-Mode,
///   Volume-Boost, geoeffnete Overlays (Drawer, Shortcut-Sheet, Diagnose)
class PlayerFeaturesDelegate {
  PlayerFeaturesDelegate({
    required Player player,
    required IMpvPropertyBridge mpvBridge,
    required PlaybackPersistenceService persistence,
    required PlayerWindowAdapter windowAdapter,
    required PlayerOverlaysController overlays,
    required SettingsController? settingsController,
    required Future<String?> Function(Uint8List bytes, String title)
        onSaveScreenshot,
    required VoidCallback onChanged,
  })  : _player = player,
        _mpvBridge = mpvBridge,
        _persistence = persistence,
        _windowAdapter = windowAdapter,
        _overlays = overlays,
        _settingsController = settingsController,
        _onSaveScreenshot = onSaveScreenshot,
        _onChanged = onChanged;

  final Player _player;
  final IMpvPropertyBridge _mpvBridge;
  final PlaybackPersistenceService _persistence;
  final PlayerWindowAdapter _windowAdapter;
  final PlayerOverlaysController _overlays;
  final SettingsController? _settingsController;
  final Future<String?> Function(Uint8List bytes, String title)
      _onSaveScreenshot;
  final VoidCallback _onChanged;

  static final RegExp _introChapterPattern = RegExp(
    r'\b(?:intro|opening|vorspann|op|credits)\b',
    caseSensitive: false,
  );

  bool isNightMode = false;
  bool isVolumeBoostEnabled = false;
  VideoAspectMode aspectMode = VideoAspectMode.original;
  int audioDelayMs = 0;
  int subtitleDelayMs = 0;
  List<PlayerChapter> chapters = const [];
  bool chaptersLoadedForEntry = false;
  bool introSkipped = false;
  int seriesIntroSkipSeconds = 0;
  List<MediaBookmark> bookmarks = const [];
  TimeDisplayMode timeDisplayMode = TimeDisplayMode.total;
  bool isMiniPlayer = false;
  Rect? _boundsBeforeMiniPlayer;
  bool _wasMaximizedBeforeMiniPlayer = false;

  double get maxVolume =>
      isVolumeBoostEnabled ? AppSpacing.volumeBoostMax : AppSpacing.volumeMax;

  int get effectiveIntroSkipSeconds => seriesIntroSkipSeconds > 0
      ? seriesIntroSkipSeconds
      : AppSpacing.defaultIntroSkipSeconds;

  int computeAutoNextRemainingSeconds({
    required bool hasNextEpisode,
    required bool autoNextDismissed,
    required SleepTimerOption sleepTimerOption,
    required Duration position,
    required Duration duration,
  }) {
    if (!hasNextEpisode ||
        autoNextDismissed ||
        sleepTimerOption == SleepTimerOption.endOfEpisode) {
      return 0;
    }
    final remainingMs = duration.inMilliseconds - position.inMilliseconds;
    final leadMs =
        AppSpacing.autoNextLeadSeconds * AppSpacing.millisecondsPerSecond;
    if (duration.inMilliseconds <= 0 ||
        remainingMs <= 0 ||
        remainingMs > leadMs) {
      return 0;
    }
    return (remainingMs / AppSpacing.millisecondsPerSecond).ceil();
  }

  bool canShowIntroSkipButton({
    required PlaybackQueueEntry? entry,
    required String? errorMessage,
    required Duration position,
    required Duration duration,
  }) {
    if (entry?.mediaType != 'episode' ||
        errorMessage != null ||
        duration <= Duration.zero ||
        introSkipped) {
      return false;
    }
    final maxWindowMs =
        AppSpacing.introSkipWindowSeconds * AppSpacing.millisecondsPerSecond;
    final posMs = position.inMilliseconds;
    if (posMs >= maxWindowMs) return false;
    if (nextChapterInIntroWindow(position) != null) return true;
    return posMs < effectiveIntroSkipSeconds * AppSpacing.millisecondsPerSecond;
  }

  double get subtitleScale =>
      _settingsController?.subtitleScale ?? AppSpacing.subtitleScaleDefault;
  int get subtitlePosition =>
      _settingsController?.subtitlePosition ??
      AppSpacing.subtitlePositionDefault;
  double get subtitleBgOpacity =>
      _settingsController?.subtitleBgOpacity ??
      AppSpacing.subtitleBgOpacityDefault;

  void resetForEntry(PlaybackQueueEntry entry) {
    chapters = const [];
    chaptersLoadedForEntry = false;
    introSkipped = false;
    audioDelayMs = 0;
    subtitleDelayMs = 0;
    bookmarks = _persistence.loadBookmarks(entry.mediaKey);
    seriesIntroSkipSeconds = entry.seriesId != null
        ? (_persistence
                .loadSeriesTrackPreferences(entry.seriesId!)
                ?.introSkipSeconds ??
            0)
        : 0;
  }

  Future<void> resetEntryMpvProperties() async {
    try {
      await _mpvBridge.setAudioDelay(0);
      await _mpvBridge.setSubtitleDelay(0);
    } catch (_) {
      // Best-effort Reset bei fehlender nativer Engine
    }
  }

  void dismissIntroSkip() {
    introSkipped = true;
    _onChanged();
  }

  Future<void> resetSessionState({bool forceMpvReset = false}) async {
    final hadDelays = audioDelayMs != 0 || subtitleDelayMs != 0;
    final hadAspect = aspectMode != VideoAspectMode.original;
    final hadNightMode = isNightMode;
    final hadBoost = isVolumeBoostEnabled;

    audioDelayMs = 0;
    subtitleDelayMs = 0;
    aspectMode = VideoAspectMode.original;
    isNightMode = false;
    isVolumeBoostEnabled = false;
    chapters = const [];
    chaptersLoadedForEntry = false;
    introSkipped = false;
    seriesIntroSkipSeconds = 0;
    bookmarks = const [];

    try {
      if (hadDelays || forceMpvReset) {
        await _mpvBridge.setAudioDelay(0);
        await _mpvBridge.setSubtitleDelay(0);
      }
      if (hadAspect || forceMpvReset) {
        await _mpvBridge.setAspectMode(VideoAspectMode.original);
      }
      if (hadNightMode) {
        await _mpvBridge.setAudioNightMode(false);
      }
      if (hadBoost) {
        await _mpvBridge.setVolumeMax(AppSpacing.volumeMax);
      }
    } catch (_) {
      // Best-effort Reset bei geschlossener oder gemockter Engine
    }
  }

  Future<void> loadChapters(bool Function() isStale) async {
    if (isStale()) return;
    try {
      final loaded = await _mpvBridge.readChapters();
      if (isStale()) return;
      chapters = loaded;
      _onChanged();
    } catch (_) {
      if (isStale()) return;
      chapters = const [];
      _onChanged();
    }
  }

  Future<void> loadExternalSubtitle(
    String dialogTitle, {
    required bool Function() isStale,
    required void Function(SubtitleTrack track) onTrackSelected,
  }) async {
    try {
      final path = await _windowAdapter.pickSubtitleFile(dialogTitle);
      if (path == null || path.trim().isEmpty || isStale()) return;
      final track = SubtitleTrack.uri(path);
      await _player.setSubtitleTrack(track);
      if (isStale()) return;
      onTrackSelected(track);
      _overlays.showActionOsd(
        PlayerActionOsdKind.subtitle,
        AppStrings.osdExternalSubLoaded,
      );
      _onChanged();
    } catch (_) {
      if (isStale()) return;
      _overlays.showActionOsd(
        PlayerActionOsdKind.error,
        AppStrings.playerExternalSubFailedOsd,
      );
    }
  }

  Future<void> applySubtitleStyle({
    double? scale,
    int? position,
    double? bgOpacity,
  }) =>
      _mpvBridge.setSubtitleStyle(
        scale: scale ?? subtitleScale,
        pos: position ?? subtitlePosition,
        bgOpacity: bgOpacity ?? subtitleBgOpacity,
      );

  Future<void> updateLiveSubtitleStyle({
    double? scale,
    int? position,
    double? bgOpacity,
  }) async {
    _settingsController?.updateSubtitleStyle(
      scale: scale,
      position: position,
      bgOpacity: bgOpacity,
    );
    await applySubtitleStyle(
      scale: scale,
      position: position,
      bgOpacity: bgOpacity,
    );
    _onChanged();
  }

  Future<void> toggleNightMode() async {
    isNightMode = !isNightMode;
    await _mpvBridge.setAudioNightMode(isNightMode);
    _overlays.showActionOsd(
      PlayerActionOsdKind.nightMode,
      isNightMode ? AppStrings.osdNightModeOn : AppStrings.osdNightModeOff,
    );
    _onChanged();
  }

  Future<void> toggleVolumeBoost(double currentVolume) async {
    isVolumeBoostEnabled = !isVolumeBoostEnabled;
    await _mpvBridge.setVolumeMax(maxVolume);
    if (!isVolumeBoostEnabled && currentVolume > AppSpacing.volumeMax) {
      await _player.setVolume(AppSpacing.volumeMax);
    }
    _overlays.showActionOsd(
      PlayerActionOsdKind.volumeBoost,
      isVolumeBoostEnabled
          ? AppStrings.osdVolumeBoostOn
          : AppStrings.osdVolumeBoostOff,
    );
    _onChanged();
  }

  Future<void> setAspectMode(VideoAspectMode mode) async {
    aspectMode = mode;
    await _mpvBridge.setAspectMode(mode);
    _overlays.showActionOsd(
      PlayerActionOsdKind.aspectMode,
      Formatters.formatAspectModeLabel(mode),
    );
    _onChanged();
  }

  Future<void> adjustAudioDelay(int deltaMs) async {
    audioDelayMs = (audioDelayMs + deltaMs)
        .clamp(AppSpacing.delayMinMs, AppSpacing.delayMaxMs);
    await _mpvBridge
        .setAudioDelay(audioDelayMs / AppSpacing.millisecondsPerSecond);
    _overlays.showActionOsd(
      PlayerActionOsdKind.audioDelay,
      '${AppStrings.playerAudioDelayLabel}: ${Formatters.formatDelayMs(audioDelayMs)}',
    );
    _onChanged();
  }

  Future<void> adjustSubtitleDelay(int deltaMs) async {
    subtitleDelayMs = (subtitleDelayMs + deltaMs)
        .clamp(AppSpacing.delayMinMs, AppSpacing.delayMaxMs);
    await _mpvBridge.setSubtitleDelay(
      subtitleDelayMs / AppSpacing.millisecondsPerSecond,
    );
    _overlays.showActionOsd(
      PlayerActionOsdKind.subtitleDelay,
      '${AppStrings.playerSubtitleDelayLabel}: ${Formatters.formatDelayMs(subtitleDelayMs)}',
    );
    _onChanged();
  }

  PlayerChapter? chapterAtPosition(Duration pos) {
    PlayerChapter? active;
    for (final c in chapters) {
      if (c.startMs <= pos.inMilliseconds) active = c;
    }
    return active;
  }

  PlayerChapter? nextChapterInIntroWindow(Duration position) {
    final maxMs =
        AppSpacing.introSkipWindowSeconds * AppSpacing.millisecondsPerSecond;
    final posMs = position.inMilliseconds;
    for (var i = 0; i < chapters.length - 1; i++) {
      final current = chapters[i];
      if (current.startMs <= maxMs &&
          _introChapterPattern.hasMatch(current.title)) {
        final next = chapters[i + 1];
        if (next.startMs > posMs && next.startMs <= maxMs) {
          return next;
        }
      }
    }
    return null;
  }

  Future<void> jumpToNextChapter(Duration position) async {
    for (final c in chapters) {
      if (c.startMs >
          position.inMilliseconds + AppSpacing.millisecondsPerSecond) {
        await _player.seek(Duration(milliseconds: c.startMs));
        _overlays.showActionOsd(PlayerActionOsdKind.chapter, c.title);
        return;
      }
    }
  }

  Future<void> jumpToPreviousChapter(Duration position) async {
    PlayerChapter? target;
    final cutoff =
        position.inMilliseconds - (2 * AppSpacing.millisecondsPerSecond);
    for (final c in chapters) {
      if (c.startMs < cutoff) target = c;
    }
    if (target != null) {
      await _player.seek(Duration(milliseconds: target.startMs));
      _overlays.showActionOsd(PlayerActionOsdKind.chapter, target.title);
    }
  }

  Future<void> skipIntro(
    PlaybackQueueEntry? entry,
    Duration position,
    Duration duration,
  ) async {
    introSkipped = true;
    final nextChapter = nextChapterInIntroWindow(position);
    if (nextChapter != null) {
      await _player.seek(Duration(milliseconds: nextChapter.startMs));
    } else {
      final targetMs = (position.inMilliseconds +
              effectiveIntroSkipSeconds * AppSpacing.millisecondsPerSecond)
          .clamp(0, duration.inMilliseconds);
      await _player.seek(Duration(milliseconds: targetMs));
      if (entry?.seriesId != null && seriesIntroSkipSeconds == 0) {
        setSeriesIntroSkipSeconds(entry?.seriesId, effectiveIntroSkipSeconds);
      }
    }
    _overlays.showActionOsd(
      PlayerActionOsdKind.introSkip,
      AppStrings.playerIntroSkipButton,
    );
    _onChanged();
  }

  void setSeriesIntroSkipSeconds(int? seriesId, int seconds) {
    seriesIntroSkipSeconds =
        seconds.clamp(0, AppSpacing.introSkipWindowSeconds);
    if (seriesId != null) {
      _persistence.saveSeriesIntroSkip(seriesId, seriesIntroSkipSeconds);
    }
    _onChanged();
  }

  void addBookmark(PlaybackQueueEntry? entry, Duration position, String label) {
    if (entry == null) return;
    _persistence.addBookmark(entry.mediaKey, position.inMilliseconds,
        label: label);
    bookmarks = _persistence.loadBookmarks(entry.mediaKey);
    _overlays.showActionOsd(
      PlayerActionOsdKind.bookmark,
      AppStrings.playerBookmarkAddedOsd,
    );
    _onChanged();
  }

  void deleteBookmark(PlaybackQueueEntry? entry, int bookmarkId) {
    _persistence.deleteBookmark(bookmarkId);
    if (entry != null) bookmarks = _persistence.loadBookmarks(entry.mediaKey);
    _overlays.showActionOsd(
      PlayerActionOsdKind.bookmark,
      AppStrings.playerBookmarkDeletedOsd,
    );
    _onChanged();
  }

  Future<void> seekToBookmark(MediaBookmark bookmark) async {
    await _player.seek(Duration(milliseconds: bookmark.positionMs));
    _overlays.showActionOsd(
      PlayerActionOsdKind.bookmark,
      Formatters.formatPlayerDuration(
          Duration(milliseconds: bookmark.positionMs)),
    );
  }

  Future<String?> captureScreenshot(
    PlaybackQueueEntry? entry, {
    required bool Function() isStale,
  }) async {
    if (entry == null || isStale()) return null;
    try {
      final bytes = await _player.screenshot(format: 'image/png');
      if (isStale()) return null;
      if (bytes == null || bytes.isEmpty) {
        _overlays.showActionOsd(
          PlayerActionOsdKind.screenshot,
          AppStrings.playerScreenshotFailedOsd,
        );
        return null;
      }
      final saved = await _onSaveScreenshot(bytes, entry.title);
      if (isStale()) return saved;
      _overlays.showActionOsd(
        PlayerActionOsdKind.screenshot,
        saved != null
            ? AppStrings.playerScreenshotSavedOsd
            : AppStrings.playerScreenshotFailedOsd,
      );
      return saved;
    } catch (_) {
      if (!isStale()) {
        _overlays.showActionOsd(
          PlayerActionOsdKind.screenshot,
          AppStrings.playerScreenshotFailedOsd,
        );
      }
      return null;
    }
  }

  void cycleTimeDisplayMode() {
    const modes = TimeDisplayMode.values;
    timeDisplayMode = modes[(timeDisplayMode.index + 1) % modes.length];
    _onChanged();
  }

  Future<void> stepFrame({
    required bool forward,
    required bool isPlaying,
  }) async {
    if (isPlaying) {
      await _player.pause();
    }
    await _mpvBridge.sendCommand([forward ? 'frame-step' : 'frame-back-step']);
    _overlays.showActionOsd(
      PlayerActionOsdKind.frameStep,
      forward ? AppStrings.osdFrameStepForward : AppStrings.osdFrameStepBack,
    );
  }

  String formatRightTimeLabel(
      Duration pos, Duration dur, double speed, DateTime now) {
    switch (timeDisplayMode) {
      case TimeDisplayMode.total:
        return Formatters.formatPlayerDuration(dur);
      case TimeDisplayMode.remaining:
        return Formatters.formatRemainingDuration(pos, dur);
      case TimeDisplayMode.finishTime:
        return Formatters.formatEstimatedFinishTime(pos, dur, speed, now);
    }
  }

  Future<void> enterMiniPlayer() async {
    _wasMaximizedBeforeMiniPlayer = await _windowAdapter.isWindowMaximized();
    if (_wasMaximizedBeforeMiniPlayer) {
      await _windowAdapter.unmaximizeWindow();
    }
    _boundsBeforeMiniPlayer = await _windowAdapter.getWindowBounds();
    await _windowAdapter.setWindowMinimumSize(
      const Size(AppSpacing.miniPlayerMinWidth, AppSpacing.miniPlayerMinHeight),
    );
    await _windowAdapter.setWindowBounds(
      Rect.fromLTWH(
        _boundsBeforeMiniPlayer!.left,
        _boundsBeforeMiniPlayer!.top,
        AppSpacing.miniPlayerWidth,
        AppSpacing.miniPlayerHeight,
      ),
    );
    await _windowAdapter.setAlwaysOnTop(true);
    _overlays.closeTopOverlay();
    isMiniPlayer = true;
    _onChanged();
  }

  Future<void> exitMiniPlayer() async {
    if (!isMiniPlayer) return;
    isMiniPlayer = false;
    await _windowAdapter.setAlwaysOnTop(false);
    await _windowAdapter.setWindowMinimumSize(
      const Size(AppSpacing.minWindowWidth, AppSpacing.minWindowHeight),
    );
    if (_boundsBeforeMiniPlayer != null) {
      await _windowAdapter.setWindowBounds(_boundsBeforeMiniPlayer!);
      _boundsBeforeMiniPlayer = null;
    }
    if (_wasMaximizedBeforeMiniPlayer) {
      _wasMaximizedBeforeMiniPlayer = false;
      await _windowAdapter.maximizeWindow();
    }
    _onChanged();
  }
}
