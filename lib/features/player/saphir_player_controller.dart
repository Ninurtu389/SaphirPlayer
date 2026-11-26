import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/desktop_platform_service.dart';
import '../../core/services/local_file_service.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/progress_sync_service.dart';
import 'playback_persistence_service.dart';
import 'playback_session.dart';

class SaphirPlayerController extends ChangeNotifier {
  SaphirPlayerController(
    DatabaseService databaseService,
    this._syncService,
    this._getNasPath, {
    Player? player,
    VideoController? videoController,
    Future<void> Function(bool fullscreen)? onSetFullScreen,
  })  : _persistence = PlaybackPersistenceService(databaseService),
        _onSetFullScreen =
            onSetFullScreen ?? DesktopPlatformService.setFullScreen {
    _player = player ??
        Player(
          configuration: const PlayerConfiguration(
            title: AppStrings.appTitle,
          ),
        );
    _videoController = videoController ??
        VideoController(
          _player,
          configuration: const VideoControllerConfiguration(
            enableHardwareAcceleration: true,
          ),
        );
    _bindStreams();
  }

  final PlaybackPersistenceService _persistence;
  final ProgressSyncService _syncService;
  final String Function() _getNasPath;
  final Future<void> Function(bool fullscreen) _onSetFullScreen;

  late final Player _player;
  late final VideoController _videoController;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _hudHideTimer;
  Timer? _progressTimer;

  bool _isDisposed = false;
  int _openRequestId = 0;

  PlaybackSession? _session;
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isFullscreen = false;
  bool _isHudVisible = true;
  bool _autoNextDismissed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100.0;
  double _volumeBeforeMute = 100.0;
  double _playbackSpeed = 1.0;
  List<AudioTrack> _audioTracks = const [];
  List<SubtitleTrack> _subtitleTracks = const [];
  AudioTrack _activeAudioTrack = AudioTrack.auto();
  SubtitleTrack _activeSubtitleTrack = SubtitleTrack.auto();
  String? _errorMessage;

  VideoController get videoController => _videoController;
  PlaybackSession? get session => _session;

  PlaybackQueueEntry? get currentEntry {
    final activeSession = _session;
    if (activeSession == null || activeSession.queue.isEmpty) return null;
    return activeSession
        .queue[_currentIndex.clamp(0, activeSession.queue.length - 1)];
  }

  PlaybackQueueEntry? get nextEntry =>
      hasNextEpisode ? _session!.queue[_currentIndex + 1] : null;

  bool get hasPreviousEpisode => _currentIndex > 0;
  bool get hasNextEpisode =>
      _session != null && _currentIndex + 1 < _session!.queue.length;

  bool get isPlaying => _isPlaying;
  bool get isFullscreen => _isFullscreen;
  bool get isHudVisible => _isHudVisible;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  bool get isMuted => _volume <= AppSpacing.volumeMin;
  double get playbackSpeed => _playbackSpeed;
  List<AudioTrack> get audioTracks => _audioTracks;
  List<SubtitleTrack> get subtitleTracks => _subtitleTracks;
  AudioTrack get activeAudioTrack => _activeAudioTrack;
  SubtitleTrack get activeSubtitleTrack => _activeSubtitleTrack;
  String? get errorMessage => _errorMessage;

  int get autoNextRemainingSeconds {
    if (!hasNextEpisode || _autoNextDismissed) {
      return 0;
    }
    final remainingMs = _duration.inMilliseconds - _position.inMilliseconds;
    final leadMs =
        AppSpacing.autoNextLeadSeconds * AppSpacing.millisecondsPerSecond;
    if (_duration.inMilliseconds <= 0 ||
        remainingMs <= 0 ||
        remainingMs > leadMs) {
      return 0;
    }
    return (remainingMs / AppSpacing.millisecondsPerSecond).ceil();
  }

  bool get showAutoNextCard => autoNextRemainingSeconds > 0;

  void dismissAutoNext() {
    _autoNextDismissed = true;
    _safeNotify();
  }

  void _bindStreams() {
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        _isPlaying = playing;
        if (!playing) {
          _persistence.recordWatchHistorySlice(
            currentEntry,
            isPlaying: false,
          );
          _stopProgressTimer();
          _persistProgress(syncRemote: true);
          showHud(keepVisibleWhilePaused: true);
        } else {
          _persistence.startPlaySegmentIfNeeded();
          _startProgressTimer();
          registerUserActivity();
        }
        _safeNotify();
      }),
    );

    _subscriptions.add(_player.stream.position.listen((pos) {
      _position = pos;
      _safeNotify();
    }));
    _subscriptions.add(_player.stream.duration.listen((dur) {
      _duration = dur;
      _safeNotify();
    }));
    _subscriptions.add(_player.stream.volume.listen((vol) {
      _volume = vol;
      _safeNotify();
    }));
    _subscriptions.add(_player.stream.tracks.listen((tracks) {
      _audioTracks = tracks.audio;
      _subtitleTracks = tracks.subtitle;
      _applySavedSeriesPreferences();
      _safeNotify();
    }));
    _subscriptions.add(_player.stream.track.listen((track) {
      _activeAudioTrack = track.audio;
      _activeSubtitleTrack = track.subtitle;
      _saveSeriesPreferences(track.audio, track.subtitle);
      _safeNotify();
    }));
    _subscriptions.add(_player.stream.completed.listen((completed) async {
      if (_isDisposed || !completed) return;
      _persistProgress(forceCompleted: true, syncRemote: true);
      if (hasNextEpisode && !_autoNextDismissed) await playNextEpisode();
    }));
    _subscriptions.add(_player.stream.error.listen((error) {
      if (_isDisposed || error.trim().isEmpty) return;
      _stopProgressTimer();
      _errorMessage = AppStrings.playerPlaybackError;
      _safeNotify();
    }));
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: AppSpacing.progressSaveIntervalSeconds),
      (_) => _persistProgress(syncRemote: false),
    );
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _applySavedSeriesPreferences() {
    final seriesId = currentEntry?.seriesId;
    if (seriesId == null) {
      return;
    }
    final prefs = _persistence.loadSeriesPreferences(seriesId);
    if (prefs == null) {
      return;
    }

    final savedAudioId = prefs.audioTrack;
    final savedSubtitleId = prefs.subtitleTrack;

    if (savedAudioId != null && savedAudioId.isNotEmpty) {
      for (final track in _audioTracks) {
        if (track.id == savedAudioId && _activeAudioTrack.id != savedAudioId) {
          _player.setAudioTrack(track);
          break;
        }
      }
    }

    if (savedSubtitleId != null) {
      if (savedSubtitleId == 'no') {
        if (_activeSubtitleTrack.id != 'no') {
          _player.setSubtitleTrack(SubtitleTrack.no());
        }
      } else if (savedSubtitleId.isNotEmpty) {
        for (final track in _subtitleTracks) {
          if (track.id == savedSubtitleId &&
              _activeSubtitleTrack.id != savedSubtitleId) {
            _player.setSubtitleTrack(track);
            break;
          }
        }
      }
    }
  }

  void _saveSeriesPreferences(AudioTrack audio, SubtitleTrack subtitle) {
    final seriesId = currentEntry?.seriesId;
    if (seriesId == null ||
        (audio.id == 'auto' && subtitle.id == 'auto')) {
      return;
    }
    _persistence.saveSeriesPreferences(seriesId, audio.id, subtitle.id);
  }

  Future<void> startSession(PlaybackSession newSession) async {
    if (newSession.queue.isEmpty) {
      return;
    }
    _session = newSession;
    _currentIndex =
        newSession.initialIndex.clamp(0, newSession.queue.length - 1);
    await _openEntryAtIndex(_currentIndex);
  }

  Future<void> _openEntryAtIndex(int index) async {
    final activeSession = _session;
    if (_isDisposed ||
        activeSession == null ||
        index < 0 ||
        index >= activeSession.queue.length) {
      return;
    }

    final requestId = ++_openRequestId;
    _currentIndex = index;
    _autoNextDismissed = false;
    _errorMessage = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _persistence.resetHistoryTracking();
    _safeNotify();

    final entry = activeSession.queue[_currentIndex];
    final fileStatus =
        await LocalFileService.checkPlayableFile(entry.filePath);
    if (_isDisposed || requestId != _openRequestId) {
      return;
    }
    if (fileStatus == PlayableFileStatus.missing) {
      _errorMessage = AppStrings.playerFileMissingError;
      _safeNotify();
      return;
    }
    if (fileStatus == PlayableFileStatus.empty) {
      _errorMessage = AppStrings.playerEmptyFileError;
      _safeNotify();
      return;
    }

    try {
      await _player.open(Media(entry.filePath), play: true);
      if (_isDisposed || requestId != _openRequestId) {
        return;
      }
      if (entry.startPositionMs > 0) {
        await _player.seek(Duration(milliseconds: entry.startPositionMs));
      }
    } catch (_) {
      if (_isDisposed || requestId != _openRequestId) {
        return;
      }
      _errorMessage = AppStrings.playerPlaybackError;
      _safeNotify();
      return;
    }

    if (_isDisposed || requestId != _openRequestId) {
      return;
    }
    _startProgressTimer();
    registerUserActivity();
  }

  Future<void> togglePlayPause() async {
    registerUserActivity();
    await _player.playOrPause();
  }

  Future<void> seekRelativeSeconds(int deltaSeconds) async {
    registerUserActivity();
    final targetMs = (_position.inMilliseconds +
            (deltaSeconds * AppSpacing.millisecondsPerSecond))
        .clamp(
      0,
      _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1 << 30,
    );
    await _player.seek(Duration(milliseconds: targetMs));
  }

  Future<void> seekToRatio(double ratio) async {
    registerUserActivity();
    if (_duration.inMilliseconds <= 0) {
      return;
    }
    final targetMs = (_duration.inMilliseconds * ratio.clamp(0.0, 1.0)).round();
    await _player.seek(Duration(milliseconds: targetMs));
  }

  Future<void> adjustVolume(double delta) async {
    registerUserActivity();
    final next =
        (_volume + delta).clamp(AppSpacing.volumeMin, AppSpacing.volumeMax);
    await _player.setVolume(next);
  }

  Future<void> toggleMute() async {
    registerUserActivity();
    if (isMuted) {
      final restored = _volumeBeforeMute > AppSpacing.volumeMin
          ? _volumeBeforeMute
          : AppSpacing.volumeMax;
      await _player.setVolume(restored);
    } else {
      _volumeBeforeMute = _volume;
      await _player.setVolume(AppSpacing.volumeMin);
    }
  }

  Future<void> setPlaybackSpeed(double speed) async {
    registerUserActivity();
    _playbackSpeed = speed;
    await _player.setRate(speed);
    _safeNotify();
  }

  Future<void> playNextEpisode() async {
    if (!hasNextEpisode) {
      return;
    }
    _stopProgressTimer();
    _persistProgress(syncRemote: true);
    await _openEntryAtIndex(_currentIndex + 1);
  }

  Future<void> playPreviousEpisode() async {
    if (!hasPreviousEpisode) {
      return;
    }
    _stopProgressTimer();
    _persistProgress(syncRemote: true);
    await _openEntryAtIndex(_currentIndex - 1);
  }

  Future<void> selectAudioTrack(AudioTrack track) async {
    registerUserActivity();
    await _player.setAudioTrack(track);
  }

  Future<void> selectSubtitleTrack(SubtitleTrack track) async {
    registerUserActivity();
    await _player.setSubtitleTrack(track);
  }

  Future<void> toggleFullscreen() async {
    registerUserActivity();
    _isFullscreen = !_isFullscreen;
    await _onSetFullScreen(_isFullscreen);
    _safeNotify();
  }

  void registerUserActivity() {
    showHud(keepVisibleWhilePaused: !_isPlaying);
  }

  void showHud({bool keepVisibleWhilePaused = false}) {
    if (!_isHudVisible) {
      _isHudVisible = true;
      _safeNotify();
    }
    _hudHideTimer?.cancel();
    if (keepVisibleWhilePaused) {
      return;
    }
    _hudHideTimer = Timer(
      const Duration(seconds: AppSpacing.hudAutoHideSeconds),
      () {
        if (!_isDisposed && _isPlaying && _isHudVisible) {
          _isHudVisible = false;
          _safeNotify();
        }
      },
    );
  }

  Future<void> stopAndClose() async {
    _openRequestId++;
    _hudHideTimer?.cancel();
    _stopProgressTimer();
    _persistence.recordWatchHistorySlice(currentEntry, isPlaying: false);
    _persistProgress(syncRemote: true);
    await _player.stop();
    if (_isFullscreen) {
      _isFullscreen = false;
      await _onSetFullScreen(false);
    }
    _persistence.resetHistoryTracking();
    _session = null;
    _safeNotify();
  }

  void _persistProgress({
    bool forceCompleted = false,
    bool syncRemote = false,
  }) {
    final entry = currentEntry;
    if (entry == null) {
      return;
    }
    if (_isPlaying) {
      _persistence.recordWatchHistorySlice(entry, isPlaying: true);
    }
    _persistence.persistProgress(
      entry: entry,
      positionMs: _position.inMilliseconds,
      durationMs: _duration.inMilliseconds,
      forceCompleted: forceCompleted,
    );
    if (syncRemote) {
      unawaited(_syncService.syncWithStorage(_getNasPath()));
    }
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _openRequestId++;
    _hudHideTimer?.cancel();
    _stopProgressTimer();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _player.dispose();
    super.dispose();
  }
}
