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
    Future<void> Function()? onHideWindow,
    Future<void> Function()? onDestroyWindow,
    VoidCallback? onForceExit,
  })  : _settingsController = settingsController,
        _libraryController = libraryController,
        _homeController = homeController,
        _statsController = statsController,
        _playerController = playerController,
        _databaseService = databaseService,
        _onHideWindow = onHideWindow ?? DesktopPlatformService.hideWindow,
        _onDestroyWindow =
            onDestroyWindow ?? DesktopPlatformService.destroyWindow,
        _onForceExit = onForceExit ?? DesktopPlatformService.forceExitProcess;

  SettingsController? _settingsController;
  LibraryController? _libraryController;
  HomeController? _homeController;
  StatsController? _statsController;
  SaphirPlayerController? _playerController;
  DatabaseService? _databaseService;
  final Future<void> Function() _onHideWindow;
  final Future<void> Function() _onDestroyWindow;
  final VoidCallback _onForceExit;

  AppSection _activeSection = AppSection.home;
  bool _isMaximized = false;
  SeriesDetailData? _selectedSeriesDetail;
  PlaybackSession? _activePlaybackSession;
  String? _statusMessage;
  Timer? _searchDebounceTimer;
  Timer? _statusClearTimer;
  Object? _windowListenerToken;
  bool _isClosing = false;
  bool _isMaintenanceInProgress = false;
  bool _isDisposed = false;

  AppSection get activeSection => _activeSection;
  bool get isMaximized => _isMaximized;
  SeriesDetailData? get selectedSeriesDetail => _selectedSeriesDetail;
  PlaybackSession? get activePlaybackSession => _activePlaybackSession;
  bool get isPlayerOpen => _activePlaybackSession != null;
  bool get isClosing => _isClosing;
  bool get isMaintenanceInProgress => _isMaintenanceInProgress;
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

  void onWindowMaximize() => _setMaximized(true);

  void onWindowUnmaximize() => _setMaximized(false);

  void _setMaximized(bool value) {
    if (_isMaximized == value) return;
    _isMaximized = value;
    _safeNotify();
  }

  Future<void> onWindowClose() async {
    if (_isClosing) return;
    _isClosing = true;
    cancelPendingTimers();

    try {
      await _onHideWindow();
    } catch (_) {}

    var playerDisposeTimedOut = false;
    var scanStopTimedOut = false;
    var shouldDrainNativeVideo = false;

    try {
      if (isPlayerOpen) {
        _libraryController?.setPlaybackActive(false, resumePausedScan: false);
        closePlaybackSession();
      }

      final shutdownTasks = <Future<void>>[];
      if (_playerController != null) {
        shutdownTasks.add(
          _runWithTimeout(
            _playerController!.disposeForShutdown(),
            const Duration(
              milliseconds: AppSpacing.shutdownPlayerDisposeTimeoutMs,
            ),
          ).then((disposed) {
            shouldDrainNativeVideo = disposed;
            playerDisposeTimedOut = !disposed;
          }),
        );
      }

      if (_libraryController != null) {
        shutdownTasks.add(
          _runWithTimeout(
            _libraryController!.cancelScanForShutdown(),
            const Duration(
              milliseconds: AppSpacing.shutdownScanStopTimeoutMs,
            ),
          ).then((stopped) {
            scanStopTimedOut = !stopped;
          }),
        );
      }

      if (shutdownTasks.isNotEmpty) {
        await Future.wait(shutdownTasks);
      }

      if (shouldDrainNativeVideo) {
        await Future<void>.delayed(
          const Duration(milliseconds: AppSpacing.shutdownNativeDrainDelayMs),
        );
      }

      if (_settingsController != null) {
        await _runWithTimeout(
          _settingsController!.syncProgress(),
          const Duration(milliseconds: AppSpacing.shutdownSyncTimeoutMs),
        );
      }

      if (!scanStopTimedOut) {
        _databaseService?.close();
      }
    } finally {
      if (playerDisposeTimedOut || scanStopTimedOut) {
        _onForceExit();
      } else {
        await _onDestroyWindow();
      }
    }
  }

  Future<bool> _runWithTimeout(Future<void> future, Duration timeout) async {
    try {
      await future.timeout(timeout);
      return true;
    } catch (_) {
      return false;
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

  void openSeriesDetail(SeriesDetailData detail) => _setSeriesDetail(detail);
  void closeSeriesDetail() => _setSeriesDetail(null);
  void _setSeriesDetail(SeriesDetailData? detail) {
    _selectedSeriesDetail = detail;
    _safeNotify();
  }

  void openPlaybackSession(PlaybackSession session) => _setSession(session);
  void closePlaybackSession() => _setSession(null);
  void _setSession(PlaybackSession? session) {
    _activePlaybackSession = session;
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
      () => _isDisposed ? null : _applyGlobalSearch(query),
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

  bool get _isBusyOrClosing => _isMaintenanceInProgress || _isClosing;

  Future<T?> _runMaintenance<T>(Future<T> Function() action) async {
    if (_isBusyOrClosing) {
      _setStatusMessage(AppStrings.maintenanceBusyStatus);
      return null;
    }
    _isMaintenanceInProgress = true;
    _safeNotify();
    try {
      if (isPlayerOpen) {
        _libraryController?.setPlaybackActive(false, resumePausedScan: false);
        await _playerController?.stopAndClose();
        closePlaybackSession();
      }
      await _libraryController?.beginMaintenance();
      return await action();
    } finally {
      _libraryController?.endMaintenance();
      _isMaintenanceInProgress = false;
      _safeNotify();
    }
  }

  Future<void> triggerScan() async {
    if (_isBusyOrClosing) return;
    await _libraryController?.syncAndRefreshLibrary();
    _homeController?.refreshHomeFeeds();
    _statsController?.refreshStats();
  }

  Future<void> handleSyncNow() async {
    if (_isBusyOrClosing) return;
    await _settingsController?.syncProgress();
    _refreshAllViews();
    _setStatusMessage(AppStrings.syncCompletedStatus);
  }

  Future<void> handleClearCache() => _runMaintenance(() async {
        final result = await _settingsController?.clearThumbnailCacheWithResult(
          onStopGeneration: () async => _libraryController?.beginMaintenance(),
        );
        _libraryController?.refreshThumbnailQueueStats();
        _refreshAllViews();
        _setStatusMessage(
          (result != null && result.hasWarnings)
              ? AppStrings.cacheClearedWithWarningsStatus
              : AppStrings.cacheClearedStatus,
        );
      });

  Future<void> handleRetryFailedThumbnails() async {
    if (_isBusyOrClosing) return;
    await _libraryController?.retryFailedThumbnails();
    _setStatusMessage(AppStrings.retryThumbnailsStatus);
  }

  Future<void> handleCreateBackup() => _runMaintenance(() async {
        final result = await _settingsController?.createBackup();
        if (result == null) return;
        _setStatusMessage(
          result.success
              ? AppStrings.backupCreatedStatus
              : AppStrings.backupFailedStatus,
        );
      });

  Future<void> handleRestoreBackup({String? backupPath}) async {
    await _runMaintenance(() async {
      final target = backupPath ?? _settingsController?.latestBackup?.filePath;
      if (target == null || _settingsController == null) {
        _setStatusMessage(AppStrings.backupRestoreFailedStatus);
        return;
      }
      final result = await _settingsController!.restoreBackupFromPath(target);
      if (result.success) {
        _selectedSeriesDetail = null;
        _refreshAllViews();
      }
      _setStatusMessage(
        result.success
            ? AppStrings.backupRestoredStatus
            : AppStrings.backupRestoreFailedStatus,
      );
    });
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
    await _runMaintenance(() async {
      final backupResult = await _settingsController?.resetDatabaseWithBackup(
        requireBackup: true,
      );
      if (backupResult != null && !backupResult.success) {
        _setStatusMessage(AppStrings.backupFailedStatus);
        return;
      }
      _selectedSeriesDetail = null;
      _libraryController?.resetLibraryState();
      _homeController?.updateSearchQuery('');
      _homeController?.refreshHomeFeeds();
      _statsController?.refreshStats();
      _setStatusMessage(AppStrings.databaseResetStatus);
    });
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
    if (_isBusyOrClosing) return;
    _libraryController?.setPlaybackActive(true);
    openPlaybackSession(session);
    await _playerController?.startSession(session);
  }

  void handlePlayerClosed() {
    _libraryController?.setPlaybackActive(false);
    closePlaybackSession();
    _refreshAllViews();
    _reopenSelectedSeries();
  }

  void handleToggleWatched(EpisodeEntry episode) {
    _homeController?.toggleEpisodeWatchedLocal(episode);
    _refreshAllViews();
    _reopenSelectedSeries();
  }

  void _reopenSelectedSeries() {
    final currentSeries = _selectedSeriesDetail;
    if (currentSeries != null) openSeriesById(currentSeries.seriesId);
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

  Future<void> syncMaximizedState() async =>
      _setMaximized(await DesktopPlatformService.isWindowMaximized());

  Future<void> minimizeWindow() => DesktopPlatformService.minimizeWindow();

  Future<void> toggleMaximizeWindow() async {
    final nextMaximized = !(await DesktopPlatformService.isWindowMaximized());
    await (nextMaximized
        ? DesktopPlatformService.maximizeWindow()
        : DesktopPlatformService.unmaximizeWindow());
    _setMaximized(nextMaximized);
  }

  Future<void> closeWindow() => DesktopPlatformService.closeWindow();

  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

  void cancelPendingTimers() {
    _searchDebounceTimer?.cancel();
    _statusClearTimer?.cancel();
    _searchDebounceTimer = _statusClearTimer = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    cancelPendingTimers();
    detachWindowListener();
    super.dispose();
  }
}
