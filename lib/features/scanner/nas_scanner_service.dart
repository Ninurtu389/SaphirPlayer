import 'dart:io';
import '../../core/constants/app_spacing.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/portable_paths.dart';
import '../../core/storage/thumbnail_cache_service.dart';
import 'media_tag_reader_service.dart';
import 'nas_scan_repository.dart';
import 'scan_coordinator.dart';
import 'scan_worker.dart';
import 'thumbnail_generator_service.dart';
import 'thumbnail_queue_service.dart';

export 'scan_models.dart';

class NasScannerService {
  NasScannerService(
    this._databaseService, {
    Future<EmbeddedMediaTags?> Function(String filePath)? tagReader,
    DirectoryLister? directoryLister,
    FileStatReader? fileStatReader,
    int deleteGuardMinEntries = AppSpacing.scanDeleteGuardMinEntries,
    double deleteGuardMaxRatio = AppSpacing.scanDeleteGuardMaxRatio,
    ScanCoordinator? coordinator,
    Map<String, String>? sourceIdsByRoot,
    ThumbnailOperationGate? thumbnailGate,
    ThumbnailQueueService? thumbnailQueue,
  })  : _repository = NasScanRepository(
          _databaseService,
          deleteGuardMinEntries: deleteGuardMinEntries,
          deleteGuardMaxRatio: deleteGuardMaxRatio,
        ),
        _tagReader = tagReader,
        _directoryLister = directoryLister,
        _fileStatReader = fileStatReader,
        _coordinator = coordinator ?? ScanCoordinator(),
        _explicitSourceIdsByRoot = sourceIdsByRoot,
        _thumbnailQueue = thumbnailQueue ??
            ThumbnailQueueService(
              _databaseService,
              gate: thumbnailGate,
            );

  final DatabaseService _databaseService;
  final NasScanRepository _repository;
  final Future<EmbeddedMediaTags?> Function(String filePath)? _tagReader;
  final DirectoryLister? _directoryLister;
  final FileStatReader? _fileStatReader;
  final ScanCoordinator _coordinator;
  final Map<String, String>? _explicitSourceIdsByRoot;
  final ThumbnailQueueService _thumbnailQueue;

  ThumbnailQueueService get thumbnailQueue => _thumbnailQueue;

  ScanLifecycleState get lifecycleState => _coordinator.state;
  bool get isScanActive => _coordinator.isActive;
  bool get isPlaybackActive => _coordinator.isPlaybackActive;
  bool get isMaintenanceLocked => _coordinator.isMaintenanceLocked;
  bool get hasPendingResume => _coordinator.hasPendingResume;
  Future<ScanResult>? get activeScanFuture => _coordinator.activeScanFuture;

  void addLifecycleListener(void Function(ScanLifecycleState) listener) {
    _coordinator.addStateListener(listener);
  }

  void removeLifecycleListener(void Function(ScanLifecycleState) listener) {
    _coordinator.removeStateListener(listener);
  }

  List<String>? consumePendingResumeRoots() =>
      _coordinator.consumePendingResumeRoots();

  void setPlaybackActive(bool active) {
    _coordinator.setPlaybackActive(active);
    _thumbnailQueue.setPlaybackActive(active);
  }

  Future<void> cancelForMaintenance() async {
    await _thumbnailQueue.cancelForMaintenance();
    await _coordinator.cancelForMaintenance(
      onKillActiveResources: ThumbnailGeneratorService.killActiveProcesses,
    );
  }

  void endMaintenance() {
    _thumbnailQueue.endMaintenance();
    _coordinator.endMaintenance();
  }

  Future<void> cancelForShutdown() async {
    await _thumbnailQueue.cancelForShutdown();
    await _coordinator.cancelForShutdown(
      onKillActiveResources: ThumbnailGeneratorService.killActiveProcesses,
    );
  }

  void dispose() {
    _thumbnailQueue.dispose();
  }

  Future<ScanResult> scanLibrary(List<String> rootPaths) {
    return _coordinator.runOrDeduplicate(
      rootPaths: rootPaths,
      executor: _executeScan,
      emptyResultBuilder: _buildEmptyResult,
    );
  }

  ScanResult _buildEmptyResult(
    ScanLifecycleState state, {
    required bool skippedDueToPlayback,
    required bool cancelledForShutdown,
  }) {
    final counts =
        _databaseService.isOpen ? _repository.currentCounts() : (0, 0);
    return ScanResult(
      nasReachable: skippedDueToPlayback,
      seriesCount: counts.$1,
      movieCount: counts.$2,
      skippedDueToPlayback: skippedDueToPlayback,
      lifecycleState: state,
      cancelledForShutdown: cancelledForShutdown,
    );
  }

  Future<ScanResult> _executeScan(
    List<String> rootPaths,
    ScanCancellationToken token,
  ) async {
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
        lifecycleState: ScanLifecycleState.completed,
      );
    }

    final sourceIdsByRoot = <String, String>{};
    for (final root in cleanedPaths) {
      final preferred = _explicitSourceIdsByRoot?[root];
      sourceIdsByRoot[root] = _databaseService.ensureMediaSource(
        root,
        preferredSourceId: preferred,
      );
    }

    final knownMetadata = _repository.loadKnownFileMetadata();
    final payload = ScanWorkerPayload(
      rootPaths: cleanedPaths,
      knownMetadata: knownMetadata,
      sourceIdsByRoot: sourceIdsByRoot,
    );

    final useInProcessWorker = _tagReader != null ||
        _directoryLister != null ||
        _fileStatReader != null;

    final output = useInProcessWorker
        ? await ScanWorker.runScan(
            payload,
            tagReader: _tagReader ?? MediaTagReaderService.readTags,
            cancellationToken: token,
            directoryLister: _directoryLister,
            fileStatReader: _fileStatReader,
          )
        : await ScanWorker.runInControllableIsolate(
            payload,
            cancellationToken: token,
          );

    if (token.isCancelled ||
        _coordinator.isShutdownCancelled ||
        _coordinator.isMaintenanceLocked ||
        output.wasCancelled ||
        !_databaseService.isOpen) {
      final counts =
          _databaseService.isOpen ? _repository.currentCounts() : (0, 0);
      final cancelledShutdown =
          token.isShutdownRequested || _coordinator.isShutdownCancelled;
      return ScanResult(
        nasReachable: output.nasReachable,
        seriesCount: counts.$1,
        movieCount: counts.$2,
        skippedDueToPlayback: !cancelledShutdown,
        lifecycleState: cancelledShutdown
            ? ScanLifecycleState.idle
            : ScanLifecycleState.paused,
        sourceReports: output.sourceReports,
        cancelledForShutdown: cancelledShutdown,
      );
    }

    if (!output.nasReachable) {
      final counts = _repository.currentCounts();
      return ScanResult(
        nasReachable: false,
        seriesCount: counts.$1,
        movieCount: counts.$2,
        skippedDueToPlayback: false,
        lifecycleState: ScanLifecycleState.completed,
        sourceReports: output.sourceReports,
      );
    }

    final diffSummary = _repository.applyDiffWithSummary(output);
    await _deleteOrphanedThumbnails(diffSummary.orphanedThumbnails);
    await _thumbnailQueue.processNextBatch(token: token);

    final counts =
        _databaseService.isOpen ? _repository.currentCounts() : (0, 0);
    final cancelledShutdown =
        token.isShutdownRequested || _coordinator.isShutdownCancelled;

    return ScanResult(
      nasReachable: true,
      seriesCount: counts.$1,
      movieCount: counts.$2,
      skippedDueToPlayback: token.isPauseRequested && !cancelledShutdown,
      lifecycleState: cancelledShutdown
          ? ScanLifecycleState.idle
          : (token.isPauseRequested
              ? ScanLifecycleState.paused
              : ScanLifecycleState.completed),
      sourceReports: output.sourceReports,
      cancelledForShutdown: cancelledShutdown,
      deletionBlockedByThreshold: diffSummary.deletionBlockedByThreshold,
      deletionBlockedRoots: diffSummary.deletionBlockedRoots,
      identityConflicts: diffSummary.identityConflicts,
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
}
