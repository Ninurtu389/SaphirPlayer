import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'sync_key_utils.dart';

class DatabaseMigrations {
  DatabaseMigrations._();

  static void migrate(Database db, int fromVersion) {
    if (fromVersion < 2) {
      final columns = db.select('PRAGMA table_info(series_preferences);');
      final hasIntroSkip = columns.any(
        (col) => col['name'] == 'intro_skip_seconds',
      );
      if (!hasIntroSkip) {
        db.execute(
          'ALTER TABLE series_preferences ADD COLUMN intro_skip_seconds INTEGER NOT NULL DEFAULT 0;',
        );
      }
      db.execute('''
        CREATE TABLE IF NOT EXISTS media_bookmarks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          media_key TEXT NOT NULL,
          position_ms INTEGER NOT NULL,
          label TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL
        );
      ''');
    }

    if (fromVersion < 3) {
      _ensureColumn(db, 'episodes', 'sync_key', 'TEXT');
      _ensureColumn(
        db,
        'episodes',
        'thumb_status',
        "TEXT NOT NULL DEFAULT 'pending'",
      );
      _ensureColumn(db, 'movies', 'sync_key', 'TEXT');
      _ensureColumn(
        db,
        'movies',
        'thumb_status',
        "TEXT NOT NULL DEFAULT 'pending'",
      );

      db.execute(
        "UPDATE episodes SET thumb_status = 'ready' WHERE thumb_path IS NOT NULL AND thumb_path != '';",
      );
      db.execute(
        "UPDATE movies SET thumb_status = 'ready' WHERE thumb_path IS NOT NULL AND thumb_path != '';",
      );

      final roots = _readConfiguredRoots(db);
      db.execute('BEGIN TRANSACTION;');
      try {
        _backfillLegacyV1Keys(
          db,
          table: 'episodes',
          prefix: 'ep',
          legacyPrefix: 'episode_',
          roots: roots,
        );
        _backfillLegacyV1Keys(
          db,
          table: 'movies',
          prefix: 'mv',
          legacyPrefix: 'movie_',
          roots: roots,
        );
        db.execute('COMMIT;');
      } catch (_) {
        db.execute('ROLLBACK;');
        rethrow;
      }
    }

    if (fromVersion < 4) {
      _ensureColumn(db, 'episodes', 'artist', 'TEXT');
      _ensureColumn(db, 'episodes', 'file_size', 'INTEGER NOT NULL DEFAULT 0');
      _ensureColumn(
        db,
        'episodes',
        'modified_at',
        'INTEGER NOT NULL DEFAULT 0',
      );
      _ensureColumn(db, 'movies', 'artist', 'TEXT');
      _ensureColumn(db, 'movies', 'file_size', 'INTEGER NOT NULL DEFAULT 0');
      _ensureColumn(db, 'movies', 'modified_at', 'INTEGER NOT NULL DEFAULT 0');
    }

    if (fromVersion < 5) {
      db.execute('''
        CREATE TABLE IF NOT EXISTS media_sources (
          source_id TEXT PRIMARY KEY,
          root_path TEXT NOT NULL UNIQUE,
          label TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'active',
          created_at INTEGER NOT NULL
        );
      ''');

      final roots = _readConfiguredRoots(db);
      db.execute('BEGIN TRANSACTION;');
      try {
        final sourceMap = _ensureMediaSourcesFromRoots(db, roots);
        _migrateTableKeysToV2(
          db,
          table: 'episodes',
          prefix: 'ep',
          legacyPrefix: 'episode_',
          roots: roots,
          sourceIdsByRoot: sourceMap,
        );
        _migrateTableKeysToV2(
          db,
          table: 'movies',
          prefix: 'mv',
          legacyPrefix: 'movie_',
          roots: roots,
          sourceIdsByRoot: sourceMap,
        );
        db.execute('COMMIT;');
      } catch (_) {
        db.execute('ROLLBACK;');
        rethrow;
      }
    }

    if (fromVersion < 6) {
      _ensureColumn(
        db,
        'episodes',
        'thumb_attempts',
        'INTEGER NOT NULL DEFAULT 0',
      );
      _ensureColumn(db, 'episodes', 'thumb_last_error', 'TEXT');
      _ensureColumn(
        db,
        'episodes',
        'thumb_retry_at',
        'INTEGER NOT NULL DEFAULT 0',
      );
      _ensureColumn(
        db,
        'movies',
        'thumb_attempts',
        'INTEGER NOT NULL DEFAULT 0',
      );
      _ensureColumn(db, 'movies', 'thumb_last_error', 'TEXT');
      _ensureColumn(
        db,
        'movies',
        'thumb_retry_at',
        'INTEGER NOT NULL DEFAULT 0',
      );

      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_episodes_thumb_queue ON episodes(thumb_status, thumb_retry_at);',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_movies_thumb_queue ON movies(thumb_status, thumb_retry_at);',
      );

      db.execute(
        "UPDATE episodes SET thumb_status = 'retry_wait', thumb_attempts = CASE WHEN thumb_attempts < 1 THEN 1 ELSE thumb_attempts END WHERE thumb_status = 'failed';",
      );
      db.execute(
        "UPDATE movies SET thumb_status = 'retry_wait', thumb_attempts = CASE WHEN thumb_attempts < 1 THEN 1 ELSE thumb_attempts END WHERE thumb_status = 'failed';",
      );
      db.execute(
        "UPDATE episodes SET thumb_status = 'pending' WHERE thumb_status = 'processing';",
      );
      db.execute(
        "UPDATE movies SET thumb_status = 'pending' WHERE thumb_status = 'processing';",
      );
    }
  }

  static void _ensureColumn(
    Database db,
    String table,
    String columnName,
    String columnDef,
  ) {
    final columns = db.select('PRAGMA table_info($table);');
    final exists = columns.any((col) => col['name'] == columnName);
    if (!exists) {
      db.execute('ALTER TABLE $table ADD COLUMN $columnName $columnDef;');
    }
  }

  static List<String> _readConfiguredRoots(Database db) {
    final roots = <String>[];
    final multiRows = db.select(
      "SELECT value FROM app_settings WHERE key = 'nas_root_paths' LIMIT 1;",
    );
    if (multiRows.isNotEmpty) {
      try {
        final decoded = jsonDecode(multiRows.first['value'] as String);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String && item.trim().isNotEmpty) {
              roots.add(item.trim());
            }
          }
        }
      } on FormatException {
        // Ignoriere fehlerhafte JSON-Einträge bei Legacy-Migration
      }
    }
    if (roots.isEmpty) {
      final singleRows = db.select(
        "SELECT value FROM app_settings WHERE key = 'nas_root_path' LIMIT 1;",
      );
      if (singleRows.isNotEmpty) {
        final val = (singleRows.first['value'] as String).trim();
        if (val.isNotEmpty) {
          roots.add(val);
        }
      }
    }
    return roots;
  }

  static Map<String, String> _ensureMediaSourcesFromRoots(
    Database db,
    List<String> roots,
  ) {
    final map = <String, String>{};
    final usedIds = <String>{};
    final existing = db.select(
      'SELECT source_id, root_path FROM media_sources;',
    );
    for (final row in existing) {
      final id = row['source_id'] as String;
      final root = row['root_path'] as String;
      usedIds.add(id);
      map[root] = id;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final root in roots) {
      final normRoot = SyncKeyUtils.normalizeRootPath(root);
      String? existingId;
      for (final entry in map.entries) {
        if (SyncKeyUtils.normalizeRootPath(entry.key) == normRoot) {
          existingId = entry.value;
          break;
        }
      }
      if (existingId != null) {
        continue;
      }
      final baseId = SyncKeyUtils.deriveDefaultSourceId(root);
      var candidate = baseId;
      var suffix = 2;
      while (usedIds.contains(candidate)) {
        candidate = '${baseId}_$suffix';
        suffix++;
      }
      usedIds.add(candidate);
      final label = p.basename(root).trim().isEmpty ? root : p.basename(root);
      db.execute(
        '''
        INSERT OR IGNORE INTO media_sources (source_id, root_path, label, status, created_at)
        VALUES (?, ?, ?, 'active', ?);
        ''',
        [candidate, root, label, now],
      );
      map[root] = candidate;
    }
    return map;
  }

  static void _backfillLegacyV1Keys(
    Database db, {
    required String table,
    required String prefix,
    required String legacyPrefix,
    required List<String> roots,
  }) {
    final rows = db.select('SELECT id, file_path, sync_key FROM $table;');
    final usedKeys = <String>{};
    for (final row in rows) {
      final existing = row['sync_key'] as String?;
      if (existing != null && existing.isNotEmpty) {
        usedKeys.add(existing);
      }
    }

    for (final row in rows) {
      final id = row['id'] as int;
      final filePath = row['file_path'] as String;
      var syncKey = row['sync_key'] as String?;
      if (syncKey == null || syncKey.isEmpty) {
        syncKey = _buildBestV1Key(prefix, filePath, roots);
        if (usedKeys.contains(syncKey)) {
          syncKey = SyncKeyUtils.buildLegacyV1SyncKey(prefix, filePath, '');
        }
        usedKeys.add(syncKey);
        db.execute(
          'UPDATE $table SET sync_key = ? WHERE id = ?;',
          [syncKey, id],
        );
      }
      _migrateMediaKeyWithMerge(db, '$legacyPrefix$id', syncKey);
    }
  }

  static void _migrateTableKeysToV2(
    Database db, {
    required String table,
    required String prefix,
    required String legacyPrefix,
    required List<String> roots,
    required Map<String, String> sourceIdsByRoot,
  }) {
    final rows = db.select('SELECT id, file_path, sync_key FROM $table;');
    final usedKeys = <String>{};
    for (final row in rows) {
      final existing = row['sync_key'] as String?;
      if (existing != null && existing.isNotEmpty) {
        usedKeys.add(existing);
      }
    }

    for (final row in rows) {
      final id = row['id'] as int;
      final filePath = row['file_path'] as String;
      final oldKey = row['sync_key'] as String?;

      if (SyncKeyUtils.isV2SyncKey(oldKey)) {
        _migrateMediaKeyWithMerge(db, '$legacyPrefix$id', oldKey!);
        continue;
      }

      var candidate = SyncKeyUtils.buildKeyFromRoots(
        prefix,
        filePath,
        roots,
        sourceIdsByRoot: sourceIdsByRoot,
      );
      if (usedKeys.contains(candidate)) {
        // Fallback auf vollen Pfad, falls zwei Dateien im Legacy-Bestand kollidieren
        final fallback = SyncKeyUtils.buildStableSyncKey(
          prefix,
          filePath,
          '',
          sourceId: SyncKeyUtils.defaultSourceId,
        );
        if (!usedKeys.contains(fallback)) {
          candidate = fallback;
        } else if (oldKey != null && oldKey.isNotEmpty) {
          // Bestehenden eindeutigen Key behalten statt Daten zu verlieren
          _migrateMediaKeyWithMerge(db, '$legacyPrefix$id', oldKey);
          continue;
        }
      }

      if (oldKey != null && oldKey.isNotEmpty) {
        usedKeys.remove(oldKey);
      }
      usedKeys.add(candidate);

      db.execute(
        'UPDATE $table SET sync_key = ? WHERE id = ?;',
        [candidate, id],
      );

      if (oldKey != null && oldKey.isNotEmpty && oldKey != candidate) {
        _migrateMediaKeyWithMerge(db, oldKey, candidate);
      }
      _migrateMediaKeyWithMerge(db, '$legacyPrefix$id', candidate);
    }
  }

  static String _buildBestV1Key(
    String prefix,
    String filePath,
    List<String> roots,
  ) {
    final normalizedFile =
        p.normalize(filePath.trim()).replaceAll('\\', '/').toLowerCase();
    String? bestRoot;
    for (final root in roots) {
      final trimmed = root.trim();
      if (trimmed.isEmpty) continue;
      final normRoot = SyncKeyUtils.normalizeRootPath(trimmed);
      if (normalizedFile == normRoot ||
          normalizedFile.startsWith('$normRoot/')) {
        if (bestRoot == null || trimmed.length > bestRoot.length) {
          bestRoot = trimmed;
        }
      }
    }
    return SyncKeyUtils.buildLegacyV1SyncKey(prefix, filePath, bestRoot ?? '');
  }

  static void _migrateMediaKeyWithMerge(
    Database db,
    String oldKey,
    String newKey,
  ) {
    if (oldKey == newKey) return;
    final oldProgress = db.select(
      'SELECT * FROM watch_progress WHERE media_key = ? LIMIT 1;',
      [oldKey],
    );
    if (oldProgress.isNotEmpty) {
      final existingNew = db.select(
        'SELECT updated_at, position_ms FROM watch_progress WHERE media_key = ? LIMIT 1;',
        [newKey],
      );
      if (existingNew.isEmpty) {
        db.execute(
          'UPDATE watch_progress SET media_key = ? WHERE media_key = ?;',
          [newKey, oldKey],
        );
      } else {
        final oldRow = oldProgress.first;
        final oldUpdated = (oldRow['updated_at'] as int?) ?? 0;
        final newUpdated = (existingNew.first['updated_at'] as int?) ?? 0;
        final oldPos = (oldRow['position_ms'] as int?) ?? 0;
        final newPos = (existingNew.first['position_ms'] as int?) ?? 0;
        if (oldUpdated > newUpdated ||
            (oldUpdated == newUpdated && oldPos > newPos)) {
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
              newKey,
            ],
          );
        }
        db.execute(
          'DELETE FROM watch_progress WHERE media_key = ?;',
          [oldKey],
        );
      }
    }

    db.execute(
      'UPDATE watch_history SET media_key = ? WHERE media_key = ?;',
      [newKey, oldKey],
    );
    db.execute(
      'UPDATE media_bookmarks SET media_key = ? WHERE media_key = ?;',
      [newKey, oldKey],
    );
  }
}
