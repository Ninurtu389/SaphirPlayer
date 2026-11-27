import '../../core/constants/app_spacing.dart';
import '../../core/services/desktop_platform_service.dart';
import '../../core/storage/database_service.dart';
import 'playback_session.dart';
import 'player_models.dart';

class PlaybackPersistenceService {
  PlaybackPersistenceService(this._databaseService);

  final DatabaseService _databaseService;

  DateTime? _playSegmentStartedAt;
  int? _activeHistoryRowId;
  String? _activeHistoryMediaKey;
  String? _activeHistoryDayKey;

  void startPlaySegmentIfNeeded() {
    _playSegmentStartedAt ??= DateTime.now();
  }

  void resetHistoryTracking() {
    _playSegmentStartedAt = null;
    _activeHistoryRowId = null;
    _activeHistoryMediaKey = null;
    _activeHistoryDayKey = null;
  }

  ({String? audioTrack, String? subtitleTrack, int introSkipSeconds})?
      loadSeriesPreferences(int seriesId) {
    final db = _databaseService.instance;
    final rows = db.select(
      'SELECT audio_track, subtitle_track, intro_skip_seconds FROM series_preferences WHERE series_id = ? LIMIT 1;',
      [seriesId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return (
      audioTrack: rows.first['audio_track'] as String?,
      subtitleTrack: rows.first['subtitle_track'] as String?,
      introSkipSeconds: (rows.first['intro_skip_seconds'] as int?) ?? 0,
    );
  }

  void saveSeriesPreferences(
    int seriesId,
    String audioTrackId,
    String subtitleTrackId, {
    int? introSkipSeconds,
  }) {
    final db = _databaseService.instance;
    if (introSkipSeconds == null) {
      db.execute(
        '''
        INSERT INTO series_preferences (series_id, audio_track, subtitle_track)
        VALUES (?, ?, ?)
        ON CONFLICT(series_id) DO UPDATE SET
          audio_track = excluded.audio_track,
          subtitle_track = excluded.subtitle_track;
        ''',
        [seriesId, audioTrackId, subtitleTrackId],
      );
      return;
    }

    db.execute(
      '''
      INSERT INTO series_preferences (series_id, audio_track, subtitle_track, intro_skip_seconds)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(series_id) DO UPDATE SET
        audio_track = excluded.audio_track,
        subtitle_track = excluded.subtitle_track,
        intro_skip_seconds = excluded.intro_skip_seconds;
      ''',
      [seriesId, audioTrackId, subtitleTrackId, introSkipSeconds],
    );
  }

  void saveSeriesIntroSkip(int seriesId, int seconds) {
    final clamped = seconds.clamp(0, AppSpacing.introSkipWindowSeconds);
    final db = _databaseService.instance;
    db.execute(
      '''
      INSERT INTO series_preferences (series_id, intro_skip_seconds)
      VALUES (?, ?)
      ON CONFLICT(series_id) DO UPDATE SET
        intro_skip_seconds = excluded.intro_skip_seconds;
      ''',
      [seriesId, clamped],
    );
  }

  List<MediaBookmark> loadBookmarks(String mediaKey) {
    final db = _databaseService.instance;
    final rows = db.select(
      '''
      SELECT id, media_key, position_ms, label, created_at
      FROM media_bookmarks
      WHERE media_key = ?
      ORDER BY position_ms ASC, id ASC;
      ''',
      [mediaKey],
    );
    return rows
        .map(
          (r) => MediaBookmark(
            id: r['id'] as int,
            mediaKey: r['media_key'] as String,
            positionMs: (r['position_ms'] as int?) ?? 0,
            label: (r['label'] as String?) ?? '',
            createdAt: (r['created_at'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  MediaBookmark addBookmark(
    String mediaKey,
    int positionMs, {
    String label = '',
  }) {
    final db = _databaseService.instance;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final safePos = positionMs < 0 ? 0 : positionMs;
    db.execute(
      '''
      INSERT INTO media_bookmarks (media_key, position_ms, label, created_at)
      VALUES (?, ?, ?, ?);
      ''',
      [mediaKey, safePos, label, nowMs],
    );
    return MediaBookmark(
      id: db.lastInsertRowId,
      mediaKey: mediaKey,
      positionMs: safePos,
      label: label,
      createdAt: nowMs,
    );
  }

  void deleteBookmark(int bookmarkId) {
    final db = _databaseService.instance;
    db.execute(
      'DELETE FROM media_bookmarks WHERE id = ?;',
      [bookmarkId],
    );
  }

  void recordWatchHistorySlice(
    PlaybackQueueEntry? entry, {
    required bool isPlaying,
  }) {
    final startedAt = _playSegmentStartedAt;
    if (startedAt == null || entry == null) {
      return;
    }

    final now = DateTime.now();
    _playSegmentStartedAt = isPlaying ? now : null;

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
        DesktopPlatformService.localHostname,
      ],
    );
    _activeHistoryRowId = db.lastInsertRowId;
    _activeHistoryMediaKey = entry.mediaKey;
    _activeHistoryDayKey = dayKey;
  }

  void persistProgress({
    required PlaybackQueueEntry entry,
    required int positionMs,
    required int durationMs,
    required bool forceCompleted,
  }) {
    if (durationMs <= 0 && positionMs <= 0 && !forceCompleted) {
      return;
    }

    final db = _databaseService.instance;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ratioReached = durationMs > 0 &&
        (positionMs / durationMs) >= AppSpacing.completedThresholdRatio;
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
        completed == 1 ? 0 : positionMs,
        durationMs,
        completed,
        nowMs,
        DesktopPlatformService.localHostname,
      ],
    );

    if (entry.seriesId != null) {
      db.execute(
        'UPDATE series SET last_watched_at = ? WHERE id = ?;',
        [nowMs, entry.seriesId],
      );
    } else if (entry.mediaType == 'movie' &&
        entry.mediaKey.startsWith('movie_')) {
      final movieId =
          int.tryParse(entry.mediaKey.substring('movie_'.length));
      if (movieId != null) {
        db.execute(
          'UPDATE movies SET last_watched_at = ? WHERE id = ?;',
          [nowMs, movieId],
        );
      }
    }
  }
}
