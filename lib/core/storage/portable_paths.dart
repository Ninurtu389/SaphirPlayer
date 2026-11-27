import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PortablePaths {
  PortablePaths._();

  static String? _testBaseDirectoryOverride;
  static String? _cachedThumbDir;

  @visibleForTesting
  static String? get testBaseDirectoryOverride => _testBaseDirectoryOverride;

  @visibleForTesting
  static set testBaseDirectoryOverride(String? value) {
    _testBaseDirectoryOverride = value;
    _cachedThumbDir = null;
  }

  static Future<void> warmUp() async {
    _cachedThumbDir = await getCacheDirectory();
  }

  static String? resolveThumbnailPath(String? storedPath) {
    if (storedPath == null) {
      return null;
    }
    final trimmed = storedPath.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (p.isAbsolute(trimmed)) {
      return trimmed;
    }
    final cachedDir = _cachedThumbDir;
    if (cachedDir != null && cachedDir.isNotEmpty) {
      return p.join(cachedDir, trimmed);
    }
    final override = _testBaseDirectoryOverride;
    if (override != null && override.isNotEmpty) {
      return p.join(override, 'cache', 'thumbnails', trimmed);
    }
    return trimmed;
  }

  static Future<String> resolveBaseDirectory() async {
    final override = _testBaseDirectoryOverride;
    if (override != null && override.isNotEmpty) {
      return override;
    }

    final exeDir = p.dirname(Platform.resolvedExecutable);
    final markerFile = File(p.join(exeDir, 'portable.flag'));
    final dataDir = Directory(p.join(exeDir, 'data'));

    if (await markerFile.exists() || await dataDir.exists()) {
      return exeDir;
    }

    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, 'SaphirPlayer');
  }

  static Future<String> getDataDirectory() async {
    final baseDir = await resolveBaseDirectory();
    final dir = Directory(p.join(baseDir, 'data'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<String> getCacheDirectory() async {
    final baseDir = await resolveBaseDirectory();
    final dir = Directory(p.join(baseDir, 'cache', 'thumbnails'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedThumbDir = dir.path;
    return dir.path;
  }

  static Future<String> getScreenshotsDirectory() async {
    final baseDir = await resolveBaseDirectory();
    final dir = Directory(p.join(baseDir, 'screenshots'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<String> getDatabaseFilePath() async {
    final dataDir = await getDataDirectory();
    return p.join(dataDir, 'saphir_player.db');
  }
}
