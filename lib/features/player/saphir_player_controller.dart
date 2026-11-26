import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/progress_sync_service.dart';
import 'playback_session.dart';

class SaphirPlayerController extends ChangeNotifier {
  SaphirPlayerController(
    this._databaseService,
    this._syncService,
    this._getNasPath,
  ) {
    _player = Player(
      configuration: const PlayerConfiguration(
        title: AppStrings.appTitle,
      ),
    );
    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _bindStreams();
  }

  final DatabaseService _databaseService;
  final ProgressSyncService _syncService;
  final String Function() _getNasPath;

  late final Player _player;
  late final VideoController _videoController;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _hudHideTimer;
  Timer? _progressTimer;

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

  DateTime? _playSegmentStartedAt;
  int? _activeHistoryRowId;
  String? _activeHistoryMediaKey;
  String? _activeHistoryDayKey;

  VideoController get videoController => _videoController;
  PlaybackSession? get session => _session;
  PlaybackQueueEntry? get currentEntry {
    final activeSession = _session;
    if (activeSession == null || activeSession.queue.isEmpty) {
      return null;
    }
    return activeSession
        .queue[_currentIndex.clamp(0, activeSession.queue.length - 1)];
  }

  PlaybackQueueEntry? get nextEntry {
    final activeSession = _session;
    if (activeSession == null || !hasNextEpisode) {
      return null;
    }
    return activeSession.queue[_currentIndex + 1];
  }

  bool get hasPreviousEpisode => _currentIndex > 0;
  bool get hasNextEpisode {
    final activeSession = _session;
    if (activeSession == null) {
      return false;
    }
    return _currentIndex + 1 < activeSession.queue.length;
  }

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
    notifyListeners();
  }

  void _bindStreams() {
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        _isPlaying = playing;
        if (!playing) {
          _recordWatchHistorySlice();
          _stopProgressTimer();
          _persistProgress(syncRemote: true);
          showHud(keepVisibleWhilePaused: true);
        } else {
          _playSegmentStartedAt ??= DateTime.now();
          _startProgressTimer();
          registerUserActivity();
        }
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.stream.position.listen((pos) {
        _position = pos;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.stream.duration.listen((dur) {
        _duration = dur;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.stream.volume.listen((vol) {
        _volume = vol;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        _audioTracks = tracks.audio;
        _subtitleTracks = tracks.subtitle;
        _applySavedSeriesPreferences();
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.stream.track.listen((track) {
        _activeAudioTrack = track.audio;
        _activeSubtitleTrack = track.subtitle;
        _saveSeriesPreferences(track.audio, track.subtitle);
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.stream.completed.listen((completed) async {
        if (completed) {
          _persistProgress(forceCompleted: true, syncRemote: true);
          if (hasNextEpisode && !_autoNextDismissed) {
            await playNextEpisode();
          }
        }
      }),
    );
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
    final db = _databaseService.instance;
    final rows = db.select(
      'SELECT audio_track, subtitle_track FROM series_preferences WHERE series_id = ? LIMIT 1;',
      [seriesId],
    );
    if (rows.isEmpty) {
      return;
    }

    final savedAudioId = rows.first['audio_track'] as String?;
    final savedSubtitleId = rows.first['subtitle_track'] as String?;

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
    if (seriesId == null) {
      return;
    }
    if (audio.id == 'auto' && subtitle.id == 'auto') {
      return;
    }
    final db = _databaseService.instance;
    db.execute(
      '''
      INSERT INTO series_preferences (series_id, audio_track, subtitle_track)
      VALUES (?, ?, ?)
      ON CONFLICT(series_id) DO UPDATE SET
        audio_track = excluded.audio_track,
        subtitle_track = excluded.subtitle_track;
      ''',
      [seriesId, audio.id, subtitle.id],
    );
  }

  Future<void> startSession(PlaybackSession newSession) async {
    _session = newSession;
    _currentIndex =
        newSession.initialIndex.clamp(0, newSession.queue.length - 1);
    await _openEntryAtIndex(_currentIndex);
  }

  Future<void> _openEntryAtIndex(int index) async {
    final activeSession = _session;
    if (activeSession == null ||
        index < 0 ||
        index >= activeSession.queue.length) {
      return;
    }

    _currentIndex = index;
    _autoNextDismissed = false;
    _errorMessage = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _playSegmentStartedAt = null;
    _activeHistoryRowId = null;
    _activeHistoryMediaKey = null;
    _activeHistoryDayKey = null;
    notifyListeners();

    final entry = activeSession.queue[_currentIndex];
    final file = File(entry.filePath);
    if (!await file.exists()) {
      _errorMessage = AppStrings.playerFileMissingError;
      notifyListeners();
      return;
    }

    await _player.open(Media(entry.filePath), play: true);

    if (entry.startPositionMs > 0) {
      await _player.seek(Duration(milliseconds: entry.startPositionMs));
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
        .clamp(0,
            _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1 << 30);
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
    notifyListeners();
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
    await windowManager.setFullScreen(_isFullscreen);
    notifyListeners();
  }

  void registerUserActivity() {
    showHud(keepVisibleWhilePaused: !_isPlaying);
  }

  void showHud({bool keepVisibleWhilePaused = false}) {
    if (!_isHudVisible) {
      _isHudVisible = true;
      notifyListeners();
    }
    _hudHideTimer?.cancel();
    if (keepVisibleWhilePaused) {
      return;
    }
    _hudHideTimer = Timer(
      const Duration(seconds: AppSpacing.hudAutoHideSeconds),
      () {
        if (_isPlaying && _isHudVisible) {
          _isHudVisible = false;
          notifyListeners();
        }
      },
    );
  }

  Future<void> stopAndClose() async {
    _hudHideTimer?.cancel();
    _stopProgressTimer();
    _recordWatchHistorySlice();
    _persistProgress(syncRemote: true);
    await _player.stop();
    if (_isFullscreen) {
      _isFullscreen = false;
      await windowManager.setFullScreen(false);
    }
    _playSegmentStartedAt = null;
    _activeHistoryRowId = null;
    _activeHistoryMediaKey = null;
    _activeHistoryDayKey = null;
    _session = null;
    notifyListeners();
  }

  void _recordWatchHistorySlice() {
    final startedAt = _playSegmentStartedAt;
    final entry = currentEntry;
    if (startedAt == null || entry == null) {
      return;
    }

    final now = DateTime.now();
    _playSegmentStartedAt = _isPlaying ? now : null;

    var elapsedMs = now.difference(startedAt).inMilliseconds;
    if (elapsedMs < AppSpacing.millisecondsPerSecond) {
      return;
    }
    const maxSliceMs = 60 * AppSpacing.millisecondsPerSecond;
    if (elapsedMs > maxSliceMs) {
      elapsedMs = maxSliceMs;
    }

    final dayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final nowMs = now.millisecondsSinceEpoch;
    final db = _databaseService.instance;

    if (_activeHistoryRowId != null &&
        _activeHistoryMediaKey == entry.mediaKey &&
        _activeHistoryDayKey == dayKey) {
      db.execute(
        'UPDATE watch_history SET watched_ms = watched_ms + ?, ended_at = ? WHERE id = ?;',
        [elapsedMs, nowMs, _activeHistoryRowId],
      );
      return;
    }

    db.execute(
      '''
      INSERT INTO watch_history (
        media_key, media_type, title, series_id, watched_ms, started_at, ended_at, day_key, weekday, source_device
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      [
        entry.mediaKey,
        entry.mediaType,
        entry.title,
        entry.seriesId,
        elapsedMs,
        startedAt.millisecondsSinceEpoch,
        nowMs,
        dayKey,
        now.weekday,
        Platform.localHostname,
      ],
    );
    _activeHistoryRowId = db.lastInsertRowId;
    _activeHistoryMediaKey = entry.mediaKey;
    _activeHistoryDayKey = dayKey;
  }

  void _persistProgress({
    bool forceCompleted = false,
    bool syncRemote = false,
  }) {
    if (_isPlaying) {
      _recordWatchHistorySlice();
    }
    final entry = currentEntry;
    if (entry == null) {
      return;
    }
    final durMs = _duration.inMilliseconds;
    final posMs = _position.inMilliseconds;
    if (durMs <= 0 && posMs <= 0 && !forceCompleted) {
      return;
    }

    final db = _databaseService.instance;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ratioReached =
        durMs > 0 && (posMs / durMs) >= AppSpacing.completedThresholdRatio;
    final completed = (forceCompleted || ratioReached) ? 1 : 0;

    db.execute(
      '''
      INSERT INTO watch_progress (
        media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(media_key) DO UPDATE SET
        position_ms = excluded.position_ms,
        duration_ms = excluded.duration_ms,
        completed = excluded.completed,
        updated_at = excluded.updated_at,
        source_device = excluded.source_device;
      ''',
      [
        entry.mediaKey,
        entry.mediaType,
        completed == 1 ? 0 : posMs,
        durMs,
        completed,
        nowMs,
        Platform.localHostname,
      ],
    );

    if (entry.seriesId != null) {
      db.execute(
        'UPDATE series SET last_watched_at = ? WHERE id = ?;',
        [nowMs, entry.seriesId],
      );
    }

    if (syncRemote) {
      unawaited(_syncService.syncWithStorage(_getNasPath()));
    }
  }

  @override
  void dispose() {
    _hudHideTimer?.cancel();
    _stopProgressTimer();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
