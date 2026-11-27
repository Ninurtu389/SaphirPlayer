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
  final Future<String?> Function(Uint8List bytes, String title) _onSaveScreenshot;
  final VoidCallback _onChanged;

  bool isNightMode = false;
  bool isVolumeBoostEnabled = false;
  VideoAspectMode aspectMode = VideoAspectMode.original;
  int audioDelayMs = 0;
  int subtitleDelayMs = 0;
  List<PlayerChapter> chapters = const [];
  bool chaptersLoadedForEntry = false;
  int seriesIntroSkipSeconds = 0;
  List<MediaBookmark> bookmarks = const [];
  TimeDisplayMode timeDisplayMode = TimeDisplayMode.total;
  bool isMiniPlayer = false;
  Rect? _boundsBeforeMiniPlayer;

  double get maxVolume =>
      isVolumeBoostEnabled ? AppSpacing.volumeBoostMax : AppSpacing.volumeMax;

  int get effectiveIntroSkipSeconds => seriesIntroSkipSeconds > 0
      ? seriesIntroSkipSeconds
      : AppSpacing.defaultIntroSkipSeconds;

  double get subtitleScale =>
      _settingsController?.subtitleScale ?? AppSpacing.subtitleScaleDefault;
  int get subtitlePosition =>
      _settingsController?.subtitlePosition ?? AppSpacing.subtitlePositionDefault;
  double get subtitleBgOpacity =>
      _settingsController?.subtitleBgOpacity ?? AppSpacing.subtitleBgOpacityDefault;

  void resetForEntry(PlaybackQueueEntry entry) {
    chapters = const [];
    chaptersLoadedForEntry = false;
    bookmarks = _persistence.loadBookmarks(entry.mediaKey);
    seriesIntroSkipSeconds = entry.seriesId != null
        ? (_persistence.loadSeriesPreferences(entry.seriesId!)?.introSkipSeconds ??
            0)
        : 0;
  }

  Future<void> loadChapters(bool Function() isDisposed) async {
    final loaded = await _mpvBridge.readChapters();
    if (isDisposed()) return;
    chapters = loaded;
    _onChanged();
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
    audioDelayMs =
        (audioDelayMs + deltaMs).clamp(AppSpacing.delayMinMs, AppSpacing.delayMaxMs);
    await _mpvBridge.setAudioDelay(audioDelayMs / AppSpacing.millisecondsPerSecond);
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
    for (final c in chapters) {
      if (c.startMs > position.inMilliseconds && c.startMs <= maxMs) return c;
    }
    return null;
  }

  Future<void> jumpToNextChapter(Duration position) async {
    for (final c in chapters) {
      if (c.startMs > position.inMilliseconds + AppSpacing.millisecondsPerSecond) {
        await _player.seek(Duration(milliseconds: c.startMs));
        _overlays.showActionOsd(PlayerActionOsdKind.chapter, c.title);
        return;
      }
    }
  }

  Future<void> jumpToPreviousChapter(Duration position) async {
    PlayerChapter? target;
    final cutoff = position.inMilliseconds - (2 * AppSpacing.millisecondsPerSecond);
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
  }

  void setSeriesIntroSkipSeconds(int? seriesId, int seconds) {
    seriesIntroSkipSeconds = seconds.clamp(0, AppSpacing.introSkipWindowSeconds);
    if (seriesId != null) {
      _persistence.saveSeriesIntroSkip(seriesId, seriesIntroSkipSeconds);
    }
    _onChanged();
  }

  void addBookmark(PlaybackQueueEntry? entry, Duration position, String label) {
    if (entry == null) return;
    _persistence.addBookmark(entry.mediaKey, position.inMilliseconds, label: label);
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
      Formatters.formatPlayerDuration(Duration(milliseconds: bookmark.positionMs)),
    );
  }

  Future<String?> captureScreenshot(PlaybackQueueEntry? entry) async {
    if (entry == null) return null;
    try {
      final bytes = await _player.screenshot(format: 'image/png');
      if (bytes == null || bytes.isEmpty) {
        _overlays.showActionOsd(
          PlayerActionOsdKind.screenshot,
          AppStrings.playerScreenshotFailedOsd,
        );
        return null;
      }
      final saved = await _onSaveScreenshot(bytes, entry.title);
      _overlays.showActionOsd(
        PlayerActionOsdKind.screenshot,
        saved != null
            ? AppStrings.playerScreenshotSavedOsd
            : AppStrings.playerScreenshotFailedOsd,
      );
      return saved;
    } catch (_) {
      _overlays.showActionOsd(
        PlayerActionOsdKind.screenshot,
        AppStrings.playerScreenshotFailedOsd,
      );
      return null;
    }
  }

  void cycleTimeDisplayMode() {
    const modes = TimeDisplayMode.values;
    timeDisplayMode = modes[(timeDisplayMode.index + 1) % modes.length];
    _onChanged();
  }

  String formatRightTimeLabel(Duration pos, Duration dur, double speed, DateTime now) {
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
    _onChanged();
  }
}
