import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/storage/database_service.dart';
import '../library/library_models.dart';

class HomeController extends ChangeNotifier {
  HomeController(this._databaseService);

  final DatabaseService _databaseService;
  final Random _random = Random();

  List<MediaCardItem> _continueWatching = const [];
  List<MediaCardItem> _rediscoverItems = const [];
  List<MediaCardItem> _recentlyAdded = const [];
  List<MediaCardItem> _seriesItems = const [];
  List<MediaCardItem> _movieItems = const [];
  MediaCardItem? _heroItem;
  String _searchQuery = '';

  List<MediaCardItem> get continueWatching => _filter(_continueWatching);
  List<MediaCardItem> get rediscoverItems => _filter(_rediscoverItems);
  List<MediaCardItem> get recentlyAdded => _filter(_recentlyAdded);
  List<MediaCardItem> get seriesItems => _filter(_seriesItems);
  List<MediaCardItem> get movieItems => _filter(_movieItems);
  MediaCardItem? get heroItem => _heroItem;
  String get searchQuery => _searchQuery;

  void updateSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  List<MediaCardItem> _filter(List<MediaCardItem> source) {
    if (_searchQuery.isEmpty) {
      return source;
    }
    return source
        .where(
          (item) =>
              item.title.toLowerCase().contains(_searchQuery) ||
              item.subtitle.toLowerCase().contains(_searchQuery),
        )
        .toList();
  }

  void refreshHomeFeeds() {
    final db = _databaseService.instance;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final staleCutoffMs =
        nowMs - (AppSpacing.staleDaysDefault * AppSpacing.millisecondsPerDay);

    final continueList = <MediaCardItem>[];

    final epProgressRows = db.select(
      '''
      SELECT
        wp.media_key,
        wp.position_ms,
        wp.duration_ms,
        wp.completed,
        wp.updated_at,
        e.id AS episode_id,
        e.series_id,
        e.episode_number,
        e.title AS episode_title,
        e.file_path,
        e.thumb_path,
        s.title AS series_title,
        s.poster_path,
        sn.season_number
      FROM watch_progress wp
      INNER JOIN episodes e ON wp.media_key = 'episode_' || e.id
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

      continueList.add(
        MediaCardItem(
          mediaKey: row['media_key'] as String,
          mediaType: 'episode',
          title: row['series_title'] as String,
          subtitle:
              'S${row['season_number']}E${row['episode_number']} · ${row['episode_title']}',
          imagePath:
              (row['thumb_path'] as String?) ?? (row['poster_path'] as String?),
          progressRatio: ratio,
          remainingMinutes: remMin,
          isCompleted: false,
          seriesId: row['series_id'] as int,
          filePath: row['file_path'] as String,
        ),
      );
    }

    final movieProgressRows = db.select(
      '''
      SELECT
        wp.media_key,
        wp.position_ms,
        wp.duration_ms,
        m.title,
        m.release_year,
        m.file_path,
        m.poster_path,
        m.thumb_path
      FROM watch_progress wp
      INNER JOIN movies m ON wp.media_key = 'movie_' || m.id
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

      continueList.add(
        MediaCardItem(
          mediaKey: row['media_key'] as String,
          mediaType: 'movie',
          title: row['title'] as String,
          subtitle: row['release_year'] != null ? '${row['release_year']}' : '',
          imagePath:
              (row['thumb_path'] as String?) ?? (row['poster_path'] as String?),
          progressRatio: ratio,
          remainingMinutes: remMin,
          isCompleted: false,
          seriesId: null,
          filePath: row['file_path'] as String,
        ),
      );
    }

    _continueWatching = continueList;

    final staleSeriesRows = db.select(
      '''
      SELECT
        s.id,
        s.title,
        s.poster_path,
        s.last_watched_at,
        (SELECT e.file_path FROM episodes e WHERE e.series_id = s.id ORDER BY e.id ASC LIMIT 1) AS first_file,
        (SELECT e.thumb_path FROM episodes e WHERE e.series_id = s.id AND e.thumb_path IS NOT NULL ORDER BY e.id ASC LIMIT 1) AS fallback_thumb
      FROM series s
      WHERE s.last_watched_at IS NULL OR s.last_watched_at < ?
      ORDER BY s.id DESC
      LIMIT 20;
      ''',
      [staleCutoffMs],
    );

    _rediscoverItems = staleSeriesRows
        .where((r) => r['first_file'] != null)
        .map(
          (r) => MediaCardItem(
            mediaKey: 'series_${r['id']}',
            mediaType: 'series',
            title: r['title'] as String,
            subtitle: '',
            imagePath: (r['poster_path'] as String?) ??
                (r['fallback_thumb'] as String?),
            progressRatio: 0.0,
            remainingMinutes: 0,
            isCompleted: false,
            seriesId: r['id'] as int,
            filePath: r['first_file'] as String,
          ),
        )
        .toList();

    final recentSeriesRows = db.select(
      '''
      SELECT
        s.id,
        s.title,
        s.poster_path,
        (SELECT e.file_path FROM episodes e WHERE e.series_id = s.id ORDER BY e.id ASC LIMIT 1) AS first_file,
        (SELECT e.thumb_path FROM episodes e WHERE e.series_id = s.id AND e.thumb_path IS NOT NULL ORDER BY e.id ASC LIMIT 1) AS fallback_thumb
      FROM series s
      ORDER BY s.id DESC
      LIMIT 15;
      ''',
    );

    _recentlyAdded = recentSeriesRows
        .where((r) => r['first_file'] != null)
        .map(
          (r) => MediaCardItem(
            mediaKey: 'series_${r['id']}',
            mediaType: 'series',
            title: r['title'] as String,
            subtitle: '',
            imagePath: (r['poster_path'] as String?) ??
                (r['fallback_thumb'] as String?),
            progressRatio: 0.0,
            remainingMinutes: 0,
            isCompleted: false,
            seriesId: r['id'] as int,
            filePath: r['first_file'] as String,
          ),
        )
        .toList();

    _heroItem = _continueWatching.isNotEmpty
        ? _continueWatching.first
        : (_recentlyAdded.isNotEmpty ? _recentlyAdded.first : null);

    final allSeriesRows = db.select(
      '''
      SELECT
        s.id,
        s.title,
        s.poster_path,
        (SELECT COUNT(*) FROM episodes e WHERE e.series_id = s.id) AS ep_count,
        (SELECT COUNT(*) FROM episodes e
         INNER JOIN watch_progress wp ON wp.media_key = 'episode_' || e.id
         WHERE e.series_id = s.id AND wp.completed = 1) AS watched_count,
        (SELECT e.file_path FROM episodes e WHERE e.series_id = s.id ORDER BY e.id ASC LIMIT 1) AS first_file,
        (SELECT e.thumb_path FROM episodes e WHERE e.series_id = s.id AND e.thumb_path IS NOT NULL ORDER BY e.id ASC LIMIT 1) AS fallback_thumb
      FROM series s
      ORDER BY s.title COLLATE NOCASE ASC;
      ''',
    );

    _seriesItems = allSeriesRows
        .where((r) => r['first_file'] != null)
        .map((r) {
          final epCount = (r['ep_count'] as int?) ?? 0;
          final watchedCount = (r['watched_count'] as int?) ?? 0;
          final ratio =
              epCount > 0 ? (watchedCount / epCount).clamp(0.0, 1.0) : 0.0;
          return MediaCardItem(
            mediaKey: 'series_${r['id']}',
            mediaType: 'series',
            title: r['title'] as String,
            subtitle:
                '${AppStrings.seriesTypeBadge} · $epCount ${AppStrings.episodesCountLabel}',
            imagePath: (r['poster_path'] as String?) ??
                (r['fallback_thumb'] as String?),
            progressRatio: ratio,
            remainingMinutes: 0,
            isCompleted: epCount > 0 && watchedCount >= epCount,
            seriesId: r['id'] as int,
            filePath: r['first_file'] as String,
          );
        })
        .toList();

    final allMovieRows = db.select(
      '''
      SELECT
        m.id,
        m.title,
        m.release_year,
        m.file_path,
        m.poster_path,
        m.thumb_path,
        COALESCE(wp.position_ms, 0) AS position_ms,
        COALESCE(wp.duration_ms, m.duration_ms) AS duration_ms,
        COALESCE(wp.completed, 0) AS completed
      FROM movies m
      LEFT JOIN watch_progress wp ON wp.media_key = 'movie_' || m.id
      ORDER BY m.title COLLATE NOCASE ASC;
      ''',
    );

    _movieItems = allMovieRows.map((r) {
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

      return MediaCardItem(
        mediaKey: 'movie_${r['id']}',
        mediaType: 'movie',
        title: r['title'] as String,
        subtitle: subtitle,
        imagePath:
            (r['thumb_path'] as String?) ?? (r['poster_path'] as String?),
        progressRatio: ratio,
        remainingMinutes: remMin,
        isCompleted: completed,
        seriesId: null,
        filePath: r['file_path'] as String,
      );
    }).toList();

    notifyListeners();
  }

  MediaCardItem? pickRandomItem() {
    final pool = <MediaCardItem>[
      ..._rediscoverItems,
      ..._recentlyAdded,
    ];
    if (pool.isEmpty) {
      return null;
    }
    return pool[_random.nextInt(pool.length)];
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
    final folderPath = sRow['folder_path'] as String;
    final summary = (sRow['summary'] as String?) ?? '';

    final seasonRows = db.select(
      'SELECT id, season_number FROM seasons WHERE series_id = ? ORDER BY season_number ASC;',
      [seriesId],
    );

    final seasons = <SeasonGroup>[];
    for (final snRow in seasonRows) {
      final seasonId = snRow['id'] as int;
      final seasonNumber = snRow['season_number'] as int;

      final epRows = db.select(
        '''
        SELECT
          e.id,
          e.episode_number,
          e.title,
          e.file_path,
          e.duration_ms,
          e.thumb_path,
          COALESCE(wp.position_ms, 0) AS position_ms,
          COALESCE(wp.completed, 0) AS completed
        FROM episodes e
        LEFT JOIN watch_progress wp ON wp.media_key = 'episode_' || e.id
        WHERE e.season_id = ?
        ORDER BY e.episode_number ASC;
        ''',
        [seasonId],
      );

      final episodes = epRows
          .map(
            (eRow) => EpisodeEntry(
              id: eRow['id'] as int,
              seriesId: seriesId,
              seasonId: seasonId,
              seasonNumber: seasonNumber,
              episodeNumber: eRow['episode_number'] as int,
              title: eRow['title'] as String,
              filePath: eRow['file_path'] as String,
              durationMs: eRow['duration_ms'] as int,
              thumbPath: eRow['thumb_path'] as String?,
              positionMs: eRow['position_ms'] as int,
              isCompleted: (eRow['completed'] as int) == 1,
            ),
          )
          .toList();

      seasons.add(
        SeasonGroup(
          seasonId: seasonId,
          seasonNumber: seasonNumber,
          episodes: episodes,
        ),
      );
    }

    return SeriesDetailData(
      seriesId: seriesId,
      title: sRow['title'] as String,
      folderPath: folderPath,
      posterPath: sRow['poster_path'] as String?,
      summary: summary.isEmpty ? null : summary,
      seasons: seasons,
    );
  }

  void toggleEpisodeWatched(EpisodeEntry episode, String deviceName) {
    final db = _databaseService.instance;
    final key = 'episode_${episode.id}';
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

    refreshHomeFeeds();
  }
}
