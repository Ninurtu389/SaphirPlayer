import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/services/local_file_service.dart';
import '../../core/utils/formatters.dart';
import 'mpv_property_bridge.dart';
import 'playback_session.dart';
import 'player_features_delegate.dart';
import 'player_models.dart';
import 'player_overlays_controller.dart';

class PlayerTransportDelegate {
  PlayerTransportDelegate({
    required Player player,
    required IMpvPropertyBridge mpvBridge,
    required PlayerWindowAdapter windowAdapter,
    required PlayerFeaturesDelegate features,
    required PlayerOverlaysController overlays,
    required SettingsController? settingsController,
    required VoidCallback onChanged,
  })  : _player = player,
        _mpvBridge = mpvBridge,
        _windowAdapter = windowAdapter,
        _features = features,
        _overlays = overlays,
        _settingsController = settingsController,
        _onChanged = onChanged;

  final Player _player;
  final IMpvPropertyBridge _mpvBridge;
  final PlayerWindowAdapter _windowAdapter;
  final PlayerFeaturesDelegate _features;
  final PlayerOverlaysController _overlays;
  final SettingsController? _settingsController;
  final VoidCallback _onChanged;

  bool isFullscreen = false;
  double volume = AppSpacing.volumeMax;
  double volumeBeforeMute = AppSpacing.volumeMax;
  double playbackSpeed = 1.0;

  bool get isMuted => volume <= AppSpacing.volumeMin;

  Future<({bool opened, String? errorMessage})> prepareAndOpenEntry(
    PlaybackQueueEntry entry, {
    required int startPosMs,
    required bool Function() isStale,
  }) async {
    _features.resetForEntry(entry);
    await _features.resetEntryMpvProperties();
    if (isStale()) return (opened: false, errorMessage: null);
    return openEntryMedia(entry, startPosMs: startPosMs, isStale: isStale);
  }

  Future<({bool opened, String? errorMessage})> openEntryMedia(
    PlaybackQueueEntry entry, {
    required int startPosMs,
    required bool Function() isStale,
  }) async {
    final status = await LocalFileService.checkPlayableFile(entry.filePath);
    if (isStale()) return (opened: false, errorMessage: null);
    if (status != PlayableFileStatus.ok) {
      return (
        opened: false,
        errorMessage: status == PlayableFileStatus.missing
            ? AppStrings.playerFileMissingError
            : AppStrings.playerEmptyFileError,
      );
    }
    try {
      await _mpvBridge.setHardwareDecoding(
        _settingsController?.hardwareAccelerationEnabled ?? true,
      );
      await _mpvBridge.setProperty('start', 'none');
      await _player.open(
        Media(
          entry.filePath,
          start: startPosMs > 0 ? Duration(milliseconds: startPosMs) : null,
        ),
        play: true,
      );
      if (isStale()) return (opened: false, errorMessage: null);
      await _features.applySubtitleStyle();
      return (opened: true, errorMessage: null);
    } catch (_) {
      return (opened: false, errorMessage: AppStrings.playerPlaybackError);
    }
  }

  Future<void> togglePlayPause({required bool isPlaying}) async {
    _overlays.registerUserActivity(isPlaying: isPlaying);
    await _player.playOrPause();
  }

  Future<void> seekRelativeSeconds(
    int deltaSeconds, {
    required Duration position,
    required Duration duration,
  }) async {
    final maxMs =
        duration.inMilliseconds > 0 ? duration.inMilliseconds : 1 << 30;
    final targetMs = (position.inMilliseconds +
            (deltaSeconds * AppSpacing.millisecondsPerSecond))
        .clamp(0, maxMs);
    await _player.seek(Duration(milliseconds: targetMs));
    _overlays.showActionOsd(
      deltaSeconds >= 0
          ? PlayerActionOsdKind.seekForward
          : PlayerActionOsdKind.seekBack,
      Formatters.formatSeekOsd(deltaSeconds),
    );
  }

  Future<void> seekToRatio(
    double ratio, {
    required Duration duration,
    required bool isPlaying,
  }) async {
    _overlays.registerUserActivity(isPlaying: isPlaying);
    if (duration.inMilliseconds <= 0) return;
    await _player.seek(
      Duration(
        milliseconds: (duration.inMilliseconds * ratio.clamp(0.0, 1.0)).round(),
      ),
    );
  }

  Future<void> adjustVolume(double delta) async {
    final next =
        (volume + delta).clamp(AppSpacing.volumeMin, _features.maxVolume);
    await _player.setVolume(next);
    _overlays.showActionOsd(
      PlayerActionOsdKind.volume,
      Formatters.formatVolumePercent(next),
    );
  }

  Future<void> toggleMute() async {
    if (isMuted) {
      final restored = volumeBeforeMute > AppSpacing.volumeMin
          ? volumeBeforeMute.clamp(AppSpacing.volumeMin, _features.maxVolume)
          : AppSpacing.volumeMax;
      await _player.setVolume(restored);
      _overlays.showActionOsd(PlayerActionOsdKind.mute, AppStrings.osdMuteOff);
    } else {
      volumeBeforeMute = volume;
      await _player.setVolume(AppSpacing.volumeMin);
      _overlays.showActionOsd(PlayerActionOsdKind.mute, AppStrings.osdMuteOn);
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeed = speed;
    await _player.setRate(speed);
    _overlays.showActionOsd(
      PlayerActionOsdKind.speed,
      Formatters.formatPlaybackSpeed(speed),
    );
    _onChanged();
  }

  void setSleepTimer(
    SleepTimerOption option, {
    Duration? customDuration,
    required bool Function() isStale,
  }) {
    _overlays.setSleepTimer(
      option,
      customDuration: customDuration,
      onExpired: () async {
        if (isStale()) return;
        await _player.pause();
        if (isStale()) return;
        _overlays.showActionOsd(
          PlayerActionOsdKind.sleepTimer,
          AppStrings.sleepTimerTriggeredOsd,
        );
      },
    );
    _overlays.showActionOsd(
      PlayerActionOsdKind.sleepTimer,
      option == SleepTimerOption.off
          ? AppStrings.osdSleepTimerOff
          : '${AppStrings.osdSleepTimerSetPrefix} ${Formatters.formatSleepTimerOptionLabel(option)}',
    );
  }

  Future<void> toggleMiniPlayer() async {
    if (_features.isMiniPlayer) {
      await _features.exitMiniPlayer();
      return;
    }
    if (isFullscreen) {
      isFullscreen = false;
      await _windowAdapter.setFullScreen(false);
    }
    await _features.enterMiniPlayer();
  }

  Future<void> startMiniPlayerWindowDrag() =>
      _windowAdapter.startWindowDragging();

  Future<void> applyDurationPostActions({
    required Duration duration,
    required Duration position,
    required int? pendingStartPositionMs,
    required void Function() clearPendingStartPosition,
    required bool Function() isStale,
  }) async {
    if (duration > Duration.zero && !_features.chaptersLoadedForEntry) {
      _features.chaptersLoadedForEntry = true;
      await _features.loadChapters(isStale);
      if (isStale()) return;
    }
    if (pendingStartPositionMs != null && duration > Duration.zero) {
      clearPendingStartPosition();
      if (pendingStartPositionMs < duration.inMilliseconds &&
          position.inMilliseconds <
              pendingStartPositionMs - (2 * AppSpacing.millisecondsPerSecond)) {
        await _player.seek(Duration(milliseconds: pendingStartPositionMs));
      }
    }
  }

  Future<bool> handleSleepTimerAtCompletion({
    required bool Function() isStale,
  }) async {
    if (_overlays.sleepTimerOption != SleepTimerOption.endOfEpisode) {
      return false;
    }
    _overlays.cancelSleepTimer();
    await _player.pause();
    if (!isStale()) {
      _overlays.showActionOsd(
        PlayerActionOsdKind.sleepTimer,
        AppStrings.sleepTimerTriggeredOsd,
      );
    }
    return true;
  }

  Future<void> toggleFullscreen({required bool isPlaying}) async {
    if (_features.isMiniPlayer) await _features.exitMiniPlayer();
    _overlays.registerUserActivity(isPlaying: isPlaying);
    isFullscreen = !isFullscreen;
    await _windowAdapter.setFullScreen(isFullscreen);
    _onChanged();
  }

  Future<void> resetForSession({required bool forceMpvReset}) async {
    if (_features.isVolumeBoostEnabled && volume > AppSpacing.volumeMax) {
      volume = AppSpacing.volumeMax;
      try {
        await _player.setVolume(AppSpacing.volumeMax);
      } catch (_) {}
    }
    if (playbackSpeed != 1.0 || forceMpvReset) {
      playbackSpeed = 1.0;
      try {
        await _player.setRate(1.0);
      } catch (_) {}
    }
  }

  Future<void> exitWindowStatesOnClose() async {
    await _features.exitMiniPlayer();
    if (isFullscreen) {
      isFullscreen = false;
      await _windowAdapter.setFullScreen(false);
    }
  }
}
