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
    final localKeys = <String>{
      for (final row in localRows) row['media_key'] as String,
    };

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
        final remoteUpdated = _asInt(existingRemote?['updated_at']);

        if (existingRemote == null || localUpdated >= remoteUpdated) {
          mergedEntries[key] = localMap;
        } else {
          final remotePos = _asInt(existingRemote['position_ms']);
          final remoteDur = _asInt(existingRemote['duration_ms']);
          final remoteCompleted = _asBool(existingRemote['completed']) ? 1 : 0;
          final remoteDevice =
              _asString(existingRemote['source_device'], fallback: 'remote');
          final remoteType =
              _asString(existingRemote['media_type'], fallback: 'episode');

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
        final remoteUpdated = _asInt(remoteMap['updated_at']);
        final alreadyInLocal = localKeys.contains(key);

        if (!alreadyInLocal) {
          final remotePos = _asInt(remoteMap['position_ms']);
          final remoteDur = _asInt(remoteMap['duration_ms']);
          final remoteCompleted = _asBool(remoteMap['completed']) ? 1 : 0;
          final remoteDevice =
              _asString(remoteMap['source_device'], fallback: 'remote');
          final remoteType =
              _asString(remoteMap['media_type'], fallback: 'episode');

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

  static int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    return false;
  }

  static String _asString(Object? value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return fallback;
  }
}
