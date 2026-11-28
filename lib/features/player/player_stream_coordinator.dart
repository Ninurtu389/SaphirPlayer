import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/services/local_file_service.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/progress_sync_service.dart';
import 'mpv_property_bridge.dart';
import 'playback_persistence_service.dart';
import 'playback_session.dart';
import 'player_features_delegate.dart';
import 'player_models.dart';
import 'player_overlays_controller.dart';
import 'player_tracks_delegate.dart';
import 'player_transport_delegate.dart';

class PlayerControllerDelegates {
  const PlayerControllerDelegates({
    required this.persistence,
    required this.player,
    required this.videoController,
    required this.overlays,
    required this.features,
    required this.tracks,
    required this.transport,
    required this.streams,
  });

  final PlaybackPersistenceService persistence;
  final Player player;
  final VideoController videoController;
  final PlayerOverlaysController overlays;
  final PlayerFeaturesDelegate features;
  final PlayerTracksDelegate tracks;
  final PlayerTransportDelegate transport;
  final PlayerStreamCoordinator streams;

  static PlayerControllerDelegates assemble({
    required DatabaseService databaseService,
    required ProgressSyncService syncService,
    required List<String> Function() getNasPaths,
    required SettingsController? settingsController,
    required Player? player,
    required VideoController? videoController,
    required IMpvPropertyBridge? mpvBridge,
    required PlayerWindowAdapter? windowAdapter,
    required Future<void> Function(bool fullscreen)? onSetFullScreen,
    required Future<String?> Function(Uint8List bytes, String title)?
        onSaveScreenshot,
    required VoidCallback onChanged,
  }) {
    final persistence = PlaybackPersistenceService(databaseService);
    final resolvedAdapter =
        windowAdapter ?? PlayerWindowAdapter(setFullScreen: onSetFullScreen);
    final resolvedPlayer = player ??
        Player(
          configuration: const PlayerConfiguration(title: AppStrings.appTitle),
        );
    final resolvedVideoController = videoController ??
        VideoController(
          resolvedPlayer,
          configuration: VideoControllerConfiguration(
            enableHardwareAcceleration:
                settingsController?.hardwareAccelerationEnabled ?? true,
          ),
        );
    final resolvedBridge = mpvBridge ?? MpvPropertyBridge(resolvedPlayer);
    final overlays = PlayerOverlaysController(
      mpvBridge: resolvedBridge,
      onChanged: onChanged,
    );
    final features = PlayerFeaturesDelegate(
      player: resolvedPlayer,
      mpvBridge: resolvedBridge,
      persistence: persistence,
      windowAdapter: resolvedAdapter,
      overlays: overlays,
      settingsController: settingsController,
      onSaveScreenshot: onSaveScreenshot ??
          (bytes, title) =>
              LocalFileService.saveScreenshotBytes(bytes: bytes, title: title),
      onChanged: onChanged,
    );
    final tracks = PlayerTracksDelegate(
      player: resolvedPlayer,
      persistence: persistence,
      overlays: overlays,
      settingsController: settingsController,
      onIntroSkipSecondsLoaded: (s) => features.seriesIntroSkipSeconds = s,
      onChanged: onChanged,
    );
    final transport = PlayerTransportDelegate(
      player: resolvedPlayer,
      mpvBridge: resolvedBridge,
      windowAdapter: resolvedAdapter,
      features: features,
      overlays: overlays,
      settingsController: settingsController,
      onChanged: onChanged,
    );
    final streams = PlayerStreamCoordinator(
      player: resolvedPlayer,
      persistence: persistence,
      syncService: syncService,
      getNasPaths: getNasPaths,
    );
    return PlayerControllerDelegates(
      persistence: persistence,
      player: resolvedPlayer,
      videoController: resolvedVideoController,
      overlays: overlays,
      features: features,
      tracks: tracks,
      transport: transport,
      streams: streams,
    );
  }
}

class PlayerStreamCoordinator {
  PlayerStreamCoordinator({
    required Player player,
    required PlaybackPersistenceService persistence,
    required ProgressSyncService syncService,
    required List<String> Function() getNasPaths,
  })  : _player = player,
        _persistence = persistence,
        _syncService = syncService,
        _getNasPaths = getNasPaths;

  final Player _player;
  final PlaybackPersistenceService _persistence;
  final ProgressSyncService _syncService;
  final List<String> Function() _getNasPaths;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _progressTimer;
  bool _isDisposed = false;
  int _openRequestId = 0;
  int _lastProgressNotifyMs = 0;
  int _lastNotifiedPositionSecond = -1;

  bool get isDisposed => _isDisposed;
  int bumpRequestId() => ++_openRequestId;
  bool isStale(int requestId) => _isDisposed || requestId != _openRequestId;
  bool Function() captureStaleCheck() {
    final requestId = _openRequestId;
    return () => _isDisposed || requestId != _openRequestId;
  }

  final ValueNotifier<({Duration position, Duration duration})>
      progressListenable =
      ValueNotifier((position: Duration.zero, duration: Duration.zero));

  void bind({
    required void Function(bool playing) onPlaying,
    required void Function(Duration pos) onPosition,
    required void Function(Duration dur) onDuration,
    required void Function(double vol) onVolume,
    required void Function(Tracks tracks) onTracks,
    required void Function(Track track) onTrack,
    required void Function(bool completed) onCompleted,
    required void Function(String error) onError,
  }) {
    _subscriptions.addAll([
      _player.stream.playing.listen(onPlaying),
      _player.stream.position.listen(onPosition),
      _player.stream.duration.listen(onDuration),
      _player.stream.volume.listen(onVolume),
      _player.stream.tracks.listen(onTracks),
      _player.stream.track.listen(onTrack),
      _player.stream.completed.listen(onCompleted),
      _player.stream.error.listen(onError),
    ]);
  }

  void updateProgressNotifier({
    required Duration position,
    required Duration duration,
    bool force = false,
  }) {
    if (_isDisposed) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final posSec = position.inSeconds;
    final durChanged = progressListenable.value.duration != duration;
    if (force ||
        durChanged ||
        position == Duration.zero ||
        posSec != _lastNotifiedPositionSecond ||
        nowMs - _lastProgressNotifyMs >= 250) {
      _lastNotifiedPositionSecond = posSec;
      _lastProgressNotifyMs = nowMs;
      progressListenable.value = (position: position, duration: duration);
    }
  }

  void startProgressTimer(void Function() onTick) {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: AppSpacing.progressSaveIntervalSeconds),
      (_) {
        if (!_isDisposed) onTick();
      },
    );
  }

  void stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void persistProgress({
    required PlaybackQueueEntry? entry,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    bool forceCompleted = false,
    bool syncRemote = false,
  }) {
    if (entry == null) return;
    if (isPlaying) _persistence.recordWatchHistorySlice(entry, isPlaying: true);
    _persistence.persistProgress(
      entry: entry,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      forceCompleted: forceCompleted,
    );
    if (syncRemote) unawaited(_syncService.syncWithRoots(_getNasPaths()));
  }

  void dispose() {
    _isDisposed = true;
    _openRequestId++;
    stopProgressTimer();
    progressListenable.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
