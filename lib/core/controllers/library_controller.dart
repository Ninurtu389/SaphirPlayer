import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../features/library/library_models.dart';
import '../../features/library/media_repository.dart';
import '../../features/scanner/nas_scanner_service.dart';
import '../../features/scanner/thumbnail_queue_service.dart';
import '../constants/app_strings.dart';
import '../models/status_feedback_models.dart';
import '../storage/database_service.dart';
import '../storage/sync_models.dart';
import 'settings_controller.dart';

class LibraryController extends ChangeNotifier {
  LibraryController(
    DatabaseService databaseService,
    this._settingsController, {
    MediaRepository? repository,
    NasScannerService? scannerService,
  })  : _repository = repository ?? MediaRepository(databaseService),
        _scannerService = scannerService ?? NasScannerService(databaseService) {
    _scannerService.addLifecycleListener(_handleScannerLifecycleChanged);
    _scannerService.addPhaseListener(_handleScannerPhaseChanged);
    _scannerService.thumbnailQueue.addListener(_handleThumbnailQueueChanged);
  }

  final MediaRepository _repository;
  final SettingsController _settingsController;
  final NasScannerService _scannerService;

  static const int _maxDiagnosticEntries = 50;

  bool _isDisposed = false;
  Future<void>? _activeRefreshFuture;
  ScanResult? _lastScanResult;
  ScanPhase _scanPhase = ScanPhase.idle;
  LibraryScanFeedback? _scanFeedback;
  String? _lastSyncStatusMessage;
  bool _hasSyncIssue = false;
  final List<String> _diagnosticLog = <String>[];
  int _seriesCount = 0;
  int _movieCount = 0;
  String _statusMessage = '';
  LibraryFilter _activeFilter = LibraryFilter.all;
  String _searchQuery = '';
  List<MediaCardItem> _seriesItems = const [];
  List<MediaCardItem> _movieItems = const [];
  ThumbnailQueueStats _thumbnailQueueStats = const ThumbnailQueueStats();

  bool get isScanning => _scannerService.isScanActive;
  ScanLifecycleState get scanState => _scannerService.lifecycleState;
  ScanPhase get scanPhase => _scanPhase;
  ScanResult? get lastScanResult => _lastScanResult;
  LibraryScanFeedback? get scanFeedback => _scanFeedback;
  bool get hasScanError => _scanFeedback?.severity == StatusSeverity.error;
  bool get hasScanWarning => _scanFeedback?.severity == StatusSeverity.warning;
  bool get isNasOffline =>
      _lastScanResult != null &&
      !_lastScanResult!.nasReachable &&
      !isScanning &&
      !hasScanError;
  String? get lastSyncStatusMessage => _lastSyncStatusMessage;
  bool get hasSyncIssue => _hasSyncIssue;
  List<String> get diagnosticLog => List.unmodifiable(_diagnosticLog);
  int get seriesCount => _seriesCount;
  int get movieCount => _movieCount;
  String get statusMessage => _statusMessage;
  LibraryFilter get activeFilter => _activeFilter;
  String get searchQuery => _searchQuery;
  ThumbnailQueueStats get thumbnailQueueStats => _thumbnailQueueStats;
  bool get hasRetryableThumbnails =>
      _thumbnailQueueStats.failedPermanentCount > 0 ||
      _thumbnailQueueStats.retryWaitCount > 0;
  String get formattedThumbnailQueueStatus =>
      _thumbnailQueueStats.formattedSummary();

  List<MediaCardItem> get filteredItems {
    final base = switch (_activeFilter) {
      LibraryFilter.all => <MediaCardItem>[..._seriesItems, ..._movieItems],
      LibraryFilter.series => _seriesItems,
      LibraryFilter.movies => _movieItems,
    };

    if (_searchQuery.isEmpty) {
      return base;
    }

    return base
        .where(
          (item) =>
              item.title.toLowerCase().contains(_searchQuery) ||
              item.subtitle.toLowerCase().contains(_searchQuery) ||
              (item.artist ?? '').toLowerCase().contains(_searchQuery),
        )
        .toList();
  }

  void _handleScannerLifecycleChanged(ScanLifecycleState state) {
    if (_isDisposed) return;
    if (state == ScanLifecycleState.pausing ||
        state == ScanLifecycleState.paused) {
      _statusMessage = AppStrings.scanPausedStatus;
    }
    _safeNotify();
  }

  void _handleScannerPhaseChanged(ScanPhase phase) {
    if (_isDisposed) return;
    _scanPhase = phase;
    _safeNotify();
  }

  void _handleThumbnailQueueChanged() {
    refreshThumbnailQueueStats();
  }

  void refreshThumbnailQueueStats() {
    if (_isDisposed) return;
    _thumbnailQueueStats = _scannerService.thumbnailQueue.readStats();
    _safeNotify();
  }

  Future<int> retryFailedThumbnails({bool resumeQueue = true}) async {
    final resetCount =
        await _scannerService.thumbnailQueue.retryAllFailedThumbnails();
    refreshThumbnailQueueStats();
    if (resetCount > 0 && resumeQueue && !_isDisposed) {
      unawaited(_scannerService.thumbnailQueue.processNextBatch());
    }
    return resetCount;
  }

  void setFilter(LibraryFilter filter) {
    if (_activeFilter == filter) {
      return;
    }
    _activeFilter = filter;
    notifyListeners();
  }

  void updateSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  void loadCountsFromCache() {
    final counts = _repository.loadCounts();
    _seriesCount = counts.seriesCount;
    _movieCount = counts.movieCount;
    _loadLibraryItemsInternal();
    _thumbnailQueueStats = _scannerService.thumbnailQueue.readStats();
    notifyListeners();
  }

  void _loadLibraryItemsInternal() {
    _seriesItems = _repository.loadAllSeries(useWatchedFraction: true);
    _movieItems = _repository.loadAllMovies();
  }

  void setPlaybackActive(bool active, {bool resumePausedScan = true}) {
    _scannerService.setPlaybackActive(active);
    if (active) {
      if (_scannerService.isScanActive) {
        _statusMessage = AppStrings.scanPausedStatus;
      }
      _safeNotify();
      return;
    }

    if (resumePausedScan &&
        _scannerService.hasPendingResume &&
        !_isDisposed &&
        _activeRefreshFuture == null) {
      final pendingRoots = _scannerService.consumePendingResumeRoots();
      if (pendingRoots != null) {
        unawaited(_startRefresh(pendingRoots));
      }
    }
  }

  Future<void> waitForActiveScan() async {
    final pending = _activeRefreshFuture ?? _scannerService.activeScanFuture;
    if (pending != null) {
      await pending;
    }
  }

  Future<void> syncAndRefreshLibrary() async {
    _hasSyncIssue = false;
    _lastSyncStatusMessage = null;
    try {
      final syncResult = await _settingsController.syncProgress();
      final feedback = _settingsController.lastSyncFeedback;
      if (!syncResult.syncedToNas &&
          (_settingsController.nasPaths.isNotEmpty ||
              syncResult.status != SyncStatus.localOnly)) {
        _hasSyncIssue = true;
        _lastSyncStatusMessage =
            feedback?.headline ?? AppStrings.syncFailedStatus;
      }
    } catch (error) {
      _hasSyncIssue = true;
      _lastSyncStatusMessage = AppStrings.syncFailedStatus;
      _appendDiagnostic('Sync-Fehler vor Scan: $error');
    }
    await refreshLibrary();
  }

  Future<void> refreshLibrary() {
    if (_isDisposed || _scannerService.isMaintenanceLocked) {
      return Future<void>.value();
    }
    final existing = _activeRefreshFuture;
    if (existing != null) {
      return existing;
    }
    return _startRefresh(_settingsController.nasPaths);
  }

  Future<void> refreshSingleSource(String rootPath) {
    final trimmed = rootPath.trim();
    if (trimmed.isEmpty || _isDisposed || _scannerService.isMaintenanceLocked) {
      return Future<void>.value();
    }
    final existing = _activeRefreshFuture;
    if (existing != null) {
      return existing;
    }
    return _startRefresh([trimmed]);
  }

  Future<void> beginMaintenance() async {
    await _scannerService.cancelForMaintenance();
    await waitForActiveScan();
  }

  void endMaintenance() {
    _scannerService.endMaintenance();
  }

  Future<void> _startRefresh(List<String> rootPaths) {
    late final Future<void> wrapped;
    wrapped = _runRefresh(rootPaths).whenComplete(() {
      if (identical(_activeRefreshFuture, wrapped)) {
        _activeRefreshFuture = null;
      }
    });
    _activeRefreshFuture = wrapped;
    return wrapped;
  }

  Future<void> _runRefresh(List<String> rootPaths) async {
    if (_isDisposed) {
      return;
    }
    _scanFeedback = null;
    if (!_scannerService.isPlaybackActive) {
      _scanPhase = ScanPhase.enumerating;
      _statusMessage = AppStrings.scanningStatus;
      _safeNotify();
    }

    try {
      final result = await _scannerService.scanLibrary(rootPaths);
      if (_isDisposed) {
        return;
      }
      _lastScanResult = result;
      _seriesCount = result.seriesCount;
      _movieCount = result.movieCount;
      _loadLibraryItemsInternal();
      _thumbnailQueueStats = _scannerService.thumbnailQueue.readStats();

      if (result.cancelledForShutdown) {
        _scanPhase = ScanPhase.idle;
        return;
      }
      _applyScanResultStatus(result);
      _settingsController.refreshMediaSources();
      await _settingsController.refreshCacheSize();
    } catch (error, stackTrace) {
      final sanitized = _sanitizeError(error);
      _appendDiagnostic('Scan-Fehler: $error');
      debugPrint('Scan-Fehler: $error\n$stackTrace');
      if (_isDisposed) {
        return;
      }
      _scanPhase = ScanPhase.failed;
      _statusMessage = AppStrings.scanFailedStatus;
      _scanFeedback = LibraryScanFeedback(
        severity: StatusSeverity.error,
        message: AppStrings.scanFailedStatus,
        detail: sanitized,
        canRetry: true,
      );
      _lastScanResult = ScanResult(
        nasReachable: false,
        seriesCount: _seriesCount,
        movieCount: _movieCount,
        skippedDueToPlayback: false,
        lifecycleState: ScanLifecycleState.failed,
        errorMessage: sanitized,
      );
    } finally {
      _safeNotify();
    }
  }

  void _applyScanResultStatus(ScanResult result) {
    if (result.skippedDueToPlayback) {
      _scanPhase = ScanPhase.paused;
      _statusMessage = AppStrings.scanPausedStatus;
      _scanFeedback = null;
      return;
    }
    if (result.lifecycleState == ScanLifecycleState.failed ||
        result.errorMessage != null) {
      _scanPhase = ScanPhase.failed;
      _statusMessage = AppStrings.scanFailedStatus;
      _scanFeedback = LibraryScanFeedback(
        severity: StatusSeverity.error,
        message: AppStrings.scanFailedStatus,
        detail: result.errorMessage,
        canRetry: true,
      );
      return;
    }

    _scanPhase = ScanPhase.completed;
    final affected = [
      for (final report in result.sourceReports)
        if (report.status != SourceScanStatus.complete) report.rootPath,
    ];

    if (!result.nasReachable) {
      _statusMessage = AppStrings.nasOfflineStatus;
      _scanFeedback = LibraryScanFeedback(
        severity: StatusSeverity.warning,
        message: AppStrings.nasOfflineStatus,
        canRetry: true,
        affectedSources: affected,
      );
      return;
    }
    if (result.deletionBlockedByThreshold) {
      _statusMessage = AppStrings.scanDeletionGuardStatus;
      _scanFeedback = LibraryScanFeedback(
        severity: StatusSeverity.warning,
        message: AppStrings.scanDeletionGuardStatus,
        canRetry: true,
        isPartial: true,
        affectedSources: result.deletionBlockedRoots,
      );
      return;
    }
    if (result.hasPartialSources) {
      _statusMessage = AppStrings.scanPartialStatus;
      _scanFeedback = LibraryScanFeedback(
        severity: StatusSeverity.warning,
        message: AppStrings.scanPartialStatus,
        canRetry: true,
        isPartial: true,
        affectedSources: affected,
      );
      return;
    }
    if (result.hasUnreachableSources) {
      _statusMessage = AppStrings.scanUnreachableSourcesStatus;
      _scanFeedback = LibraryScanFeedback(
        severity: StatusSeverity.warning,
        message: AppStrings.scanUnreachableSourcesStatus,
        canRetry: true,
        isPartial: true,
        affectedSources: affected,
      );
      return;
    }
    if (result.hasIdentityConflicts) {
      _statusMessage = AppStrings.scanIdentityConflictStatus;
      _scanFeedback = const LibraryScanFeedback(
        severity: StatusSeverity.warning,
        message: AppStrings.scanIdentityConflictStatus,
        canRetry: false,
      );
      return;
    }

    _statusMessage =
        '$_seriesCount ${AppStrings.seriesCountLabel} · $_movieCount ${AppStrings.moviesCountLabel}';
    _scanFeedback = LibraryScanFeedback(
      severity: StatusSeverity.success,
      message: _statusMessage,
    );
  }

  void _appendDiagnostic(String message) {
    final stamp = DateTime.now().toIso8601String();
    _diagnosticLog.add('[$stamp] $message');
    if (_diagnosticLog.length > _maxDiagnosticEntries) {
      _diagnosticLog.removeAt(0);
    }
  }

  static String _sanitizeError(Object error) {
    final raw = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.length <= 180) return raw;
    return '${raw.substring(0, 177)}...';
  }

  Future<void> cancelScanForShutdown() => _scannerService.cancelForShutdown();

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _scannerService.removeLifecycleListener(_handleScannerLifecycleChanged);
    _scannerService.removePhaseListener(_handleScannerPhaseChanged);
    _scannerService.thumbnailQueue.removeListener(_handleThumbnailQueueChanged);
    _scannerService.dispose();
    super.dispose();
  }

  void resetLibraryState() {
    _seriesCount = 0;
    _movieCount = 0;
    _seriesItems = const [];
    _movieItems = const [];
    _lastScanResult = null;
    _scanPhase = ScanPhase.idle;
    _scanFeedback = null;
    _lastSyncStatusMessage = null;
    _hasSyncIssue = false;
    _statusMessage = '';
    _searchQuery = '';
    _activeFilter = LibraryFilter.all;
    notifyListeners();
  }
}
