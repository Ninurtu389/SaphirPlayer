import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/core/storage/portable_paths.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/storage/sync_key_utils.dart';
import 'package:saphir_player/features/player/playback_persistence_service.dart';
import 'package:saphir_player/features/stats/stats_controller.dart';
import 'package:sqlite3/sqlite3.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('Database v1/v2/v0 -> v3 migration & idempotency', () {
    test('migrates v1 schema to v3 preserving existing data and backfilling sync_key',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final v1Path = p.join(env.tempRoot.path, 'legacy_v1.db');
      final raw = sqlite3.open(v1Path);
      raw.execute('''
        CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE series (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          folder_path TEXT NOT NULL UNIQUE,
          poster_path TEXT,
          summary TEXT,
          last_watched_at INTEGER
        );
        CREATE TABLE seasons (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          season_number INTEGER NOT NULL,
          folder_path TEXT NOT NULL
        );
        CREATE TABLE episodes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          season_id INTEGER NOT NULL,
          episode_number INTEGER NOT NULL,
          title TEXT NOT NULL,
          file_path TEXT NOT NULL UNIQUE,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          thumb_path TEXT
        );
        CREATE TABLE movies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          release_year INTEGER,
          file_path TEXT NOT NULL UNIQUE,
          poster_path TEXT,
          thumb_path TEXT,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          last_watched_at INTEGER
        );
        CREATE TABLE watch_progress (
          media_key TEXT PRIMARY KEY,
          media_type TEXT NOT NULL,
          position_ms INTEGER NOT NULL DEFAULT 0,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          source_device TEXT NOT NULL
        );
        CREATE TABLE series_preferences (
          series_id INTEGER PRIMARY KEY,
          audio_track TEXT,
          subtitle_track TEXT
        );
        CREATE TABLE watch_history (
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
      raw.execute(
        "INSERT INTO app_settings (key, value) VALUES ('nas_root_path', 'D:\\NAS');",
      );
      raw.execute(
        "INSERT INTO series (id, title, folder_path) VALUES (1, 'Dark', 'D:\\NAS\\Dark');",
      );
      raw.execute(
        "INSERT INTO seasons (id, series_id, season_number, folder_path) VALUES (1, 1, 1, 'D:\\NAS\\Dark\\S1');",
      );
      raw.execute(
        "INSERT INTO episodes (id, series_id, season_id, episode_number, title, file_path, thumb_path) VALUES (1, 1, 1, 1, 'Ep1', 'D:\\NAS\\Dark\\S01E01.mkv', 'ep_1.jpg');",
      );
      raw.execute(
        "INSERT INTO movies (id, title, file_path) VALUES (1, 'Arrival', 'D:\\NAS\\Arrival.mkv');",
      );
      raw.execute(
        "INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device) VALUES ('episode_1', 'episode', 45000, 120000, 0, 1000, 'PC');",
      );
      raw.execute(
        "INSERT INTO series_preferences (series_id, audio_track, subtitle_track) VALUES (1, 'deu', 'no');",
      );
      raw.execute('PRAGMA user_version = 1;');
      raw.dispose();

      final service = DatabaseService();
      await service.open(dbPath: v1Path);
      addTearDown(service.close);

      final db = service.instance;
      expect(db.select('PRAGMA user_version;').first.values.first, 4);

      final cols = db
          .select('PRAGMA table_info(series_preferences);')
          .map((r) => r['name'] as String)
          .toSet();
      expect(cols, contains('intro_skip_seconds'));

      final epRow = db.select('SELECT sync_key, thumb_status FROM episodes WHERE id = 1;').first;
      final expectedEpKey = SyncKeyUtils.buildStableSyncKey('ep', r'D:\NAS\Dark\S01E01.mkv', r'D:\NAS');
      expect(epRow['sync_key'], expectedEpKey);
      expect(epRow['thumb_status'], 'ready');

      final mvRow = db.select('SELECT sync_key, thumb_status FROM movies WHERE id = 1;').first;
      expect(mvRow['sync_key'], SyncKeyUtils.buildStableSyncKey('mv', r'D:\NAS\Arrival.mkv', r'D:\NAS'));
      expect(mvRow['thumb_status'], 'pending');

      final wpRows = db.select('SELECT media_key, position_ms FROM watch_progress;');
      expect(wpRows.length, 1);
      expect(wpRows.first['media_key'], expectedEpKey);
      expect(wpRows.first['position_ms'], 45000);

      final pref = db
          .select('SELECT * FROM series_preferences WHERE series_id = 1;')
          .first;
      expect(pref['audio_track'], 'deu');
      expect(pref['subtitle_track'], 'no');
      expect(pref['intro_skip_seconds'], 0);

      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table';")
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables, contains('media_bookmarks'));

      // Re-opening must be idempotent
      service.close();
      await service.open(dbPath: v1Path);
      expect(
        service.instance.select('PRAGMA user_version;').first.values.first,
        4,
      );
    });

    test('migrates v2 schema to v3 and repairs user_version == 0 with existing tables',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      for (final version in [2, 0]) {
        final dbPath = p.join(env.tempRoot.path, 'legacy_v$version.db');
        final raw = sqlite3.open(dbPath);
        raw.execute('''
          CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
          CREATE TABLE series (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            folder_path TEXT NOT NULL UNIQUE,
            poster_path TEXT,
            summary TEXT,
            last_watched_at INTEGER
          );
          CREATE TABLE seasons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            series_id INTEGER NOT NULL,
            season_number INTEGER NOT NULL,
            folder_path TEXT NOT NULL
          );
          CREATE TABLE episodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            series_id INTEGER NOT NULL,
            season_id INTEGER NOT NULL,
            episode_number INTEGER NOT NULL,
            title TEXT NOT NULL,
            file_path TEXT NOT NULL UNIQUE,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            thumb_path TEXT
          );
          CREATE TABLE movies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            release_year INTEGER,
            file_path TEXT NOT NULL UNIQUE,
            poster_path TEXT,
            thumb_path TEXT,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            last_watched_at INTEGER
          );
          CREATE TABLE watch_progress (
            media_key TEXT PRIMARY KEY,
            media_type TEXT NOT NULL,
            position_ms INTEGER NOT NULL DEFAULT 0,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            completed INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL,
            source_device TEXT NOT NULL
          );
          CREATE TABLE series_preferences (
            series_id INTEGER PRIMARY KEY,
            audio_track TEXT,
            subtitle_track TEXT,
            intro_skip_seconds INTEGER NOT NULL DEFAULT 0
          );
          CREATE TABLE media_bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            media_key TEXT NOT NULL,
            position_ms INTEGER NOT NULL,
            label TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL
          );
          CREATE TABLE watch_history (
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
        raw.execute(
          "INSERT INTO movies (id, title, file_path) VALUES (1, 'Dune', 'D:\\Filme\\Dune.mkv');",
        );
        raw.execute('PRAGMA user_version = $version;');
        raw.dispose();

        final service = DatabaseService();
        await service.open(dbPath: dbPath);
        addTearDown(service.close);

        final db = service.instance;
        expect(db.select('PRAGMA user_version;').first.values.first, 4);
        final movieCols = db
            .select('PRAGMA table_info(movies);')
            .map((r) => r['name'] as String)
            .toSet();
        expect(
          movieCols,
          containsAll(['sync_key', 'thumb_status', 'artist', 'file_size', 'modified_at']),
        );
        final mv = db.select('SELECT sync_key FROM movies WHERE id = 1;').first;
        expect(mv['sync_key'], isNotNull);
      }
    });

    test('migrates v3 schema to v4 preserving watch_progress, bookmarks, and preferences',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final v3Path = p.join(env.tempRoot.path, 'legacy_v3.db');
      final raw = sqlite3.open(v3Path);
      raw.execute('''
        CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE series (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          folder_path TEXT NOT NULL UNIQUE,
          poster_path TEXT,
          summary TEXT,
          last_watched_at INTEGER
        );
        CREATE TABLE seasons (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          season_number INTEGER NOT NULL,
          folder_path TEXT NOT NULL
        );
        CREATE TABLE episodes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          season_id INTEGER NOT NULL,
          episode_number INTEGER NOT NULL,
          title TEXT NOT NULL,
          file_path TEXT NOT NULL UNIQUE,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          thumb_path TEXT,
          sync_key TEXT,
          thumb_status TEXT NOT NULL DEFAULT 'pending'
        );
        CREATE TABLE movies (
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
        CREATE TABLE watch_progress (
          media_key TEXT PRIMARY KEY,
          media_type TEXT NOT NULL,
          position_ms INTEGER NOT NULL DEFAULT 0,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          source_device TEXT NOT NULL
        );
        CREATE TABLE series_preferences (
          series_id INTEGER PRIMARY KEY,
          audio_track TEXT,
          subtitle_track TEXT,
          intro_skip_seconds INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE media_bookmarks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          media_key TEXT NOT NULL,
          position_ms INTEGER NOT NULL,
          label TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL
        );
        CREATE TABLE watch_history (
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
      raw.execute(
        "INSERT INTO series (id, title, folder_path) VALUES (1, 'Andor', 'D:\\NAS\\Andor');",
      );
      raw.execute(
        "INSERT INTO seasons (id, series_id, season_number, folder_path) VALUES (1, 1, 1, 'D:\\NAS\\Andor\\S1');",
      );
      raw.execute(
        "INSERT INTO episodes (id, series_id, season_id, episode_number, title, file_path, duration_ms, sync_key) VALUES (1, 1, 1, 1, 'Kassa', 'D:\\NAS\\Andor\\S01E01.mkv', 2400000, 'ep_andor_1');",
      );
      raw.execute(
        "INSERT INTO movies (id, title, release_year, file_path, duration_ms, sync_key) VALUES (1, 'Arrival', 2016, 'D:\\NAS\\Arrival.mkv', 6900000, 'mv_arrival');",
      );
      raw.execute(
        "INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device) VALUES ('ep_andor_1', 'episode', 600000, 2400000, 0, 5000, 'Laptop');",
      );
      raw.execute(
        "INSERT INTO media_bookmarks (media_key, position_ms, label, created_at) VALUES ('ep_andor_1', 300000, 'Intro Ende', 5000);",
      );
      raw.execute(
        "INSERT INTO series_preferences (series_id, audio_track, subtitle_track, intro_skip_seconds) VALUES (1, 'eng', 'deu', 85);",
      );
      raw.execute('PRAGMA user_version = 3;');
      raw.dispose();

      final service = DatabaseService();
      await service.open(dbPath: v3Path);
      addTearDown(service.close);

      final db = service.instance;
      expect(db.select('PRAGMA user_version;').first.values.first, 4);

      final epCols = db
          .select('PRAGMA table_info(episodes);')
          .map((r) => r['name'] as String)
          .toSet();
      final mvCols = db
          .select('PRAGMA table_info(movies);')
          .map((r) => r['name'] as String)
          .toSet();
      expect(epCols, containsAll(['artist', 'file_size', 'modified_at']));
      expect(mvCols, containsAll(['artist', 'file_size', 'modified_at']));

      final ep = db
          .select('SELECT title, artist, file_size, modified_at FROM episodes WHERE id = 1;')
          .first;
      expect(ep['title'], 'Kassa');
      expect(ep['artist'], isNull);
      expect(ep['file_size'], 0);
      expect(ep['modified_at'], 0);

      final mv = db
          .select('SELECT title, artist, file_size, modified_at FROM movies WHERE id = 1;')
          .first;
      expect(mv['title'], 'Arrival');
      expect(mv['artist'], isNull);
      expect(mv['file_size'], 0);
      expect(mv['modified_at'], 0);

      final wp = db.select("SELECT position_ms FROM watch_progress WHERE media_key = 'ep_andor_1';").first;
      expect(wp['position_ms'], 600000);

      final bm = db.select("SELECT label, position_ms FROM media_bookmarks WHERE media_key = 'ep_andor_1';").first;
      expect(bm['label'], 'Intro Ende');
      expect(bm['position_ms'], 300000);

      final pref = db.select('SELECT intro_skip_seconds, audio_track FROM series_preferences WHERE series_id = 1;').first;
      expect(pref['intro_skip_seconds'], 85);
      expect(pref['audio_track'], 'eng');

      // Re-opening must be idempotent
      service.close();
      await service.open(dbPath: v3Path);
      expect(service.instance.select('PRAGMA user_version;').first.values.first, 4);
    });
  });

  group('PortablePaths, Sync across DBs & Stats integrity', () {
    test('PortablePaths.resolveThumbnailPath resolves relative and preserves absolute paths',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      expect(PortablePaths.resolveThumbnailPath(null), isNull);
      expect(PortablePaths.resolveThumbnailPath('   '), isNull);

      final rel = PortablePaths.resolveThumbnailPath('ep_abc123.jpg');
      expect(rel, p.join(env.tempRoot.path, 'app_base', 'cache', 'thumbnails', 'ep_abc123.jpg'));

      final abs = p.join(env.tempRoot.path, 'custom', 'poster.jpg');
      expect(PortablePaths.resolveThumbnailPath(abs), abs);
    });

    test('ProgressSyncService syncs across two DBs with swapped AUTOINCREMENT IDs and handles parallel calls',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final nasDir = env.createSubdir('shared_nas');
      final dbPathA = p.join(env.tempRoot.path, 'device_a.db');
      final dbPathB = p.join(env.tempRoot.path, 'device_b.db');

      final dbA = DatabaseService();
      final dbB = DatabaseService();
      await dbA.open(dbPath: dbPathA);
      await dbB.open(dbPath: dbPathB);
      addTearDown(dbA.close);
      addTearDown(dbB.close);

      final keyEpA = SyncKeyUtils.buildStableSyncKey('ep', r'\\NAS\Dark\S01E01.mkv', r'\\NAS');
      final keyEpB = SyncKeyUtils.buildStableSyncKey('ep', r'\\NAS\Andor\S01E01.mkv', r'\\NAS');

      // Device A: Dark is id=1, Andor is id=2
      dbA.instance.execute("INSERT INTO series (id, title, folder_path) VALUES (1, 'Dark', 'D1'), (2, 'Andor', 'A1');");
      dbA.instance.execute("INSERT INTO seasons (id, series_id, season_number, folder_path) VALUES (1, 1, 1, 'S1'), (2, 2, 1, 'S2');");
      dbA.instance.execute(
        "INSERT INTO episodes (id, series_id, season_id, episode_number, title, file_path, sync_key) VALUES (1, 1, 1, 1, 'Ep1', 'f1', ?), (2, 2, 2, 1, 'Ep2', 'f2', ?);",
        [keyEpA, keyEpB],
      );
      dbA.instance.execute(
        "INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device) VALUES (?, 'episode', 50000, 100000, 0, 5000, 'DeviceA');",
        [keyEpA],
      );

      // Device B: Andor is id=1, Dark is id=2 (swapped AUTOINCREMENT IDs!)
      dbB.instance.execute("INSERT INTO series (id, title, folder_path) VALUES (1, 'Andor', 'A1'), (2, 'Dark', 'D1');");
      dbB.instance.execute("INSERT INTO seasons (id, series_id, season_number, folder_path) VALUES (1, 1, 1, 'S2'), (2, 2, 1, 'S1');");
      dbB.instance.execute(
        "INSERT INTO episodes (id, series_id, season_id, episode_number, title, file_path, sync_key) VALUES (1, 1, 1, 1, 'Ep2', 'f2', ?), (2, 2, 2, 1, 'Ep1', 'f1', ?);",
        [keyEpB, keyEpA],
      );

      final syncA = ProgressSyncService(dbA);
      final syncB = ProgressSyncService(dbB);

      // Parallel sync calls on A must serialize without .tmp leftovers
      final resultsA = await Future.wait([
        syncA.syncWithRoots([nasDir.path]),
        syncA.syncWithRoots([nasDir.path]),
      ]);
      expect(resultsA.every((r) => r.syncedToNas), isTrue);
      expect(File(p.join(nasDir.path, 'progress_sync.json.tmp')).existsSync(), isFalse);

      final resultB = await syncB.syncWithRoots([nasDir.path]);
      expect(resultB.syncedToNas, isTrue);

      final progressOnB = dbB.instance.select(
        'SELECT media_key, position_ms FROM watch_progress WHERE media_key = ?;',
        [keyEpA],
      );
      expect(progressOnB.length, 1);
      expect(progressOnB.first['position_ms'], 50000);
    });

    test('StatsController excludes orphaned watch_progress rows from completed counts',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      seedSampleLibrary(env.dbService);

      // Insert orphaned completed progress entries that do not match any episode/movie
      env.dbService.instance.execute(
        '''
        INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device)
        VALUES
          ('orphan_ep_1', 'episode', 0, 1000, 1, 1000, 'PC'),
          ('orphan_ep_2', 'episode', 0, 1000, 1, 1000, 'PC'),
          ('orphan_mv_1', 'movie', 0, 1000, 1, 1000, 'PC');
        ''',
      );
      env.dbService.instance.execute(
        "UPDATE watch_progress SET completed = 1 WHERE media_key = 'episode_1';",
      );

      final stats = StatsController(env.dbService);
      stats.refreshStats();
      expect(stats.summary.completedEpisodes, 1);
      expect(stats.summary.totalEpisodes, 4);
      expect(stats.summary.completedMovies, 0);
      expect(stats.summary.totalMovies, 2);
      stats.dispose();
    });
  });

  group('MediaBookmarks CRUD & resetDatabase', () {
    test('creates, sorts by position_ms, deletes, and clears on reset',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      final persistence = PlaybackPersistenceService(env.dbService);

      final bm2 = persistence.addBookmark('episode_1', 90000, label: 'Zwei');
      final bm1 = persistence.addBookmark('episode_1', 30000, label: 'Eins');
      persistence.addBookmark('episode_2', 15000, label: 'Andere');

      final loaded = persistence.loadBookmarks('episode_1');
      expect(loaded.length, 2);
      expect(loaded[0].id, bm1.id);
      expect(loaded[0].positionMs, 30000);
      expect(loaded[1].id, bm2.id);
      expect(loaded[1].positionMs, 90000);

      persistence.deleteBookmark(bm1.id);
      expect(persistence.loadBookmarks('episode_1').length, 1);

      env.dbService.resetDatabase();
      expect(persistence.loadBookmarks('episode_1'), isEmpty);
      expect(persistence.loadBookmarks('episode_2'), isEmpty);
    });
  });

  group('SettingsController subtitle & hwdec persistence', () {
    test('persists and resets subtitle defaults, style, and hwdec', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final settings = SettingsController(env.dbService);
      await settings.load();

      expect(settings.subtitlesEnabledByDefault, isFalse);
      expect(settings.preferredSubtitleLanguage, AppStrings.subtitleLangCodeDe);
      expect(settings.subtitleScale, AppSpacing.subtitleScaleDefault);
      expect(settings.subtitlePosition, AppSpacing.subtitlePositionDefault);
      expect(settings.subtitleBgOpacity, AppSpacing.subtitleBgOpacityDefault);
      expect(settings.hardwareAccelerationEnabled, isTrue);

      settings.updateSubtitlesDefaultEnabled(true);
      settings.updatePreferredSubtitleLanguage(AppStrings.subtitleLangCodeEn);
      settings.updateSubtitleStyle(scale: 1.4, position: 85, bgOpacity: 0.5);
      settings.updateHardwareAcceleration(false);

      final reloaded = SettingsController(env.dbService);
      await reloaded.load();
      expect(reloaded.subtitlesEnabledByDefault, isTrue);
      expect(reloaded.preferredSubtitleLanguage, AppStrings.subtitleLangCodeEn);
      expect(reloaded.subtitleScale, 1.4);
      expect(reloaded.subtitlePosition, 85);
      expect(reloaded.subtitleBgOpacity, 0.5);
      expect(reloaded.hardwareAccelerationEnabled, isFalse);

      await reloaded.resetDatabase();
      expect(reloaded.subtitlesEnabledByDefault, isFalse);
      expect(reloaded.preferredSubtitleLanguage, AppStrings.subtitleLangCodeDe);
      expect(reloaded.subtitleScale, AppSpacing.subtitleScaleDefault);
      expect(reloaded.subtitlePosition, AppSpacing.subtitlePositionDefault);
      expect(reloaded.subtitleBgOpacity, AppSpacing.subtitleBgOpacityDefault);
      expect(reloaded.hardwareAccelerationEnabled, isTrue);

      reloaded.dispose();
      settings.dispose();
    });
  });
}
