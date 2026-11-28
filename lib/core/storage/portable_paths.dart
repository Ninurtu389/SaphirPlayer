import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum StorageMode {
  standard,
  portable,
}

class StorageAccessException implements Exception {
  const StorageAccessException({
    required this.path,
    required this.mode,
    required this.message,
    this.cause,
  });

  final String path;
  final StorageMode mode;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final modeLabel = mode == StorageMode.portable ? 'portable' : 'standard';
    final causeSuffix = cause != null ? ' ($cause)' : '';
    return 'StorageAccessException[$modeLabel] "$path": $message$causeSuffix';
  }
}

class StorageLayout {
  const StorageLayout({
    required this.mode,
    required this.baseDirectory,
    required this.dataDirectory,
    required this.cacheDirectory,
    required this.screenshotsDirectory,
    required this.databaseFilePath,
    String? backupsDirectory,
    this.legacyPortableDbPath,
  }) : _backupsDirectory = backupsDirectory;

  final StorageMode mode;
  final String baseDirectory;
  final String dataDirectory;
  final String cacheDirectory;
  final String screenshotsDirectory;
  final String databaseFilePath;
  final String? _backupsDirectory;
  final String? legacyPortableDbPath;

  String get backupsDirectory =>
      _backupsDirectory ?? p.join(baseDirectory, 'backups');

  bool get isPortable => mode == StorageMode.portable;
  bool get hasLegacyMigrationCandidate => legacyPortableDbPath != null;

  String? resolveThumbnailPath(String? storedPath) {
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
    return p.join(cacheDirectory, trimmed);
  }
}

class PortablePaths {
  PortablePaths._();

  static const String portableFlagFileName = 'portable.flag';
  static const String appFolderName = 'SaphirPlayer';
  static const String databaseFileName = 'saphir_player.db';
  static const String _probeContent = 'saphir_probe_ok';

  static String? _testBaseDirectoryOverride;
  static String? _cachedThumbDir;
  static StorageLayout? _activeLayout;

  static StorageLayout? get activeLayout => _activeLayout;

  @visibleForTesting
  static String? get testBaseDirectoryOverride => _testBaseDirectoryOverride;

  @visibleForTesting
  static set testBaseDirectoryOverride(String? value) {
    _testBaseDirectoryOverride = value;
    _activeLayout = null;
    _cachedThumbDir = null;
  }

  @visibleForTesting
  static void resetForTesting() {
    _testBaseDirectoryOverride = null;
    _activeLayout = null;
    _cachedThumbDir = null;
  }

  static StorageLayout _buildLayout({
    required StorageMode mode,
    required String baseDirectory,
    String? legacyPortableDbPath,
  }) {
    final dataDir = p.join(baseDirectory, 'data');
    return StorageLayout(
      mode: mode,
      baseDirectory: baseDirectory,
      dataDirectory: dataDir,
      cacheDirectory: p.join(baseDirectory, 'cache', 'thumbnails'),
      screenshotsDirectory: p.join(baseDirectory, 'screenshots'),
      databaseFilePath: p.join(dataDir, databaseFileName),
      backupsDirectory: p.join(baseDirectory, 'backups'),
      legacyPortableDbPath: legacyPortableDbPath,
    );
  }

  static Future<StorageLayout> resolveLayout({
    String? executablePath,
    Future<Directory> Function()? appSupportDirectoryProvider,
    String? baseDirectoryOverride,
  }) async {
    final effectiveOverride =
        baseDirectoryOverride ?? _testBaseDirectoryOverride;
    if (effectiveOverride != null && effectiveOverride.isNotEmpty) {
      return _buildLayout(
        mode: StorageMode.portable,
        baseDirectory: effectiveOverride,
      );
    }

    final exeDir = p.dirname(executablePath ?? Platform.resolvedExecutable);
    var hasPortableFlag = false;
    try {
      hasPortableFlag =
          await File(p.join(exeDir, portableFlagFileName)).exists();
    } on FileSystemException {
      hasPortableFlag = false;
    }

    if (hasPortableFlag) {
      return _buildLayout(
        mode: StorageMode.portable,
        baseDirectory: exeDir,
      );
    }

    final supportDir =
        await (appSupportDirectoryProvider ?? getApplicationSupportDirectory)();
    final baseDir = p.join(supportDir.path, appFolderName);
    final targetDbPath = p.join(baseDir, 'data', databaseFileName);
    String? legacyPortableDbPath;
    try {
      final legacyFile = File(p.join(exeDir, 'data', databaseFileName));
      final targetFile = File(targetDbPath);
      if (!await targetFile.exists() &&
          await legacyFile.exists() &&
          await legacyFile.length() > 0) {
        legacyPortableDbPath = legacyFile.path;
      }
    } on FileSystemException {
      legacyPortableDbPath = null;
    }

    return _buildLayout(
      mode: StorageMode.standard,
      baseDirectory: baseDir,
      legacyPortableDbPath: legacyPortableDbPath,
    );
  }

  static Future<void> verifyDirectoryWritable(
    String dirPath, {
    required StorageMode mode,
  }) async {
    final dir = Directory(dirPath);
    File? probeFile;
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final probeName =
          '.saphir_write_probe_${pid}_${DateTime.now().microsecondsSinceEpoch}.tmp';
      probeFile = File(p.join(dirPath, probeName));
      await probeFile.writeAsString(_probeContent, flush: true);
      final readBack = await probeFile.readAsString();
      if (readBack != _probeContent) {
        throw StorageAccessException(
          path: dirPath,
          mode: mode,
          message: 'Schreib-/Lesetest fehlgeschlagen (Inhalt weicht ab).',
        );
      }
    } on StorageAccessException {
      rethrow;
    } on FileSystemException catch (error) {
      throw StorageAccessException(
        path: dirPath,
        mode: mode,
        message: 'Speicherverzeichnis ist nicht beschreibbar.',
        cause: error,
      );
    } on IOException catch (error) {
      throw StorageAccessException(
        path: dirPath,
        mode: mode,
        message: 'Speicherverzeichnis ist nicht les- oder beschreibbar.',
        cause: error,
      );
    } finally {
      if (probeFile != null) {
        try {
          if (await probeFile.exists()) {
            await probeFile.delete();
          }
        } on FileSystemException {
          // Best-effort Cleanup der Probe-Datei
        }
      }
    }
  }

  static Future<StorageLayout> initialize({
    String? executablePath,
    Future<Directory> Function()? appSupportDirectoryProvider,
    String? baseDirectoryOverride,
  }) async {
    final layout = await resolveLayout(
      executablePath: executablePath,
      appSupportDirectoryProvider: appSupportDirectoryProvider,
      baseDirectoryOverride: baseDirectoryOverride,
    );
    await verifyDirectoryWritable(layout.dataDirectory, mode: layout.mode);
    await verifyDirectoryWritable(layout.cacheDirectory, mode: layout.mode);
    _activeLayout = layout;
    _cachedThumbDir = layout.cacheDirectory;
    return layout;
  }

  static Future<StorageLayout> warmUp() => initialize();

  static Future<StorageLayout> _ensureLayout() async {
    final existing = _activeLayout;
    if (existing != null) {
      return existing;
    }
    final resolved = await resolveLayout();
    _activeLayout = resolved;
    _cachedThumbDir = resolved.cacheDirectory;
    return resolved;
  }

  static Future<String> migrateLegacyDatabase(StorageLayout layout) async {
    final sourcePath = layout.legacyPortableDbPath;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw StateError('Kein Legacy-Migrationspfad vorhanden.');
    }
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StorageAccessException(
        path: sourcePath,
        mode: layout.mode,
        message: 'Quell-Datenbank für Legacy-Migration nicht gefunden.',
      );
    }
    final targetFile = File(layout.databaseFilePath);
    if (await targetFile.exists()) {
      throw StorageAccessException(
        path: layout.databaseFilePath,
        mode: layout.mode,
        message:
            'Zieldatenbank existiert bereits und wird nicht überschrieben.',
      );
    }

    await verifyDirectoryWritable(layout.dataDirectory, mode: layout.mode);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final backupDir = Directory(
      p.join(layout.dataDirectory, 'legacy_migration_backup_$stamp'),
    );
    await backupDir.create(recursive: true);

    const suffixes = ['', '-wal', '-shm'];
    for (final suffix in suffixes) {
      final src = File('$sourcePath$suffix');
      if (!await src.exists()) continue;
      final expectedBytes = await src.length();
      final backupCopy =
          File(p.join(backupDir.path, '$databaseFileName$suffix'));
      await src.copy(backupCopy.path);
      if (await backupCopy.length() != expectedBytes) {
        throw StorageAccessException(
          path: backupCopy.path,
          mode: layout.mode,
          message: 'Sicherungskopie unvollständig.',
        );
      }
    }

    for (final suffix in suffixes) {
      final src = File('$sourcePath$suffix');
      if (!await src.exists()) continue;
      final expectedBytes = await src.length();
      final target = File('${layout.databaseFilePath}$suffix');
      final tempTarget = File('${target.path}.migrating_$stamp');
      await src.copy(tempTarget.path);
      if (await tempTarget.length() != expectedBytes) {
        throw StorageAccessException(
          path: tempTarget.path,
          mode: layout.mode,
          message: 'Migrierte Datenbankdatei unvollständig.',
        );
      }
      await tempTarget.rename(target.path);
    }

    return backupDir.path;
  }

  static String? resolveThumbnailPath(String? storedPath) {
    final active = _activeLayout;
    if (active != null) {
      return active.resolveThumbnailPath(storedPath);
    }
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
    return (await _ensureLayout()).baseDirectory;
  }

  static Future<String> getDataDirectory() async {
    final layout = await _ensureLayout();
    final dir = Directory(layout.dataDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<String> getCacheDirectory() async {
    final layout = await _ensureLayout();
    final dir = Directory(layout.cacheDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedThumbDir = dir.path;
    return dir.path;
  }

  static Future<String> getScreenshotsDirectory() async {
    final layout = await _ensureLayout();
    final dir = Directory(layout.screenshotsDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<String> getBackupsDirectory() async {
    final layout = await _ensureLayout();
    final dir = Directory(layout.backupsDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static Future<String> getDatabaseFilePath() async {
    final layout = await _ensureLayout();
    await getDataDirectory();
    return layout.databaseFilePath;
  }
}
