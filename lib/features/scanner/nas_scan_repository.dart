import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import '../../core/storage/database_service.dart';
import 'media_parser.dart';
import 'scan_models.dart';

export 'scan_models.dart';

class NasScanRepository {
  NasScanRepository(
    this._databaseService, {
    this.deleteGuardMinEntries = AppSpacing.scanDeleteGuardMinEntries,
    this.deleteGuardMaxRatio = AppSpacing.scanDeleteGuardMaxRatio,
  });

  final DatabaseService _databaseService;
  final int deleteGuardMinEntries;
  final double deleteGuardMaxRatio;

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
        e.file_path, e.file_size, e.modified_at, e.title, e.artist,
        e.duration_ms, e.sync_key, e.episode_number, sn.season_number,
        s.title AS series_title, s.summary AS series_summary
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
      SELECT file_path, file_size, modified_at, title, artist,
             duration_ms, sync_key, release_year
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

  List<String> applyDiff(ScanOutput output, {bool allowMassDeletion = false}) {
    return applyDiffWithSummary(
      output,
      allowMassDeletion: allowMassDeletion,
    ).orphanedThumbnails;
  }

  /// Zwei-Stufen-Diff (A02) + Duplikat-/Identitätskonfliktschutz (A06):
  /// 1. Upserts gültiger Medien prüfen sync_key-Kollisionen vorab.
  /// 2. Löschungen erfolgen ausschließlich für `effectiveCompleteRoots`.
  ScanDiffSummary applyDiffWithSummary(
    ScanOutput output, {
    bool allowMassDeletion = false,
  }) {
    if (output.wasCancelled) {
      return const ScanDiffSummary();
    }
    final db = _databaseService.instance;
    db.execute('BEGIN TRANSACTION;');

    try {
      final activeEpisodePaths = <String>{};
      final activeMoviePaths = <String>{};
      final identityConflicts = <ScanIdentityConflict>[];

      final existingEpKeys = _loadExistingKeyMap(db, 'episodes');
      final existingMvKeys = _loadExistingKeyMap(db, 'movies');
      final existingEpThumbs = _loadThumbMetaMap(db, 'episodes');
      final existingMvThumbs = _loadThumbMetaMap(db, 'movies');
      final orphanedThumbs = <String>[];
      final batchEpKeys = <String, String>{};
      final batchMvKeys = <String, String>{};

      for (final item in output.seriesList) {
        final validEpisodes = <ParsedEpisode>[];
        for (final ep in item.episodes) {
          activeEpisodePaths.add(ep.filePath);
          final conflict = _detectKeyConflict(
            mediaType: 'episode',
            syncKey: ep.syncKey,
            filePath: ep.filePath,
            batchKeys: batchEpKeys,
            existingKeys: existingEpKeys,
          );
          if (conflict != null) {
            identityConflicts.add(conflict);
            continue;
          }
          if (ep.syncKey.isNotEmpty) {
            batchEpKeys[ep.syncKey] = ep.filePath;
          }
          validEpisodes.add(ep);
        }

        if (validEpisodes.isEmpty) {
          continue;
        }

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

        final seriesId = db.select(
          'SELECT id FROM series WHERE folder_path = ? LIMIT 1;',
          [item.folderPath],
        ).first['id'] as int;

        for (final ep in validEpisodes) {
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

          final seasonId = db.select(
            'SELECT id FROM seasons WHERE series_id = ? AND season_number = ? LIMIT 1;',
            [seriesId, ep.seasonNumber],
          ).first['id'] as int;

          final prevThumb = existingEpThumbs[ep.filePath];
          if (prevThumb != null &&
              prevThumb.thumbPath.isNotEmpty &&
              (prevThumb.fileSize != ep.fileSize ||
                  prevThumb.modifiedAt != ep.modifiedAt)) {
            orphanedThumbs.add(prevThumb.thumbPath);
          }

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
              thumb_path = CASE
                WHEN episodes.file_size != excluded.file_size
                  OR episodes.modified_at != excluded.modified_at
                THEN NULL
                ELSE episodes.thumb_path
              END,
              thumb_status = CASE
                WHEN episodes.file_size != excluded.file_size
                  OR episodes.modified_at != excluded.modified_at
                THEN 'pending'
                ELSE episodes.thumb_status
              END,
              thumb_attempts = CASE
                WHEN episodes.file_size != excluded.file_size
                  OR episodes.modified_at != excluded.modified_at
                THEN 0
                ELSE episodes.thumb_attempts
              END,
              thumb_last_error = CASE
                WHEN episodes.file_size != excluded.file_size
                  OR episodes.modified_at != excluded.modified_at
                THEN NULL
                ELSE episodes.thumb_last_error
              END,
              thumb_retry_at = CASE
                WHEN episodes.file_size != excluded.file_size
                  OR episodes.modified_at != excluded.modified_at
                THEN 0
                ELSE episodes.thumb_retry_at
              END,
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
        final conflict = _detectKeyConflict(
          mediaType: 'movie',
          syncKey: movie.syncKey,
          filePath: movie.filePath,
          batchKeys: batchMvKeys,
          existingKeys: existingMvKeys,
        );
        if (conflict != null) {
          identityConflicts.add(conflict);
          continue;
        }
        if (movie.syncKey.isNotEmpty) {
          batchMvKeys[movie.syncKey] = movie.filePath;
        }

        final prevThumb = existingMvThumbs[movie.filePath];
        if (prevThumb != null &&
            prevThumb.thumbPath.isNotEmpty &&
            (prevThumb.fileSize != movie.fileSize ||
                prevThumb.modifiedAt != movie.modifiedAt)) {
          orphanedThumbs.add(prevThumb.thumbPath);
        }

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
            thumb_path = CASE
              WHEN movies.file_size != excluded.file_size
                OR movies.modified_at != excluded.modified_at
              THEN NULL
              ELSE movies.thumb_path
            END,
            thumb_status = CASE
              WHEN movies.file_size != excluded.file_size
                OR movies.modified_at != excluded.modified_at
              THEN 'pending'
              ELSE movies.thumb_status
            END,
            thumb_attempts = CASE
              WHEN movies.file_size != excluded.file_size
                OR movies.modified_at != excluded.modified_at
              THEN 0
              ELSE movies.thumb_attempts
            END,
            thumb_last_error = CASE
              WHEN movies.file_size != excluded.file_size
                OR movies.modified_at != excluded.modified_at
              THEN NULL
              ELSE movies.thumb_last_error
            END,
            thumb_retry_at = CASE
              WHEN movies.file_size != excluded.file_size
                OR movies.modified_at != excluded.modified_at
              THEN 0
              ELSE movies.thumb_retry_at
            END,
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

      final deletionBlockedRoots = <String>[];
      var plannedEpisodeDeletions = 0;
      var plannedMovieDeletions = 0;

      final completeRoots = output.effectiveCompleteRoots;
      if (completeRoots.isNotEmpty) {
        final allEpisodes =
            db.select('SELECT id, file_path, thumb_path FROM episodes;');
        final allMovies =
            db.select('SELECT id, file_path, thumb_path FROM movies;');
        final deletedEpisodeIds = <int>{};
        final deletedMovieIds = <int>{};

        for (final root in completeRoots) {
          final rootList = [root];
          var existingInRoot = 0;
          final epToDelete = <Map<String, Object?>>[];
          final mvToDelete = <Map<String, Object?>>[];

          for (final row in allEpisodes) {
            final pathStr = row['file_path'] as String;
            if (!_isPathUnderAnyRoot(pathStr, rootList)) continue;
            existingInRoot++;
            if (!activeEpisodePaths.contains(pathStr)) {
              epToDelete.add(row);
            }
          }
          for (final row in allMovies) {
            final pathStr = row['file_path'] as String;
            if (!_isPathUnderAnyRoot(pathStr, rootList)) continue;
            existingInRoot++;
            if (!activeMoviePaths.contains(pathStr)) {
              mvToDelete.add(row);
            }
          }

          final missingInRoot = epToDelete.length + mvToDelete.length;
          if (missingInRoot == 0) continue;

          if (!allowMassDeletion &&
              existingInRoot >= deleteGuardMinEntries &&
              (missingInRoot / existingInRoot) >= deleteGuardMaxRatio) {
            deletionBlockedRoots.add(root);
            continue;
          }

          for (final row in epToDelete) {
            final id = row['id'] as int;
            if (!deletedEpisodeIds.add(id)) continue;
            plannedEpisodeDeletions++;
            final thumb = row['thumb_path'] as String?;
            if (thumb != null && thumb.isNotEmpty) {
              orphanedThumbs.add(thumb);
            }
            db.execute('DELETE FROM episodes WHERE id = ?;', [id]);
          }
          for (final row in mvToDelete) {
            final id = row['id'] as int;
            if (!deletedMovieIds.add(id)) continue;
            plannedMovieDeletions++;
            final thumb = row['thumb_path'] as String?;
            if (thumb != null && thumb.isNotEmpty) {
              orphanedThumbs.add(thumb);
            }
            db.execute('DELETE FROM movies WHERE id = ?;', [id]);
          }
        }
      }

      db.execute(
        'DELETE FROM seasons WHERE NOT EXISTS (SELECT 1 FROM episodes e WHERE e.season_id = seasons.id);',
      );
      db.execute(
        'DELETE FROM series WHERE NOT EXISTS (SELECT 1 FROM episodes e WHERE e.series_id = series.id);',
      );

      db.execute('COMMIT;');
      return ScanDiffSummary(
        orphanedThumbnails: orphanedThumbs,
        plannedEpisodeDeletions: plannedEpisodeDeletions,
        plannedMovieDeletions: plannedMovieDeletions,
        deletionBlockedByThreshold: deletionBlockedRoots.isNotEmpty,
        deletionBlockedRoots: deletionBlockedRoots,
        identityConflicts: identityConflicts,
      );
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static Map<String, ({int fileSize, int modifiedAt, String thumbPath})>
      _loadThumbMetaMap(
    dynamic db,
    String table,
  ) {
    final rows = db.select(
      'SELECT file_path, file_size, modified_at, thumb_path FROM $table;',
    );
    final map = <String, ({int fileSize, int modifiedAt, String thumbPath})>{};
    for (final row in rows) {
      map[row['file_path'] as String] = (
        fileSize: (row['file_size'] as int?) ?? 0,
        modifiedAt: (row['modified_at'] as int?) ?? 0,
        thumbPath: (row['thumb_path'] as String?) ?? '',
      );
    }
    return map;
  }

  static Map<String, String> _loadExistingKeyMap(dynamic db, String table) {
    final rows = db.select(
      "SELECT sync_key, file_path FROM $table WHERE sync_key IS NOT NULL AND sync_key != '';",
    );
    return {
      for (final row in rows)
        row['sync_key'] as String: row['file_path'] as String,
    };
  }

  static ScanIdentityConflict? _detectKeyConflict({
    required String mediaType,
    required String syncKey,
    required String filePath,
    required Map<String, String> batchKeys,
    required Map<String, String> existingKeys,
  }) {
    if (syncKey.isEmpty) return null;
    final batchConflict = batchKeys[syncKey];
    if (batchConflict != null && !_pathsEquivalent(batchConflict, filePath)) {
      return ScanIdentityConflict(
        mediaType: mediaType,
        syncKey: syncKey,
        filePath: filePath,
        conflictingFilePath: batchConflict,
      );
    }
    final dbConflict = existingKeys[syncKey];
    if (dbConflict != null && !_pathsEquivalent(dbConflict, filePath)) {
      return ScanIdentityConflict(
        mediaType: mediaType,
        syncKey: syncKey,
        filePath: filePath,
        conflictingFilePath: dbConflict,
      );
    }
    return null;
  }

  static bool _pathsEquivalent(String a, String b) =>
      p.normalize(a).toLowerCase() == p.normalize(b).toLowerCase();

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
