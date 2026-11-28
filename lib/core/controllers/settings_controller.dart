import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/app_spacing.dart';
import '../constants/app_strings.dart';
import '../services/desktop_platform_service.dart';
import '../storage/database_backup_service.dart';
import '../storage/database_service.dart';
import '../storage/portable_paths.dart';
import '../storage/progress_sync_service.dart';
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
  final ProgressSyncService _syncService;
  final ThumbnailCacheService _cacheService;
  final DatabaseBackupService _backupService;

  static const String _nasPathKey = 'nas_root_path';
  static const String _nasPathsKey = 'nas_root_paths';
  static const String _globalEffectKey = 'effect_mode_global';
  static const String _subtitlesDefaultKey = 'subtitles_default_enabled';
  static const String _preferredSubtitleLangKey = 'preferred_subtitle_language';
  static const String _subtitleScaleKey = 'subtitle_scale';
  static const String _subtitlePositionKey = 'subtitle_position';
  static const String _subtitleBgOpacityKey = 'subtitle_bg_opacity';

  bool _isDisposed = false;
  List<String> _nasPaths = [];
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

  List<String> get nasPaths => List.unmodifiable(_nasPaths);
  String get nasPath => _nasPaths.isNotEmpty ? _nasPaths.first : '';
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

  String get formattedLatestBackup {
    final backup = _latestBackup;
    if (backup == null) {
      return AppStrings.backupNoneLabel;
    }
    final dt = backup.createdAt;
    final date =
        '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '${AppStrings.backupLatestPrefix} $date $time (${Formatters.formatCacheSize(backup.sizeBytes)})';
  }

  String get _deviceEffectKey =>
      'effect_mode_${DesktopPlatformService.localHostname}';
  String get _deviceHwdecKey => 'hwdec_${DesktopPlatformService.localHostname}';

  Future<SyncResult> syncProgress() {
    return _syncService.syncWithRoots(_nasPaths);
  }

  Future<bool?> pickAndAddFolder(String dialogTitle) async {
    final selectedDirectory =
        await DesktopPlatformService.pickMediaDirectory(dialogTitle);
    if (selectedDirectory == null) {
      return null;
    }
    return addNasPath(selectedDirectory);
  }

  Future<void> load() async {
    await refreshCacheSize();
    await refreshLatestBackup();
    final db = _databaseService.instance;

    final multiRows = db.select(
      'SELECT value FROM app_settings WHERE key = ? LIMIT 1;',
      [_nasPathsKey],
    );

    final loadedPaths = <String>[];
    if (multiRows.isNotEmpty) {
      try {
        final decoded = jsonDecode(multiRows.first['value'] as String);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String && item.trim().isNotEmpty) {
              _addUniquePath(loadedPaths, item.trim());
            }
          }
        }
      } on FormatException {
        // Fallback auf Einzelpfad-Key bei beschädigtem JSON
      }
    }

    if (loadedPaths.isEmpty) {
      final nasRows = db.select(
        'SELECT value FROM app_settings WHERE key = ? LIMIT 1;',
        [_nasPathKey],
      );
      if (nasRows.isNotEmpty) {
        final legacyPath = (nasRows.first['value'] as String).trim();
        if (legacyPath.isNotEmpty) {
          loadedPaths.add(legacyPath);
        }
      }
    }

    _nasPaths = loadedPaths;

    final deviceRows = db.select(
      'SELECT value FROM app_settings WHERE key = ? LIMIT 1;',
      [_deviceEffectKey],
    );
    if (deviceRows.isNotEmpty) {
      _perDeviceEffect = true;
      _effectMode = EffectMode.fromStorage(deviceRows.first['value'] as String);
    } else {
      _perDeviceEffect = false;
      final globalRows = db.select(
        'SELECT value FROM app_settings WHERE key = ? LIMIT 1;',
        [_globalEffectKey],
      );
      _effectMode = EffectMode.fromStorage(
        globalRows.isNotEmpty ? globalRows.first['value'] as String : null,
      );
    }

    _subtitlesEnabledByDefault = _readSetting(db, _subtitlesDefaultKey) == '1';
    final lang = _readSetting(db, _preferredSubtitleLangKey);
    _preferredSubtitleLanguage = _normalizeSubtitleLang(lang);
    _subtitleScale =
        (double.tryParse(_readSetting(db, _subtitleScaleKey) ?? '') ??
                AppSpacing.subtitleScaleDefault)
            .clamp(AppSpacing.subtitleScaleMin, AppSpacing.subtitleScaleMax);
    _subtitlePosition =
        (int.tryParse(_readSetting(db, _subtitlePositionKey) ?? '') ??
                AppSpacing.subtitlePositionDefault)
            .clamp(
      AppSpacing.subtitlePositionMin,
      AppSpacing.subtitlePositionMax,
    );
    _subtitleBgOpacity =
        (double.tryParse(_readSetting(db, _subtitleBgOpacityKey) ?? '') ??
                AppSpacing.subtitleBgOpacityDefault)
            .clamp(
      AppSpacing.subtitleBgOpacityMin,
      AppSpacing.subtitleBgOpacityMax,
    );
    final hwdecRaw = _readSetting(db, _deviceHwdecKey);
    _hardwareAccelerationEnabled = hwdecRaw == null ? true : hwdecRaw == '1';

    _safeNotify();
  }

  String? _readSetting(dynamic db, String key) {
    final rows = db.select(
      'SELECT value FROM app_settings WHERE key = ? LIMIT 1;',
      [key],
    );
    return rows.isNotEmpty ? rows.first['value'] as String : null;
  }

  static String _normalizeSubtitleLang(String? raw) {
    if (raw == AppStrings.subtitleLangCodeEn ||
        raw == AppStrings.subtitleLangCodeAuto) {
      return raw!;
    }
    return AppStrings.subtitleLangCodeDe;
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
    final result = await _backupService.createBackup(
      _databaseService,
      reason: reason,
    );
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

  Future<void> clearThumbnailCache() async {
    await clearThumbnailCacheWithResult();
  }

  static bool _addUniquePath(List<String> target, String candidate) {
    final normalized = candidate.toLowerCase();
    final exists = target.any((p) => p.toLowerCase() == normalized);
    if (exists) {
      return false;
    }
    target.add(candidate);
    return true;
  }

  bool addNasPath(String value, {String? sourceId}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final added = _addUniquePath(_nasPaths, trimmed);
    if (!added) {
      return false;
    }
    if (_databaseService.isOpen) {
      _databaseService.ensureMediaSource(
        trimmed,
        preferredSourceId: sourceId,
      );
    }
    save();
    return true;
  }

  void removeNasPath(String path) {
    final normalized = path.trim().toLowerCase();
    _nasPaths.removeWhere((p) => p.toLowerCase() == normalized);
    save();
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

  void _persistEffectMode() {
    if (_perDeviceEffect) {
      _upsertSetting(_deviceEffectKey, _effectMode.toStorage());
    } else {
      _databaseService.instance.execute(
        'DELETE FROM app_settings WHERE key = ?;',
        [_deviceEffectKey],
      );
      _upsertSetting(_globalEffectKey, _effectMode.toStorage());
    }
  }

  void updateSubtitlesDefaultEnabled(bool enabled) {
    _subtitlesEnabledByDefault = enabled;
    _upsertSetting(_subtitlesDefaultKey, enabled ? '1' : '0');
    notifyListeners();
  }

  void updatePreferredSubtitleLanguage(String language) {
    _preferredSubtitleLanguage = _normalizeSubtitleLang(language);
    _upsertSetting(_preferredSubtitleLangKey, _preferredSubtitleLanguage);
    notifyListeners();
  }

  void updateSubtitleStyle({
    double? scale,
    int? position,
    double? bgOpacity,
  }) {
    if (scale != null) {
      _subtitleScale = scale.clamp(
        AppSpacing.subtitleScaleMin,
        AppSpacing.subtitleScaleMax,
      );
      _upsertSetting(_subtitleScaleKey, _subtitleScale.toStringAsFixed(2));
    }
    if (position != null) {
      _subtitlePosition = position.clamp(
        AppSpacing.subtitlePositionMin,
        AppSpacing.subtitlePositionMax,
      );
      _upsertSetting(_subtitlePositionKey, _subtitlePosition.toString());
    }
    if (bgOpacity != null) {
      _subtitleBgOpacity = bgOpacity.clamp(
        AppSpacing.subtitleBgOpacityMin,
        AppSpacing.subtitleBgOpacityMax,
      );
      _upsertSetting(
        _subtitleBgOpacityKey,
        _subtitleBgOpacity.toStringAsFixed(2),
      );
    }
    notifyListeners();
  }

  void updateHardwareAcceleration(bool enabled) {
    _hardwareAccelerationEnabled = enabled;
    _upsertSetting(_deviceHwdecKey, enabled ? '1' : '0');
    notifyListeners();
  }

  void _upsertSetting(String key, String value) {
    _databaseService.instance.execute(
      '''
      INSERT INTO app_settings (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value;
      ''',
      [key, value],
    );
  }

  void save() {
    _upsertSetting(_nasPathsKey, jsonEncode(_nasPaths));
    _upsertSetting(_nasPathKey, nasPath);
    _persistEffectMode();

    _upsertSetting(
      _subtitlesDefaultKey,
      _subtitlesEnabledByDefault ? '1' : '0',
    );
    _upsertSetting(_preferredSubtitleLangKey, _preferredSubtitleLanguage);
    _upsertSetting(_subtitleScaleKey, _subtitleScale.toStringAsFixed(2));
    _upsertSetting(_subtitlePositionKey, _subtitlePosition.toString());
    _upsertSetting(
      _subtitleBgOpacityKey,
      _subtitleBgOpacity.toStringAsFixed(2),
    );
    _upsertSetting(_deviceHwdecKey, _hardwareAccelerationEnabled ? '1' : '0');

    notifyListeners();
  }

  Future<BackupResult> resetDatabaseWithBackup({
    bool requireBackup = true,
    Future<void> Function()? onStopJobs,
  }) async {
    _isMaintenanceInProgress = true;
    _safeNotify();
    try {
      if (onStopJobs != null) {
        await onStopJobs();
      }
      await _syncService.waitForIdle();

      BackupResult backupResult = const BackupResult(success: true);
      if (requireBackup) {
        backupResult = await _backupService.createBackup(
          _databaseService,
          reason: 'pre_reset',
        );
        if (!backupResult.success) {
          return backupResult;
        }
        _latestBackup = backupResult.backupInfo;
      }

      _databaseService.resetDatabase();
      _nasPaths = [];
      _effectMode = EffectMode.glass;
      _perDeviceEffect = true;
      _subtitlesEnabledByDefault = false;
      _preferredSubtitleLanguage = AppStrings.subtitleLangCodeDe;
      _subtitleScale = AppSpacing.subtitleScaleDefault;
      _subtitlePosition = AppSpacing.subtitlePositionDefault;
      _subtitleBgOpacity = AppSpacing.subtitleBgOpacityDefault;
      _hardwareAccelerationEnabled = true;

      final clearResult = await _cacheService.clearCacheWithResult(
        _databaseService,
      );
      _cacheBytes = clearResult.remainingBytes;
      _latestBackup = await _backupService.latestBackup();
      return backupResult;
    } finally {
      _isMaintenanceInProgress = false;
      _safeNotify();
    }
  }

  Future<void> resetDatabase() async {
    final result = await resetDatabaseWithBackup(requireBackup: true);
    if (!result.success) {
      throw StateError(
        result.errorMessage ?? AppStrings.backupFailedStatus,
      );
    }
  }

  Future<RestoreResult> restoreBackupFromPath(
    String backupPath, {
    Future<void> Function()? onStopJobs,
  }) async {
    _isMaintenanceInProgress = true;
    _safeNotify();
    try {
      if (onStopJobs != null) {
        await onStopJobs();
      }
      await _syncService.waitForIdle();
      final result = await _backupService.restoreBackup(
        _databaseService,
        backupPath,
      );
      if (result.success) {
        await load();
      } else {
        await refreshLatestBackup();
      }
      return result;
    } finally {
      _isMaintenanceInProgress = false;
      _safeNotify();
    }
  }

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
}
