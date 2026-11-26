import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/storage/database_service.dart';
import 'media_parser.dart';

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
  final List<ParsedMovie> movies;
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

  void applyDiff(ScanOutput output) {
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

          final existingEp = db.select(
            'SELECT id FROM episodes WHERE file_path = ? LIMIT 1;',
            [ep.filePath],
          );

          if (existingEp.isEmpty) {
            db.execute(
              '''
              INSERT INTO episodes (series_id, season_id, episode_number, title, file_path)
              VALUES (?, ?, ?, ?, ?);
              ''',
              [
                seriesId,
                seasonId,
                ep.episodeNumber,
                ep.episodeTitle,
                ep.filePath,
              ],
            );
          } else {
            db.execute(
              '''
              UPDATE episodes
              SET series_id = ?, season_id = ?, episode_number = ?, title = ?
              WHERE file_path = ?;
              ''',
              [
                seriesId,
                seasonId,
                ep.episodeNumber,
                ep.episodeTitle,
                ep.filePath,
              ],
            );
          }
        }
      }

      for (final movie in output.movies) {
        activeMoviePaths.add(movie.filePath);
        final posterPath = findLocalPosterNearFile(movie.filePath);

        db.execute(
          '''
          INSERT INTO movies (title, release_year, file_path, poster_path)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(file_path) DO UPDATE SET
            title = excluded.title,
            release_year = excluded.release_year,
            poster_path = COALESCE(excluded.poster_path, movies.poster_path);
          ''',
          [movie.title, movie.releaseYear, movie.filePath, posterPath],
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

      for (final thumbPath in orphanedThumbs) {
        try {
          final thumbFile = File(thumbPath);
          if (thumbFile.existsSync()) {
            thumbFile.deleteSync();
          }
        } on FileSystemException {
          // Gesperrte Cache-Datei ignorieren
        }
      }
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
