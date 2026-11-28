import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/progress_sync_service.dart';
import 'mpv_property_bridge.dart';
import 'playback_persistence_service.dart';
import 'playback_session.dart';
import 'player_features_delegate.dart';
import 'player_models.dart';
import 'player_overlays_controller.dart';
import 'player_stream_coordinator.dart';
import 'player_tracks_delegate.dart';
import 'player_transport_delegate.dart';

class SaphirPlayerController extends ChangeNotifier {
  SaphirPlayerController(
    DatabaseService databaseService,
    ProgressSyncService syncService,
    List<String> Function() getNasPaths, {
    SettingsController? settingsController,
    Player? player,
    VideoController? videoController,
    IMpvPropertyBridge? mpvBridge,
    PlayerWindowAdapter? windowAdapter,
    Future<void> Function(bool fullscreen)? onSetFullScreen,
    Future<String?> Function(Uint8List bytes, String title)? onSaveScreenshot,
  }) {
    final d = PlayerControllerDelegates.assemble(
      databaseService: databaseService,
      syncService: syncService,
      getNasPaths: getNasPaths,
      settingsController: settingsController,
      player: player,
      videoController: videoController,
      mpvBridge: mpvBridge,
      windowAdapter: windowAdapter,
      onSetFullScreen: onSetFullScreen,
      onSaveScreenshot: onSaveScreenshot,
      onChanged: _safeNotify,
    );
    _persistence = d.persistence;
    _player = d.player;
    _videoController = d.videoController;
    _overlays = d.overlays;
    _features = d.features;
    _tracks = d.tracks;
    _transport = d.transport;
    _streams = d.streams;
    _bindStreams();
  }

  late final PlaybackPersistenceService _persistence;
  late final Player _player;
  late final VideoController _videoController;
  late final PlayerOverlaysController _overlays;
  late final PlayerFeaturesDelegate _features;
  late final PlayerTracksDelegate _tracks;
  late final PlayerTransportDelegate _transport;
  late final PlayerStreamCoordinator _streams;
  bool _playerDisposed = false;
  int? _pendingStartPositionMs;

  PlaybackSession? _session;
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _autoNextDismissed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _errorMessage;

  ValueNotifier<({Duration position, Duration duration})>
      get progressListenable => _streams.progressListenable;
  VideoController get videoController => _videoController;
  PlaybackSession? get session => _session;
  PlaybackQueueEntry? get currentEntry =>
      (_session == null || _session!.queue.isEmpty)
          ? null
          : _session!.queue[_currentIndex.clamp(0, _session!.queue.length - 1)];
  PlaybackQueueEntry? get nextEntry =>
      hasNextEpisode ? _session!.queue[_currentIndex + 1] : null;
  int get currentIndex => _currentIndex;
  bool get hasPreviousEpisode => _currentIndex > 0;
  bool get hasNextEpisode =>
      _session != null && _currentIndex + 1 < _session!.queue.length;
  bool get isPlaying => _isPlaying;
  bool get isFullscreen => _transport.isFullscreen;
  bool get isMiniPlayer => _features.isMiniPlayer;
  bool get isHudVisible => _overlays.isHudVisible;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _transport.volume;
  double get maxVolume => _features.maxVolume;
  bool get isMuted => _transport.isMuted;
  double get playbackSpeed => _transport.playbackSpeed;
  List<AudioTrack> get audioTracks => _tracks.audioTracks;
  List<SubtitleTrack> get subtitleTracks => _tracks.subtitleTracks;
  AudioTrack get activeAudioTrack => _tracks.activeAudioTrack;
  SubtitleTrack get activeSubtitleTrack => _tracks.activeSubtitleTrack;
  String? get errorMessage => _errorMessage;
  bool get isNightMode => _features.isNightMode;
  bool get isVolumeBoostEnabled => _features.isVolumeBoostEnabled;
  VideoAspectMode get aspectMode => _features.aspectMode;
  int get audioDelayMs => _features.audioDelayMs;
  int get subtitleDelayMs => _features.subtitleDelayMs;
  List<PlayerChapter> get chapters => _features.chapters;
  int get seriesIntroSkipSeconds => _features.seriesIntroSkipSeconds;
  int get effectiveIntroSkipSeconds => _features.effectiveIntroSkipSeconds;
  List<MediaBookmark> get bookmarks => _features.bookmarks;
  TimeDisplayMode get timeDisplayMode => _features.timeDisplayMode;
  double get subtitleScale => _features.subtitleScale;
  int get subtitlePosition => _features.subtitlePosition;
  double get subtitleBgOpacity => _features.subtitleBgOpacity;
  String? get osdMessage => _overlays.osdMessage;
  PlayerActionOsdKind? get osdKind => _overlays.osdKind;
  bool get showDiagnostics => _overlays.showDiagnostics;
  PlayerDiagnostics? get diagnostics => _overlays.diagnostics;
  bool get isEpisodeDrawerOpen => _overlays.isEpisodeDrawerOpen;
  bool get isShortcutSheetOpen => _overlays.isShortcutSheetOpen;
  SleepTimerOption get sleepTimerOption => _overlays.sleepTimerOption;
  Duration? get sleepTimerRemaining => _overlays.sleepTimerRemaining;

  int get autoNextRemainingSeconds => _features.computeAutoNextRemainingSeconds(
        hasNextEpisode: hasNextEpisode,
        autoNextDismissed: _autoNextDismissed,
        sleepTimerOption: sleepTimerOption,
        position: _position,
        duration: _duration,
      );
  bool get showAutoNextCard => autoNextRemainingSeconds > 0;
  bool get showIntroSkipButton => _features.canShowIntroSkipButton(
        entry: currentEntry,
        errorMessage: _errorMessage,
        position: _position,
        duration: _duration,
      );

  void dismissAutoNext() {
    _autoNextDismissed = true;
    _safeNotify();
  }

  void dismissIntroSkip() => _features.dismissIntroSkip();

  void _bindStreams() {
    _streams.bind(
      onPlaying: _onPlayingChanged,
      onPosition: _onPositionChanged,
      onDuration: _onDurationChanged,
      onVolume: (vol) {
        if (_streams.isDisposed) return;
        _transport.volume = vol;
        _safeNotify();
      },
      onTracks: (tracks) {
        if (_streams.isDisposed) return;
        _tracks.onAvailableTracksChanged(
          tracks,
          entry: currentEntry,
          isStale: _streams.captureStaleCheck(),
        );
      },
      onTrack: (track) {
        if (!_streams.isDisposed) _tracks.onActiveTrackChanged(track);
      },
      onCompleted: _onCompletedChanged,
      onError: (error) {
        if (_streams.isDisposed || error.trim().isEmpty) return;
        _streams.stopProgressTimer();
        _errorMessage = AppStrings.playerPlaybackError;
        _safeNotify();
      },
    );
  }

  void _onPositionChanged(Duration pos) {
    if (_streams.isDisposed) return;
    final prevIntro = showIntroSkipButton;
    final prevAutoNext = autoNextRemainingSeconds;
    _position = pos;
    _streams.updateProgressNotifier(position: _position, duration: _duration);
    if (showIntroSkipButton != prevIntro ||
        autoNextRemainingSeconds != prevAutoNext) {
      _safeNotify();
    }
  }

  void _onDurationChanged(Duration dur) {
    if (_streams.isDisposed) return;
    _duration = dur;
    unawaited(
      _transport.applyDurationPostActions(
        duration: dur,
        position: _position,
        pendingStartPositionMs: _pendingStartPositionMs,
        clearPendingStartPosition: () => _pendingStartPositionMs = null,
        isStale: _streams.captureStaleCheck(),
      ),
    );
    _streams.updateProgressNotifier(
      position: _position,
      duration: _duration,
      force: true,
    );
    _safeNotify();
  }

  void _onPlayingChanged(bool playing) {
    if (_streams.isDisposed) return;
    _isPlaying = playing;
    if (!playing) {
      _persistence.recordWatchHistorySlice(currentEntry, isPlaying: false);
      _streams.stopProgressTimer();
      _persistProgress(syncRemote: true);
      _overlays.showHud(isPlaying: false, keepVisibleWhilePaused: true);
    } else {
      _persistence.startPlaySegmentIfNeeded();
      _streams.startProgressTimer(() => _persistProgress(syncRemote: false));
      registerUserActivity();
    }
    _safeNotify();
  }

  Future<void> _onCompletedChanged(bool completed) async {
    if (_streams.isDisposed || !completed) return;
    final isStale = _streams.captureStaleCheck();
    _persistProgress(forceCompleted: true, syncRemote: true);
    final handled = await _transport.handleSleepTimerAtCompletion(
      isStale: isStale,
    );
    if (handled || isStale()) return;
    if (hasNextEpisode && !_autoNextDismissed) {
      await playNextEpisode(skipPersist: true);
    }
  }

  void _resetTransientEntryFields({required bool closeOverlays}) {
    _streams.stopProgressTimer();
    if (closeOverlays) {
      _overlays.resetForClose();
    } else {
      _overlays.resetForEntry();
    }
    _persistence.resetHistoryTracking();
    _tracks.resetForEntry();
    _isPlaying = false;
    _autoNextDismissed = false;
    _errorMessage = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _pendingStartPositionMs = null;
  }

  Future<void> startSession(PlaybackSession newSession) async {
    if (_streams.isDisposed || newSession.queue.isEmpty) return;
    if (_session != null) {
      _persistence.recordWatchHistorySlice(currentEntry, isPlaying: false);
      _persistProgress(syncRemote: false);
    }
    await _resetSessionState();
    if (_streams.isDisposed) return;
    _session = newSession;
    _currentIndex =
        newSession.initialIndex.clamp(0, newSession.queue.length - 1);
    await _openEntryAtIndex(_currentIndex);
  }

  Future<void> _resetSessionState({bool forceMpvReset = false}) async {
    _streams.bumpRequestId();
    _resetTransientEntryFields(closeOverlays: true);
    await _transport.resetForSession(forceMpvReset: forceMpvReset);
    await _features.resetSessionState(forceMpvReset: forceMpvReset);
    _streams.updateProgressNotifier(
      position: _position,
      duration: _duration,
      force: true,
    );
  }

  Future<void> _openEntryAtIndex(int index) async {
    final s = _session;
    if (_streams.isDisposed ||
        s == null ||
        index < 0 ||
        index >= s.queue.length) {
      return;
    }
    final requestId = _streams.bumpRequestId();
    bool isStale() => _streams.isStale(requestId);
    _currentIndex = index;
    _resetTransientEntryFields(closeOverlays: false);
    final entry = s.queue[_currentIndex];
    final startPosMs = _persistence.loadSavedResumePositionMs(entry.mediaKey) ??
        entry.startPositionMs;
    _pendingStartPositionMs = startPosMs > 0 ? startPosMs : null;
    _streams.updateProgressNotifier(
      position: _position,
      duration: _duration,
      force: true,
    );
    _safeNotify();
    final result = await _transport.prepareAndOpenEntry(
      entry,
      startPosMs: startPosMs,
      isStale: isStale,
    );
    if (isStale()) return;
    if (!result.opened) {
      _errorMessage = result.errorMessage;
      _safeNotify();
      return;
    }
    _streams.startProgressTimer(() => _persistProgress(syncRemote: false));
    registerUserActivity();
  }

  Future<void> togglePlayPause() =>
      _transport.togglePlayPause(isPlaying: _isPlaying);
  Future<void> seekRelativeSeconds(int deltaSeconds) =>
      _transport.seekRelativeSeconds(deltaSeconds,
          position: _position, duration: _duration);
  Future<void> seekToRatio(double ratio) =>
      _transport.seekToRatio(ratio, duration: _duration, isPlaying: _isPlaying);
  Future<void> adjustVolume(double delta) => _transport.adjustVolume(delta);
  Future<void> toggleMute() => _transport.toggleMute();
  Future<void> setPlaybackSpeed(double speed) =>
      _transport.setPlaybackSpeed(speed);
  Future<void> playNextEpisode({bool skipPersist = false}) =>
      _switchEpisode(_currentIndex + 1, hasNextEpisode,
          skipPersist: skipPersist);
  Future<void> playPreviousEpisode() =>
      _switchEpisode(_currentIndex - 1, hasPreviousEpisode);

  Future<void> _switchEpisode(int index, bool allowed,
      {bool skipPersist = false}) async {
    if (!allowed) return;
    _streams.stopProgressTimer();
    if (!skipPersist) _persistProgress(syncRemote: true);
    await _openEntryAtIndex(index);
  }

  Future<void> playEntryAtIndex(int index) async {
    if (_session == null || index < 0 || index >= _session!.queue.length) {
      return;
    }
    _overlays.closeEpisodeDrawer();
    _streams.stopProgressTimer();
    _persistProgress(syncRemote: true);
    await _openEntryAtIndex(index);
  }

  Future<void> selectAudioTrack(AudioTrack track) {
    registerUserActivity();
    return _tracks.selectAudioTrack(track,
        entry: currentEntry, isStale: _streams.captureStaleCheck());
  }

  Future<void> selectSubtitleTrack(SubtitleTrack track) {
    registerUserActivity();
    return _tracks.selectSubtitleTrack(track,
        entry: currentEntry, isStale: _streams.captureStaleCheck());
  }

  Future<void> loadExternalSubtitle(String dialogTitle) =>
      _features.loadExternalSubtitle(
        dialogTitle,
        isStale: _streams.captureStaleCheck(),
        onTrackSelected: _tracks.setExternalSubtitleActive,
      );

  Future<void> toggleNightMode() => _features.toggleNightMode();
  Future<void> toggleVolumeBoost() => _features.toggleVolumeBoost(volume);
  Future<void> setAspectMode(VideoAspectMode m) => _features.setAspectMode(m);
  Future<void> cycleAspectMode() => setAspectMode(VideoAspectMode.values[
      (_features.aspectMode.index + 1) % VideoAspectMode.values.length]);
  Future<void> adjustAudioDelay(int ms) => _features.adjustAudioDelay(ms);
  Future<void> resetAudioDelay() => adjustAudioDelay(-audioDelayMs);
  Future<void> adjustSubtitleDelay(int ms) => _features.adjustSubtitleDelay(ms);
  Future<void> resetSubtitleDelay() => adjustSubtitleDelay(-subtitleDelayMs);
  Future<void> updateLiveSubtitleStyle(
          {double? scale, int? position, double? bgOpacity}) =>
      _features.updateLiveSubtitleStyle(
          scale: scale, position: position, bgOpacity: bgOpacity);
  PlayerChapter? chapterAtPosition(Duration pos) =>
      _features.chapterAtPosition(pos);
  Future<void> jumpToNextChapter() => _features.jumpToNextChapter(_position);
  Future<void> jumpToPreviousChapter() =>
      _features.jumpToPreviousChapter(_position);
  Future<void> skipIntro() =>
      _features.skipIntro(currentEntry, _position, _duration);
  void setSeriesIntroSkipSeconds(int s) =>
      _features.setSeriesIntroSkipSeconds(currentEntry?.seriesId, s);
  void addBookmarkAtCurrentPosition({String label = ''}) =>
      _features.addBookmark(currentEntry, _position, label);
  void deleteBookmark(int id) => _features.deleteBookmark(currentEntry, id);
  Future<void> seekToBookmark(MediaBookmark bm) => _features.seekToBookmark(bm);
  Future<String?> captureScreenshot() => _features
      .captureScreenshot(currentEntry, isStale: _streams.captureStaleCheck());
  void cycleTimeDisplayMode() => _features.cycleTimeDisplayMode();
  String formatRightTimeLabel({DateTime? now}) =>
      _features.formatRightTimeLabel(
          _position, _duration, playbackSpeed, now ?? DateTime.now());
  Future<void> stepFrame({required bool forward}) =>
      _features.stepFrame(forward: forward, isPlaying: _isPlaying);
  void showActionOsd(PlayerActionOsdKind kind, String message) =>
      _overlays.showActionOsd(kind, message);
  void toggleDiagnostics() => _overlays.toggleDiagnostics();
  void toggleEpisodeDrawer() => _overlays.toggleEpisodeDrawer();
  void toggleShortcutSheet() => _overlays.toggleShortcutSheet();
  bool closeTopOverlay() => _overlays.closeTopOverlay();
  void setSleepTimer(SleepTimerOption option, {Duration? customDuration}) =>
      _transport.setSleepTimer(option,
          customDuration: customDuration,
          isStale: _streams.captureStaleCheck());
  Future<void> toggleMiniPlayer() => _transport.toggleMiniPlayer();
  Future<void> startMiniPlayerWindowDrag() =>
      _transport.startMiniPlayerWindowDrag();
  Future<void> toggleFullscreen() =>
      _transport.toggleFullscreen(isPlaying: _isPlaying);
  void setMenuOrDialogOpen(bool open) =>
      _overlays.setMenuOrDialogOpen(open, isPlaying: _isPlaying);
  void registerUserActivity() =>
      _overlays.registerUserActivity(isPlaying: _isPlaying);
  void showHud({bool keepVisibleWhilePaused = false}) => _overlays.showHud(
      isPlaying: _isPlaying, keepVisibleWhilePaused: keepVisibleWhilePaused);

  Future<void> stopAndClose() async {
    _persistence.recordWatchHistorySlice(currentEntry, isPlaying: false);
    _persistProgress(syncRemote: true);
    await _resetSessionState(forceMpvReset: true);
    await _player.stop();
    await _transport.exitWindowStatesOnClose();
    _session = null;
    _safeNotify();
  }

  void _persistProgress(
          {bool forceCompleted = false, bool syncRemote = false}) =>
      _streams.persistProgress(
        entry: currentEntry,
        isPlaying: _isPlaying,
        position: _position,
        duration: _duration,
        forceCompleted: forceCompleted,
        syncRemote: syncRemote,
      );

  void _safeNotify() {
    if (!_streams.isDisposed) notifyListeners();
  }

  void _teardownResources() {
    _streams.dispose();
    _overlays.dispose();
  }

  Future<void> disposeForShutdown() async {
    if (_playerDisposed) return;
    _persistence.recordWatchHistorySlice(currentEntry, isPlaying: false);
    _persistProgress(syncRemote: false);
    _persistence.resetHistoryTracking();
    _session = null;
    _teardownResources();
    _playerDisposed = true;
    await _player.dispose();
  }

  @override
  void dispose() {
    if (!_streams.isDisposed) _teardownResources();
    if (!_playerDisposed) {
      _playerDisposed = true;
      unawaited(_player.dispose());
    }
    super.dispose();
  }
}
