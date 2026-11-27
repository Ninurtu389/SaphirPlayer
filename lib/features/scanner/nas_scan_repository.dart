import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/storage/database_service.dart';
import 'media_parser.dart';

class CachedFileMeta {
  const CachedFileMeta({
    required this.isEpisode,
    required this.filePath,
    required this.fileSize,
    required this.modifiedAt,
    required this.title,
    required this.artist,
    required this.durationMs,
    required this.syncKey,
    this.seriesTitle,
    this.seriesSummary,
    this.seasonNumber,
    this.episodeNumber,
    this.releaseYear,
  });

  final bool isEpisode;
  final String filePath;
  final int fileSize;
  final int modifiedAt;
  final String title;
  final String? artist;
  final int durationMs;
  final String syncKey;
  final String? seriesTitle;
  final String? seriesSummary;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? releaseYear;

  ParsedEpisode? toParsedEpisode() {
    if (!isEpisode ||
        seriesTitle == null ||
        seasonNumber == null ||
        episodeNumber == null) {
      return null;
    }
    return ParsedEpisode(
      seriesTitle: seriesTitle!,
      seasonNumber: seasonNumber!,
      episodeNumber: episodeNumber!,
      episodeTitle: title,
      filePath: filePath,
      syncKey: syncKey,
      artist: artist,
      durationMs: durationMs,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
    );
  }

  ParsedMovie toParsedMovie() {
    return ParsedMovie(
      title: title,
      releaseYear: releaseYear,
      filePath: filePath,
      syncKey: syncKey,
      artist: artist,
      durationMs: durationMs,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
    );
  }
}

class ScannedSeriesData {
  const ScannedSeriesData({
    required this.title,
    required this.folderPath,
    required this.posterPath,
    required this.summary,
    required this.episodes,
  });

  final String title;
  final String folderPath;
  final String? posterPath;
  final String? summary;
  final List<ParsedEpisode> episodes;
}

class ScannedMovieData {
  const ScannedMovieData({
    required this.title,
    required this.releaseYear,
    required this.filePath,
    required this.posterPath,
    required this.syncKey,
    this.artist,
    this.durationMs = 0,
    this.fileSize = 0,
    this.modifiedAt = 0,
  });

  final String title;
  final int? releaseYear;
  final String filePath;
  final String? posterPath;
  final String syncKey;
  final String? artist;
  final int durationMs;
  final int fileSize;
  final int modifiedAt;
}

class ScanOutput {
  const ScanOutput({
    required this.nasReachable,
    required this.reachableRoots,
    required this.seriesList,
    required this.movies,
  });

  final bool nasReachable;
  final List<String> reachableRoots;
  final List<ScannedSeriesData> seriesList;
  final List<ScannedMovieData> movies;
}

class NasScanRepository {
  NasScanRepository(this._databaseService);

  final DatabaseService _databaseService;

  (int, int) currentCounts() {
    final db = _databaseService.instance;
    final seriesRow = db.select('SELECT COUNT(*) AS cnt FROM series;').first;
    final moviesRow = db.select('SELECT COUNT(*) AS cnt FROM movies;').first;
    return (seriesRow['cnt'] as int, moviesRow['cnt'] as int);
  }

  Map<String, CachedFileMeta> loadKnownFileMetadata() {
    final db = _databaseService.instance;
    final map = <String, CachedFileMeta>{};

    final epRows = db.select(
      '''
      SELECT
        e.file_path,
        e.file_size,
        e.modified_at,
        e.title,
        e.artist,
        e.duration_ms,
        e.sync_key,
        e.episode_number,
        sn.season_number,
        s.title AS series_title,
        s.summary AS series_summary
      FROM episodes e
      INNER JOIN series s ON e.series_id = s.id
      INNER JOIN seasons sn ON e.season_id = sn.id;
      ''',
    );
    for (final row in epRows) {
      final pathStr = row['file_path'] as String;
      map[pathStr] = CachedFileMeta(
        isEpisode: true,
        filePath: pathStr,
        fileSize: (row['file_size'] as int?) ?? 0,
        modifiedAt: (row['modified_at'] as int?) ?? 0,
        title: row['title'] as String,
        artist: row['artist'] as String?,
        durationMs: (row['duration_ms'] as int?) ?? 0,
        syncKey: (row['sync_key'] as String?) ?? '',
        seriesTitle: row['series_title'] as String?,
        seriesSummary: row['series_summary'] as String?,
        seasonNumber: row['season_number'] as int?,
        episodeNumber: row['episode_number'] as int?,
      );
    }

    final mvRows = db.select(
      '''
      SELECT
        file_path,
        file_size,
        modified_at,
        title,
        artist,
        duration_ms,
        sync_key,
        release_year
      FROM movies;
      ''',
    );
    for (final row in mvRows) {
      final pathStr = row['file_path'] as String;
      map[pathStr] = CachedFileMeta(
        isEpisode: false,
        filePath: pathStr,
        fileSize: (row['file_size'] as int?) ?? 0,
        modifiedAt: (row['modified_at'] as int?) ?? 0,
        title: row['title'] as String,
        artist: row['artist'] as String?,
        durationMs: (row['duration_ms'] as int?) ?? 0,
        syncKey: (row['sync_key'] as String?) ?? '',
        releaseYear: row['release_year'] as int?,
      );
    }

    return map;
  }

  List<String> applyDiff(ScanOutput output) {
    final db = _databaseService.instance;
    db.execute('BEGIN TRANSACTION;');

    try {
      final activeEpisodePaths = <String>{};
      final activeMoviePaths = <String>{};

      for (final item in output.seriesList) {
        db.execute(
          '''
          INSERT INTO series (title, folder_path, poster_path, summary)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(folder_path) DO UPDATE SET
            title = excluded.title,
            poster_path = COALESCE(excluded.poster_path, series.poster_path),
            summary = COALESCE(excluded.summary, series.summary);
          ''',
          [item.title, item.folderPath, item.posterPath, item.summary],
        );

        final seriesRow = db.select(
          'SELECT id FROM series WHERE folder_path = ? LIMIT 1;',
          [item.folderPath],
        ).first;
        final seriesId = seriesRow['id'] as int;

        for (final ep in item.episodes) {
          activeEpisodePaths.add(ep.filePath);
          final seasonFolder = p.dirname(ep.filePath);

          db.execute(
            '''
            INSERT INTO seasons (series_id, season_number, folder_path)
            VALUES (?, ?, ?)
            ON CONFLICT(series_id, season_number) DO UPDATE SET
              folder_path = excluded.folder_path;
            ''',
            [seriesId, ep.seasonNumber, seasonFolder],
          );

          final seasonRow = db.select(
            'SELECT id FROM seasons WHERE series_id = ? AND season_number = ? LIMIT 1;',
            [seriesId, ep.seasonNumber],
          ).first;
          final seasonId = seasonRow['id'] as int;

          final syncKey = ep.syncKey.isEmpty ? null : ep.syncKey;

          db.execute(
            '''
            INSERT INTO episodes (
              series_id, season_id, episode_number, title, file_path,
              duration_ms, sync_key, artist, file_size, modified_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_path) DO UPDATE SET
              series_id = excluded.series_id,
              season_id = excluded.season_id,
              episode_number = excluded.episode_number,
              title = excluded.title,
              duration_ms = CASE
                WHEN excluded.duration_ms > 0 THEN excluded.duration_ms
                ELSE episodes.duration_ms
              END,
              sync_key = COALESCE(excluded.sync_key, episodes.sync_key),
              artist = excluded.artist,
              file_size = excluded.file_size,
              modified_at = excluded.modified_at;
            ''',
            [
              seriesId,
              seasonId,
              ep.episodeNumber,
              ep.episodeTitle,
              ep.filePath,
              ep.durationMs,
              syncKey,
              ep.artist,
              ep.fileSize,
              ep.modifiedAt,
            ],
          );
        }
      }

      for (final movie in output.movies) {
        activeMoviePaths.add(movie.filePath);
        final syncKey = movie.syncKey.isEmpty ? null : movie.syncKey;

        db.execute(
          '''
          INSERT INTO movies (
            title, release_year, file_path, poster_path,
            duration_ms, sync_key, artist, file_size, modified_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(file_path) DO UPDATE SET
            title = excluded.title,
            release_year = excluded.release_year,
            poster_path = COALESCE(excluded.poster_path, movies.poster_path),
            duration_ms = CASE
              WHEN excluded.duration_ms > 0 THEN excluded.duration_ms
              ELSE movies.duration_ms
            END,
            sync_key = COALESCE(excluded.sync_key, movies.sync_key),
            artist = excluded.artist,
            file_size = excluded.file_size,
            modified_at = excluded.modified_at;
          ''',
          [
            movie.title,
            movie.releaseYear,
            movie.filePath,
            movie.posterPath,
            movie.durationMs,
            syncKey,
            movie.artist,
            movie.fileSize,
            movie.modifiedAt,
          ],
        );
      }

      final orphanedThumbs = <String>[];

      final allEpisodes =
          db.select('SELECT id, file_path, thumb_path FROM episodes;');
      for (final row in allEpisodes) {
        final pathStr = row['file_path'] as String;
        if (_isPathUnderAnyRoot(pathStr, output.reachableRoots) &&
            !activeEpisodePaths.contains(pathStr)) {
          final thumb = row['thumb_path'] as String?;
          if (thumb != null && thumb.isNotEmpty) {
            orphanedThumbs.add(thumb);
          }
          db.execute('DELETE FROM episodes WHERE id = ?;', [row['id']]);
        }
      }

      final allMovies =
          db.select('SELECT id, file_path, thumb_path FROM movies;');
      for (final row in allMovies) {
        final pathStr = row['file_path'] as String;
        if (_isPathUnderAnyRoot(pathStr, output.reachableRoots) &&
            !activeMoviePaths.contains(pathStr)) {
          final thumb = row['thumb_path'] as String?;
          if (thumb != null && thumb.isNotEmpty) {
            orphanedThumbs.add(thumb);
          }
          db.execute('DELETE FROM movies WHERE id = ?;', [row['id']]);
        }
      }

      db.execute(
        'DELETE FROM seasons WHERE NOT EXISTS (SELECT 1 FROM episodes e WHERE e.season_id = seasons.id);',
      );
      db.execute(
        'DELETE FROM series WHERE NOT EXISTS (SELECT 1 FROM episodes e WHERE e.series_id = series.id);',
      );

      db.execute('COMMIT;');
      return orphanedThumbs;
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static String? findLocalPosterInDir(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      return null;
    }
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File && MediaParser.isImageFile(entity.path)) {
        final name = p.basenameWithoutExtension(entity.path).toLowerCase();
        if (name == 'poster' || name == 'folder' || name == 'cover') {
          return entity.path;
        }
      }
    }
    return null;
  }

  static String? findLocalPosterNearFile(String mediaFilePath) {
    return findLocalPosterInDir(p.dirname(mediaFilePath));
  }

  static bool _isPathUnderAnyRoot(String filePath, List<String> roots) {
    final normalizedFile = p.normalize(filePath).toLowerCase();
    for (final root in roots) {
      final normalizedRoot = p.normalize(root).toLowerCase();
      if (normalizedFile == normalizedRoot ||
          normalizedFile.startsWith('$normalizedRoot${p.separator}') ||
          normalizedFile.startsWith('$normalizedRoot/')) {
        return true;
      }
    }
    return false;
  }
}
