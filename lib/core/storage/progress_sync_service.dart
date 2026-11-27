import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'database_service.dart';
import 'portable_paths.dart';

class SyncResult {
  const SyncResult({
    required this.syncedToNas,
    required this.targetPath,
  });

  final bool syncedToNas;
  final String targetPath;
}

class ProgressSyncService {
  ProgressSyncService(this._databaseService);

  final DatabaseService _databaseService;
  static const String _syncFileName = 'progress_sync.json';
  Future<void> _syncQueue = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    Zone.root.run(() {
      _syncQueue = _syncQueue.then(
        (_) => _runTask(task, completer),
        onError: (_) => _runTask(task, completer),
      );
    });
    return completer.future;
  }

  Future<void> _runTask<T>(
    Future<T> Function() task,
    Completer<T> completer,
  ) async {
    try {
      final result = await task();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    } catch (e, st) {
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
    }
  }

  Future<({String path, bool isNas})> _resolveSyncTarget(
    String nasRootPath,
  ) async {
    final trimmed = nasRootPath.trim();
    if (trimmed.isNotEmpty) {
      final nasDir = Directory(trimmed);
      if (await nasDir.exists()) {
        return (path: p.join(trimmed, _syncFileName), isNas: true);
      }
    }
    final dataDir = await PortablePaths.getDataDirectory();
    return (path: p.join(dataDir, _syncFileName), isNas: false);
  }

  Future<SyncResult> syncWithRoots(List<String> nasRootPaths) {
    return _enqueue(() async {
      for (final root in nasRootPaths) {
        final trimmed = root.trim();
        if (trimmed.isNotEmpty && await Directory(trimmed).exists()) {
          return _performSync(trimmed);
        }
      }
      return _performSync('');
    });
  }

  Future<SyncResult> syncWithStorage(String nasRootPath) {
    return _enqueue(() => _performSync(nasRootPath));
  }

  Future<SyncResult> _performSync(String nasRootPath) async {
    if (!_databaseService.isOpen) {
      return const SyncResult(syncedToNas: false, targetPath: '');
    }
    final target = await _resolveSyncTarget(nasRootPath);
    if (!_databaseService.isOpen) {
      return SyncResult(syncedToNas: false, targetPath: target.path);
    }
    final syncPath = target.path;
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

    if (!_databaseService.isOpen) {
      return SyncResult(syncedToNas: false, targetPath: syncPath);
    }

    _normalizeLocalLegacyKeys(db);

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

    var writeSucceeded = false;
    final tmpFile = File('$syncPath.tmp');
    try {
      final payload = jsonEncode({
        'version': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'entries': mergedEntries,
      });
      await tmpFile.writeAsString(payload, flush: true);
      await tmpFile.rename(syncPath);
      writeSucceeded = true;
    } on FileSystemException {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } on FileSystemException {
          // Best-effort Cleanup fehlgeschlagener Temp-Datei
        }
      }
    }

    return SyncResult(
      syncedToNas: target.isNas && writeSucceeded,
      targetPath: syncPath,
    );
  }

  void _normalizeLocalLegacyKeys(Database db) {
    final mappings = <(String legacyKey, String syncKey)>[];
    final epRows = db.select(
      "SELECT id, sync_key FROM episodes WHERE sync_key IS NOT NULL AND sync_key != '';",
    );
    for (final row in epRows) {
      mappings.add(('episode_${row['id']}', row['sync_key'] as String));
    }
    final mvRows = db.select(
      "SELECT id, sync_key FROM movies WHERE sync_key IS NOT NULL AND sync_key != '';",
    );
    for (final row in mvRows) {
      mappings.add(('movie_${row['id']}', row['sync_key'] as String));
    }
    if (mappings.isEmpty) {
      return;
    }

    db.execute('BEGIN TRANSACTION;');
    try {
      for (final (legacyKey, syncKey) in mappings) {
        final legacyRows = db.select(
          'SELECT * FROM watch_progress WHERE media_key = ? LIMIT 1;',
          [legacyKey],
        );
        if (legacyRows.isEmpty) continue;
        final existingNew = db.select(
          'SELECT updated_at FROM watch_progress WHERE media_key = ? LIMIT 1;',
          [syncKey],
        );
        if (existingNew.isEmpty) {
          db.execute(
            'UPDATE watch_progress SET media_key = ? WHERE media_key = ?;',
            [syncKey, legacyKey],
          );
        } else {
          final oldRow = legacyRows.first;
          final oldUpdated = (oldRow['updated_at'] as int?) ?? 0;
          final newUpdated = (existingNew.first['updated_at'] as int?) ?? 0;
          if (oldUpdated > newUpdated) {
            db.execute(
              '''
              UPDATE watch_progress
              SET position_ms = ?, duration_ms = ?, completed = ?, updated_at = ?, source_device = ?
              WHERE media_key = ?;
              ''',
              [
                oldRow['position_ms'],
                oldRow['duration_ms'],
                oldRow['completed'],
                oldUpdated,
                oldRow['source_device'],
                syncKey,
              ],
            );
          }
          db.execute(
            'DELETE FROM watch_progress WHERE media_key = ?;',
            [legacyKey],
          );
        }
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
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
