import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import '../library/metadata_reader.dart';
import 'media_parser.dart';
import 'media_tag_reader_service.dart';
import 'nas_scan_repository.dart';

typedef DirectoryLister = List<FileSystemEntity> Function(Directory dir);
typedef FileStatReader = FileStat Function(File file);

class ScanWorkerPayload {
  const ScanWorkerPayload({
    required this.rootPaths,
    required this.knownMetadata,
    this.sourceIdsByRoot = const {},
    this.sourceLabelsByRoot = const {},
  });

  final List<String> rootPaths;
  final Map<String, CachedFileMeta> knownMetadata;
  final Map<String, String> sourceIdsByRoot;
  final Map<String, String> sourceLabelsByRoot;
}

class _IsolateStartMessage {
  const _IsolateStartMessage({
    required this.replyPort,
    required this.payload,
  });

  final SendPort replyPort;
  final ScanWorkerPayload payload;
}

class ScanWorker {
  ScanWorker._();

  static const int _cooperativeYieldBatch = 16;

  static Future<ScanOutput> runInControllableIsolate(
    ScanWorkerPayload payload, {
    ScanCancellationToken? cancellationToken,
    void Function(ScanPhase phase)? onPhaseChanged,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return _cancelledOutput(payload.rootPaths);
    }

    final resultPort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    final resultCompleter = Completer<ScanOutput>();
    final exitCompleter = Completer<void>();

    Isolate? isolate;
    SendPort? workerControlPort;
    Timer? shutdownKillTimer;
    var controlPortSentCancel = false;

    void dispatchCancelToIsolate() {
      if (workerControlPort != null && !controlPortSentCancel) {
        controlPortSentCancel = true;
        workerControlPort!.send('cancel');
      }
      if ((cancellationToken?.isShutdownRequested ?? false) &&
          shutdownKillTimer == null) {
        shutdownKillTimer = Timer(
          const Duration(milliseconds: AppSpacing.scanIsolateShutdownGraceMs),
          () {
            isolate?.kill(priority: Isolate.immediate);
          },
        );
      }
    }

    void onTokenChanged() {
      dispatchCancelToIsolate();
    }

    cancellationToken?.addListener(onTokenChanged);

    final resultSub = resultPort.listen((message) {
      if (message is SendPort) {
        workerControlPort = message;
        if (cancellationToken?.isCancelled ?? false) {
          dispatchCancelToIsolate();
        }
      } else if (message is ScanPhase) {
        onPhaseChanged?.call(message);
      } else if (message is ScanOutput && !resultCompleter.isCompleted) {
        resultCompleter.complete(message);
      }
    });

    final errorSub = errorPort.listen((message) {
      if (resultCompleter.isCompleted) return;
      if (message is List && message.length >= 2) {
        resultCompleter.completeError(
          StateError('Scan-Isolate-Fehler: ${message[0]}'),
          StackTrace.fromString(message[1].toString()),
        );
      } else {
        resultCompleter
            .completeError(StateError('Scan-Isolate-Fehler: $message'));
      }
    });

    final exitSub = exitPort.listen((_) {
      if (!exitCompleter.isCompleted) {
        exitCompleter.complete();
      }
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(_cancelledOutput(payload.rootPaths));
      }
    });

    try {
      isolate = await Isolate.spawn<_IsolateStartMessage>(
        _isolateEntry,
        _IsolateStartMessage(
          replyPort: resultPort.sendPort,
          payload: payload,
        ),
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
        debugName: 'SaphirNasScanWorker',
      );

      if (cancellationToken?.isCancelled ?? false) {
        dispatchCancelToIsolate();
      }

      final output = await resultCompleter.future;
      await exitCompleter.future.timeout(
        const Duration(milliseconds: AppSpacing.scanIsolateShutdownGraceMs),
        onTimeout: () {
          isolate?.kill(priority: Isolate.immediate);
        },
      );
      return output;
    } finally {
      cancellationToken?.removeListener(onTokenChanged);
      shutdownKillTimer?.cancel();
      await resultSub.cancel();
      await errorSub.cancel();
      await exitSub.cancel();
      resultPort.close();
      errorPort.close();
      exitPort.close();
    }
  }

  static Future<void> _isolateEntry(_IsolateStartMessage start) async {
    final controlPort = ReceivePort();
    var cancelled = false;
    final sub = controlPort.listen((message) {
      if (message == 'cancel') {
        cancelled = true;
      }
    });
    start.replyPort.send(controlPort.sendPort);

    try {
      final output = await runScan(
        start.payload,
        tagReader: MediaTagReaderService.readTags,
        isCancelledOverride: () => cancelled,
        yieldPeriodically: true,
        onPhaseChanged: (phase) => start.replyPort.send(phase),
      );
      start.replyPort.send(output);
    } finally {
      await sub.cancel();
      controlPort.close();
    }
  }

  static Future<ScanOutput> runScan(
    ScanWorkerPayload payload, {
    required Future<EmbeddedMediaTags?> Function(String filePath) tagReader,
    ScanCancellationToken? cancellationToken,
    DirectoryLister? directoryLister,
    FileStatReader? fileStatReader,
    bool Function()? isCancelledOverride,
    bool yieldPeriodically = false,
    void Function(ScanPhase phase)? onPhaseChanged,
  }) async {
    bool isCancelled() =>
        (cancellationToken?.isCancelled ?? false) ||
        (isCancelledOverride?.call() ?? false);

    final lister = directoryLister ??
        (Directory dir) => dir.listSync(recursive: false, followLinks: false);
    final statReader = fileStatReader ?? (File file) => file.statSync();

    final reachableRoots = <String>[];
    final completeRoots = <String>[];
    final sourceReports = <SourceScanReport>[];
    final episodesBySeries = <String, List<ParsedEpisode>>{};
    final posterBySeries = <String, String>{};
    final folderBySeries = <String, String>{};
    final summaryBySeries = <String, String?>{};
    final sourceIdBySeries = <String, String?>{};
    final movies = <ScannedMovieData>[];
    var anyCancelled = false;

    for (final rootPath in payload.rootPaths) {
      final sourceId = payload.sourceIdsByRoot[rootPath];
      final sourceLabel = payload.sourceLabelsByRoot[rootPath];
      final startedAtMs = DateTime.now().millisecondsSinceEpoch;

      if (isCancelled()) {
        anyCancelled = true;
        sourceReports.add(
          SourceScanReport(
            rootPath: rootPath,
            status: SourceScanStatus.cancelled,
            sourceId: sourceId,
            label: sourceLabel,
            startedAtMs: startedAtMs,
            finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        break;
      }

      final rootDir = Directory(rootPath);
      if (!rootDir.existsSync()) {
        sourceReports.add(
          SourceScanReport(
            rootPath: rootPath,
            status: SourceScanStatus.unreachable,
            sourceId: sourceId,
            label: sourceLabel,
            startedAtMs: startedAtMs,
            finishedAtMs: DateTime.now().millisecondsSinceEpoch,
            errors: [
              ScanDirectoryError(
                path: rootPath,
                message: 'Quellordner nicht erreichbar',
              ),
            ],
          ),
        );
        continue;
      }

      onPhaseChanged?.call(ScanPhase.enumerating);
      final traversal = await _traverseRootSafely(
        rootDir,
        lister: lister,
        isCancelled: isCancelled,
        yieldPeriodically: yieldPeriodically,
      );
      if (traversal.cancelled) {
        anyCancelled = true;
        sourceReports.add(
          SourceScanReport(
            rootPath: rootPath,
            status: SourceScanStatus.cancelled,
            errors: traversal.errors,
            filesExamined: traversal.files.length,
            sourceId: sourceId,
            label: sourceLabel,
            startedAtMs: startedAtMs,
            finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        break;
      }
      if (!traversal.rootReadable) {
        sourceReports.add(
          SourceScanReport(
            rootPath: rootPath,
            status: SourceScanStatus.unreachable,
            errors: traversal.errors,
            sourceId: sourceId,
            label: sourceLabel,
            startedAtMs: startedAtMs,
            finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        continue;
      }

      onPhaseChanged?.call(ScanPhase.readingMetadata);
      final rootErrors = List<ScanDirectoryError>.of(traversal.errors);
      var mediaFoundInRoot = 0;
      var filesExamined = 0;

      for (final entity in traversal.files) {
        if (isCancelled()) {
          anyCancelled = true;
          break;
        }
        if (yieldPeriodically && filesExamined % _cooperativeYieldBatch == 0) {
          await Future<void>.delayed(Duration.zero);
          if (isCancelled()) {
            anyCancelled = true;
            break;
          }
        }

        final filePath = entity.path;
        if (!MediaParser.isVideoFile(filePath)) {
          continue;
        }
        filesExamined++;

        final FileStat stat;
        try {
          stat = statReader(entity);
        } on FileSystemException catch (error) {
          rootErrors.add(
            ScanDirectoryError(path: filePath, message: error.toString()),
          );
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
          if (isCancelled()) {
            anyCancelled = true;
            break;
          }
          episode = MediaParser.parseEpisodeWithTags(
            filePath,
            rootPath,
            tags,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            sourceId: sourceId,
          );
          tagSummary = tags?.summary;
        }

        mediaFoundInRoot++;
        if (episode != null) {
          final resolved = _resolveSeriesRoot(
            filePath,
            rootPath,
            episode.seriesTitle,
          );
          final key = resolved.groupKey;
          episodesBySeries.putIfAbsent(key, () => []).add(episode);
          sourceIdBySeries.putIfAbsent(key, () => sourceId);
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
                  sourceId: sourceId,
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
              sourceId: sourceId,
            ),
          );
        }
      }

      if (anyCancelled) {
        sourceReports.add(
          SourceScanReport(
            rootPath: rootPath,
            status: SourceScanStatus.cancelled,
            errors: rootErrors,
            filesExamined: filesExamined,
            mediaFound: mediaFoundInRoot,
            sourceId: sourceId,
            label: sourceLabel,
            startedAtMs: startedAtMs,
            finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        break;
      }

      final status = rootErrors.isEmpty
          ? SourceScanStatus.complete
          : SourceScanStatus.partial;
      reachableRoots.add(rootPath);
      if (status == SourceScanStatus.complete) {
        completeRoots.add(rootPath);
      }
      sourceReports.add(
        SourceScanReport(
          rootPath: rootPath,
          status: status,
          errors: rootErrors,
          filesExamined: filesExamined,
          mediaFound: mediaFoundInRoot,
          sourceId: sourceId,
          label: sourceLabel,
          startedAtMs: startedAtMs,
          finishedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    if (anyCancelled) {
      return ScanOutput(
        nasReachable: reachableRoots.isNotEmpty,
        reachableRoots: reachableRoots,
        completeRoots: completeRoots,
        seriesList: const [],
        movies: const [],
        sourceReports: sourceReports,
        sourceIdsByRoot: payload.sourceIdsByRoot,
        wasCancelled: true,
      );
    }

    if (reachableRoots.isEmpty) {
      return ScanOutput(
        nasReachable: false,
        reachableRoots: const [],
        completeRoots: const [],
        seriesList: const [],
        movies: const [],
        sourceReports: sourceReports,
        sourceIdsByRoot: payload.sourceIdsByRoot,
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
          sourceId: sourceIdBySeries[key],
        ),
      );
    }

    return ScanOutput(
      nasReachable: true,
      reachableRoots: reachableRoots,
      completeRoots: completeRoots,
      seriesList: seriesList,
      movies: movies,
      sourceReports: sourceReports,
      sourceIdsByRoot: payload.sourceIdsByRoot,
    );
  }

  static ScanOutput _cancelledOutput(List<String> rootPaths) {
    return ScanOutput(
      nasReachable: false,
      reachableRoots: const [],
      completeRoots: const [],
      seriesList: const [],
      movies: const [],
      sourceReports: [
        for (final root in rootPaths)
          SourceScanReport(
            rootPath: root,
            status: SourceScanStatus.cancelled,
          ),
      ],
      wasCancelled: true,
    );
  }

  static Future<
      ({
        List<File> files,
        List<ScanDirectoryError> errors,
        bool rootReadable,
        bool cancelled,
      })> _traverseRootSafely(
    Directory rootDir, {
    required DirectoryLister lister,
    required bool Function() isCancelled,
    required bool yieldPeriodically,
  }) async {
    final files = <File>[];
    final errors = <ScanDirectoryError>[];
    final pendingDirs = <Directory>[rootDir];
    var rootReadable = false;
    var visitedDirs = 0;

    while (pendingDirs.isNotEmpty) {
      if (isCancelled()) {
        return (
          files: files,
          errors: errors,
          rootReadable: rootReadable,
          cancelled: true,
        );
      }
      if (yieldPeriodically && visitedDirs > 0 && visitedDirs % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (isCancelled()) {
          return (
            files: files,
            errors: errors,
            rootReadable: rootReadable,
            cancelled: true,
          );
        }
      }

      final current = pendingDirs.removeLast();
      visitedDirs++;
      try {
        final children = lister(current);
        rootReadable = true;
        for (final entity in children) {
          if (entity is File) {
            files.add(entity);
          } else if (entity is Directory) {
            pendingDirs.add(entity);
          }
        }
      } on FileSystemException catch (error) {
        errors.add(
          ScanDirectoryError(path: current.path, message: error.toString()),
        );
        if (!rootReadable && current.path == rootDir.path) {
          return (
            files: files,
            errors: errors,
            rootReadable: false,
            cancelled: false,
          );
        }
      }
    }

    return (
      files: files,
      errors: errors,
      rootReadable: rootReadable,
      cancelled: false,
    );
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
