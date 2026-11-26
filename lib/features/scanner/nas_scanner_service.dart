import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/portable_paths.dart';
import '../library/metadata_reader.dart';
import 'media_parser.dart';
import 'nas_scan_repository.dart';
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

class NasScannerService {
  NasScannerService(this._databaseService)
      : _repository = NasScanRepository(_databaseService);

  final DatabaseService _databaseService;
  final NasScanRepository _repository;
  bool _isPlaybackActive = false;

  bool get isPlaybackActive => _isPlaybackActive;

  void setPlaybackActive(bool active) {
    _isPlaybackActive = active;
  }

  Future<ScanResult> scanLibrary(List<String> rootPaths) async {
    if (_isPlaybackActive) {
      final counts = _repository.currentCounts();
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
      final counts = _repository.currentCounts();
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
      final counts = _repository.currentCounts();
      return ScanResult(
        nasReachable: false,
        seriesCount: counts.$1,
        movieCount: counts.$2,
        skippedDueToPlayback: false,
      );
    }

    _repository.applyDiff(output);
    await _generateMissingThumbnails();
    final counts = _repository.currentCounts();

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
          allowMediaKitFallback: mediaKitSession != null,
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
          allowMediaKitFallback: mediaKitSession != null,
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

  static ScanOutput _runScanInIsolate(_ScanPayload payload) {
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

      final entries = _listFilesSafely(rootDir);
      if (entries == null) {
        continue;
      }

      reachableRoots.add(rootPath);

      for (final entity in entries) {
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
                NasScanRepository.findLocalPosterInDir(seriesFolder) ??
                NasScanRepository.findLocalPosterNearFile(filePath) ??
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
      return const ScanOutput(
        nasReachable: false,
        reachableRoots: [],
        seriesList: [],
        movies: [],
      );
    }

    final seriesList = <ScannedSeriesData>[];
    for (final entry in episodesBySeries.entries) {
      final key = entry.key;
      final eps = entry.value;
      if (eps.isEmpty) {
        continue;
      }
      final posterRaw = posterBySeries[key];
      seriesList.add(
        ScannedSeriesData(
          title: eps.first.seriesTitle,
          folderPath: folderBySeries[key] ?? reachableRoots.first,
          posterPath:
              (posterRaw != null && posterRaw.isNotEmpty) ? posterRaw : null,
          summary: summaryBySeries[key],
          episodes: eps,
        ),
      );
    }

    return ScanOutput(
      nasReachable: true,
      reachableRoots: reachableRoots,
      seriesList: seriesList,
      movies: movies,
    );
  }

  static List<File>? _listFilesSafely(Directory rootDir) {
    final files = <File>[];
    final pendingDirs = <Directory>[rootDir];
    var rootReadable = false;

    while (pendingDirs.isNotEmpty) {
      final current = pendingDirs.removeLast();
      try {
        final children = current.listSync(recursive: false, followLinks: false);
        rootReadable = true;
        for (final entity in children) {
          if (entity is File) {
            files.add(entity);
          } else if (entity is Directory) {
            pendingDirs.add(entity);
          }
        }
      } on FileSystemException {
        if (!rootReadable && current.path == rootDir.path) {
          return null;
        }
      }
    }
    return files;
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
