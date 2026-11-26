import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'database_service.dart';
import 'portable_paths.dart';

class ProgressSyncService {
  ProgressSyncService(this._databaseService);

  final DatabaseService _databaseService;
  static const String _syncFileName = 'progress_sync.json';

  Future<String> _resolveSyncFilePath(String nasRootPath) async {
    final trimmed = nasRootPath.trim();
    if (trimmed.isNotEmpty) {
      final nasDir = Directory(trimmed);
      if (await nasDir.exists()) {
        return p.join(trimmed, _syncFileName);
      }
    }
    final dataDir = await PortablePaths.getDataDirectory();
    return p.join(dataDir, _syncFileName);
  }

  Future<void> syncWithRoots(List<String> nasRootPaths) async {
    for (final root in nasRootPaths) {
      final trimmed = root.trim();
      if (trimmed.isNotEmpty && await Directory(trimmed).exists()) {
        await syncWithStorage(trimmed);
        return;
      }
    }
    await syncWithStorage('');
  }

  Future<void> syncWithStorage(String nasRootPath) async {
    final syncPath = await _resolveSyncFilePath(nasRootPath);
    final syncFile = File(syncPath);
    final db = _databaseService.instance;

    final remoteEntries = <String, Map<String, dynamic>>{};

    if (await syncFile.exists()) {
      try {
        final raw = await syncFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final items = decoded['entries'];
          if (items is Map<String, dynamic>) {
            for (final entry in items.entries) {
              if (entry.value is Map<String, dynamic>) {
                remoteEntries[entry.key] = Map<String, dynamic>.from(
                  entry.value as Map<String, dynamic>,
                );
              }
            }
          }
        }
      } on FileSystemException {
        // Lokalen Stand beibehalten, falls Netzzugriff kurz unterbrochen ist
      } on FormatException {
        // Beschädigte Sync-Datei nicht zum Absturz führen lassen
      }
    }

    final localRows = db.select(
      '''
      SELECT media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device
      FROM watch_progress;
      ''',
    );

    final mergedEntries = <String, Map<String, dynamic>>{...remoteEntries};

    db.execute('BEGIN TRANSACTION;');
    try {
      for (final row in localRows) {
        final key = row['media_key'] as String;
        final localUpdated = row['updated_at'] as int;
        final localMap = {
          'media_type': row['media_type'] as String,
          'position_ms': row['position_ms'] as int,
          'duration_ms': row['duration_ms'] as int,
          'completed': (row['completed'] as int) == 1,
          'updated_at': localUpdated,
          'source_device': row['source_device'] as String,
        };

        final existingRemote = mergedEntries[key];
        final remoteUpdated = (existingRemote?['updated_at'] as int?) ?? 0;

        if (existingRemote == null || localUpdated >= remoteUpdated) {
          mergedEntries[key] = localMap;
        } else {
          final remotePos = (existingRemote['position_ms'] as int?) ?? 0;
          final remoteDur = (existingRemote['duration_ms'] as int?) ?? 0;
          final remoteCompleted =
              (existingRemote['completed'] as bool?) == true ? 1 : 0;
          final remoteDevice =
              (existingRemote['source_device'] as String?) ?? 'remote';
          final remoteType =
              (existingRemote['media_type'] as String?) ?? 'episode';

          db.execute(
            '''
            INSERT INTO watch_progress (
              media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(media_key) DO UPDATE SET
              media_type = excluded.media_type,
              position_ms = excluded.position_ms,
              duration_ms = excluded.duration_ms,
              completed = excluded.completed,
              updated_at = excluded.updated_at,
              source_device = excluded.source_device;
            ''',
            [
              key,
              remoteType,
              remotePos,
              remoteDur,
              remoteCompleted,
              remoteUpdated,
              remoteDevice,
            ],
          );
        }
      }

      for (final entry in remoteEntries.entries) {
        final key = entry.key;
        final remoteMap = entry.value;
        final remoteUpdated = (remoteMap['updated_at'] as int?) ?? 0;
        final alreadyInLocal =
            localRows.any((r) => (r['media_key'] as String) == key);

        if (!alreadyInLocal) {
          final remotePos = (remoteMap['position_ms'] as int?) ?? 0;
          final remoteDur = (remoteMap['duration_ms'] as int?) ?? 0;
          final remoteCompleted =
              (remoteMap['completed'] as bool?) == true ? 1 : 0;
          final remoteDevice =
              (remoteMap['source_device'] as String?) ?? 'remote';
          final remoteType = (remoteMap['media_type'] as String?) ?? 'episode';

          db.execute(
            '''
            INSERT OR IGNORE INTO watch_progress (
              media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device
            )
            VALUES (?, ?, ?, ?, ?, ?, ?);
            ''',
            [
              key,
              remoteType,
              remotePos,
              remoteDur,
              remoteCompleted,
              remoteUpdated,
              remoteDevice,
            ],
          );
        }
      }

      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }

    try {
      final payload = jsonEncode({
        'version': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'entries': mergedEntries,
      });
      await syncFile.writeAsString(payload, flush: true);
    } on FileSystemException {
      // Lokaler Fortschritt bleibt erhalten, falls NAS gerade nicht beschreibbar ist
    }
  }
}
