import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/app_spacing.dart';
import '../constants/app_strings.dart';
import '../models/media_source_models.dart';
import '../models/status_feedback_models.dart';
import '../services/desktop_platform_service.dart';
import '../storage/app_settings_store.dart';
import '../storage/database_backup_service.dart';
import '../storage/database_service.dart';
import '../storage/media_source_repository.dart';
import '../storage/portable_paths.dart';
import '../storage/progress_sync_service.dart';
import '../storage/sync_feedback_mapper.dart';
import '../storage/thumbnail_cache_service.dart';
import '../theme/effect_mode.dart';
import '../utils/formatters.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(
    this._databaseService, {
    ProgressSyncService? syncService,
    ThumbnailCacheService? cacheService,
    DatabaseBackupService? backupService,
    ThumbnailOperationGate? thumbnailGate,
    StorageLayout? storageLayout,
  })  : _storageLayout = storageLayout,
        _sourceRepository = MediaSourceRepository(_databaseService),
        _syncService = syncService ??
            ProgressSyncService(_databaseService, storageLayout: storageLayout),
        _cacheService = cacheService ??
            ThumbnailCacheService(
              storageLayout: storageLayout,
              gate: thumbnailGate,
            ),
        _backupService = backupService ??
            DatabaseBackupService(storageLayout: storageLayout);

  final DatabaseService _databaseService;
  final StorageLayout? _storageLayout;
  final MediaSourceRepository _sourceRepository;
  final ProgressSyncService _syncService;
  final ThumbnailCacheService _cacheService;
  final DatabaseBackupService _backupService;

  static const int _maxDiagnosticEntries = 50;

  bool _isDisposed = false;
  List<String> _nasPaths = [];
  List<MediaSourceEntry> _mediaSources = const [];
  EffectMode _effectMode = EffectMode.glass;
  bool _perDeviceEffect = true;
  int _cacheBytes = 0;
  bool _subtitlesEnabledByDefault = false;
  String _preferredSubtitleLanguage = AppStrings.subtitleLangCodeDe;
  double _subtitleScale = AppSpacing.subtitleScaleDefault;
  int _subtitlePosition = AppSpacing.subtitlePositionDefault;
  double _subtitleBgOpacity = AppSpacing.subtitleBgOpacityDefault;
  bool _hardwareAccelerationEnabled = true;
  BackupInfo? _latestBackup;
  bool _isMaintenanceInProgress = false;
  SyncFeedbackSummary? _lastSyncFeedback;
  SyncFeedbackSummary? _lastSuccessfulNasSync;
  String? _settingsLoadError;
  List<String> _settingsLoadWarnings = const [];
  Future<SyncResult>? _activeStartupSync;
  final List<String> _diagnosticLog = <String>[];

  List<String> get nasPaths => List.unmodifiable(_nasPaths);
  String get nasPath => _nasPaths.isNotEmpty ? _nasPaths.first : '';
  List<MediaSourceEntry> get mediaSources => List.unmodifiable(_mediaSources);
  EffectMode get effectMode => _effectMode;
  bool get perDeviceEffect => _perDeviceEffect;
  int get cacheBytes => _cacheBytes;
  String get formattedCacheSize => Formatters.formatCacheSize(_cacheBytes);
  bool get subtitlesEnabledByDefault => _subtitlesEnabledByDefault;
  String get preferredSubtitleLanguage => _preferredSubtitleLanguage;
  double get subtitleScale => _subtitleScale;
  int get subtitlePosition => _subtitlePosition;
  double get subtitleBgOpacity => _subtitleBgOpacity;
  bool get hardwareAccelerationEnabled => _hardwareAccelerationEnabled;
  bool get isPortableMode =>
      (_storageLayout ?? PortablePaths.activeLayout)?.isPortable ?? false;
  String get storageDataPath =>
      (_storageLayout ?? PortablePaths.activeLayout)?.dataDirectory ?? '';
  Map<String, String> get sourceIdsByRoot => _databaseService.isOpen
      ? _databaseService.loadSourceIdsByRoot()
      : const {};
  BackupInfo? get latestBackup => _latestBackup;
  bool get isMaintenanceInProgress => _isMaintenanceInProgress;
  SyncFeedbackSummary? get lastSyncFeedback => _lastSyncFeedback;
  SyncFeedbackSummary? get lastSuccessfulNasSync => _lastSuccessfulNasSync;
  String? get settingsLoadError => _settingsLoadError;
  bool get hasSettingsLoadError => _settingsLoadError != null;
  List<String> get settingsLoadWarnings =>
      List.unmodifiable(_settingsLoadWarnings);
  List<String> get diagnosticLog => List.unmodifiable(_diagnosticLog);
  String get formattedLastSuccessfulSync =>
      AppSettingsStore.formatLastSuccessfulSync(_lastSuccessfulNasSync);
  String get formattedLatestBackup =>
      AppSettingsStore.formatLatestBackup(_latestBackup);
  String get _deviceEffectKey =>
      'effect_mode_${DesktopPlatformService.localHostname}';
  String get _deviceHwdecKey => 'hwdec_${DesktopPlatformService.localHostname}';

  void _appendDiagnostic(String message) {
    final stamp = DateTime.now().toIso8601String();
    _diagnosticLog.add('[$stamp] $message');
    if (_diagnosticLog.length > _maxDiagnosticEntries) {
      _diagnosticLog.removeAt(0);
    }
    debugPrint('[SettingsController] $message');
  }

  Future<SyncResult> syncProgress({
    SyncCancellationToken? cancellationToken,
  }) async {
    try {
      final result = await _syncService.syncWithRoots(
        _nasPaths,
        cancellationToken: cancellationToken,
      );
      final feedback = SyncFeedbackMapper.fromResult(result);
      _lastSyncFeedback = feedback;
      if (result.syncedToNas) {
        _lastSuccessfulNasSync = feedback;
        if (_databaseService.isOpen) {
          AppSettingsStore.persistNasSyncMeta(
            _databaseService.instance,
            timestampMs: feedback.timestampMs,
            targetPath: result.targetPath,
          );
        }
      } else if (feedback.severity == StatusSeverity.warning ||
          feedback.severity == StatusSeverity.error) {
        _appendDiagnostic(
          'Sync (${result.status.name}): '
          '${feedback.diagnosticMessage ?? feedback.headline} '
          '[${result.targetPath}]',
        );
      }
      _safeNotify();
      return result;
    } catch (error) {
      final feedback = SyncFeedbackMapper.fromException(error);
      _lastSyncFeedback = feedback;
      _appendDiagnostic('Sync-Fehler: $error');
      _safeNotify();
      return SyncResult(
        syncedToNas: false,
        targetPath: '',
        status: SyncStatus.failed,
        message: error.toString(),
      );
    }
  }

  /// Führt den Start-Sync dedupliziert aus, sodass parallele Aufrufe denselben
  /// Lauf teilen.
  Future<SyncResult> runStartupSync({
    SyncCancellationToken? cancellationToken,
  }) {
    final active = _activeStartupSync;
    if (active != null) return active;
    late final Future<SyncResult> future;
    future =
        syncProgress(cancellationToken: cancellationToken).whenComplete(() {
      if (identical(_activeStartupSync, future)) _activeStartupSync = null;
    });
    _activeStartupSync = future;
    return future;
  }

  Future<bool?> pickAndAddFolder(String dialogTitle) async {
    final selected =
        await DesktopPlatformService.pickMediaDirectory(dialogTitle);
    return selected == null ? null : addNasPath(selected);
  }

  Future<void> load() async {
    _settingsLoadError = null;
    _settingsLoadWarnings = const [];
    try {
      await refreshCacheSize();
    } catch (error) {
      _appendDiagnostic('Cache-Größe konnte nicht ermittelt werden: $error');
    }
    await refreshLatestBackup();

    try {
      final db = _databaseService.instance;
      final snap = AppSettingsStore.loadAll(
        db,
        deviceEffectKey: _deviceEffectKey,
        deviceHwdecKey: _deviceHwdecKey,
      );
      _applySnapshot(snap);
      for (final path in _nasPaths) {
        _sourceRepository.ensureActiveSource(path);
      }
      _mediaSources = _sourceRepository.loadSources();
      _settingsLoadWarnings = snap.fieldWarnings;
      for (final warning in snap.fieldWarnings) {
        _appendDiagnostic('Settings-Feldfallback: $warning');
      }
    } catch (error) {
      _applySnapshot(AppSettingsSnapshot.defaults());
      _mediaSources = const [];
      _settingsLoadError = AppStrings.settingsLoadErrorStatus;
      _appendDiagnostic('Settings-Ladefehler: $error');
    }
    _safeNotify();
  }

  void _applySnapshot(AppSettingsSnapshot snap) {
    _nasPaths = List<String>.of(snap.nasPaths);
    _effectMode = snap.effectMode;
    _perDeviceEffect = snap.perDeviceEffect;
    _subtitlesEnabledByDefault = snap.subtitlesEnabledByDefault;
    _preferredSubtitleLanguage = snap.preferredSubtitleLanguage;
    _subtitleScale = snap.subtitleScale;
    _subtitlePosition = snap.subtitlePosition;
    _subtitleBgOpacity = snap.subtitleBgOpacity;
    _hardwareAccelerationEnabled = snap.hardwareAccelerationEnabled;
    _lastSuccessfulNasSync = SyncFeedbackMapper.restoredNasSync(
      snap.lastNasSyncAtMs,
      snap.lastNasSyncTarget,
    );
  }

  void refreshMediaSources() {
    if (!_databaseService.isOpen) return;
    _mediaSources = _sourceRepository.loadSources();
    _safeNotify();
  }

  Future<void> refreshCacheSize() async {
    _cacheBytes = await _cacheService.calculateCacheBytes();
    _safeNotify();
  }

  Future<void> refreshLatestBackup() async {
    try {
      _latestBackup = await _backupService.latestBackup();
    } on FileSystemException {
      _latestBackup = null;
    }
    _safeNotify();
  }

  Future<BackupResult> createBackup({String reason = 'manual'}) async {
    final result =
        await _backupService.createBackup(_databaseService, reason: reason);
    if (result.success) {
      _latestBackup = result.backupInfo;
      _safeNotify();
    }
    return result;
  }

  Future<CacheClearResult> clearThumbnailCacheWithResult({
    Future<void> Function()? onStopGeneration,
  }) async {
    final result = await _cacheService.clearCacheWithResult(
      _databaseService,
      onStopGeneration: onStopGeneration,
    );
    _cacheBytes = result.remainingBytes;
    _safeNotify();
    return result;
  }

  Future<void> clearThumbnailCache() => clearThumbnailCacheWithResult();

  bool addNasPath(String value, {String? sourceId}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final added = AppSettingsStore.addUniquePath(_nasPaths, trimmed);
    if (!added) return false;
    if (_databaseService.isOpen) {
      _sourceRepository.ensureActiveSource(trimmed,
          preferredSourceId: sourceId);
      _mediaSources = _sourceRepository.loadSources();
    }
    save();
    return true;
  }

  void removeNasPath(String path) {
    final normalized = path.trim().toLowerCase();
    _nasPaths.removeWhere((p) => p.toLowerCase() == normalized);
    final existing = _sourceRepository.findByRootPath(path);
    if (existing != null) {
      _sourceRepository.setSourceStatus(
        existing.sourceId,
        MediaSourceStatus.disabled,
      );
      _mediaSources = _sourceRepository.loadSources();
    }
    save();
  }

  Future<SourceRemovalResult?> removeMediaSource(
    String sourceId, {
    required SourceRemovalAction action,
  }) async {
    final entry = _sourceRepository.findById(sourceId);
    if (entry == null) return null;
    final normalized = entry.rootPath.trim().toLowerCase();
    _nasPaths.removeWhere((p) => p.toLowerCase() == normalized);

    final SourceRemovalResult result;
    if (action == SourceRemovalAction.disableKeepData) {
      _sourceRepository.setSourceStatus(sourceId, MediaSourceStatus.disabled);
      result = SourceRemovalResult(
        sourceId: sourceId,
        rootPath: entry.rootPath,
        action: action,
      );
    } else {
      result = _sourceRepository.removeSourceIndex(sourceId);
      await MediaSourceRepository.deleteOrphanedThumbnails(
        result.orphanedThumbnails,
      );
      await refreshCacheSize();
    }
    _mediaSources = _sourceRepository.loadSources();
    save();
    return result;
  }

  bool reactivateMediaSource(String sourceId) {
    final entry = _sourceRepository.findById(sourceId);
    if (entry == null) return false;
    _sourceRepository.setSourceStatus(sourceId, MediaSourceStatus.active);
    AppSettingsStore.addUniquePath(_nasPaths, entry.rootPath);
    _mediaSources = _sourceRepository.loadSources();
    save();
    return true;
  }

  void updateEffectMode(EffectMode mode) {
    _effectMode = mode;
    _persistEffectMode();
    notifyListeners();
  }

  void updatePerDeviceEffect(bool enabled) {
    _perDeviceEffect = enabled;
    _persistEffectMode();
    notifyListeners();
  }

  void _persistEffectMode() => AppSettingsStore.persistEffectMode(
        _databaseService.instance,
        perDeviceEffect: _perDeviceEffect,
        deviceEffectKey: _deviceEffectKey,
        effectMode: _effectMode,
      );

  void updateSubtitlesDefaultEnabled(bool enabled) {
    _subtitlesEnabledByDefault = enabled;
    _upsertSetting(AppSettingsStore.subtitlesDefaultKey, enabled ? '1' : '0');
    notifyListeners();
  }

  void updatePreferredSubtitleLanguage(String language) {
    _preferredSubtitleLanguage =
        AppSettingsStore.normalizeSubtitleLang(language);
    _upsertSetting(
      AppSettingsStore.preferredSubtitleLangKey,
      _preferredSubtitleLanguage,
    );
    notifyListeners();
  }

  void updateSubtitleStyle({double? scale, int? position, double? bgOpacity}) {
    final next = AppSettingsStore.saveSubtitleStyle(
      _databaseService.instance,
      currentScale: _subtitleScale,
      currentPosition: _subtitlePosition,
      currentBgOpacity: _subtitleBgOpacity,
      scale: scale,
      position: position,
      bgOpacity: bgOpacity,
    );
    _subtitleScale = next.scale;
    _subtitlePosition = next.position;
    _subtitleBgOpacity = next.bgOpacity;
    notifyListeners();
  }

  void updateHardwareAcceleration(bool enabled) {
    _hardwareAccelerationEnabled = enabled;
    _upsertSetting(_deviceHwdecKey, enabled ? '1' : '0');
    notifyListeners();
  }

  void _upsertSetting(String key, String value) =>
      AppSettingsStore.upsertSetting(_databaseService.instance, key, value);

  void save() {
    AppSettingsStore.saveAll(
      _databaseService.instance,
      nasPaths: _nasPaths,
      nasPath: nasPath,
      perDeviceEffect: _perDeviceEffect,
      deviceEffectKey: _deviceEffectKey,
      effectMode: _effectMode,
      subtitlesEnabledByDefault: _subtitlesEnabledByDefault,
      preferredSubtitleLanguage: _preferredSubtitleLanguage,
      subtitleScale: _subtitleScale,
      subtitlePosition: _subtitlePosition,
      subtitleBgOpacity: _subtitleBgOpacity,
      deviceHwdecKey: _deviceHwdecKey,
      hardwareAccelerationEnabled: _hardwareAccelerationEnabled,
    );
    notifyListeners();
  }

  Future<T> _runMaintenanceSyncGuarded<T>(
    Future<void> Function()? onStopJobs,
    Future<T> Function() action,
  ) async {
    _isMaintenanceInProgress = true;
    _safeNotify();
    try {
      if (onStopJobs != null) await onStopJobs();
      await _syncService.waitForIdle();
      return await action();
    } finally {
      _isMaintenanceInProgress = false;
      _safeNotify();
    }
  }

  Future<BackupResult> resetDatabaseWithBackup({
    bool requireBackup = true,
    Future<void> Function()? onStopJobs,
  }) =>
      _runMaintenanceSyncGuarded(onStopJobs, () async {
        var backupResult = const BackupResult(success: true);
        if (requireBackup) {
          backupResult = await _backupService.createBackup(
            _databaseService,
            reason: 'pre_reset',
          );
          if (!backupResult.success) return backupResult;
          _latestBackup = backupResult.backupInfo;
        }
        _databaseService.resetDatabase();
        _applySnapshot(AppSettingsSnapshot.defaults());
        _mediaSources = const [];
        _lastSyncFeedback = null;
        _settingsLoadError = null;
        _settingsLoadWarnings = const [];
        final clearResult =
            await _cacheService.clearCacheWithResult(_databaseService);
        _cacheBytes = clearResult.remainingBytes;
        _latestBackup = await _backupService.latestBackup();
        return backupResult;
      });

  Future<void> resetDatabase() async {
    final result = await resetDatabaseWithBackup(requireBackup: true);
    if (!result.success) {
      throw StateError(result.errorMessage ?? AppStrings.backupFailedStatus);
    }
  }

  Future<RestoreResult> restoreBackupFromPath(
    String backupPath, {
    Future<void> Function()? onStopJobs,
  }) =>
      _runMaintenanceSyncGuarded(onStopJobs, () async {
        final result =
            await _backupService.restoreBackup(_databaseService, backupPath);
        if (result.success) {
          await load();
        } else {
          await refreshLatestBackup();
        }
        return result;
      });

  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
