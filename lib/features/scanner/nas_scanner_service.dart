import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/portable_paths.dart';
import '../library/metadata_reader.dart';
import 'media_parser.dart';
import 'thumbnail_generator_service.dart';

class ScanResult {
  const ScanResult({
    required this.nasReachable,
    required this.seriesCount,
    required this.movieCount,
    required this.skippedDueToPlayback,
  });

  final bool nasReachable;
  final int seriesCount;
  final int movieCount;
  final bool skippedDueToPlayback;
}

class _ScanPayload {
  const _ScanPayload({
    required this.rootPaths,
    required this.thumbCacheDir,
  });

  final List<String> rootPaths;
  final String thumbCacheDir;
}

class _ScannedSeriesData {
  const _ScannedSeriesData({
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

class _ScanOutput {
  const _ScanOutput({
    required this.nasReachable,
    required this.reachableRoots,
    required this.seriesList,
    required this.movies,
  });

  final bool nasReachable;
  final List<String> reachableRoots;
  final List<_ScannedSeriesData> seriesList;
  final List<ParsedMovie> movies;
}

class NasScannerService {
  NasScannerService(this._databaseService);

  final DatabaseService _databaseService;
  bool _isPlaybackActive = false;

  bool get isPlaybackActive => _isPlaybackActive;

  void setPlaybackActive(bool active) {
    _isPlaybackActive = active;
  }

  Future<ScanResult> scanLibrary(List<String> rootPaths) async {
    if (_isPlaybackActive) {
      final counts = _currentCounts();
      return ScanResult(
        nasReachable: true,
        seriesCount: counts.$1,
        movieCount: counts.$2,
        skippedDueToPlayback: true,
      );
    }

    final cleanedPaths = <String>[];
    for (final path in rootPaths) {
      final trimmed = path.trim();
      if (trimmed.isNotEmpty &&
          !cleanedPaths.any((p) => p.toLowerCase() == trimmed.toLowerCase())) {
        cleanedPaths.add(trimmed);
      }
    }

    if (cleanedPaths.isEmpty) {
      final counts = _currentCounts();
      return ScanResult(
        nasReachable: false,
        seriesCount: counts.$1,
        movieCount: counts.$2,
        skippedDueToPlayback: false,
      );
    }

    final thumbDir = await PortablePaths.getCacheDirectory();
    final output = await Isolate.run(
      () => _runScanInIsolate(
        _ScanPayload(
          rootPaths: cleanedPaths,
          thumbCacheDir: thumbDir,
        ),
      ),
    );

    if (!output.nasReachable) {
      final counts = _currentCounts();
      return ScanResult(
        nasReachable: false,
        seriesCount: counts.$1,
        movieCount: counts.$2,
        skippedDueToPlayback: false,
      );
    }

    _applyDiffToDatabase(output);
    await _generateMissingThumbnails();
    final counts = _currentCounts();

    return ScanResult(
      nasReachable: true,
      seriesCount: counts.$1,
      movieCount: counts.$2,
      skippedDueToPlayback: _isPlaybackActive,
    );
  }

  Future<void> _generateMissingThumbnails() async {
    if (_isPlaybackActive) {
      return;
    }

    final db = _databaseService.instance;
    final episodeRows = db.select(
      '''
      SELECT id, file_path, duration_ms
      FROM episodes
      WHERE thumb_path IS NULL OR thumb_path = ''
      LIMIT ?;
      ''',
      [AppSpacing.maxThumbnailsPerScan],
    );

    final remainingQuota = AppSpacing.maxThumbnailsPerScan - episodeRows.length;
    final movieRows = remainingQuota > 0
        ? db.select(
            '''
            SELECT id, file_path, duration_ms
            FROM movies
            WHERE thumb_path IS NULL OR thumb_path = ''
            LIMIT ?;
            ''',
            [remainingQuota],
          )
        : const <Map<String, Object?>>[];

    if (episodeRows.isEmpty && movieRows.isEmpty) {
      return;
    }

    final mediaKitSession = await ThumbnailMediaKitSession.create();

    try {
      for (final row in episodeRows) {
        if (_isPlaybackActive) {
          break;
        }
        final id = row['id'] as int;
        final filePath = row['file_path'] as String;
        final durationMs = row['duration_ms'] as int;

        final thumbPath =
            await ThumbnailGeneratorService.generateEpisodeThumbnail(
          videoFilePath: filePath,
          durationMs: durationMs,
          isPlaybackActive: _isPlaybackActive,
          mediaKitSession: mediaKitSession,
        );

        if (thumbPath != null && !_isPlaybackActive) {
          db.execute(
            'UPDATE episodes SET thumb_path = ? WHERE id = ?;',
            [thumbPath, id],
          );
        }
      }

      for (final row in movieRows) {
        if (_isPlaybackActive) {
          break;
        }
        final id = row['id'] as int;
        final filePath = row['file_path'] as String;
        final durationMs = row['duration_ms'] as int;

        final thumbPath = await ThumbnailGeneratorService.generateThumbnail(
          videoFilePath: filePath,
          durationMs: durationMs,
          isPlaybackActive: _isPlaybackActive,
          prefix: 'mv',
          mediaKitSession: mediaKitSession,
        );

        if (thumbPath != null && !_isPlaybackActive) {
          db.execute(
            'UPDATE movies SET thumb_path = ? WHERE id = ?;',
            [thumbPath, id],
          );
        }
      }
    } finally {
      await mediaKitSession?.dispose();
    }
  }

  (int, int) _currentCounts() {
    final db = _databaseService.instance;
    final seriesRow = db.select('SELECT COUNT(*) AS cnt FROM series;').first;
    final moviesRow = db.select('SELECT COUNT(*) AS cnt FROM movies;').first;
    return (seriesRow['cnt'] as int, moviesRow['cnt'] as int);
  }

  void _applyDiffToDatabase(_ScanOutput output) {
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
                ep.filePath
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
                ep.filePath
              ],
            );
          }
        }
      }

      for (final movie in output.movies) {
        activeMoviePaths.add(movie.filePath);
        final posterPath = _findLocalPosterNearFile(movie.filePath);

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

      final allEpisodes = db.select('SELECT id, file_path FROM episodes;');
      for (final row in allEpisodes) {
        final pathStr = row['file_path'] as String;
        if (_isPathUnderAnyRoot(pathStr, output.reachableRoots) &&
            !activeEpisodePaths.contains(pathStr)) {
          db.execute('DELETE FROM episodes WHERE id = ?;', [row['id']]);
        }
      }

      final allMovies = db.select('SELECT id, file_path FROM movies;');
      for (final row in allMovies) {
        final pathStr = row['file_path'] as String;
        if (_isPathUnderAnyRoot(pathStr, output.reachableRoots) &&
            !activeMoviePaths.contains(pathStr)) {
          db.execute('DELETE FROM movies WHERE id = ?;', [row['id']]);
        }
      }

      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static String? _findLocalPosterInDir(String dirPath) {
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

  static String? _findLocalPosterNearFile(String mediaFilePath) {
    return _findLocalPosterInDir(p.dirname(mediaFilePath));
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

  static _ScanOutput _runScanInIsolate(_ScanPayload payload) {
    final reachableRoots = <String>[];
    final episodesBySeries = <String, List<ParsedEpisode>>{};
    final posterBySeries = <String, String>{};
    final folderBySeries = <String, String>{};
    final summaryBySeries = <String, String?>{};
    final movies = <ParsedMovie>[];

    for (final rootPath in payload.rootPaths) {
      final rootDir = Directory(rootPath);
      if (!rootDir.existsSync()) {
        continue;
      }

      List<FileSystemEntity> entries;
      try {
        entries = rootDir.listSync(recursive: true, followLinks: false);
      } on FileSystemException {
        continue;
      }

      reachableRoots.add(rootPath);

      for (final entity in entries) {
        if (entity is! File) {
          continue;
        }
        final filePath = entity.path;
        if (!MediaParser.isVideoFile(filePath)) {
          continue;
        }

        final episode = MediaParser.parseEpisode(filePath, rootPath);
        if (episode != null) {
          final seriesFolder = _resolveSeriesRoot(filePath, rootPath);
          final key = seriesFolder.toLowerCase();
          episodesBySeries.putIfAbsent(key, () => []).add(episode);
          folderBySeries.putIfAbsent(key, () => seriesFolder);
          posterBySeries.putIfAbsent(
            key,
            () =>
                _findLocalPosterInDir(seriesFolder) ??
                _findLocalPosterNearFile(filePath) ??
                '',
          );
          summaryBySeries.putIfAbsent(
            key,
            () => MetadataReader.readSeriesSummary(seriesFolder),
          );
        } else {
          movies.add(MediaParser.parseMovie(filePath, rootPath));
        }
      }
    }

    if (reachableRoots.isEmpty) {
      return const _ScanOutput(
        nasReachable: false,
        reachableRoots: [],
        seriesList: [],
        movies: [],
      );
    }

    final seriesList = <_ScannedSeriesData>[];
    for (final entry in episodesBySeries.entries) {
      final key = entry.key;
      final eps = entry.value;
      if (eps.isEmpty) {
        continue;
      }
      final posterRaw = posterBySeries[key];
      seriesList.add(
        _ScannedSeriesData(
          title: eps.first.seriesTitle,
          folderPath: folderBySeries[key] ?? reachableRoots.first,
          posterPath:
              (posterRaw != null && posterRaw.isNotEmpty) ? posterRaw : null,
          summary: summaryBySeries[key],
          episodes: eps,
        ),
      );
    }

    return _ScanOutput(
      nasReachable: true,
      reachableRoots: reachableRoots,
      seriesList: seriesList,
      movies: movies,
    );
  }

  static String _resolveSeriesRoot(String episodeFilePath, String rootPath) {
    final rel = p.relative(episodeFilePath, from: rootPath);
    final parts = p.split(rel);
    for (var i = parts.length - 2; i >= 0; i--) {
      if (!MediaParser.isNonSeriesSubfolder(parts[i])) {
        return p.joinAll([rootPath, ...parts.take(i + 1)]);
      }
    }
    return p.dirname(episodeFilePath);
  }
}
