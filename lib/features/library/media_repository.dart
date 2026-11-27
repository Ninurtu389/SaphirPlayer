import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/portable_paths.dart';
import '../../core/utils/formatters.dart';
import 'library_models.dart';

class MediaRepository {
  MediaRepository(this._databaseService);

  final DatabaseService _databaseService;

  ({int seriesCount, int movieCount}) loadCounts() {
    final db = _databaseService.instance;
    final seriesRow = db.select('SELECT COUNT(*) AS cnt FROM series;').first;
    final moviesRow = db.select('SELECT COUNT(*) AS cnt FROM movies;').first;
    return (
      seriesCount: seriesRow['cnt'] as int,
      movieCount: moviesRow['cnt'] as int,
    );
  }

  List<MediaCardItem> loadContinueWatching() {
    final db = _databaseService.instance;
    final entries = <({int updatedAt, MediaCardItem item})>[];

    final epProgressRows = db.select(
      '''
      SELECT
        wp.media_key,
        wp.position_ms,
        wp.duration_ms,
        wp.updated_at,
        e.series_id,
        e.episode_number,
        e.title AS episode_title,
        e.file_path,
        e.thumb_path,
        s.title AS series_title,
        s.poster_path,
        sn.season_number
      FROM watch_progress wp
      INNER JOIN episodes e
        ON wp.media_key = COALESCE(NULLIF(e.sync_key, ''), 'episode_' || e.id)
      INNER JOIN series s ON e.series_id = s.id
      INNER JOIN seasons sn ON e.season_id = sn.id
      WHERE wp.completed = 0 AND wp.position_ms > 0
      ORDER BY wp.updated_at DESC;
      ''',
    );

    for (final row in epProgressRows) {
      final posMs = row['position_ms'] as int;
      final durMs = row['duration_ms'] as int;
      final ratio = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
      final remMs = durMs > posMs ? durMs - posMs : 0;
      final remMin = (remMs / AppSpacing.millisecondsPerMinute).ceil();

      entries.add((
        updatedAt: (row['updated_at'] as int?) ?? 0,
        item: MediaCardItem(
          mediaKey: row['media_key'] as String,
          mediaType: 'episode',
          title: row['series_title'] as String,
          subtitle: Formatters.formatEpisodeSubtitle(
            row['season_number'] as int,
            row['episode_number'] as int,
            row['episode_title'] as String,
          ),
          imagePath: _resolvePreferredImage(
            row['thumb_path'] as String?,
            row['poster_path'] as String?,
          ),
          progressRatio: ratio,
          remainingMinutes: remMin,
          isCompleted: false,
          seriesId: row['series_id'] as int,
          filePath: row['file_path'] as String,
        ),
      ));
    }

    final movieProgressRows = db.select(
      '''
      SELECT
        wp.media_key,
        wp.position_ms,
        wp.duration_ms,
        wp.updated_at,
        m.title,
        m.release_year,
        m.file_path,
        m.poster_path,
        m.thumb_path
      FROM watch_progress wp
      INNER JOIN movies m
        ON wp.media_key = COALESCE(NULLIF(m.sync_key, ''), 'movie_' || m.id)
      WHERE wp.completed = 0 AND wp.position_ms > 0
      ORDER BY wp.updated_at DESC;
      ''',
    );

    for (final row in movieProgressRows) {
      final posMs = row['position_ms'] as int;
      final durMs = row['duration_ms'] as int;
      final ratio = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
      final remMs = durMs > posMs ? durMs - posMs : 0;
      final remMin = (remMs / AppSpacing.millisecondsPerMinute).ceil();

      entries.add((
        updatedAt: (row['updated_at'] as int?) ?? 0,
        item: MediaCardItem(
          mediaKey: row['media_key'] as String,
          mediaType: 'movie',
          title: row['title'] as String,
          subtitle: row['release_year'] != null ? '${row['release_year']}' : '',
          imagePath: _resolvePreferredImage(
            row['thumb_path'] as String?,
            row['poster_path'] as String?,
          ),
          progressRatio: ratio,
          remainingMinutes: remMin,
          isCompleted: false,
          seriesId: null,
          filePath: row['file_path'] as String,
        ),
      ));
    }

    entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return entries.map((e) => e.item).toList();
  }

  List<MediaCardItem> loadRecentlyAdded({int limitPerType = 15}) {
    final db = _databaseService.instance;
    final seriesRows = db.select(
      '''
      SELECT
        s.id,
        s.title,
        s.poster_path,
        (SELECT e.file_path FROM episodes e WHERE e.series_id = s.id ORDER BY e.id ASC LIMIT 1) AS first_file,
        (SELECT e.thumb_path FROM episodes e WHERE e.series_id = s.id AND e.thumb_path IS NOT NULL ORDER BY e.id ASC LIMIT 1) AS fallback_thumb
      FROM series s
      ORDER BY s.id DESC
      LIMIT ?;
      ''',
      [limitPerType],
    );

    final recentSeries = seriesRows
        .where((r) => r['first_file'] != null)
        .map(
          (r) => MediaCardItem(
            mediaKey: 'series_${r['id']}',
            mediaType: 'series',
            title: r['title'] as String,
            subtitle: '',
            imagePath: _resolvePreferredImage(
              r['poster_path'] as String?,
              r['fallback_thumb'] as String?,
            ),
            progressRatio: 0.0,
            remainingMinutes: 0,
            isCompleted: false,
            seriesId: r['id'] as int,
            filePath: r['first_file'] as String,
          ),
        )
        .toList();

    final movieRows = db.select(
      '''
      SELECT
        m.id,
        m.title,
        m.release_year,
        m.file_path,
        m.poster_path,
        m.thumb_path,
        m.sync_key,
        COALESCE(wp.position_ms, 0) AS position_ms,
        COALESCE(wp.duration_ms, m.duration_ms) AS duration_ms,
        COALESCE(wp.completed, 0) AS completed
      FROM movies m
      LEFT JOIN watch_progress wp
        ON wp.media_key = COALESCE(NULLIF(m.sync_key, ''), 'movie_' || m.id)
      ORDER BY m.id DESC
      LIMIT ?;
      ''',
      [limitPerType],
    );

    final recentMovies = movieRows.map(_movieRowToCardItem).toList();
    return [...recentSeries, ...recentMovies];
  }

  List<MediaCardItem> loadRediscoverItems(
    int staleCutoffMs, {
    int limitPerType = 20,
  }) {
    final db = _databaseService.instance;
    final staleSeriesRows = db.select(
      '''
      SELECT
        s.id,
        s.title,
        s.poster_path,
        (SELECT e.file_path FROM episodes e WHERE e.series_id = s.id ORDER BY e.id ASC LIMIT 1) AS first_file,
        (SELECT e.thumb_path FROM episodes e WHERE e.series_id = s.id AND e.thumb_path IS NOT NULL ORDER BY e.id ASC LIMIT 1) AS fallback_thumb
      FROM series s
      WHERE s.last_watched_at IS NULL OR s.last_watched_at < ?
      ORDER BY s.id DESC
      LIMIT ?;
      ''',
      [staleCutoffMs, limitPerType],
    );

    final staleSeries = staleSeriesRows
        .where((r) => r['first_file'] != null)
        .map(
          (r) => MediaCardItem(
            mediaKey: 'series_${r['id']}',
            mediaType: 'series',
            title: r['title'] as String,
            subtitle: '',
            imagePath: _resolvePreferredImage(
              r['poster_path'] as String?,
              r['fallback_thumb'] as String?,
            ),
            progressRatio: 0.0,
            remainingMinutes: 0,
            isCompleted: false,
            seriesId: r['id'] as int,
            filePath: r['first_file'] as String,
          ),
        )
        .toList();

    final staleMovieRows = db.select(
      '''
      SELECT
        m.id,
        m.title,
        m.release_year,
        m.file_path,
        m.poster_path,
        m.thumb_path,
        m.sync_key,
        COALESCE(wp.position_ms, 0) AS position_ms,
        COALESCE(wp.duration_ms, m.duration_ms) AS duration_ms,
        COALESCE(wp.completed, 0) AS completed
      FROM movies m
      LEFT JOIN watch_progress wp
        ON wp.media_key = COALESCE(NULLIF(m.sync_key, ''), 'movie_' || m.id)
      WHERE m.last_watched_at IS NULL OR m.last_watched_at < ?
      ORDER BY m.id DESC
      LIMIT ?;
      ''',
      [staleCutoffMs, limitPerType],
    );

    final staleMovies = staleMovieRows.map(_movieRowToCardItem).toList();
    return [...staleSeries, ...staleMovies];
  }

  List<MediaCardItem> loadAllSeries({bool useWatchedFraction = false}) {
    final db = _databaseService.instance;
    final rows = db.select(
      '''
      SELECT
        s.id,
        s.title,
        s.poster_path,
        (SELECT COUNT(*) FROM episodes e WHERE e.series_id = s.id) AS ep_count,
        (SELECT COUNT(*) FROM episodes e
         INNER JOIN watch_progress wp
           ON wp.media_key = COALESCE(NULLIF(e.sync_key, ''), 'episode_' || e.id)
         WHERE e.series_id = s.id AND wp.completed = 1) AS watched_count,
        (SELECT e.file_path FROM episodes e WHERE e.series_id = s.id ORDER BY e.id ASC LIMIT 1) AS first_file,
        (SELECT e.thumb_path FROM episodes e WHERE e.series_id = s.id AND e.thumb_path IS NOT NULL ORDER BY e.id ASC LIMIT 1) AS fallback_thumb
      FROM series s
      ORDER BY s.title COLLATE NOCASE ASC;
      ''',
    );

    return rows.where((r) => r['first_file'] != null).map((r) {
      final epCount = (r['ep_count'] as int?) ?? 0;
      final watchedCount = (r['watched_count'] as int?) ?? 0;
      final ratio =
          epCount > 0 ? (watchedCount / epCount).clamp(0.0, 1.0) : 0.0;
      final subtitle = useWatchedFraction
          ? '${AppStrings.seriesTypeBadge} · $watchedCount/$epCount'
          : '${AppStrings.seriesTypeBadge} · $epCount ${AppStrings.episodesCountLabel}';
      return MediaCardItem(
        mediaKey: 'series_${r['id']}',
        mediaType: 'series',
        title: r['title'] as String,
        subtitle: subtitle,
        imagePath: _resolvePreferredImage(
          r['poster_path'] as String?,
          r['fallback_thumb'] as String?,
        ),
        progressRatio: ratio,
        remainingMinutes: 0,
        isCompleted: epCount > 0 && watchedCount >= epCount,
        seriesId: r['id'] as int,
        filePath: r['first_file'] as String,
      );
    }).toList();
  }

  List<MediaCardItem> loadAllMovies() {
    final db = _databaseService.instance;
    final rows = db.select(
      '''
      SELECT
        m.id,
        m.title,
        m.release_year,
        m.file_path,
        m.poster_path,
        m.thumb_path,
        m.sync_key,
        COALESCE(wp.position_ms, 0) AS position_ms,
        COALESCE(wp.duration_ms, m.duration_ms) AS duration_ms,
        COALESCE(wp.completed, 0) AS completed
      FROM movies m
      LEFT JOIN watch_progress wp
        ON wp.media_key = COALESCE(NULLIF(m.sync_key, ''), 'movie_' || m.id)
      ORDER BY m.title COLLATE NOCASE ASC;
      ''',
    );

    return rows.map(_movieRowToCardItem).toList();
  }

  SeriesDetailData? loadSeriesDetail(int seriesId) {
    final db = _databaseService.instance;
    final seriesRows = db.select(
      'SELECT id, title, folder_path, poster_path, summary FROM series WHERE id = ? LIMIT 1;',
      [seriesId],
    );
    if (seriesRows.isEmpty) {
      return null;
    }

    final sRow = seriesRows.first;
    final summary = (sRow['summary'] as String?) ?? '';

    final rows = db.select(
      '''
      SELECT
        sn.id AS season_id,
        sn.season_number,
        e.id AS episode_id,
        e.episode_number,
        e.title AS episode_title,
        e.file_path,
        e.duration_ms,
        e.thumb_path,
        e.sync_key,
        COALESCE(wp.position_ms, 0) AS position_ms,
        COALESCE(wp.completed, 0) AS completed
      FROM seasons sn
      INNER JOIN episodes e ON e.season_id = sn.id
      LEFT JOIN watch_progress wp
        ON wp.media_key = COALESCE(NULLIF(e.sync_key, ''), 'episode_' || e.id)
      WHERE sn.series_id = ?
      ORDER BY sn.season_number ASC, e.episode_number ASC;
      ''',
      [seriesId],
    );

    final seasonOrder = <int>[];
    final seasonNumbers = <int, int>{};
    final episodesBySeason = <int, List<EpisodeEntry>>{};

    for (final row in rows) {
      final seasonId = row['season_id'] as int;
      if (!episodesBySeason.containsKey(seasonId)) {
        seasonOrder.add(seasonId);
        seasonNumbers[seasonId] = row['season_number'] as int;
        episodesBySeason[seasonId] = [];
      }
      episodesBySeason[seasonId]!.add(
        EpisodeEntry(
          id: row['episode_id'] as int,
          seriesId: seriesId,
          seasonId: seasonId,
          seasonNumber: row['season_number'] as int,
          episodeNumber: row['episode_number'] as int,
          title: row['episode_title'] as String,
          filePath: row['file_path'] as String,
          durationMs: row['duration_ms'] as int,
          thumbPath: PortablePaths.resolveThumbnailPath(
            row['thumb_path'] as String?,
          ),
          positionMs: row['position_ms'] as int,
          isCompleted: (row['completed'] as int) == 1,
          syncKey: row['sync_key'] as String?,
        ),
      );
    }

    final seasons = [
      for (final seasonId in seasonOrder)
        SeasonGroup(
          seasonId: seasonId,
          seasonNumber: seasonNumbers[seasonId]!,
          episodes: episodesBySeason[seasonId]!,
        ),
    ];

    return SeriesDetailData(
      seriesId: seriesId,
      title: sRow['title'] as String,
      folderPath: sRow['folder_path'] as String,
      posterPath: PortablePaths.resolveThumbnailPath(
        sRow['poster_path'] as String?,
      ),
      summary: summary.isEmpty ? null : summary,
      seasons: seasons,
    );
  }

  int loadResumePositionMs(String mediaKey) {
    final db = _databaseService.instance;
    final rows = db.select(
      'SELECT position_ms, completed FROM watch_progress WHERE media_key = ? LIMIT 1;',
      [mediaKey],
    );
    if (rows.isEmpty) {
      return 0;
    }
    if ((rows.first['completed'] as int?) == 1) {
      return 0;
    }
    return (rows.first['position_ms'] as int?) ?? 0;
  }

  void toggleEpisodeWatched(EpisodeEntry episode, String deviceName) {
    final db = _databaseService.instance;
    final key = episode.mediaKey;
    final nextCompleted = episode.isCompleted ? 0 : 1;
    final nextPosition = nextCompleted == 1 ? episode.durationMs : 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    db.execute(
      '''
      INSERT INTO watch_progress (
        media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device
      )
      VALUES (?, 'episode', ?, ?, ?, ?, ?)
      ON CONFLICT(media_key) DO UPDATE SET
        position_ms = excluded.position_ms,
        duration_ms = excluded.duration_ms,
        completed = excluded.completed,
        updated_at = excluded.updated_at,
        source_device = excluded.source_device;
      ''',
      [key, nextPosition, episode.durationMs, nextCompleted, nowMs, deviceName],
    );
  }

  void removeFromContinueWatching(String mediaKey, String deviceName) {
    final db = _databaseService.instance;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    db.execute(
      '''
      UPDATE watch_progress
      SET position_ms = 0, completed = 0, updated_at = ?, source_device = ?
      WHERE media_key = ? AND completed = 0;
      ''',
      [nowMs, deviceName, mediaKey],
    );
  }

  static MediaCardItem _movieRowToCardItem(Map<String, Object?> r) {
    final posMs = r['position_ms'] as int;
    final durMs = r['duration_ms'] as int;
    final completed = (r['completed'] as int) == 1;
    final ratio = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    final remMs = (!completed && durMs > posMs) ? durMs - posMs : 0;
    final remMin = (remMs / AppSpacing.millisecondsPerMinute).ceil();
    final year = r['release_year'] as int?;
    final subtitle = year != null
        ? '${AppStrings.movieTypeBadge} · $year'
        : AppStrings.movieTypeBadge;
    final rawSyncKey = r['sync_key'] as String?;
    final mediaKey = (rawSyncKey != null && rawSyncKey.isNotEmpty)
        ? rawSyncKey
        : 'movie_${r['id']}';

    return MediaCardItem(
      mediaKey: mediaKey,
      mediaType: 'movie',
      title: r['title'] as String,
      subtitle: subtitle,
      imagePath: _resolvePreferredImage(
        r['thumb_path'] as String?,
        r['poster_path'] as String?,
      ),
      progressRatio: ratio,
      remainingMinutes: remMin,
      isCompleted: completed,
      seriesId: null,
      filePath: r['file_path'] as String,
    );
  }

  static String? _resolvePreferredImage(String? primary, String? fallback) {
    return PortablePaths.resolveThumbnailPath(primary) ??
        PortablePaths.resolveThumbnailPath(fallback);
  }
}
