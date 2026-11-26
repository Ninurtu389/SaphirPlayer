import 'package:sqlite3/sqlite3.dart';
import 'portable_paths.dart';

class DatabaseService {
  Database? _db;

  Future<void> open({String? dbPath}) async {
    if (_db != null) {
      return;
    }
    final resolvedPath = dbPath ?? await PortablePaths.getDatabaseFilePath();
    final db = sqlite3.open(resolvedPath);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    _createSchema(db);
    _db = db;
  }

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
        last_watched_at INTEGER
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
        FOREIGN KEY (series_id) REFERENCES series(id) ON DELETE CASCADE
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

    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_watch_history_day ON watch_history(day_key);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_watch_history_media ON watch_history(media_key);',
    );
  }

  void resetDatabase() {
    final db = instance;
    db.execute('BEGIN TRANSACTION;');
    try {
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
