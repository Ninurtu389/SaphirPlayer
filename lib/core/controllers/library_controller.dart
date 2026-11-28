import 'package:flutter/foundation.dart';
import '../../features/library/library_models.dart';
import '../../features/library/media_repository.dart';
import '../../features/scanner/nas_scanner_service.dart';
import '../constants/app_strings.dart';
import '../storage/database_service.dart';
import 'settings_controller.dart';

class LibraryController extends ChangeNotifier {
  LibraryController(
    DatabaseService databaseService,
    this._settingsController, {
    MediaRepository? repository,
  })  : _repository = repository ?? MediaRepository(databaseService),
        _scannerService = NasScannerService(databaseService);

  final MediaRepository _repository;
  final SettingsController _settingsController;
  final NasScannerService _scannerService;

  bool _isDisposed = false;
  bool _isScanning = false;
  int _seriesCount = 0;
  int _movieCount = 0;
  String _statusMessage = '';
  LibraryFilter _activeFilter = LibraryFilter.all;
  String _searchQuery = '';
  List<MediaCardItem> _seriesItems = const [];
  List<MediaCardItem> _movieItems = const [];

  bool get isScanning => _isScanning;
  int get seriesCount => _seriesCount;
  int get movieCount => _movieCount;
  String get statusMessage => _statusMessage;
  LibraryFilter get activeFilter => _activeFilter;
  String get searchQuery => _searchQuery;

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
    notifyListeners();
  }

  void _loadLibraryItemsInternal() {
    _seriesItems = _repository.loadAllSeries(useWatchedFraction: true);
    _movieItems = _repository.loadAllMovies();
  }

  void setPlaybackActive(bool active) {
    _scannerService.setPlaybackActive(active);
    if (active && _isScanning) {
      _isScanning = false;
      _statusMessage = AppStrings.scanPausedStatus;
      notifyListeners();
    }
  }

  Future<void> syncAndRefreshLibrary() async {
    await _settingsController.syncProgress();
    await refreshLibrary();
  }

  Future<void> refreshLibrary() async {
    if (_isScanning || _isDisposed) {
      return;
    }
    _isScanning = true;
    _statusMessage = AppStrings.scanningStatus;
    _safeNotify();

    try {
      final result =
          await _scannerService.scanLibrary(_settingsController.nasPaths);
      if (_isDisposed) {
        return;
      }
      _seriesCount = result.seriesCount;
      _movieCount = result.movieCount;
      _loadLibraryItemsInternal();

      if (result.skippedDueToPlayback) {
        _statusMessage = AppStrings.scanPausedStatus;
      } else if (!result.nasReachable) {
        _statusMessage = AppStrings.nasOfflineStatus;
      } else {
        _statusMessage =
            '$_seriesCount ${AppStrings.seriesCountLabel} · $_movieCount ${AppStrings.moviesCountLabel}';
      }
      await _settingsController.refreshCacheSize();
    } finally {
      _isScanning = false;
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
    super.dispose();
  }

  void resetLibraryState() {
    _seriesCount = 0;
    _movieCount = 0;
    _seriesItems = const [];
    _movieItems = const [];
    _statusMessage = '';
    _searchQuery = '';
    _activeFilter = LibraryFilter.all;
    notifyListeners();
  }
}
