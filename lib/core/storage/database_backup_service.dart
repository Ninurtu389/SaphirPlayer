import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'database_service.dart';
import 'portable_paths.dart';

class BackupInfo {
  const BackupInfo({
    required this.filePath,
    required this.fileName,
    required this.createdAt,
    required this.sizeBytes,
    required this.schemaVersion,
    required this.reason,
  });

  final String filePath;
  final String fileName;
  final DateTime createdAt;
  final int sizeBytes;
  final int schemaVersion;
  final String reason;
}

class BackupResult {
  const BackupResult({
    required this.success,
    this.backupInfo,
    this.errorMessage,
  });

  final bool success;
  final BackupInfo? backupInfo;
  final String? errorMessage;
}

class RestoreResult {
  const RestoreResult({
    required this.success,
    this.preRestoreBackupPath,
    this.errorMessage,
  });

  final bool success;
  final String? preRestoreBackupPath;
  final String? errorMessage;
}

class DatabaseBackupService {
  DatabaseBackupService({
    StorageLayout? storageLayout,
    int maxRetention = 10,
    String? backupDirectoryOverride,
  })  : _storageLayout = storageLayout,
        _maxRetention = maxRetention < 1 ? 1 : maxRetention,
        _backupDirectoryOverride = backupDirectoryOverride;

  final StorageLayout? _storageLayout;
  final int _maxRetention;
  final String? _backupDirectoryOverride;

  static int _sequenceCounter = 0;

  static final RegExp _fileNamePattern = RegExp(
    r'^saphir_backup_v(\d+)_([a-z]+(?:_[a-z]+)*)_(\d+)(?:_(\d+))?\.db$',
  );

  Future<String> _resolveBackupDirectoryPath({
    required bool createIfMissing,
  }) async {
    final override = _backupDirectoryOverride;
    if (override != null && override.isNotEmpty) {
      if (createIfMissing) {
        final dir = Directory(override);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }
      return override;
    }
    final layoutDir = _storageLayout?.backupsDirectory;
    if (layoutDir != null && layoutDir.isNotEmpty) {
      if (createIfMissing) {
        final dir = Directory(layoutDir);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }
      return layoutDir;
    }
    if (!createIfMissing) {
      final base = await PortablePaths.resolveBaseDirectory();
      return p.join(base, 'backups');
    }
    return PortablePaths.getBackupsDirectory();
  }

  Future<String> resolveBackupDirectory() =>
      _resolveBackupDirectoryPath(createIfMissing: true);

  static Future<BackupInfo> createSnapshotFromDatabase(
    Database db, {
    required String backupDirPath,
    required String reason,
    int maxRetention = 10,
  }) async {
    final backupDir = Directory(backupDirPath);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final safeReason = reason
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final resolvedReason = safeReason.isEmpty ? 'manual' : safeReason;

    try {
      db.execute('PRAGMA wal_checkpoint(PASSIVE);');
    } on SqliteException {
      // Best-effort Checkpoint bei :memory: oder Read-Only-Zustand ignorieren
    }

    final versionRows = db.select('PRAGMA user_version;');
    final version = versionRows.isNotEmpty
        ? (versionRows.first.values.first as int? ?? 0)
        : 0;

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final seq = ++_sequenceCounter;
    final finalName =
        'saphir_backup_v${version}_${resolvedReason}_${stamp}_$seq.db';
    final finalPath = p.join(backupDirPath, finalName);
    final tempFile = File('$finalPath.tmp');

    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      db.execute('VACUUM INTO ?;', [tempFile.path]);

      final validation = validateBackupFile(
        tempFile.path,
        requireCoreTables: false,
      );
      if (!validation.valid) {
        throw StateError(
          validation.error ?? 'Backup-Integritätsprüfung fehlgeschlagen.',
        );
      }

      await tempFile.rename(finalPath);
      final finalFile = File(finalPath);
      final stat = await finalFile.stat();

      await _enforceRetention(backupDir, maxRetention);

      return BackupInfo(
        filePath: finalPath,
        fileName: finalName,
        createdAt: DateTime.fromMillisecondsSinceEpoch(stamp),
        sizeBytes: stat.size,
        schemaVersion: validation.schemaVersion,
        reason: resolvedReason,
      );
    } catch (_) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } on FileSystemException {
          // Best-effort Cleanup
        }
      }
      rethrow;
    }
  }

  static ({bool valid, int schemaVersion, String? error}) validateBackupFile(
    String backupPath, {
    bool requireCoreTables = true,
  }) {
    final file = File(backupPath);
    if (!file.existsSync()) {
      return (
        valid: false,
        schemaVersion: 0,
        error: 'Backup-Datei nicht gefunden.',
      );
    }
    try {
      if (file.lengthSync() <= 0) {
        return (
          valid: false,
          schemaVersion: 0,
          error: 'Backup-Datei ist leer.',
        );
      }
    } on FileSystemException catch (error) {
      return (valid: false, schemaVersion: 0, error: error.message);
    }

    Database? ro;
    try {
      ro = sqlite3.open(backupPath, mode: OpenMode.readOnly);
      final integrity = ro.select('PRAGMA integrity_check;');
      final firstVal = integrity.isNotEmpty
          ? (integrity.first.values.first?.toString().toLowerCase() ?? '')
          : '';
      if (firstVal != 'ok') {
        return (
          valid: false,
          schemaVersion: 0,
          error: 'Integritätsprüfung fehlgeschlagen ($firstVal).',
        );
      }

      final verRows = ro.select('PRAGMA user_version;');
      final version =
          verRows.isNotEmpty ? (verRows.first.values.first as int? ?? 0) : 0;
      if (version < 0 || version > DatabaseService.schemaVersion) {
        return (
          valid: false,
          schemaVersion: version,
          error: 'Nicht unterstützte Backup-Schema-Version ($version).',
        );
      }

      final tables = ro
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
          )
          .map((r) => r['name'] as String)
          .toSet();

      if (requireCoreTables) {
        const requiredTables = {
          'app_settings',
          'series',
          'episodes',
          'movies',
          'watch_progress',
        };
        if (!tables.containsAll(requiredTables)) {
          return (
            valid: false,
            schemaVersion: version,
            error: 'Backup enthält nicht alle Kerntabellen.',
          );
        }
      }

      return (valid: true, schemaVersion: version, error: null);
    } on SqliteException catch (error) {
      return (valid: false, schemaVersion: 0, error: error.message);
    } finally {
      ro?.dispose();
    }
  }

  Future<BackupResult> createBackup(
    DatabaseService databaseService, {
    String reason = 'manual',
  }) async {
    if (!databaseService.isOpen) {
      return const BackupResult(
        success: false,
        errorMessage: 'Datenbank ist nicht geöffnet.',
      );
    }
    try {
      final dirPath = await resolveBackupDirectory();
      final info = await createSnapshotFromDatabase(
        databaseService.instance,
        backupDirPath: dirPath,
        reason: reason,
        maxRetention: _maxRetention,
      );
      return BackupResult(success: true, backupInfo: info);
    } catch (error) {
      return BackupResult(
        success: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<List<BackupInfo>> listBackups() async {
    final dirPath = await _resolveBackupDirectoryPath(createIfMissing: false);
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return const [];
    }

    final backups = <BackupInfo>[];
    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final match = _fileNamePattern.firstMatch(name);
      if (match == null) continue;
      try {
        final stat = await entity.stat();
        final version = int.tryParse(match.group(1) ?? '') ?? 0;
        final reason = match.group(2) ?? 'manual';
        final ts = int.tryParse(match.group(3) ?? '') ??
            stat.modified.millisecondsSinceEpoch;
        backups.add(
          BackupInfo(
            filePath: entity.path,
            fileName: name,
            createdAt: DateTime.fromMillisecondsSinceEpoch(ts),
            sizeBytes: stat.size,
            schemaVersion: version,
            reason: reason,
          ),
        );
      } on FileSystemException {
        // Einzelne unlesbare Datei überspringen
      }
    }

    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  Future<BackupInfo?> latestBackup() async {
    final backups = await listBackups();
    return backups.isNotEmpty ? backups.first : null;
  }

  Future<RestoreResult> restoreBackup(
    DatabaseService databaseService,
    String backupPath,
  ) async {
    if (!databaseService.isOpen) {
      return const RestoreResult(
        success: false,
        errorMessage: 'Datenbank ist nicht geöffnet.',
      );
    }
    final liveDbPath = databaseService.currentDbPath;
    if (liveDbPath == null || liveDbPath == ':memory:') {
      return const RestoreResult(
        success: false,
        errorMessage:
            'Wiederherstellung für In-Memory-Datenbank nicht unterstützt.',
      );
    }

    final validation = validateBackupFile(backupPath, requireCoreTables: true);
    if (!validation.valid) {
      return RestoreResult(
        success: false,
        errorMessage: validation.error ?? 'Ungültige Backup-Datei.',
      );
    }

    final preRestore = await createBackup(
      databaseService,
      reason: 'pre_restore',
    );
    if (!preRestore.success || preRestore.backupInfo == null) {
      return RestoreResult(
        success: false,
        errorMessage: preRestore.errorMessage ??
            'Sicherung vor Wiederherstellung fehlgeschlagen.',
      );
    }
    final safetyPath = preRestore.backupInfo!.filePath;

    databaseService.close();
    final tempRestore = File('$liveDbPath.restoring');
    try {
      for (final suffix in const ['-wal', '-shm']) {
        final sidecar = File('$liveDbPath$suffix');
        if (await sidecar.exists()) {
          await sidecar.delete();
        }
      }
      final sourceFile = File(backupPath);
      final expectedBytes = await sourceFile.length();
      await sourceFile.copy(tempRestore.path);
      if (await tempRestore.length() != expectedBytes) {
        throw const FileSystemException('Kopierte Backup-Datei unvollständig.');
      }
      final liveFile = File(liveDbPath);
      if (await liveFile.exists()) {
        await liveFile.delete();
      }
      await tempRestore.rename(liveDbPath);

      await databaseService.open(dbPath: liveDbPath);
      return RestoreResult(
        success: true,
        preRestoreBackupPath: safetyPath,
      );
    } catch (error) {
      try {
        databaseService.close();
        if (await tempRestore.exists()) {
          await tempRestore.delete();
        }
        final safetyFile = File(safetyPath);
        if (await safetyFile.exists()) {
          final liveFile = File(liveDbPath);
          if (await liveFile.exists()) {
            await liveFile.delete();
          }
          await safetyFile.copy(liveDbPath);
          await databaseService.open(dbPath: liveDbPath);
        }
      } catch (_) {
        // Fallback-Wiederherstellung best-effort
      }
      return RestoreResult(
        success: false,
        preRestoreBackupPath: safetyPath,
        errorMessage: error.toString(),
      );
    }
  }

  static Future<void> _enforceRetention(
    Directory backupDir,
    int maxRetention,
  ) async {
    final files = <({File file, int ts})>[];
    await for (final entity
        in backupDir.list(recursive: false, followLinks: false)) {
      if (entity is! File) continue;
      final match = _fileNamePattern.firstMatch(p.basename(entity.path));
      if (match == null) continue;
      final ts = int.tryParse(match.group(3) ?? '') ?? 0;
      files.add((file: entity, ts: ts));
    }
    if (files.length <= maxRetention) return;
    files.sort((a, b) => b.ts.compareTo(a.ts));
    for (var i = maxRetention; i < files.length; i++) {
      try {
        await files[i].file.delete();
      } on FileSystemException {
        // Best-effort Cleanup alter Backups
      }
    }
  }
}
