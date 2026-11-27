import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'portable_paths.dart';
import 'sync_key_utils.dart';

class DatabaseService {
  static const int schemaVersion = 3;

  Database? _db;

  Future<void> open({String? dbPath}) async {
    if (_db != null) {
      return;
    }
    final resolvedPath = dbPath ?? await PortablePaths.getDatabaseFilePath();
    final db = sqlite3.open(resolvedPath);
    try {
      db.execute('PRAGMA journal_mode = WAL;');
      db.execute('PRAGMA synchronous = NORMAL;');
      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('PRAGMA busy_timeout = 5000;');
      final hadExistingTables = db
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';",
          )
          .isNotEmpty;
      final versionRows = db.select('PRAGMA user_version;');
      final currentVersion = versionRows.isNotEmpty
          ? (versionRows.first.values.first as int? ?? 0)
          : 0;
      _createSchema(db);
      if (currentVersion == 0) {
        if (hadExistingTables) {
          _migrateSchema(db, 0);
        }
        db.execute('PRAGMA user_version = $schemaVersion;');
      } else if (currentVersion < schemaVersion) {
        _migrateSchema(db, currentVersion);
        db.execute('PRAGMA user_version = $schemaVersion;');
      }
      _createIndices(db);
      _db = db;
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }

  bool get isOpen => _db != null;

  Database get instance {
    final current = _db;
    if (current == null) {
      throw StateError('DatabaseService ist noch nicht geoeffnet.');
    }
    return current;
  }

  void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS series (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        folder_path TEXT NOT NULL UNIQUE,
        poster_path TEXT,
        summary TEXT,
        last_watched_at INTEGER
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS seasons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        series_id INTEGER NOT NULL,
        season_number INTEGER NOT NULL,
        folder_path TEXT NOT NULL,
        FOREIGN KEY (series_id) REFERENCES series(id) ON DELETE CASCADE,
        UNIQUE (series_id, season_number)
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS episodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        series_id INTEGER NOT NULL,
        season_id INTEGER NOT NULL,
        episode_number INTEGER NOT NULL,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL UNIQUE,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        thumb_path TEXT,
        sync_key TEXT,
        thumb_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (series_id) REFERENCES series(id) ON DELETE CASCADE,
        FOREIGN KEY (season_id) REFERENCES seasons(id) ON DELETE CASCADE
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS movies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        release_year INTEGER,
        file_path TEXT NOT NULL UNIQUE,
        poster_path TEXT,
        thumb_path TEXT,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        last_watched_at INTEGER,
        sync_key TEXT,
        thumb_status TEXT NOT NULL DEFAULT 'pending'
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS watch_progress (
        media_key TEXT PRIMARY KEY,
        media_type TEXT NOT NULL,
        position_ms INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        completed INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        source_device TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS series_preferences (
        series_id INTEGER PRIMARY KEY,
        audio_track TEXT,
        subtitle_track TEXT,
        intro_skip_seconds INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (series_id) REFERENCES series(id) ON DELETE CASCADE
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS media_bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_key TEXT NOT NULL,
        position_ms INTEGER NOT NULL,
        label TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS watch_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_key TEXT NOT NULL,
        media_type TEXT NOT NULL,
        title TEXT NOT NULL,
        series_id INTEGER,
        watched_ms INTEGER NOT NULL DEFAULT 0,
        started_at INTEGER NOT NULL,
        ended_at INTEGER NOT NULL,
        day_key TEXT NOT NULL,
        weekday INTEGER NOT NULL,
        source_device TEXT NOT NULL
      );
    ''');
  }

  void _createIndices(Database db) {
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_media_bookmarks_key ON media_bookmarks(media_key);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_watch_history_day ON watch_history(day_key);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_watch_history_media ON watch_history(media_key);',
    );
    db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_episodes_sync_key ON episodes(sync_key);',
    );
    db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_movies_sync_key ON movies(sync_key);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_episodes_series_id ON episodes(series_id);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_episodes_season_id ON episodes(season_id);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_seasons_series_id ON seasons(series_id);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_watch_progress_completed_updated ON watch_progress(completed, updated_at);',
    );
  }

  void _migrateSchema(Database db, int fromVersion) {
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
        _backfillMediaSyncKeys(
          db,
          table: 'episodes',
          prefix: 'ep',
          legacyPrefix: 'episode_',
          roots: roots,
        );
        _backfillMediaSyncKeys(
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
  }

  void _ensureColumn(
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

  List<String> _readConfiguredRoots(Database db) {
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

  void _backfillMediaSyncKeys(
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
        syncKey = SyncKeyUtils.buildKeyFromRoots(prefix, filePath, roots);
        if (usedKeys.contains(syncKey)) {
          syncKey = SyncKeyUtils.buildStableSyncKey(prefix, filePath, '');
        }
        usedKeys.add(syncKey);
        db.execute(
          'UPDATE $table SET sync_key = ? WHERE id = ?;',
          [syncKey, id],
        );
      }
      _migrateLegacyMediaKey(db, '$legacyPrefix$id', syncKey);
    }
  }

  void _migrateLegacyMediaKey(
    Database db,
    String legacyKey,
    String syncKey,
  ) {
    final legacyProgress = db.select(
      'SELECT * FROM watch_progress WHERE media_key = ? LIMIT 1;',
      [legacyKey],
    );
    if (legacyProgress.isNotEmpty) {
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
        final oldRow = legacyProgress.first;
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

    db.execute(
      'UPDATE watch_history SET media_key = ? WHERE media_key = ?;',
      [syncKey, legacyKey],
    );
    db.execute(
      'UPDATE media_bookmarks SET media_key = ? WHERE media_key = ?;',
      [syncKey, legacyKey],
    );
  }

  void resetDatabase() {
    final db = instance;
    db.execute('BEGIN TRANSACTION;');
    try {
      db.execute('DELETE FROM media_bookmarks;');
      db.execute('DELETE FROM watch_history;');
      db.execute('DELETE FROM watch_progress;');
      db.execute('DELETE FROM series_preferences;');
      db.execute('DELETE FROM episodes;');
      db.execute('DELETE FROM seasons;');
      db.execute('DELETE FROM series;');
      db.execute('DELETE FROM movies;');
      db.execute('DELETE FROM app_settings;');
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void close() {
    _db?.dispose();
    _db = null;
  }
}
