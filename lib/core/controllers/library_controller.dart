import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../features/library/library_models.dart';
import '../../features/library/media_repository.dart';
import '../../features/scanner/nas_scanner_service.dart';
import '../../features/scanner/thumbnail_queue_service.dart';
import '../constants/app_strings.dart';
import '../storage/database_service.dart';
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
    _scannerService.thumbnailQueue.addListener(_handleThumbnailQueueChanged);
  }

  final MediaRepository _repository;
  final SettingsController _settingsController;
  final NasScannerService _scannerService;

  bool _isDisposed = false;
  Future<void>? _activeRefreshFuture;
  ScanResult? _lastScanResult;
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
  ScanResult? get lastScanResult => _lastScanResult;
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
    await _settingsController.syncProgress();
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
    if (!_scannerService.isPlaybackActive) {
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

      if (result.cancelledForShutdown) {
        return;
      }
      if (result.skippedDueToPlayback) {
        _statusMessage = AppStrings.scanPausedStatus;
      } else if (!result.nasReachable) {
        _statusMessage = AppStrings.nasOfflineStatus;
      } else if (result.deletionBlockedByThreshold) {
        _statusMessage = AppStrings.scanDeletionGuardStatus;
      } else if (result.hasPartialSources) {
        _statusMessage = AppStrings.scanPartialStatus;
      } else {
        _statusMessage =
            '$_seriesCount ${AppStrings.seriesCountLabel} · $_movieCount ${AppStrings.moviesCountLabel}';
      }
      await _settingsController.refreshCacheSize();
    } finally {
      _safeNotify();
    }
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
    _statusMessage = '';
    _searchQuery = '';
    _activeFilter = LibraryFilter.all;
    notifyListeners();
  }
}
