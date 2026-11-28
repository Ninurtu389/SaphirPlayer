import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/library_controller.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/models/media_source_models.dart';
import '../../core/models/status_feedback_models.dart';
import '../../core/services/desktop_platform_service.dart';
import '../../core/storage/database_service.dart';
import '../home/home_controller.dart';
import '../library/library_models.dart';
import '../player/playback_session.dart';
import '../player/saphir_player_controller.dart';
import '../stats/stats_controller.dart';
import 'shell_shutdown_runner.dart';
import 'shell_startup_coordinator.dart';
import 'shell_window_delegate.dart';

enum AppSection { home, library, stats, settings }

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
    ShutdownTimeouts shutdownTimeouts = const ShutdownTimeouts(),
  })  : _settingsController = settingsController,
        _libraryController = libraryController,
        _homeController = homeController,
        _statsController = statsController,
        _playerController = playerController,
        _databaseService = databaseService,
        _onHideWindow = onHideWindow ?? DesktopPlatformService.hideWindow,
        _onDestroyWindow =
            onDestroyWindow ?? DesktopPlatformService.destroyWindow,
        _onForceExit = onForceExit ?? DesktopPlatformService.forceExitProcess,
        _shutdownTimeouts = shutdownTimeouts {
    _window = ShellWindowDelegate(onChanged: _safeNotify);
  }

  SettingsController? _settingsController;
  LibraryController? _libraryController;
  HomeController? _homeController;
  StatsController? _statsController;
  SaphirPlayerController? _playerController;
  DatabaseService? _databaseService;
  final Future<void> Function() _onHideWindow;
  final Future<void> Function() _onDestroyWindow;
  final VoidCallback _onForceExit;
  final ShutdownTimeouts _shutdownTimeouts;
  final ShellStartupCoordinator _startup = ShellStartupCoordinator();
  late final ShellWindowDelegate _window;

  AppSection _activeSection = AppSection.home;
  SeriesDetailData? _selectedSeriesDetail;
  PlaybackSession? _activePlaybackSession;
  StatusBannerMessage? _statusBanner;
  Timer? _searchDebounceTimer;
  Timer? _statusClearTimer;
  bool _isClosing = false;
  ShutdownPhase _shutdownPhase = ShutdownPhase.idle;
  ShutdownReport? _lastShutdownReport;
  Future<ShutdownReport>? _shutdownFuture;
  bool _isMaintenanceInProgress = false;
  bool _isDisposed = false;

  AppSection get activeSection => _activeSection;
  bool get isMaximized => _window.isMaximized;
  SeriesDetailData? get selectedSeriesDetail => _selectedSeriesDetail;
  PlaybackSession? get activePlaybackSession => _activePlaybackSession;
  bool get isPlayerOpen => _activePlaybackSession != null;
  bool get isClosing => _isClosing;
  ShutdownPhase get shutdownPhase => _shutdownPhase;
  ShutdownReport? get lastShutdownReport => _lastShutdownReport;
  bool get isMaintenanceInProgress => _isMaintenanceInProgress;
  StatusBannerMessage? get statusBanner => _statusBanner;
  String? get statusMessage => _statusBanner?.message;
  StatusBannerMessage? get startupBanner => _startup.startupBanner;
  bool get canRetryStartupSync => _startup.canRetryStartupSync;

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

  void initializeStartupState() => _startup.initializeFromSettings(
        _settingsController,
        onChanged: _safeNotify,
      );

  Future<void> runStartupSync({
    Future<void> Function()? onPostSyncThumbnailBatch,
  }) =>
      _startup.runStartupSync(
        settingsController: _settingsController,
        libraryController: _libraryController,
        databaseService: _databaseService,
        isClosingOrDisposed: () => _isClosing || _isDisposed,
        isPlayerOpen: () => isPlayerOpen,
        onRefreshViews: _refreshAllViews,
        onChanged: _safeNotify,
        onPostSyncThumbnailBatch: onPostSyncThumbnailBatch,
      );

  Future<void> retryStartupSync() => runStartupSync();
  void dismissStartupBanner() => _startup.dismissBanner(onChanged: _safeNotify);
  void attachWindowListener() =>
      _window.attachWindowListener(onClose: onWindowClose);
  void detachWindowListener() => _window.detachWindowListener();
  void onWindowMaximize() => _window.onWindowMaximize();
  void onWindowUnmaximize() => _window.onWindowUnmaximize();
  Future<void> startWindowDragging() => _window.startWindowDragging();
  Future<void> syncMaximizedState() => _window.syncMaximizedState();
  Future<void> minimizeWindow() => _window.minimizeWindow();
  Future<void> toggleMaximizeWindow() => _window.toggleMaximizeWindow();
  Future<void> closeWindow() => _window.closeWindow();

  Future<void> onWindowClose() {
    final existing = _shutdownFuture;
    if (existing != null) return existing;

    _isClosing = true;
    cancelPendingTimers();
    final future = ShellShutdownRunner.execute(
      isPlayerOpen: isPlayerOpen,
      onClosePlaybackSession: closePlaybackSession,
      settingsController: _settingsController,
      libraryController: _libraryController,
      playerController: _playerController,
      databaseService: _databaseService,
      onHideWindow: _onHideWindow,
      onDestroyWindow: _onDestroyWindow,
      onForceExit: _onForceExit,
      onPhaseChanged: (phase) => _shutdownPhase = phase,
      timeouts: _shutdownTimeouts,
    ).then((report) {
      _lastShutdownReport = report;
      return report;
    });
    _shutdownFuture = future;
    return future;
  }

  void selectSection(AppSection section) {
    _selectedSeriesDetail = null;
    if (section == AppSection.stats) _statsController?.refreshStats();
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

  void _setStatusMessage(
    String message, {
    StatusSeverity severity = StatusSeverity.success,
    String? detail,
  }) {
    _statusClearTimer?.cancel();
    _statusBanner = StatusBannerMessage(
        message: message, severity: severity, detail: detail);
    _safeNotify();
    _statusClearTimer = Timer(
      const Duration(seconds: AppSpacing.statusBannerAutoHideSeconds),
      () {
        if (_isDisposed) return;
        _statusBanner = null;
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
      _setStatusMessage(AppStrings.maintenanceBusyStatus,
          severity: StatusSeverity.warning);
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

  Future<void> handleRescanSource(String rootPath) async {
    if (_isBusyOrClosing) return;
    await _libraryController?.refreshSingleSource(rootPath);
    _homeController?.refreshHomeFeeds();
    _statsController?.refreshStats();
  }

  Future<void> handleSyncNow() async {
    if (_isBusyOrClosing || _settingsController == null) return;
    await _settingsController!.syncProgress();
    _refreshAllViews();
    final feedback = _settingsController!.lastSyncFeedback;
    _setStatusMessage(
      feedback?.headline ?? AppStrings.syncFailedStatus,
      severity: feedback?.severity ?? StatusSeverity.error,
      detail: feedback?.detail,
    );
  }

  Future<void> handleClearCache() => _runMaintenance(() async {
        final result = await _settingsController?.clearThumbnailCacheWithResult(
          onStopGeneration: () async => _libraryController?.beginMaintenance(),
        );
        _libraryController?.refreshThumbnailQueueStats();
        _refreshAllViews();
        final hasWarn = result != null && result.hasWarnings;
        _setStatusMessage(
          hasWarn
              ? AppStrings.cacheClearedWithWarningsStatus
              : AppStrings.cacheClearedStatus,
          severity: hasWarn ? StatusSeverity.warning : StatusSeverity.success,
        );
      });

  Future<void> handleRetryFailedThumbnails() async {
    if (_isBusyOrClosing) return;
    await _libraryController?.retryFailedThumbnails();
    _setStatusMessage(AppStrings.retryThumbnailsStatus,
        severity: StatusSeverity.info);
  }

  Future<void> handleCreateBackup() => _runMaintenance(() async {
        final result = await _settingsController?.createBackup();
        if (result == null) return;
        _setStatusMessage(
          result.success
              ? AppStrings.backupCreatedStatus
              : AppStrings.backupFailedStatus,
          severity:
              result.success ? StatusSeverity.success : StatusSeverity.error,
        );
      });

  Future<void> handleRestoreBackup({String? backupPath}) =>
      _runMaintenance(() async {
        final target =
            backupPath ?? _settingsController?.latestBackup?.filePath;
        if (target == null || _settingsController == null) {
          _setStatusMessage(AppStrings.backupRestoreFailedStatus,
              severity: StatusSeverity.error);
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
          severity:
              result.success ? StatusSeverity.success : StatusSeverity.error,
        );
      });

  Future<void> handleAddFolderFromPicker() async {
    final added = await _settingsController
        ?.pickAndAddFolder(AppStrings.pickFolderDialogTitle);
    if (added == null || _isDisposed) return;
    _setStatusMessage(
      added ? AppStrings.folderAddedStatus : AppStrings.folderDuplicateStatus,
      severity: added ? StatusSeverity.success : StatusSeverity.info,
    );
  }

  bool handleAddFolderFromInput(String rawPath) {
    final candidate = rawPath.trim();
    if (candidate.isEmpty || _settingsController == null) return false;
    final added = _settingsController!.addNasPath(candidate);
    _setStatusMessage(
      added ? AppStrings.folderAddedStatus : AppStrings.folderDuplicateStatus,
      severity: added ? StatusSeverity.success : StatusSeverity.info,
    );
    return added;
  }

  void handleRemoveFolder(String path) {
    _settingsController?.removeNasPath(path);
    _selectedSeriesDetail = null;
    _refreshAllViews();
    _setStatusMessage(AppStrings.folderRemovedStatus,
        severity: StatusSeverity.info);
  }

  Future<void> handleRemoveMediaSource(
      String sourceId, SourceRemovalAction action) async {
    if (_settingsController == null) return;
    if (action == SourceRemovalAction.disableKeepData) {
      await _settingsController!.removeMediaSource(sourceId, action: action);
      _selectedSeriesDetail = null;
      _refreshAllViews();
      _setStatusMessage(AppStrings.sourceDisabledStatus,
          severity: StatusSeverity.info);
      return;
    }
    await _runMaintenance(() async {
      await _settingsController!.removeMediaSource(sourceId, action: action);
      _selectedSeriesDetail = null;
      _refreshAllViews();
      _setStatusMessage(AppStrings.sourceRemovedWithIndexStatus,
          severity: StatusSeverity.info);
    });
  }

  void handleReactivateMediaSource(String sourceId) {
    if (_settingsController == null ||
        !_settingsController!.reactivateMediaSource(sourceId)) {
      return;
    }
    _refreshAllViews();
    _setStatusMessage(AppStrings.sourceReactivatedStatus,
        severity: StatusSeverity.success);
  }

  Future<void> handleResetDatabase() => _runMaintenance(() async {
        final backupResult = await _settingsController?.resetDatabaseWithBackup(
            requireBackup: true);
        if (backupResult != null && !backupResult.success) {
          _setStatusMessage(AppStrings.backupFailedStatus,
              severity: StatusSeverity.error);
          return;
        }
        _selectedSeriesDetail = null;
        _libraryController?.resetLibraryState();
        _homeController?.updateSearchQuery('');
        _homeController?.refreshHomeFeeds();
        _statsController?.refreshStats();
        _setStatusMessage(AppStrings.databaseResetStatus,
            severity: StatusSeverity.info);
      });

  void handleSaveSettings(String pendingInput) {
    final trimmed = pendingInput.trim();
    if (trimmed.isNotEmpty) _settingsController?.addNasPath(trimmed);
    _settingsController?.save();
    _setStatusMessage(AppStrings.savedStatus);
  }

  void openSeriesById(int seriesId) {
    final detail = _homeController?.loadSeriesDetail(seriesId);
    if (detail != null) openSeriesDetail(detail);
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
