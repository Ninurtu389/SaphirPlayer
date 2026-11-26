import 'package:flutter/foundation.dart';
import '../../features/library/library_models.dart';
import '../../features/scanner/nas_scanner_service.dart';
import '../constants/app_spacing.dart';
import '../constants/app_strings.dart';
import '../storage/database_service.dart';
import 'settings_controller.dart';

class LibraryController extends ChangeNotifier {
  LibraryController(this._databaseService, this._settingsController)
      : _scannerService = NasScannerService(_databaseService);

  final DatabaseService _databaseService;
  final SettingsController _settingsController;
  final NasScannerService _scannerService;

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
              item.subtitle.toLowerCase().contains(_searchQuery),
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
    final db = _databaseService.instance;
    final seriesRow = db.select('SELECT COUNT(*) AS cnt FROM series;').first;
    final moviesRow = db.select('SELECT COUNT(*) AS cnt FROM movies;').first;
    _seriesCount = seriesRow['cnt'] as int;
    _movieCount = moviesRow['cnt'] as int;
    _loadLibraryItemsInternal();
    notifyListeners();
  }

  void _loadLibraryItemsInternal() {
    final db = _databaseService.instance;
    final seriesRows = db.select(
      '''
      SELECT
        s.id,
        s.title,
        s.poster_path,
        (SELECT COUNT(*) FROM episodes e WHERE e.series_id = s.id) AS ep_count,
        (SELECT COUNT(*) FROM episodes e
         INNER JOIN watch_progress wp ON wp.media_key = 'episode_' || e.id
         WHERE e.series_id = s.id AND wp.completed = 1) AS watched_count,
        (SELECT e.file_path FROM episodes e WHERE e.series_id = s.id ORDER BY e.id ASC LIMIT 1) AS first_file,
        (SELECT e.thumb_path FROM episodes e WHERE e.series_id = s.id AND e.thumb_path IS NOT NULL ORDER BY e.id ASC LIMIT 1) AS fallback_thumb
      FROM series s
      ORDER BY s.title COLLATE NOCASE ASC;
      ''',
    );

    _seriesItems = seriesRows
        .where((r) => r['first_file'] != null)
        .map(
          (r) {
            final epCount = (r['ep_count'] as int?) ?? 0;
            final watchedCount = (r['watched_count'] as int?) ?? 0;
            final ratio =
                epCount > 0 ? (watchedCount / epCount).clamp(0.0, 1.0) : 0.0;
            return MediaCardItem(
              mediaKey: 'series_${r['id']}',
              mediaType: 'series',
              title: r['title'] as String,
              subtitle:
                  '${AppStrings.seriesTypeBadge} · $watchedCount/$epCount',
              imagePath: (r['poster_path'] as String?) ??
                  (r['fallback_thumb'] as String?),
              progressRatio: ratio,
              remainingMinutes: 0,
              isCompleted: epCount > 0 && watchedCount >= epCount,
              seriesId: r['id'] as int,
              filePath: r['first_file'] as String,
            );
          },
        )
        .toList();

    final movieRows = db.select(
      '''
      SELECT
        m.id,
        m.title,
        m.release_year,
        m.file_path,
        m.poster_path,
        m.thumb_path,
        COALESCE(wp.position_ms, 0) AS position_ms,
        COALESCE(wp.duration_ms, m.duration_ms) AS duration_ms,
        COALESCE(wp.completed, 0) AS completed
      FROM movies m
      LEFT JOIN watch_progress wp ON wp.media_key = 'movie_' || m.id
      ORDER BY m.title COLLATE NOCASE ASC;
      ''',
    );

    _movieItems = movieRows.map((r) {
      final posMs = r['position_ms'] as int;
      final durMs = r['duration_ms'] as int;
      final completed = (r['completed'] as int) == 1;
      final ratio =
          durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
      final remMs = (!completed && durMs > posMs) ? durMs - posMs : 0;
      final remMin = (remMs / AppSpacing.millisecondsPerMinute).ceil();
      final year = r['release_year'] as int?;
      final subtitle = year != null
          ? '${AppStrings.movieTypeBadge} · $year'
          : AppStrings.movieTypeBadge;

      return MediaCardItem(
        mediaKey: 'movie_${r['id']}',
        mediaType: 'movie',
        title: r['title'] as String,
        subtitle: subtitle,
        imagePath:
            (r['thumb_path'] as String?) ?? (r['poster_path'] as String?),
        progressRatio: ratio,
        remainingMinutes: remMin,
        isCompleted: completed,
        seriesId: null,
        filePath: r['file_path'] as String,
      );
    }).toList();
  }

  void setPlaybackActive(bool active) {
    _scannerService.setPlaybackActive(active);
    if (active && _isScanning) {
      _isScanning = false;
      _statusMessage = AppStrings.scanPausedStatus;
      notifyListeners();
    }
  }

  Future<void> refreshLibrary() async {
    if (_isScanning) {
      return;
    }
    _isScanning = true;
    _statusMessage = AppStrings.scanningStatus;
    notifyListeners();

    try {
      final result =
          await _scannerService.scanLibrary(_settingsController.nasPaths);
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
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }
}
