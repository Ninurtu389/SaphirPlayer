import 'dart:async';
import '../../core/constants/app_spacing.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/thumbnail_cache_service.dart';
import 'scan_models.dart';
import 'thumbnail_generator_service.dart';
import 'thumbnail_queue_repository.dart';

export 'thumbnail_queue_repository.dart';

typedef ThumbnailOutcomeGenerator = Future<ThumbnailGenerationOutcome>
    Function({
  required String videoFilePath,
  required int durationMs,
  required String prefix,
  required int fileSize,
  required int modifiedAt,
  required bool Function() isAborted,
  ThumbnailMediaKitSession? mediaKitSession,
  bool allowMediaKitFallback,
});

/// Serielle, persistente Thumbnail-Queue mit Retry-Backoff und Batch-Fortsetzung.
class ThumbnailQueueService {
  ThumbnailQueueService(
    this._databaseService, {
    ThumbnailOperationGate? gate,
    ThumbnailOutcomeGenerator? generator,
    Future<ThumbnailMediaKitSession?> Function()? sessionFactory,
    DateTime Function()? nowProvider,
    int batchLimit = AppSpacing.maxThumbnailsPerScan,
    int maxRetryAttempts = AppSpacing.thumbnailMaxRetryAttempts,
    int retryBaseSeconds = AppSpacing.thumbnailRetryBaseSeconds,
    Duration batchContinuationDelay = const Duration(
      milliseconds: AppSpacing.thumbnailQueueBatchDelayMs,
    ),
  })  : _repository = ThumbnailQueueRepository(_databaseService),
        _gate = gate ?? ThumbnailOperationGate(),
        _generator = generator ?? _defaultGenerator,
        _sessionFactory = sessionFactory ?? ThumbnailMediaKitSession.create,
        _now = nowProvider ?? DateTime.now,
        _batchLimit = batchLimit,
        _maxRetryAttempts = maxRetryAttempts,
        _retryBaseSeconds = retryBaseSeconds,
        _batchContinuationDelay = batchContinuationDelay;

  final DatabaseService _databaseService;
  final ThumbnailQueueRepository _repository;
  final ThumbnailOperationGate _gate;
  final ThumbnailOutcomeGenerator _generator;
  final Future<ThumbnailMediaKitSession?> Function() _sessionFactory;
  final DateTime Function() _now;
  final int _batchLimit;
  final int _maxRetryAttempts;
  final int _retryBaseSeconds;
  final Duration _batchContinuationDelay;
  final List<void Function()> _listeners = <void Function()>[];

  Future<int>? _activeBatch;
  Timer? _continueTimer;
  bool _isDisposed = false;
  bool _isShutdownCancelled = false;
  bool _isMaintenanceLocked = false;
  bool _isPlaybackActive = false;
  bool _resumeAfterPlayback = false;
  bool _autoContinueAfterResume = true;

  bool get isRunning => _activeBatch != null;
  bool get isPlaybackActive => _isPlaybackActive;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notifyListeners() {
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  /// Setzt hängende `processing`-Einträge (z. B. nach App-Absturz) zurück.
  int recoverStaleProcessingJobs() {
    final recovered = _repository.recoverStaleProcessingJobs();
    if (recovered > 0) _notifyListeners();
    return recovered;
  }

  ThumbnailQueueStats readStats() => _repository.readStats();

  void setPlaybackActive(bool active) {
    _isPlaybackActive = active;
    if (active) {
      if (_continueTimer != null) {
        _continueTimer?.cancel();
        _continueTimer = null;
        _resumeAfterPlayback = true;
      }
      ThumbnailGeneratorService.killActiveProcesses();
      return;
    }
    if (_resumeAfterPlayback &&
        !_isDisposed &&
        !_isShutdownCancelled &&
        !_isMaintenanceLocked &&
        _autoContinueAfterResume) {
      _resumeAfterPlayback = false;
      _scheduleContinuation(autoContinueBatches: true);
    }
  }

  Future<void> cancelForMaintenance() async {
    _continueTimer?.cancel();
    _continueTimer = null;
    _resumeAfterPlayback = false;
    _isMaintenanceLocked = true;
    ThumbnailGeneratorService.killActiveProcesses();
    final active = _activeBatch;
    if (active != null) {
      try {
        await active;
      } catch (_) {}
    }
  }

  void endMaintenance() {
    _isMaintenanceLocked = false;
  }

  Future<void> cancelForShutdown() async {
    _isShutdownCancelled = true;
    _continueTimer?.cancel();
    _continueTimer = null;
    _resumeAfterPlayback = false;
    await ThumbnailGeneratorService.terminateActiveProcesses();
    final active = _activeBatch;
    if (active != null) {
      try {
        await active;
      } catch (_) {}
    }
  }

  void dispose() {
    _isDisposed = true;
    _isShutdownCancelled = true;
    _continueTimer?.cancel();
    _continueTimer = null;
    _resumeAfterPlayback = false;
    _listeners.clear();
  }

  /// Verarbeitet bis zu `_batchLimit` fällige Jobs seriell (Concurrency = 1).
  Future<int> processNextBatch({
    bool autoContinueBatches = true,
    ScanCancellationToken? token,
  }) {
    if (_activeBatch != null) return _activeBatch!;
    _continueTimer?.cancel();
    _continueTimer = null;
    _autoContinueAfterResume = autoContinueBatches;

    final future = _runGuardedBatch(
      autoContinueBatches: autoContinueBatches,
      token: token,
    );
    _activeBatch = future;
    future.whenComplete(() {
      if (identical(_activeBatch, future)) _activeBatch = null;
    });
    return future;
  }

  Future<int> _runGuardedBatch({
    required bool autoContinueBatches,
    ScanCancellationToken? token,
  }) async {
    final nowMs = _now().millisecondsSinceEpoch;
    if (_isBlocked(token) || !_databaseService.isOpen) {
      if (_isPlaybackActive &&
          autoContinueBatches &&
          _repository.hasDueJobs(nowMs)) {
        _resumeAfterPlayback = true;
      }
      return 0;
    }

    var processedCount = 0;
    await _gate.trackGenerationTask(() async {
      processedCount = await _executeBatch(token);
    });

    _notifyListeners();
    final afterMs = _now().millisecondsSinceEpoch;
    if (autoContinueBatches &&
        !_isBlocked(token) &&
        processedCount > 0 &&
        _repository.hasDueJobs(afterMs)) {
      _scheduleContinuation(autoContinueBatches: true);
    } else if (_isPlaybackActive &&
        autoContinueBatches &&
        _repository.hasDueJobs(afterMs)) {
      _resumeAfterPlayback = true;
    }
    return processedCount;
  }

  Future<int> _executeBatch(ScanCancellationToken? token) async {
    if (_isBlocked(token) || !_databaseService.isOpen) return 0;

    final jobs = _repository.loadDueJobs(
      _now().millisecondsSinceEpoch,
      _batchLimit,
    );
    if (jobs.isEmpty) return 0;

    ThumbnailMediaKitSession? mediaKitSession;
    var mediaKitAttempted = false;
    var processed = 0;

    void onTokenCancel() {
      if (token?.isShutdownRequested ?? false) {
        ThumbnailGeneratorService.killActiveProcesses();
      }
    }

    token?.addListener(onTokenCancel);

    Future<ThumbnailGenerationOutcome> runWithFallback(
      QueuedThumbnailJob job,
    ) async {
      final first = await _generator(
        videoFilePath: job.filePath,
        durationMs: job.durationMs,
        prefix: job.prefix,
        fileSize: job.fileSize,
        modifiedAt: job.modifiedAt,
        isAborted: () => _isBlocked(token),
        mediaKitSession: mediaKitSession,
        allowMediaKitFallback: mediaKitSession != null,
      );
      if (first.isSuccess ||
          first.failureKind == ThumbnailFailureKind.cancelled ||
          first.failureKind == ThumbnailFailureKind.permanent ||
          _isBlocked(token) ||
          mediaKitAttempted) {
        return first;
      }
      mediaKitAttempted = true;
      mediaKitSession = await _sessionFactory();
      if (mediaKitSession == null || _isBlocked(token)) return first;
      return _generator(
        videoFilePath: job.filePath,
        durationMs: job.durationMs,
        prefix: job.prefix,
        fileSize: job.fileSize,
        modifiedAt: job.modifiedAt,
        isAborted: () => _isBlocked(token),
        mediaKitSession: mediaKitSession,
        allowMediaKitFallback: true,
      );
    }

    try {
      for (final job in jobs) {
        if (_isBlocked(token) || !_databaseService.isOpen) break;
        _repository.markProcessing(job);
        final outcome = await runWithFallback(job);
        if (!_databaseService.isOpen) break;

        if (_isBlocked(token) ||
            outcome.failureKind == ThumbnailFailureKind.cancelled) {
          _repository.restoreInterruptedJob(job);
          break;
        }

        processed++;
        if (outcome.isSuccess) {
          await _repository.markReady(job, outcome);
        } else {
          _recordFailure(job, outcome);
        }
      }
    } finally {
      token?.removeListener(onTokenCancel);
      await mediaKitSession?.dispose();
    }
    return processed;
  }

  void _recordFailure(
    QueuedThumbnailJob job,
    ThumbnailGenerationOutcome outcome,
  ) {
    final nextAttempts = job.priorAttempts + 1;
    final sanitizedError = ThumbnailCacheKey.sanitizeErrorMessage(
      outcome.errorMessage ?? 'thumbnail generation failed',
    );
    final isPermanent = outcome.failureKind == ThumbnailFailureKind.permanent ||
        nextAttempts >= _maxRetryAttempts;
    if (isPermanent) {
      _repository.markFailedPermanent(job, nextAttempts, sanitizedError);
      return;
    }
    final backoffSec = _retryBaseSeconds * (1 << (nextAttempts - 1));
    final retryAtMs = _now().millisecondsSinceEpoch + backoffSec * 1000;
    _repository.markRetryWait(job, nextAttempts, sanitizedError, retryAtMs);
  }

  void _scheduleContinuation({required bool autoContinueBatches}) {
    _continueTimer?.cancel();
    if (_isDisposed || _isShutdownCancelled || _isMaintenanceLocked) return;
    _continueTimer = Timer(_batchContinuationDelay, () {
      _continueTimer = null;
      if (!_isDisposed && !_isShutdownCancelled && !_isMaintenanceLocked) {
        unawaited(processNextBatch(autoContinueBatches: autoContinueBatches));
      }
    });
  }

  bool _isBlocked(ScanCancellationToken? token) =>
      _isDisposed ||
      _isShutdownCancelled ||
      _isMaintenanceLocked ||
      _isPlaybackActive ||
      _gate.isGenerationBlocked ||
      (token?.isCancelled ?? false);

  /// Setzt ein einzelnes Medium manuell in der Warteschlange zurück.
  Future<int> retryMediaThumbnail({
    required bool isEpisode,
    required int mediaId,
  }) async {
    final changed = _repository.resetMediaThumbnail(
      isEpisode: isEpisode,
      mediaId: mediaId,
    );
    _notifyListeners();
    return changed;
  }

  /// Setzt fehlgeschlagene/wartende Medien eines bestimmten Quellpfads zurück.
  Future<int> retrySourceThumbnails(String sourceRoot) async {
    final updated = _repository.resetSourceThumbnails(sourceRoot);
    _notifyListeners();
    return updated;
  }

  /// Setzt alle fehlgeschlagenen oder wartenden Thumbnails sofort auf `pending`.
  Future<int> retryAllFailedThumbnails() async {
    final updated = _repository.resetAllFailedThumbnails();
    _notifyListeners();
    return updated;
  }

  static Future<ThumbnailGenerationOutcome> _defaultGenerator({
    required String videoFilePath,
    required int durationMs,
    required String prefix,
    required int fileSize,
    required int modifiedAt,
    required bool Function() isAborted,
    ThumbnailMediaKitSession? mediaKitSession,
    bool allowMediaKitFallback = true,
  }) {
    return ThumbnailGeneratorService.generateThumbnailWithOutcome(
      videoFilePath: videoFilePath,
      durationMs: durationMs,
      isPlaybackActive: isAborted,
      prefix: prefix,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      mediaKitSession: mediaKitSession,
      allowMediaKitFallback: allowMediaKitFallback,
    );
  }
}
