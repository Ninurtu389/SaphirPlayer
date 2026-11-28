import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:sqlite3/sqlite3.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('DatabaseService schema, constraints, and error handling', () {
    test('creates all tables, indices, pragmas, and user_version in :memory:',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);

      final db = env.dbService.instance;
      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();

      expect(
        tables,
        containsAll([
          'app_settings',
          'series',
          'seasons',
          'episodes',
          'movies',
          'watch_progress',
          'series_preferences',
          'watch_history',
          'media_bookmarks',
          'media_sources',
        ]),
      );

      final indices = db
          .select("SELECT name FROM sqlite_master WHERE type = 'index';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(
        indices,
        containsAll([
          'idx_watch_history_day',
          'idx_watch_history_media',
          'idx_media_bookmarks_key',
          'idx_episodes_sync_key',
          'idx_movies_sync_key',
          'idx_episodes_series_id',
          'idx_episodes_season_id',
          'idx_seasons_series_id',
          'idx_watch_progress_completed_updated',
          'idx_episodes_thumb_queue',
          'idx_movies_thumb_queue',
          'idx_series_source_id',
          'idx_episodes_source_id',
          'idx_movies_source_id',
        ]),
      );

      final fk = db.select('PRAGMA foreign_keys;').first.values.first;
      expect(fk, 1);

      final version = db.select('PRAGMA user_version;').first.values.first;
      expect(version, DatabaseService.schemaVersion);

      final epCols = db
          .select('PRAGMA table_info(episodes);')
          .map((r) => r['name'] as String)
          .toSet();
      expect(
        epCols,
        containsAll([
          'artist',
          'file_size',
          'modified_at',
          'thumb_attempts',
          'thumb_last_error',
          'thumb_retry_at',
          'source_id',
        ]),
      );

      final mvCols = db
          .select('PRAGMA table_info(movies);')
          .map((r) => r['name'] as String)
          .toSet();
      expect(
        mvCols,
        containsAll([
          'artist',
          'file_size',
          'modified_at',
          'thumb_attempts',
          'thumb_last_error',
          'thumb_retry_at',
          'source_id',
        ]),
      );

      final prefCols = db
          .select('PRAGMA table_info(series_preferences);')
          .map((r) => r['name'] as String)
          .toSet();
      expect(
        prefCols,
        containsAll([
          'series_id',
          'audio_track',
          'subtitle_track',
          'intro_skip_seconds',
          'audio_pref_json',
          'subtitle_pref_json',
        ]),
      );
    });

    test('throws StateError when accessed before open()', () {
      final uninitialized = DatabaseService();
      expect(() => uninitialized.instance, throwsStateError);
    });

    test('enforces UNIQUE constraints and ON DELETE CASCADE', () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      final db = env.dbService.instance;

      db.execute(
        "INSERT INTO series (title, folder_path) VALUES ('Dark', 'D:\\Dark');",
      );
      final seriesId = db.lastInsertRowId;

      // Duplicate folder_path fails
      expect(
        () => db.execute(
          "INSERT INTO series (title, folder_path) VALUES ('Dark 2', 'D:\\Dark');",
        ),
        throwsA(isA<SqliteException>()),
      );

      db.execute(
        "INSERT INTO seasons (series_id, season_number, folder_path) VALUES (?, 1, 'D:\\Dark\\S1');",
        [seriesId],
      );
      final seasonId = db.lastInsertRowId;

      db.execute(
        "INSERT INTO episodes (series_id, season_id, episode_number, title, file_path) VALUES (?, ?, 1, 'Ep1', 'D:\\Dark\\S01E01.mkv');",
        [seriesId, seasonId],
      );
      db.execute(
        "INSERT INTO series_preferences (series_id, audio_track, subtitle_track) VALUES (?, 'deu', 'no');",
        [seriesId],
      );

      // Deleting series cascades to seasons, episodes, and series_preferences
      db.execute('DELETE FROM series WHERE id = ?;', [seriesId]);
      expect(db.select('SELECT COUNT(*) AS c FROM seasons;').first['c'], 0);
      expect(db.select('SELECT COUNT(*) AS c FROM episodes;').first['c'], 0);
      expect(
        db.select('SELECT COUNT(*) AS c FROM series_preferences;').first['c'],
        0,
      );
    });

    test(
        'handles Unicode, special characters, and SQL injection payloads safely',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      final db = env.dbService.instance;

      const trickyTitle = "日本語 & ÄÖÜß ' OR 1=1; DROP TABLE series; --";
      const trickyPath = r'\\NAS\Serien\日本語\S01E01 (1080p) [H.265].mkv';

      db.execute(
        'INSERT INTO movies (title, file_path) VALUES (?, ?);',
        [trickyTitle, trickyPath],
      );

      final row = db.select(
          'SELECT title, file_path FROM movies WHERE file_path = ?;',
          [trickyPath]).first;
      expect(row['title'], trickyTitle);
      expect(row['file_path'], trickyPath);
    });

    test('handles large datasets (500 series, 2000 episodes, 500 movies)',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      final db = env.dbService.instance;

      db.execute('BEGIN TRANSACTION;');
      final insertSeries = db.prepare(
        'INSERT INTO series (title, folder_path) VALUES (?, ?);',
      );
      final insertSeason = db.prepare(
        'INSERT INTO seasons (series_id, season_number, folder_path) VALUES (?, 1, ?);',
      );
      final insertEpisode = db.prepare(
        'INSERT INTO episodes (series_id, season_id, episode_number, title, file_path, duration_ms) VALUES (?, ?, ?, ?, ?, 1800000);',
      );
      final insertMovie = db.prepare(
        'INSERT INTO movies (title, file_path, duration_ms) VALUES (?, ?, 5400000);',
      );

      for (var s = 1; s <= 500; s++) {
        insertSeries.execute(['Series $s', 'D:\\Serien\\S$s']);
        final sid = db.lastInsertRowId;
        insertSeason.execute([sid, 'D:\\Serien\\S$s\\Season 1']);
        final snId = db.lastInsertRowId;
        for (var e = 1; e <= 4; e++) {
          insertEpisode.execute([
            sid,
            snId,
            e,
            'Ep $e',
            'D:\\Serien\\S$s\\S01E0$e.mkv',
          ]);
        }
        insertMovie.execute(['Movie $s', 'D:\\Filme\\M$s.mkv']);
      }
      insertSeries.dispose();
      insertSeason.dispose();
      insertEpisode.dispose();
      insertMovie.dispose();
      db.execute('COMMIT;');

      expect(db.select('SELECT COUNT(*) AS c FROM series;').first['c'], 500);
      expect(db.select('SELECT COUNT(*) AS c FROM episodes;').first['c'], 2000);
      expect(db.select('SELECT COUNT(*) AS c FROM movies;').first['c'], 500);

      env.dbService.resetDatabase();
      expect(db.select('SELECT COUNT(*) AS c FROM series;').first['c'], 0);
      expect(db.select('SELECT COUNT(*) AS c FROM episodes;').first['c'], 0);
      expect(db.select('SELECT COUNT(*) AS c FROM movies;').first['c'], 0);
    });

    test('reports SqliteException cleanly on corrupt or locked database file',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      // 1. Corrupt DB file
      final corruptPath = p.join(env.tempRoot.path, 'corrupt.db');
      File(corruptPath).writeAsStringSync('not a sqlite database file');
      final corruptDb = DatabaseService();
      await expectLater(
        () => corruptDb.open(dbPath: corruptPath),
        throwsA(isA<SqliteException>()),
      );
      corruptDb.close();

      // 2. Locked DB file (exclusive lock held by another connection)
      final lockedPath = p.join(env.tempRoot.path, 'locked.db');
      final locker = sqlite3.open(lockedPath);
      locker.execute('CREATE TABLE t(id INTEGER PRIMARY KEY);');
      locker.execute('BEGIN EXCLUSIVE;');
      try {
        final contender = sqlite3.open(lockedPath);
        expect(
          () => contender.execute('INSERT INTO t VALUES (1);'),
          throwsA(isA<SqliteException>()),
        );
        contender.dispose();
      } finally {
        locker.execute('ROLLBACK;');
        locker.dispose();
      }
    });
  });

  group('ProgressSyncService', () {
    test(
        'handles corrupt JSON and wrong field types without throwing TypeError',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final syncDir = env.createSubdir('nas_sync');
      final syncFile = File(p.join(syncDir.path, 'progress_sync.json'));

      // Corrupt JSON is preserved without throwing and reports corrupt status
      syncFile.writeAsStringSync('{invalid json');
      final sync = ProgressSyncService(env.dbService);
      final corruptResult = await sync.syncWithStorage(syncDir.path);
      expect(corruptResult.status, SyncStatus.corrupt);
      expect(corruptResult.syncedToNas, isFalse);
      expect(syncFile.readAsStringSync(), '{invalid json');

      // Mixed valid + invalid field types: invalid entry is isolated while valid entry imports cleanly
      syncFile.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'entries': {
            'episode_bad_type': {
              'media_type': 123,
              'position_ms': '45000',
              'duration_ms': 120000.4,
              'completed': 'true',
              'updated_at': 99999,
              'source_device': null,
            },
            'episode_10': {
              'media_type': 'episode',
              'position_ms': '45000',
              'duration_ms': 120000.4,
              'completed': 'true',
              'updated_at': 99999,
              'source_device': null,
            },
          },
        }),
      );

      final result = await sync.syncWithStorage(syncDir.path);
      expect(result.syncedToNas, isTrue);
      expect(result.isolatedEntryCount, 1);
      final badRows = env.dbService.instance.select(
        "SELECT * FROM watch_progress WHERE media_key = 'episode_bad_type';",
      );
      expect(badRows, isEmpty);
      final rows = env.dbService.instance.select(
        "SELECT * FROM watch_progress WHERE media_key = 'episode_10';",
      );
      expect(rows.length, 1);
      expect(rows.first['position_ms'], 45000);
      expect(rows.first['duration_ms'], 120000);
      expect(rows.first['completed'], 1);
      expect(rows.first['media_type'], 'episode');
      expect(rows.first['source_device'], 'remote');
    });

    test('falls back to local data/progress_sync.json when NAS is offline',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      env.dbService.instance.execute(
        '''
        INSERT INTO watch_progress (
          media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device
        ) VALUES ('movie_5', 'movie', 5000, 60000, 0, 12345, 'TestLaptop');
        ''',
      );

      final sync = ProgressSyncService(env.dbService);
      final syncResult =
          await sync.syncWithRoots([p.join(env.tempRoot.path, 'offline_nas')]);
      expect(syncResult.syncedToNas, isFalse);

      final localSync = File(
        p.join(env.tempRoot.path, 'app_base', 'data', 'progress_sync.json'),
      );
      expect(localSync.existsSync(), isTrue);
      final decoded =
          jsonDecode(localSync.readAsStringSync()) as Map<String, dynamic>;
      final entries = decoded['entries'] as Map<String, dynamic>;
      expect(entries.containsKey('movie_5'), isTrue);
    });
  });
}
