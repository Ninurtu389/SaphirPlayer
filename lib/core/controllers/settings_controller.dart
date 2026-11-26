import 'dart:io';
import 'package:flutter/foundation.dart';
import '../storage/database_service.dart';
import '../storage/portable_paths.dart';
import '../theme/effect_mode.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._databaseService);

  final DatabaseService _databaseService;

  static const String _nasPathKey = 'nas_root_path';
  static const String _globalEffectKey = 'effect_mode_global';

  String _nasPath = '';
  String _dataDirectoryPath = '';
  EffectMode _effectMode = EffectMode.glass;
  bool _perDeviceEffect = true;

  String get nasPath => _nasPath;
  String get dataDirectoryPath => _dataDirectoryPath;
  EffectMode get effectMode => _effectMode;
  bool get perDeviceEffect => _perDeviceEffect;

  String get _deviceEffectKey => 'effect_mode_${Platform.localHostname}';

  Future<void> load() async {
    _dataDirectoryPath = await PortablePaths.getDataDirectory();
    final db = _databaseService.instance;

    final nasRows = db.select(
      'SELECT value FROM app_settings WHERE key = ? LIMIT 1;',
      [_nasPathKey],
    );
    if (nasRows.isNotEmpty) {
      _nasPath = nasRows.first['value'] as String;
    }

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

  void updateNasPath(String value) {
    _nasPath = value.trim();
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
      [_nasPathKey, _nasPath],
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
}
