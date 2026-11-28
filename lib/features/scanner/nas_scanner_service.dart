import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/portable_paths.dart';
import '../library/metadata_reader.dart';
import 'media_parser.dart';
import 'media_tag_reader_service.dart';
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
    required this.knownMetadata,
  });

  final List<String> rootPaths;
  final Map<String, CachedFileMeta> knownMetadata;
}

class NasScannerService {
  NasScannerService(
    this._databaseService, {
    Future<EmbeddedMediaTags?> Function(String filePath)? tagReader,
  })  : _repository = NasScanRepository(_databaseService),
        _tagReader = tagReader;

  final DatabaseService _databaseService;
  final NasScanRepository _repository;
  final Future<EmbeddedMediaTags?> Function(String filePath)? _tagReader;
  bool _isPlaybackActive = false;
  bool _isShutdownCancelled = false;
  Future<ScanResult>? _activeScanFuture;

  bool get isPlaybackActive => _isPlaybackActive;
  bool get _shouldAbort => _isPlaybackActive || _isShutdownCancelled;

  void setPlaybackActive(bool active) {
    _isPlaybackActive = active;
  }

  Future<void> cancelForShutdown() async {
    _isShutdownCancelled = true;
    ThumbnailGeneratorService.killActiveProcesses();
    final active = _activeScanFuture;
    if (active != null) {
      await active.catchError(
        (_) => const ScanResult(
          nasReachable: false,
          seriesCount: 0,
          movieCount: 0,
          skippedDueToPlayback: true,
        ),
      );
    }
  }

  Future<ScanResult> scanLibrary(List<String> rootPaths) {
    final future = _scanLibraryInternal(rootPaths);
    _activeScanFuture = future;
    return future.whenComplete(() {
      if (identical(_activeScanFuture, future)) _activeScanFuture = null;
    });
  }

  Future<ScanResult> _scanLibraryInternal(List<String> rootPaths) async {
    if (_shouldAbort) {
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

    final knownMetadata = _repository.loadKnownFileMetadata();
    final payload = _ScanPayload(
      rootPaths: cleanedPaths,
      knownMetadata: knownMetadata,
    );
    final output = _tagReader == null
        ? await Isolate.run(() => _runScanInIsolate(payload))
        : await _runScan(payload, tagReader: _tagReader);

    if (_shouldAbort) {
      final counts = _repository.currentCounts();
      return ScanResult(
        nasReachable: output.nasReachable,
        seriesCount: counts.$1,
        movieCount: counts.$2,
        skippedDueToPlayback: true,
      );
    }

    if (!output.nasReachable) {
      final counts = _repository.currentCounts();
      return ScanResult(
        nasReachable: false,
        seriesCount: counts.$1,
        movieCount: counts.$2,
        skippedDueToPlayback: false,
      );
    }

    final orphanedThumbs = _repository.applyDiff(output);
    await _deleteOrphanedThumbnails(orphanedThumbs);
    await _generateMissingThumbnails();
    final counts = _repository.currentCounts();

    return ScanResult(
      nasReachable: true,
      seriesCount: counts.$1,
      movieCount: counts.$2,
      skippedDueToPlayback: _shouldAbort,
    );
  }

  Future<void> _deleteOrphanedThumbnails(List<String> orphanedThumbs) async {
    for (final stored in orphanedThumbs) {
      final resolved = PortablePaths.resolveThumbnailPath(stored);
      if (resolved == null || resolved.isEmpty) {
        continue;
      }
      try {
        final thumbFile = File(resolved);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      } on FileSystemException {
        // Gesperrte Cache-Datei ignorieren
      }
    }
  }

  Future<void> _generateMissingThumbnails() async {
    if (_shouldAbort) {
      return;
    }

    final db = _databaseService.instance;
    final episodeRows = db.select(
      '''
      SELECT id, file_path, duration_ms
      FROM episodes
      WHERE thumb_status = 'pending' AND (thumb_path IS NULL OR thumb_path = '')
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
            WHERE thumb_status = 'pending' AND (thumb_path IS NULL OR thumb_path = '')
            LIMIT ?;
            ''',
            [remainingQuota],
          )
        : const <Map<String, Object?>>[];

    if (episodeRows.isEmpty && movieRows.isEmpty) {
      return;
    }

    ThumbnailMediaKitSession? mediaKitSession;
    var mediaKitAttempted = false;

    Future<ThumbnailGenerationResult?> generateWithLazyFallback({
      required String filePath,
      required int durationMs,
      required String prefix,
    }) async {
      final result = await ThumbnailGeneratorService.generateThumbnail(
        videoFilePath: filePath,
        durationMs: durationMs,
        isPlaybackActive: () => _shouldAbort,
        prefix: prefix,
        mediaKitSession: mediaKitSession,
        allowMediaKitFallback: mediaKitSession != null,
      );
      if (result != null || _shouldAbort || mediaKitAttempted) {
        return result;
      }
      mediaKitAttempted = true;
      mediaKitSession = await ThumbnailMediaKitSession.create();
      if (mediaKitSession == null || _shouldAbort) {
        return null;
      }
      return ThumbnailGeneratorService.generateThumbnail(
        videoFilePath: filePath,
        durationMs: durationMs,
        isPlaybackActive: () => _shouldAbort,
        prefix: prefix,
        mediaKitSession: mediaKitSession,
        allowMediaKitFallback: true,
      );
    }

    Future<void> processRows(
      List<Map<String, Object?>> rows,
      String table,
      String prefix,
    ) async {
      for (final row in rows) {
        if (_shouldAbort) break;
        final id = row['id'] as int;
        final filePath = row['file_path'] as String;
        final durationMs = row['duration_ms'] as int;
        final result = await generateWithLazyFallback(
          filePath: filePath,
          durationMs: durationMs,
          prefix: prefix,
        );
        if (_shouldAbort) break;
        if (result?.fileName != null) {
          final nextDur = (durationMs == 0 && (result!.durationMs ?? 0) > 0)
              ? result.durationMs!
              : durationMs;
          db.execute(
            "UPDATE $table SET thumb_path = ?, thumb_status = 'ready', duration_ms = ? WHERE id = ?;",
            [result!.fileName, nextDur, id],
          );
        } else {
          db.execute(
            "UPDATE $table SET thumb_status = 'failed' WHERE id = ?;",
            [id],
          );
        }
      }
    }

    try {
      await processRows(episodeRows, 'episodes', 'ep');
      await processRows(movieRows, 'movies', 'mv');
    } finally {
      await mediaKitSession?.dispose();
    }
  }

  static Future<ScanOutput> _runScanInIsolate(_ScanPayload payload) {
    return _runScan(payload, tagReader: MediaTagReaderService.readTags);
  }

  static Future<ScanOutput> _runScan(
    _ScanPayload payload, {
    required Future<EmbeddedMediaTags?> Function(String filePath) tagReader,
  }) async {
    final reachableRoots = <String>[];
    final episodesBySeries = <String, List<ParsedEpisode>>{};
    final posterBySeries = <String, String>{};
    final folderBySeries = <String, String>{};
    final summaryBySeries = <String, String?>{};
    final movies = <ScannedMovieData>[];

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

        final FileStat stat;
        try {
          stat = entity.statSync();
        } on FileSystemException {
          continue;
        }
        final fileSize = stat.size;
        final modifiedAt = stat.modified.millisecondsSinceEpoch;
        final cached = payload.knownMetadata[filePath];
        final isUnchanged = cached != null &&
            cached.modifiedAt > 0 &&
            cached.fileSize == fileSize &&
            cached.modifiedAt == modifiedAt;

        ParsedEpisode? episode;
        String? tagSummary;
        EmbeddedMediaTags? tags;

        if (isUnchanged) {
          episode = cached.toParsedEpisode();
          tagSummary = episode != null ? cached.seriesSummary : null;
        } else {
          tags = await tagReader(filePath);
          episode = MediaParser.parseEpisodeWithTags(
            filePath,
            rootPath,
            tags,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
          );
          tagSummary = tags?.summary;
        }

        if (episode != null) {
          final resolved = _resolveSeriesRoot(
            filePath,
            rootPath,
            episode.seriesTitle,
          );
          final key = resolved.groupKey;
          episodesBySeries.putIfAbsent(key, () => []).add(episode);
          folderBySeries.putIfAbsent(key, () => resolved.folderPath);
          posterBySeries.putIfAbsent(
            key,
            () =>
                (resolved.metaDir != null
                    ? NasScanRepository.findLocalPosterInDir(resolved.metaDir!)
                    : null) ??
                NasScanRepository.findLocalPosterNearFile(filePath) ??
                '',
          );
          final existingSummary = summaryBySeries[key];
          if (existingSummary == null || existingSummary.isEmpty) {
            final fileSummary = resolved.metaDir != null
                ? MetadataReader.readSeriesSummary(resolved.metaDir!)
                : null;
            summaryBySeries[key] =
                (fileSummary != null && fileSummary.isNotEmpty)
                    ? fileSummary
                    : tagSummary;
          }
        } else {
          final parsed = isUnchanged
              ? cached.toParsedMovie()
              : MediaParser.parseMovieWithTags(
                  filePath,
                  rootPath,
                  tags,
                  fileSize: fileSize,
                  modifiedAt: modifiedAt,
                );
          movies.add(
            ScannedMovieData(
              title: parsed.title,
              releaseYear: parsed.releaseYear,
              filePath: parsed.filePath,
              posterPath: NasScanRepository.findLocalPosterNearFile(filePath),
              syncKey: parsed.syncKey,
              artist: parsed.artist,
              durationMs: parsed.durationMs,
              fileSize: parsed.fileSize,
              modifiedAt: parsed.modifiedAt,
            ),
          );
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

  static ({String groupKey, String folderPath, String? metaDir})
      _resolveSeriesRoot(
    String episodeFilePath,
    String rootPath,
    String seriesTitle,
  ) {
    final rel = p.relative(episodeFilePath, from: rootPath);
    final parts = p.split(rel);
    for (var i = parts.length - 2; i >= 0; i--) {
      if (!MediaParser.isNonSeriesSubfolder(parts[i])) {
        final seriesFolder = p.joinAll([rootPath, ...parts.take(i + 1)]);
        return (
          groupKey: seriesFolder.toLowerCase(),
          folderPath: seriesFolder,
          metaDir: seriesFolder,
        );
      }
    }
    final normalizedTitle = seriesTitle.trim().toLowerCase();
    return (
      groupKey: '$rootPath::$normalizedTitle'.toLowerCase(),
      folderPath: '$rootPath::$normalizedTitle',
      metaDir: null,
    );
  }
}
