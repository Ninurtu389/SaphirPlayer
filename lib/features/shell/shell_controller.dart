import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/library_controller.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/services/desktop_platform_service.dart';
import '../../core/storage/database_service.dart';
import '../home/home_controller.dart';
import '../library/library_models.dart';
import '../player/playback_session.dart';
import '../player/saphir_player_controller.dart';
import '../stats/stats_controller.dart';

enum AppSection {
  home,
  library,
  stats,
  settings,
}

class ShellController extends ChangeNotifier {
  ShellController({
    SettingsController? settingsController,
    LibraryController? libraryController,
    HomeController? homeController,
    StatsController? statsController,
    SaphirPlayerController? playerController,
    DatabaseService? databaseService,
  })  : _settingsController = settingsController,
        _libraryController = libraryController,
        _homeController = homeController,
        _statsController = statsController,
        _playerController = playerController,
        _databaseService = databaseService;

  SettingsController? _settingsController;
  LibraryController? _libraryController;
  HomeController? _homeController;
  StatsController? _statsController;
  SaphirPlayerController? _playerController;
  DatabaseService? _databaseService;

  AppSection _activeSection = AppSection.home;
  bool _isMaximized = false;
  SeriesDetailData? _selectedSeriesDetail;
  PlaybackSession? _activePlaybackSession;
  String? _statusMessage;
  Timer? _searchDebounceTimer;
  Timer? _statusClearTimer;
  Object? _windowListenerToken;
  bool _isClosing = false;
  bool _isDisposed = false;

  AppSection get activeSection => _activeSection;
  bool get isMaximized => _isMaximized;
  SeriesDetailData? get selectedSeriesDetail => _selectedSeriesDetail;
  PlaybackSession? get activePlaybackSession => _activePlaybackSession;
  bool get isPlayerOpen => _activePlaybackSession != null;
  String? get statusMessage => _statusMessage;

  void attachDependencies({
    SettingsController? settingsController,
    LibraryController? libraryController,
    HomeController? homeController,
    StatsController? statsController,
    SaphirPlayerController? playerController,
    DatabaseService? databaseService,
  }) {
    _settingsController ??= settingsController;
    _libraryController ??= libraryController;
    _homeController ??= homeController;
    _statsController ??= statsController;
    _playerController ??= playerController;
    _databaseService ??= databaseService;
  }

  void attachWindowListener() {
    if (_windowListenerToken != null) return;
    _windowListenerToken = DesktopPlatformService.registerWindowCallbacks(
      onMaximize: onWindowMaximize,
      onUnmaximize: onWindowUnmaximize,
      onClose: onWindowClose,
    );
  }

  void detachWindowListener() {
    if (_windowListenerToken == null) return;
    DesktopPlatformService.unregisterWindowCallbacks(_windowListenerToken);
    _windowListenerToken = null;
  }

  void onWindowMaximize() {
    if (!_isMaximized) {
      _isMaximized = true;
      _safeNotify();
    }
  }

  void onWindowUnmaximize() {
    if (_isMaximized) {
      _isMaximized = false;
      _safeNotify();
    }
  }

  Future<void> onWindowClose() async {
    if (_isClosing) return;
    _isClosing = true;
    try {
      if (isPlayerOpen) {
        await _playerController?.stopAndClose();
      }
      await _settingsController?.syncProgress();
      _databaseService?.close();
    } finally {
      await DesktopPlatformService.destroyWindow();
    }
  }

  void selectSection(AppSection section) {
    _selectedSeriesDetail = null;
    if (section == AppSection.stats) {
      _statsController?.refreshStats();
    }
    if (_activeSection == section) {
      _safeNotify();
      return;
    }
    _activeSection = section;
    _safeNotify();
  }

  void openSeriesDetail(SeriesDetailData detail) {
    _selectedSeriesDetail = detail;
    _safeNotify();
  }

  void closeSeriesDetail() {
    _selectedSeriesDetail = null;
    _safeNotify();
  }

  void openPlaybackSession(PlaybackSession session) {
    _activePlaybackSession = session;
    _safeNotify();
  }

  void closePlaybackSession() {
    _activePlaybackSession = null;
    _safeNotify();
  }

  void _setStatusMessage(String message) {
    _statusClearTimer?.cancel();
    _statusMessage = message;
    _safeNotify();
    _statusClearTimer = Timer(
      const Duration(seconds: AppSpacing.statusBannerAutoHideSeconds),
      () {
        if (_isDisposed) return;
        _statusMessage = null;
        _safeNotify();
      },
    );
  }

  void _refreshAllViews() {
    _libraryController?.loadCountsFromCache();
    _homeController?.refreshHomeFeeds();
    _statsController?.refreshStats();
  }

  void updateGlobalSearch(String query) {
    _searchDebounceTimer?.cancel();
    if (query.trim().isEmpty) {
      _applyGlobalSearch(query);
      return;
    }
    _searchDebounceTimer = Timer(
      const Duration(milliseconds: AppSpacing.searchDebounceMs),
      () {
        if (!_isDisposed) {
          _applyGlobalSearch(query);
        }
      },
    );
  }

  void clearGlobalSearchImmediate() {
    _searchDebounceTimer?.cancel();
    _applyGlobalSearch('');
  }

  void _applyGlobalSearch(String query) {
    _homeController?.updateSearchQuery(query);
    _libraryController?.updateSearchQuery(query);
    final hasQuery = query.trim().isNotEmpty;
    if (hasQuery &&
        (_selectedSeriesDetail != null ||
            _activeSection == AppSection.settings ||
            _activeSection == AppSection.stats)) {
      selectSection(AppSection.library);
      return;
    }
    _safeNotify();
  }

  Future<void> triggerScan() async {
    await _libraryController?.syncAndRefreshLibrary();
    _homeController?.refreshHomeFeeds();
    _statsController?.refreshStats();
  }

  Future<void> handleSyncNow() async {
    await _settingsController?.syncProgress();
    _refreshAllViews();
    _setStatusMessage(AppStrings.syncCompletedStatus);
  }

  Future<void> handleClearCache() async {
    await _settingsController?.clearThumbnailCache();
    _refreshAllViews();
    _setStatusMessage(AppStrings.cacheClearedStatus);
  }

  Future<void> handleAddFolderFromPicker() async {
    final added = await _settingsController?.pickAndAddFolder(
      AppStrings.pickFolderDialogTitle,
    );
    if (added == null || _isDisposed) {
      return;
    }
    _setStatusMessage(
      added ? AppStrings.folderAddedStatus : AppStrings.folderDuplicateStatus,
    );
  }

  bool handleAddFolderFromInput(String rawPath) {
    final candidate = rawPath.trim();
    if (candidate.isEmpty || _settingsController == null) {
      return false;
    }
    final added = _settingsController!.addNasPath(candidate);
    _setStatusMessage(
      added ? AppStrings.folderAddedStatus : AppStrings.folderDuplicateStatus,
    );
    return added;
  }

  void handleRemoveFolder(String path) {
    _settingsController?.removeNasPath(path);
    _setStatusMessage(AppStrings.folderRemovedStatus);
  }

  Future<void> handleResetDatabase() async {
    await _settingsController?.resetDatabase();
    _libraryController?.resetLibraryState();
    _homeController?.updateSearchQuery('');
    _homeController?.refreshHomeFeeds();
    _statsController?.refreshStats();
    _setStatusMessage(AppStrings.databaseResetStatus);
  }

  void handleSaveSettings(String pendingInput) {
    final trimmed = pendingInput.trim();
    if (trimmed.isNotEmpty) {
      _settingsController?.addNasPath(trimmed);
    }
    _settingsController?.save();
    _setStatusMessage(AppStrings.savedStatus);
  }

  void openSeriesById(int seriesId) {
    final detail = _homeController?.loadSeriesDetail(seriesId);
    if (detail != null) {
      openSeriesDetail(detail);
    }
  }

  Future<void> launchPlayer(PlaybackSession session) async {
    _libraryController?.setPlaybackActive(true);
    openPlaybackSession(session);
    await _playerController?.startSession(session);
  }

  void handlePlayerClosed() {
    _libraryController?.setPlaybackActive(false);
    closePlaybackSession();
    _refreshAllViews();
    final currentSeries = _selectedSeriesDetail;
    if (currentSeries != null) {
      openSeriesById(currentSeries.seriesId);
    }
  }

  void handleToggleWatched(EpisodeEntry episode) {
    _homeController?.toggleEpisodeWatchedLocal(episode);
    _refreshAllViews();
    final currentSeries = _selectedSeriesDetail;
    if (currentSeries != null) {
      openSeriesById(currentSeries.seriesId);
    }
  }

  void handleRemoveFromContinueWatching(MediaCardItem item) {
    _homeController?.removeFromContinueWatching(item);
    _refreshAllViews();
    if (_settingsController != null) {
      unawaited(_settingsController!.syncProgress());
    }
  }

  Future<void> startWindowDragging() =>
      DesktopPlatformService.startWindowDragging();

  Future<void> syncMaximizedState() async {
    _isMaximized = await DesktopPlatformService.isWindowMaximized();
    _safeNotify();
  }

  Future<void> minimizeWindow() => DesktopPlatformService.minimizeWindow();

  Future<void> toggleMaximizeWindow() async {
    final maximized = await DesktopPlatformService.isWindowMaximized();
    if (maximized) {
      await DesktopPlatformService.unmaximizeWindow();
    } else {
      await DesktopPlatformService.maximizeWindow();
    }
    _isMaximized = !maximized;
    _safeNotify();
  }

  Future<void> closeWindow() => DesktopPlatformService.closeWindow();

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void cancelPendingTimers() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = null;
    _statusClearTimer?.cancel();
    _statusClearTimer = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    cancelPendingTimers();
    detachWindowListener();
    super.dispose();
  }
}
