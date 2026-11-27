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
import '../../core/utils/formatters.dart';
import 'mpv_property_bridge.dart';
import 'playback_persistence_service.dart';
import 'playback_session.dart';
import 'player_features_delegate.dart';
import 'player_models.dart';
import 'player_overlays_controller.dart';
import 'track_preference_resolver.dart';

class SaphirPlayerController extends ChangeNotifier {
  SaphirPlayerController(
    DatabaseService databaseService,
    this._syncService,
    this._getNasPath, {
    SettingsController? settingsController,
    Player? player,
    VideoController? videoController,
    IMpvPropertyBridge? mpvBridge,
    PlayerWindowAdapter? windowAdapter,
    Future<void> Function(bool fullscreen)? onSetFullScreen,
    Future<String?> Function(Uint8List bytes, String title)? onSaveScreenshot,
  })  : _persistence = PlaybackPersistenceService(databaseService),
        _settingsController = settingsController,
        _windowAdapter =
            windowAdapter ?? PlayerWindowAdapter(setFullScreen: onSetFullScreen) {
    _player = player ??
        Player(configuration: const PlayerConfiguration(title: AppStrings.appTitle));
    _videoController = videoController ??
        VideoController(
          _player,
          configuration: VideoControllerConfiguration(
            enableHardwareAcceleration:
                settingsController?.hardwareAccelerationEnabled ?? true,
          ),
        );
    _mpvBridge = mpvBridge ?? MpvPropertyBridge(_player);
    _overlays = PlayerOverlaysController(mpvBridge: _mpvBridge, onChanged: _safeNotify);
    _features = PlayerFeaturesDelegate(
      player: _player,
      mpvBridge: _mpvBridge,
      persistence: _persistence,
      windowAdapter: _windowAdapter,
      overlays: _overlays,
      settingsController: _settingsController,
      onSaveScreenshot: onSaveScreenshot ??
          (bytes, title) =>
              LocalFileService.saveScreenshotBytes(bytes: bytes, title: title),
      onChanged: _safeNotify,
    );
    _bindStreams();
  }

  final PlaybackPersistenceService _persistence;
  final ProgressSyncService _syncService;
  final String Function() _getNasPath;
  final SettingsController? _settingsController;
  final PlayerWindowAdapter _windowAdapter;
  late final Player _player;
  late final VideoController _videoController;
  late final IMpvPropertyBridge _mpvBridge;
  late final PlayerOverlaysController _overlays;
  late final PlayerFeaturesDelegate _features;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _hudHideTimer;
  Timer? _progressTimer;
  bool _isDisposed = false;
  int _openRequestId = 0;
  int? _pendingStartPositionMs;

  PlaybackSession? _session;
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isFullscreen = false;
  bool _isHudVisible = true;
  bool _autoNextDismissed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = AppSpacing.volumeMax;
  double _volumeBeforeMute = AppSpacing.volumeMax;
  double _playbackSpeed = 1.0;
  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  AudioTrack _activeAudioTrack = AudioTrack.auto();
  SubtitleTrack _activeSubtitleTrack = SubtitleTrack.auto();
  String? _autoAppliedSubtitleId;
  String? _errorMessage;

  VideoController get videoController => _videoController;
  PlaybackSession? get session => _session;
  PlaybackQueueEntry? get currentEntry => (_session == null || _session!.queue.isEmpty)
      ? null
      : _session!.queue[_currentIndex.clamp(0, _session!.queue.length - 1)];
  PlaybackQueueEntry? get nextEntry =>
      hasNextEpisode ? _session!.queue[_currentIndex + 1] : null;
  int get currentIndex => _currentIndex;
  bool get hasPreviousEpisode => _currentIndex > 0;
  bool get hasNextEpisode =>
      _session != null && _currentIndex + 1 < _session!.queue.length;
  bool get isPlaying => _isPlaying;
  bool get isFullscreen => _isFullscreen;
  bool get isMiniPlayer => _features.isMiniPlayer;
  bool get isHudVisible => _isHudVisible;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  double get maxVolume => _features.maxVolume;
  bool get isMuted => _volume <= AppSpacing.volumeMin;
  double get playbackSpeed => _playbackSpeed;
  List<AudioTrack> get audioTracks => _audioTracks;
  List<SubtitleTrack> get subtitleTracks => _subtitleTracks;
  AudioTrack get activeAudioTrack => _activeAudioTrack;
  SubtitleTrack get activeSubtitleTrack => _activeSubtitleTrack;
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

  int get autoNextRemainingSeconds {
    if (!hasNextEpisode ||
        _autoNextDismissed ||
        sleepTimerOption == SleepTimerOption.endOfEpisode) {
      return 0;
    }
    final remainingMs = _duration.inMilliseconds - _position.inMilliseconds;
    final leadMs = AppSpacing.autoNextLeadSeconds * AppSpacing.millisecondsPerSecond;
    if (_duration.inMilliseconds <= 0 || remainingMs <= 0 || remainingMs > leadMs) {
      return 0;
    }
    return (remainingMs / AppSpacing.millisecondsPerSecond).ceil();
  }

  bool get showAutoNextCard => autoNextRemainingSeconds > 0;
  bool get showIntroSkipButton =>
      currentEntry?.mediaType == 'episode' &&
      _errorMessage == null &&
      _duration > Duration.zero &&
      !_features.introSkipped &&
      _position.inMilliseconds < effectiveIntroSkipSeconds * AppSpacing.millisecondsPerSecond &&
      (_features.nextChapterInIntroWindow(_position) != null || effectiveIntroSkipSeconds > 0);

  void dismissAutoNext() {
    _autoNextDismissed = true;
    _safeNotify();
  }

  void _bindStreams() {
    _subscriptions.addAll([
      _player.stream.playing.listen(_onPlayingChanged),
      _player.stream.position.listen((pos) {
        _position = pos;
        _safeNotify();
      }),
      _player.stream.duration.listen((dur) {
        _duration = dur;
        if (dur > Duration.zero && !_features.chaptersLoadedForEntry) {
          _features.chaptersLoadedForEntry = true;
          unawaited(_features.loadChapters(() => _isDisposed));
        }
        final pendingMs = dur > Duration.zero ? _pendingStartPositionMs : null;
        if (pendingMs != null) {
          _pendingStartPositionMs = null;
          if (_position.inMilliseconds < pendingMs - (2 * AppSpacing.millisecondsPerSecond)) {
            unawaited(_player.seek(Duration(milliseconds: pendingMs)));
          }
        }
        _safeNotify();
      }),
      _player.stream.volume.listen((vol) {
        _volume = vol;
        _safeNotify();
      }),
      _player.stream.tracks.listen((tracks) {
        _audioTracks = tracks.audio;
        _subtitleTracks = tracks.subtitle;
        _applyTrackPreferences();
        _safeNotify();
      }),
      _player.stream.track.listen((track) {
        _activeAudioTrack = track.audio;
        _activeSubtitleTrack = track.subtitle;
        _saveSeriesPreferences(track.audio, track.subtitle);
        _safeNotify();
      }),
      _player.stream.completed.listen(_onCompletedChanged),
      _player.stream.error.listen((error) {
        if (_isDisposed || error.trim().isEmpty) return;
        _stopProgressTimer();
        _errorMessage = AppStrings.playerPlaybackError;
        _safeNotify();
      }),
    ]);
  }

  void _onPlayingChanged(bool playing) {
    _isPlaying = playing;
    if (!playing) {
      _persistence.recordWatchHistorySlice(currentEntry, isPlaying: false);
      _stopProgressTimer();
      _persistProgress(syncRemote: true);
      showHud(keepVisibleWhilePaused: true);
    } else {
      _persistence.startPlaySegmentIfNeeded();
      _startProgressTimer();
      registerUserActivity();
    }
    _safeNotify();
  }

  Future<void> _onCompletedChanged(bool completed) async {
    if (_isDisposed || !completed) return;
    _persistProgress(forceCompleted: true, syncRemote: true);
    if (sleepTimerOption == SleepTimerOption.endOfEpisode) {
      _overlays.cancelSleepTimer();
      await _player.pause();
      _overlays.showActionOsd(PlayerActionOsdKind.sleepTimer, AppStrings.sleepTimerTriggeredOsd);
      return;
    }
    if (hasNextEpisode && !_autoNextDismissed) await playNextEpisode();
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: AppSpacing.progressSaveIntervalSeconds), (_) => _persistProgress(syncRemote: false));
  }
  void _stopProgressTimer() { _progressTimer?.cancel(); _progressTimer = null; }

  void _applyTrackPreferences() {
    final sid = currentEntry?.seriesId;
    final prefs = sid != null ? _persistence.loadSeriesPreferences(sid) : null;
    if (prefs != null) _features.seriesIntroSkipSeconds = prefs.introSkipSeconds;
    final resolved = TrackPreferenceResolver.resolve(
      seriesPreferences: prefs,
      audioTracks: _audioTracks,
      subtitleTracks: _subtitleTracks,
      activeAudioTrack: _activeAudioTrack,
      activeSubtitleTrack: _activeSubtitleTrack,
      subtitlesEnabledByDefault:
          _settingsController?.subtitlesEnabledByDefault ?? false,
      preferredSubtitleLanguage: _settingsController?.preferredSubtitleLanguage ??
          AppStrings.subtitleLangCodeDe,
    );
    if (resolved.audio != null) _player.setAudioTrack(resolved.audio!);
    if (resolved.subtitle != null) {
      _autoAppliedSubtitleId = resolved.fromSeries ? null : resolved.subtitle!.id;
      _player.setSubtitleTrack(resolved.subtitle!);
    }
  }

  void _saveSeriesPreferences(AudioTrack audio, SubtitleTrack subtitle) {
    final seriesId = currentEntry?.seriesId;
    if (seriesId == null || (audio.id == 'auto' && subtitle.id == 'auto')) return;
    if (_autoAppliedSubtitleId != null && subtitle.id == _autoAppliedSubtitleId) {
      _autoAppliedSubtitleId = null;
      return;
    }
    _persistence.saveSeriesPreferences(seriesId, audio.id, subtitle.id);
  }

  Future<void> startSession(PlaybackSession newSession) async {
    if (newSession.queue.isEmpty) return;
    _session = newSession;
    _currentIndex = newSession.initialIndex.clamp(0, newSession.queue.length - 1);
    await _openEntryAtIndex(_currentIndex);
  }

  Future<void> _openEntryAtIndex(int index) async {
    final s = _session;
    if (_isDisposed || s == null || index < 0 || index >= s.queue.length) return;
    final requestId = ++_openRequestId;
    _currentIndex = index;
    _autoNextDismissed = false;
    _errorMessage = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _autoAppliedSubtitleId = null;
    _persistence.resetHistoryTracking();
    final entry = s.queue[_currentIndex];
    final startPosMs = entry.startPositionMs;
    _pendingStartPositionMs = startPosMs > 0 ? startPosMs : null;
    _features.resetForEntry(entry);
    _safeNotify();
    final status = await LocalFileService.checkPlayableFile(entry.filePath);
    if (_isDisposed || requestId != _openRequestId) return;
    if (status != PlayableFileStatus.ok) {
      _errorMessage = status == PlayableFileStatus.missing ? AppStrings.playerFileMissingError : AppStrings.playerEmptyFileError;
      _safeNotify();
      return;
    }
    try {
      await _mpvBridge.setProperty('start', 'none');
      await _player.open(Media(entry.filePath, start: startPosMs > 0 ? Duration(milliseconds: startPosMs) : null), play: true);
      if (_isDisposed || requestId != _openRequestId) return;
      if (startPosMs > 0) {
        await _player.seek(Duration(milliseconds: startPosMs));
        if (_position.inMilliseconds >= startPosMs - AppSpacing.millisecondsPerSecond) _pendingStartPositionMs = null;
      }
      await _features.applySubtitleStyle();
    } catch (_) {
      if (_isDisposed || requestId != _openRequestId) return;
      _errorMessage = AppStrings.playerPlaybackError;
      _safeNotify();
      return;
    }
    if (_isDisposed || requestId != _openRequestId) return;
    _startProgressTimer();
    registerUserActivity();
  }
  Future<void> togglePlayPause() async { registerUserActivity(); await _player.playOrPause(); }
  Future<void> seekRelativeSeconds(int deltaSeconds) async {
    final targetMs = (_position.inMilliseconds + (deltaSeconds * AppSpacing.millisecondsPerSecond))
        .clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1 << 30);
    await _player.seek(Duration(milliseconds: targetMs));
    _overlays.showActionOsd(deltaSeconds >= 0 ? PlayerActionOsdKind.seekForward : PlayerActionOsdKind.seekBack, Formatters.formatSeekOsd(deltaSeconds));
  }
  Future<void> seekToRatio(double ratio) async {
    registerUserActivity();
    if (_duration.inMilliseconds <= 0) return;
    await _player.seek(Duration(milliseconds: (_duration.inMilliseconds * ratio.clamp(0.0, 1.0)).round()));
  }
  Future<void> adjustVolume(double delta) async {
    final next = (_volume + delta).clamp(AppSpacing.volumeMin, maxVolume);
    await _player.setVolume(next);
    _overlays.showActionOsd(PlayerActionOsdKind.volume, Formatters.formatVolumePercent(next));
  }
  Future<void> toggleMute() async {
    if (isMuted) {
      final restored = _volumeBeforeMute > AppSpacing.volumeMin ? _volumeBeforeMute.clamp(AppSpacing.volumeMin, maxVolume) : AppSpacing.volumeMax;
      await _player.setVolume(restored);
      _overlays.showActionOsd(PlayerActionOsdKind.mute, AppStrings.osdMuteOff);
    } else {
      _volumeBeforeMute = _volume;
      await _player.setVolume(AppSpacing.volumeMin);
      _overlays.showActionOsd(PlayerActionOsdKind.mute, AppStrings.osdMuteOn);
    }
  }
  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    await _player.setRate(speed);
    _overlays.showActionOsd(PlayerActionOsdKind.speed, Formatters.formatSubtitleScale(speed));
    _safeNotify();
  }
  Future<void> playNextEpisode() async {
    if (!hasNextEpisode) return;
    _stopProgressTimer();
    _persistProgress(syncRemote: true);
    await _openEntryAtIndex(_currentIndex + 1);
  }
  Future<void> playPreviousEpisode() async {
    if (!hasPreviousEpisode) return;
    _stopProgressTimer();
    _persistProgress(syncRemote: true);
    await _openEntryAtIndex(_currentIndex - 1);
  }
  Future<void> playEntryAtIndex(int index) async {
    if (_session == null || index < 0 || index >= _session!.queue.length) return;
    _overlays.closeEpisodeDrawer();
    _stopProgressTimer();
    _persistProgress(syncRemote: true);
    await _openEntryAtIndex(index);
  }
  Future<void> selectAudioTrack(AudioTrack track) async { registerUserActivity(); await _player.setAudioTrack(track); }
  Future<void> selectSubtitleTrack(SubtitleTrack track) async { registerUserActivity(); _autoAppliedSubtitleId = null; await _player.setSubtitleTrack(track); }

  Future<void> toggleNightMode() => _features.toggleNightMode();
  Future<void> toggleVolumeBoost() => _features.toggleVolumeBoost(_volume);
  Future<void> setAspectMode(VideoAspectMode m) => _features.setAspectMode(m);
  Future<void> cycleAspectMode() => setAspectMode(VideoAspectMode.values[(_features.aspectMode.index + 1) % VideoAspectMode.values.length]);
  Future<void> adjustAudioDelay(int ms) => _features.adjustAudioDelay(ms);
  Future<void> resetAudioDelay() => adjustAudioDelay(-audioDelayMs);
  Future<void> adjustSubtitleDelay(int ms) => _features.adjustSubtitleDelay(ms);
  Future<void> resetSubtitleDelay() => adjustSubtitleDelay(-subtitleDelayMs);
  Future<void> loadExternalSubtitle(String dialogTitle) async {
    final path = await _windowAdapter.pickSubtitleFile(dialogTitle);
    if (path == null || _isDisposed) return;
    _autoAppliedSubtitleId = null;
    await _player.setSubtitleTrack(SubtitleTrack.uri(path));
    _overlays.showActionOsd(PlayerActionOsdKind.subtitle, AppStrings.osdExternalSubLoaded);
  }
  Future<void> updateLiveSubtitleStyle({double? scale, int? position, double? bgOpacity}) => _features.updateLiveSubtitleStyle(scale: scale, position: position, bgOpacity: bgOpacity);
  PlayerChapter? chapterAtPosition(Duration pos) => _features.chapterAtPosition(pos);
  Future<void> jumpToNextChapter() => _features.jumpToNextChapter(_position);
  Future<void> jumpToPreviousChapter() => _features.jumpToPreviousChapter(_position);
  Future<void> skipIntro() => _features.skipIntro(currentEntry, _position, _duration);
  void setSeriesIntroSkipSeconds(int s) => _features.setSeriesIntroSkipSeconds(currentEntry?.seriesId, s);
  void addBookmarkAtCurrentPosition({String label = ''}) => _features.addBookmark(currentEntry, _position, label);
  void deleteBookmark(int id) => _features.deleteBookmark(currentEntry, id);
  Future<void> seekToBookmark(MediaBookmark bm) => _features.seekToBookmark(bm);
  Future<String?> captureScreenshot() => _features.captureScreenshot(currentEntry);
  void cycleTimeDisplayMode() => _features.cycleTimeDisplayMode();
  String formatRightTimeLabel({DateTime? now}) => _features.formatRightTimeLabel(_position, _duration, _playbackSpeed, now ?? DateTime.now());
  Future<void> stepFrame({required bool forward}) async {
    if (_isPlaying) await _player.pause();
    await _mpvBridge.sendCommand([forward ? 'frame-step' : 'frame-back-step']);
    _overlays.showActionOsd(PlayerActionOsdKind.frameStep, forward ? AppStrings.osdFrameStepForward : AppStrings.osdFrameStepBack);
  }
  void showActionOsd(PlayerActionOsdKind kind, String message) => _overlays.showActionOsd(kind, message);
  void toggleDiagnostics() => _overlays.toggleDiagnostics();
  void toggleEpisodeDrawer() => _overlays.toggleEpisodeDrawer();
  void toggleShortcutSheet() => _overlays.toggleShortcutSheet();
  bool closeTopOverlay() => _overlays.closeTopOverlay();
  void setSleepTimer(SleepTimerOption option, {Duration? customDuration}) {
    _overlays.setSleepTimer(option, customDuration: customDuration, onExpired: () async {
      if (_isDisposed) return;
      await _player.pause();
      _overlays.showActionOsd(PlayerActionOsdKind.sleepTimer, AppStrings.sleepTimerTriggeredOsd);
    });
    _overlays.showActionOsd(PlayerActionOsdKind.sleepTimer, option == SleepTimerOption.off ? AppStrings.osdSleepTimerOff : '${AppStrings.osdSleepTimerSetPrefix} ${Formatters.formatSleepTimerOptionLabel(option)}');
  }
  Future<void> toggleMiniPlayer() async {
    if (_features.isMiniPlayer) { await _features.exitMiniPlayer(); return; }
    if (_isFullscreen) { _isFullscreen = false; await _windowAdapter.setFullScreen(false); }
    await _features.enterMiniPlayer();
  }
  Future<void> startMiniPlayerWindowDrag() => _windowAdapter.startWindowDragging();
  Future<void> toggleFullscreen() async {
    if (_features.isMiniPlayer) await _features.exitMiniPlayer();
    registerUserActivity();
    _isFullscreen = !_isFullscreen;
    await _windowAdapter.setFullScreen(_isFullscreen);
    _safeNotify();
  }
  void registerUserActivity() => showHud(keepVisibleWhilePaused: !_isPlaying);
  void showHud({bool keepVisibleWhilePaused = false}) {
    if (!_isHudVisible) { _isHudVisible = true; _safeNotify(); }
    _hudHideTimer?.cancel();
    if (keepVisibleWhilePaused) return;
    _hudHideTimer = Timer(const Duration(seconds: AppSpacing.hudAutoHideSeconds), () {
      if (!_isDisposed && _isPlaying && _isHudVisible) { _isHudVisible = false; _safeNotify(); }
    });
  }
  Future<void> stopAndClose() async {
    _openRequestId++;
    _hudHideTimer?.cancel();
    _stopProgressTimer();
    _overlays.resetForClose();
    _persistence.recordWatchHistorySlice(currentEntry, isPlaying: false);
    _persistProgress(syncRemote: true);
    await _player.stop();
    await _features.exitMiniPlayer();
    if (_isFullscreen) { _isFullscreen = false; await _windowAdapter.setFullScreen(false); }
    _persistence.resetHistoryTracking();
    _session = null;
    _safeNotify();
  }
  void _persistProgress({bool forceCompleted = false, bool syncRemote = false}) {
    final entry = currentEntry;
    if (entry == null) return;
    if (_isPlaying) _persistence.recordWatchHistorySlice(entry, isPlaying: true);
    _persistence.persistProgress(entry: entry, positionMs: _position.inMilliseconds, durationMs: _duration.inMilliseconds, forceCompleted: forceCompleted);
    if (syncRemote) unawaited(_syncService.syncWithStorage(_getNasPath()));
  }
  void _safeNotify() { if (!_isDisposed) notifyListeners(); }
  @override
  void dispose() {
    _isDisposed = true;
    _openRequestId++;
    _hudHideTimer?.cancel();
    _stopProgressTimer();
    _overlays.dispose();
    for (final sub in _subscriptions) { sub.cancel(); }
    _subscriptions.clear();
    _player.dispose();
    super.dispose();
  }
}
