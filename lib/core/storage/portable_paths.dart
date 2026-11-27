import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PortablePaths {
  PortablePaths._();

  @visibleForTesting
  static String? testBaseDirectoryOverride;

  static Future<String> resolveBaseDirectory() async {
    final override = testBaseDirectoryOverride;
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
