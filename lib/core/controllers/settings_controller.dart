import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../storage/database_service.dart';
import '../storage/portable_paths.dart';
import '../theme/effect_mode.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._databaseService);

  final DatabaseService _databaseService;

  static const String _nasPathKey = 'nas_root_path';
  static const String _nasPathsKey = 'nas_root_paths';
  static const String _globalEffectKey = 'effect_mode_global';

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

  String get _deviceEffectKey => 'effect_mode_${Platform.localHostname}';

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

    notifyListeners();
  }

  Future<void> refreshCacheSize() async {
    final cachePath = await PortablePaths.getCacheDirectory();
    final cacheDir = Directory(cachePath);
    var totalBytes = 0;

    if (await cacheDir.exists()) {
      await for (final entity
          in cacheDir.list(recursive: false, followLinks: false)) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }
    }

    _cacheBytes = totalBytes;
    notifyListeners();
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
    notifyListeners();
  }
}
