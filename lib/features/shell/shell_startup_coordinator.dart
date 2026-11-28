import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/library_controller.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/models/status_feedback_models.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/progress_sync_service.dart';

class ShellStartupCoordinator {
  StatusBannerMessage? _startupBanner;
  bool _canRetryStartupSync = false;
  Future<void>? _activeRun;

  StatusBannerMessage? get startupBanner => _startupBanner;
  bool get canRetryStartupSync => _canRetryStartupSync;

  void initializeFromSettings(
    SettingsController? settings, {
    required VoidCallback onChanged,
  }) {
    if (settings == null) return;
    if (settings.hasSettingsLoadError) {
      _startupBanner = StatusBannerMessage(
        message: settings.settingsLoadError!,
        severity: StatusSeverity.error,
        detail: settings.diagnosticLog.isNotEmpty
            ? settings.diagnosticLog.last
            : null,
      );
      _canRetryStartupSync = false;
      onChanged();
      return;
    }
    if (settings.settingsLoadWarnings.isNotEmpty) {
      _startupBanner = StatusBannerMessage(
        message: AppStrings.settingsFieldFallbackWarning,
        severity: StatusSeverity.warning,
        detail: settings.settingsLoadWarnings.join(' · '),
      );
      _canRetryStartupSync = false;
      onChanged();
    }
  }

  void dismissBanner({required VoidCallback onChanged}) {
    if (_startupBanner == null && !_canRetryStartupSync) return;
    _startupBanner = null;
    _canRetryStartupSync = false;
    onChanged();
  }

  Future<void> runStartupSync({
    required SettingsController? settingsController,
    required LibraryController? libraryController,
    required DatabaseService? databaseService,
    required bool Function() isClosingOrDisposed,
    required bool Function() isPlayerOpen,
    required VoidCallback onRefreshViews,
    required VoidCallback onChanged,
    Future<void> Function()? onPostSyncThumbnailBatch,
  }) {
    if (_activeRun != null) return _activeRun!;
    if (settingsController == null || isClosingOrDisposed()) {
      return Future<void>.value();
    }

    late final Future<void> runFuture;
    runFuture = _executeStartupSync(
      settingsController: settingsController,
      libraryController: libraryController,
      databaseService: databaseService,
      isClosingOrDisposed: isClosingOrDisposed,
      isPlayerOpen: isPlayerOpen,
      onRefreshViews: onRefreshViews,
      onChanged: onChanged,
      onPostSyncThumbnailBatch: onPostSyncThumbnailBatch,
    ).whenComplete(() {
      if (identical(_activeRun, runFuture)) {
        _activeRun = null;
      }
    });
    _activeRun = runFuture;
    return runFuture;
  }

  Future<void> _executeStartupSync({
    required SettingsController settingsController,
    required LibraryController? libraryController,
    required DatabaseService? databaseService,
    required bool Function() isClosingOrDisposed,
    required bool Function() isPlayerOpen,
    required VoidCallback onRefreshViews,
    required VoidCallback onChanged,
    Future<void> Function()? onPostSyncThumbnailBatch,
  }) async {
    final result = await settingsController.runStartupSync();
    if (isClosingOrDisposed() ||
        (databaseService != null && !databaseService.isOpen)) {
      return;
    }

    onRefreshViews();

    final feedback = settingsController.lastSyncFeedback;
    final hasConfiguredNas = settingsController.nasPaths.isNotEmpty;
    final shouldShowSyncIssue = hasConfiguredNas &&
        !result.syncedToNas &&
        result.status != SyncStatus.cancelled;

    if (shouldShowSyncIssue) {
      _startupBanner = StatusBannerMessage(
        message: feedback?.headline ?? AppStrings.syncFailedStatus,
        severity: feedback?.severity ?? StatusSeverity.warning,
        detail: feedback?.detail ?? result.message,
      );
      _canRetryStartupSync = true;
      onChanged();
    } else if (_canRetryStartupSync &&
        !settingsController.hasSettingsLoadError) {
      _startupBanner = null;
      _canRetryStartupSync = false;
      onChanged();
    }

    if (!isPlayerOpen() &&
        !isClosingOrDisposed() &&
        onPostSyncThumbnailBatch != null) {
      await onPostSyncThumbnailBatch();
    }
  }
}
