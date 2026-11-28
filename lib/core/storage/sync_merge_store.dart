import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'sync_key_utils.dart';
import 'sync_models.dart';

class SyncMergeStore {
  SyncMergeStore._();

  static Map<String, SyncEntry> loadLocalEntries(Database db) {
    final rows = db.select(
      '''
      SELECT media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device
      FROM watch_progress;
      ''',
    );
    return {
      for (final row in rows)
        row['media_key'] as String: SyncEntry(
          mediaKey: row['media_key'] as String,
          mediaType: row['media_type'] as String,
          positionMs: row['position_ms'] as int,
          durationMs: row['duration_ms'] as int,
          completed: (row['completed'] as int) == 1,
          updatedAt: row['updated_at'] as int,
          sourceDevice: row['source_device'] as String,
        ),
    };
  }

  static Map<String, SyncEntry> mergeAndPersistToDb(
    Database db,
    Map<String, SyncEntry> localEntries,
    Map<String, SyncEntry> remoteEntries,
  ) {
    final mergedEntries = <String, SyncEntry>{...remoteEntries};

    db.execute('BEGIN TRANSACTION;');
    try {
      for (final entry in localEntries.entries) {
        final key = entry.key;
        final local = entry.value;
        final remote = remoteEntries[key];

        if (remote == null) {
          mergedEntries[key] = local;
          continue;
        }

        final winner = SyncEntry.resolveConflict(local, remote);
        if (identical(winner, local)) {
          final nextRev = local.samePayloadAs(remote)
              ? remote.revision
              : (remote.revision + 1);
          mergedEntries[key] = local.copyWith(revision: nextRev);
        } else {
          mergedEntries[key] = remote;
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
              remote.mediaType,
              remote.positionMs,
              remote.durationMs,
              remote.completed ? 1 : 0,
              remote.updatedAt,
              remote.sourceDevice,
            ],
          );
        }
      }

      for (final entry in remoteEntries.entries) {
        if (localEntries.containsKey(entry.key)) continue;
        final remote = entry.value;
        db.execute(
          '''
          INSERT OR IGNORE INTO watch_progress (
            media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device
          )
          VALUES (?, ?, ?, ?, ?, ?, ?);
          ''',
          [
            entry.key,
            remote.mediaType,
            remote.positionMs,
            remote.durationMs,
            remote.completed ? 1 : 0,
            remote.updatedAt,
            remote.sourceDevice,
          ],
        );
      }

      db.execute('COMMIT;');
      return mergedEntries;
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static Map<String, String> buildLegacyV1ToV2Map(Database db) {
    final map = <String, String>{};
    final sourceRows = db.select('SELECT root_path FROM media_sources;');
    final roots = [for (final r in sourceRows) r['root_path'] as String];
    if (roots.isEmpty) return map;

    void addRows(String table, String prefix) {
      final rows = db.select(
        "SELECT file_path, sync_key FROM $table WHERE sync_key IS NOT NULL AND sync_key != '';",
      );
      for (final row in rows) {
        final filePath = row['file_path'] as String;
        final v2Key = row['sync_key'] as String;
        final bestRoot = _findBestRoot(filePath, roots);
        if (bestRoot != null) {
          final v1Key = SyncKeyUtils.buildLegacyV1SyncKey(
            prefix,
            filePath,
            bestRoot,
          );
          if (v1Key != v2Key) {
            map[v1Key] = v2Key;
          }
        }
      }
    }

    addRows('episodes', 'ep');
    addRows('movies', 'mv');
    return map;
  }

  static String? _findBestRoot(String filePath, List<String> roots) {
    final normFile =
        p.normalize(filePath.trim()).replaceAll('\\', '/').toLowerCase();
    String? bestRoot;
    for (final root in roots) {
      final normRoot = SyncKeyUtils.normalizeRootPath(root);
      if (normFile == normRoot || normFile.startsWith('$normRoot/')) {
        if (bestRoot == null || root.length > bestRoot.length) {
          bestRoot = root;
        }
      }
    }
    return bestRoot;
  }

  static Map<String, SyncEntry> remapEntries(
    Map<String, SyncEntry> raw,
    Map<String, String> v1ToV2,
  ) {
    if (v1ToV2.isEmpty) return raw;
    final remapped = <String, SyncEntry>{};
    for (final entry in raw.entries) {
      final targetKey = v1ToV2[entry.key] ?? entry.key;
      final candidate = targetKey == entry.key
          ? entry.value
          : SyncEntry(
              mediaKey: targetKey,
              mediaType: entry.value.mediaType,
              positionMs: entry.value.positionMs,
              durationMs: entry.value.durationMs,
              completed: entry.value.completed,
              updatedAt: entry.value.updatedAt,
              sourceDevice: entry.value.sourceDevice,
              revision: entry.value.revision,
            );
      final existing = remapped[targetKey];
      remapped[targetKey] = existing == null
          ? candidate
          : SyncEntry.resolveConflict(existing, candidate);
    }
    return remapped;
  }

  static void normalizeLocalLegacyKeys(Database db) {
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
}
