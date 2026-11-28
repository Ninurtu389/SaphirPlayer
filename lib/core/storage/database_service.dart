import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'database_backup_service.dart';
import 'database_migrations.dart';
import 'portable_paths.dart';
import 'sync_key_utils.dart';

class DatabaseService {
  DatabaseService({StorageLayout? storageLayout})
      : _storageLayout = storageLayout;

  static const int schemaVersion = 8;

  final StorageLayout? _storageLayout;
  Database? _db;
  String? _currentDbPath;

  String? get currentDbPath => _currentDbPath;

  Future<void> open({String? dbPath}) async {
    if (_db != null) {
      return;
    }
    final resolvedPath = dbPath ??
        _storageLayout?.databaseFilePath ??
        await PortablePaths.getDatabaseFilePath();
    if (resolvedPath != ':memory:') {
      await PortablePaths.verifyDirectoryWritable(
        p.dirname(resolvedPath),
        mode: _storageLayout?.mode ??
            PortablePaths.activeLayout?.mode ??
            StorageMode.standard,
      );
    }
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
      final needsMigration = (currentVersion == 0 && hadExistingTables) ||
          (currentVersion > 0 && currentVersion < schemaVersion);
      if (needsMigration && resolvedPath != ':memory:') {
        final backupDir = _storageLayout?.backupsDirectory ??
            p.join(p.dirname(resolvedPath), 'backups');
        await DatabaseBackupService.createSnapshotFromDatabase(
          db,
          backupDirPath: backupDir,
          reason: 'pre_migration',
        );
      }
      _createSchema(db);
      if (currentVersion == 0) {
        if (hadExistingTables) {
          DatabaseMigrations.migrate(db, 0);
        }
        db.execute('PRAGMA user_version = $schemaVersion;');
      } else if (currentVersion < schemaVersion) {
        DatabaseMigrations.migrate(db, currentVersion);
        db.execute('PRAGMA user_version = $schemaVersion;');
      }
      _createIndices(db);
      _db = db;
      _currentDbPath = resolvedPath;
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
      CREATE TABLE IF NOT EXISTS media_sources (
        source_id TEXT PRIMARY KEY,
        root_path TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL,
        last_scan_at INTEGER,
        last_success_scan_at INTEGER,
        last_scan_status TEXT,
        last_scan_error TEXT,
        last_files_examined INTEGER NOT NULL DEFAULT 0,
        last_media_found INTEGER NOT NULL DEFAULT 0,
        last_error_count INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS series (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        folder_path TEXT NOT NULL UNIQUE,
        poster_path TEXT,
        summary TEXT,
        last_watched_at INTEGER,
        source_id TEXT
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
        thumb_attempts INTEGER NOT NULL DEFAULT 0,
        thumb_last_error TEXT,
        thumb_retry_at INTEGER NOT NULL DEFAULT 0,
        artist TEXT,
        file_size INTEGER NOT NULL DEFAULT 0,
        modified_at INTEGER NOT NULL DEFAULT 0,
        source_id TEXT,
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
        thumb_status TEXT NOT NULL DEFAULT 'pending',
        thumb_attempts INTEGER NOT NULL DEFAULT 0,
        thumb_last_error TEXT,
        thumb_retry_at INTEGER NOT NULL DEFAULT 0,
        artist TEXT,
        file_size INTEGER NOT NULL DEFAULT 0,
        modified_at INTEGER NOT NULL DEFAULT 0,
        source_id TEXT
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
        audio_pref_json TEXT,
        subtitle_pref_json TEXT,
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
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_episodes_thumb_queue ON episodes(thumb_status, thumb_retry_at);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_movies_thumb_queue ON movies(thumb_status, thumb_retry_at);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_series_source_id ON series(source_id);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_episodes_source_id ON episodes(source_id);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_movies_source_id ON movies(source_id);',
    );
  }

  Map<String, String> loadSourceIdsByRoot() {
    final db = instance;
    final rows = db.select(
      'SELECT source_id, root_path FROM media_sources ORDER BY created_at ASC;',
    );
    return {
      for (final row in rows)
        row['root_path'] as String: row['source_id'] as String,
    };
  }

  String ensureMediaSource(
    String rootPath, {
    String? preferredSourceId,
    String? label,
  }) {
    final trimmed = rootPath.trim();
    if (trimmed.isEmpty) {
      return SyncKeyUtils.defaultSourceId;
    }
    final db = instance;
    final normTarget = SyncKeyUtils.normalizeRootPath(trimmed);
    final rows =
        db.select('SELECT source_id, root_path, status FROM media_sources;');
    final usedIds = <String>{};
    for (final row in rows) {
      final id = row['source_id'] as String;
      final existingRoot = row['root_path'] as String;
      final existingStatus = (row['status'] as String?) ?? 'active';
      usedIds.add(id);
      if (SyncKeyUtils.normalizeRootPath(existingRoot) == normTarget) {
        if (existingStatus != 'active') {
          db.execute(
            "UPDATE media_sources SET status = 'active' WHERE source_id = ?;",
            [id],
          );
        }
        return id;
      }
    }

    final baseId =
        (preferredSourceId != null && preferredSourceId.trim().isNotEmpty)
            ? SyncKeyUtils.normalizeSourceId(preferredSourceId)
            : SyncKeyUtils.deriveDefaultSourceId(trimmed);
    var candidate = baseId;
    var suffix = 2;
    while (usedIds.contains(candidate)) {
      candidate = '${baseId}_$suffix';
      suffix++;
    }

    final resolvedLabel = (label != null && label.trim().isNotEmpty)
        ? label.trim()
        : (p.basename(trimmed).trim().isEmpty ? trimmed : p.basename(trimmed));

    db.execute(
      '''
      INSERT INTO media_sources (source_id, root_path, label, status, created_at)
      VALUES (?, ?, ?, 'active', ?);
      ''',
      [
        candidate,
        trimmed,
        resolvedLabel,
        DateTime.now().millisecondsSinceEpoch
      ],
    );
    return candidate;
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
      db.execute('DELETE FROM media_sources;');
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
    _currentDbPath = null;
  }
}
