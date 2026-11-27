import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/features/player/playback_persistence_service.dart';
import 'package:sqlite3/sqlite3.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('Database v1 -> v2 migration & idempotency', () {
    test('migrates v1 schema to v2 preserving existing data', () async {
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
        "INSERT INTO series (id, title, folder_path) VALUES (1, 'Dark', 'D:\\Dark');",
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
      expect(db.select('PRAGMA user_version;').first.values.first, 2);

      final cols = db
          .select('PRAGMA table_info(series_preferences);')
          .map((r) => r['name'] as String)
          .toSet();
      expect(cols, contains('intro_skip_seconds'));

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
        2,
      );
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
