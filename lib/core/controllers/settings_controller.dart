import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/desktop_platform_service.dart';
import '../storage/database_service.dart';
import '../storage/portable_paths.dart';
import '../storage/progress_sync_service.dart';
import '../theme/effect_mode.dart';
import '../utils/formatters.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(
    this._databaseService, {
    ProgressSyncService? syncService,
  }) : _syncService = syncService ?? ProgressSyncService(_databaseService);

  final DatabaseService _databaseService;
  final ProgressSyncService _syncService;

  static const String _nasPathKey = 'nas_root_path';
  static const String _nasPathsKey = 'nas_root_paths';
  static const String _globalEffectKey = 'effect_mode_global';

  bool _isDisposed = false;
  List<String> _nasPaths = [];
  String _dataDirectoryPath = '';
  EffectMode _effectMode = EffectMode.glass;
  bool _perDeviceEffect = true;
  int _cacheBytes = 0;

  List<String> get nasPaths => List.unmodifiable(_nasPaths);
  String get nasPath => _nasPaths.isNotEmpty ? _nasPaths.first : '';
  String get dataDirectoryPath => _dataDirectoryPath;
  EffectMode get effectMode => _effectMode;
  bool get perDeviceEffect => _perDeviceEffect;
  int get cacheBytes => _cacheBytes;
  String get formattedCacheSize => Formatters.formatCacheSize(_cacheBytes);

  String get _deviceEffectKey =>
      'effect_mode_${DesktopPlatformService.localHostname}';

  Future<void> syncProgress() async {
    await _syncService.syncWithRoots(_nasPaths);
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
    _dataDirectoryPath = await PortablePaths.getDataDirectory();
    await refreshCacheSize();
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

    _safeNotify();
  }

  Future<void> refreshCacheSize() async {
    final cachePath = await PortablePaths.getCacheDirectory();
    final cacheDir = Directory(cachePath);
    var totalBytes = 0;

    if (await cacheDir.exists()) {
      await for (final entity
          in cacheDir.list(recursive: false, followLinks: false)) {
        if (entity is File) {
          try {
            totalBytes += await entity.length();
          } on FileSystemException {
            // Einzelne gesperrte Datei ignorieren
          }
        }
      }
    }

    _cacheBytes = totalBytes;
    _safeNotify();
  }

  Future<void> clearThumbnailCache() async {
    final cachePath = await PortablePaths.getCacheDirectory();
    final cacheDir = Directory(cachePath);

    if (await cacheDir.exists()) {
      await for (final entity
          in cacheDir.list(recursive: false, followLinks: false)) {
        if (entity is File) {
          try {
            await entity.delete();
          } on FileSystemException {
            // Einzelne gesperrte Datei überspringen
          }
        }
      }
    }

    final db = _databaseService.instance;
    db.execute('UPDATE episodes SET thumb_path = NULL;');
    db.execute('UPDATE movies SET thumb_path = NULL;');
    await refreshCacheSize();
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

  bool addNasPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final added = _addUniquePath(_nasPaths, trimmed);
    if (!added) {
      return false;
    }
    save();
    return true;
  }

  void removeNasPath(String path) {
    final normalized = path.trim().toLowerCase();
    _nasPaths.removeWhere((p) => p.toLowerCase() == normalized);
    save();
  }

  void updateNasPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _nasPaths = [];
    } else if (_nasPaths.isEmpty) {
      _nasPaths = [trimmed];
    } else {
      _nasPaths[0] = trimmed;
    }
    notifyListeners();
  }

  void updateEffectMode(EffectMode mode) {
    _effectMode = mode;
    notifyListeners();
  }

  void updatePerDeviceEffect(bool enabled) {
    _perDeviceEffect = enabled;
    notifyListeners();
  }

  void save() {
    final db = _databaseService.instance;
    db.execute(
      '''
      INSERT INTO app_settings (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value;
      ''',
      [_nasPathsKey, jsonEncode(_nasPaths)],
    );
    db.execute(
      '''
      INSERT INTO app_settings (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value;
      ''',
      [_nasPathKey, nasPath],
    );

    if (_perDeviceEffect) {
      db.execute(
        '''
        INSERT INTO app_settings (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        ''',
        [_deviceEffectKey, _effectMode.toStorage()],
      );
    } else {
      db.execute(
        'DELETE FROM app_settings WHERE key = ?;',
        [_deviceEffectKey],
      );
      db.execute(
        '''
        INSERT INTO app_settings (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        ''',
        [_globalEffectKey, _effectMode.toStorage()],
      );
    }

    notifyListeners();
  }

  Future<void> resetDatabase() async {
    _databaseService.resetDatabase();
    _nasPaths = [];
    _effectMode = EffectMode.glass;
    _perDeviceEffect = true;
    await clearThumbnailCache();
    _safeNotify();
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
