import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/database_backup_service.dart';
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/storage/thumbnail_cache_service.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/scanner/media_tag_reader_service.dart';
import 'package:saphir_player/features/scanner/nas_scanner_service.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import 'package:saphir_player/features/stats/stats_controller.dart';
import 'package:sqlite3/sqlite3.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('A25 Database Backup & Restore', () {
    test(
        'backup during active WAL mode captures committed data, validates integrity, and enforces retention',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      seedSampleLibrary(env.dbService);
      // Zusätzliche WAL-Transaktionen ohne DB-Close
      env.dbService.instance.execute(
        "INSERT INTO media_bookmarks (media_key, position_ms, label, created_at) VALUES ('episode_1', 42000, 'WAL-Szene', 1000);",
      );

      final backupService = DatabaseBackupService(maxRetention: 2);
      final b1 =
          await backupService.createBackup(env.dbService, reason: 'manual');
      final b2 =
          await backupService.createBackup(env.dbService, reason: 'manual');
      final b3 =
          await backupService.createBackup(env.dbService, reason: 'manual');

      expect(b1.success, isTrue);
      expect(b2.success, isTrue);
      expect(b3.success, isTrue);
      expect(
        DatabaseBackupService.validateBackupFile(b3.backupInfo!.filePath).valid,
        isTrue,
      );

      final listed = await backupService.listBackups();
      expect(listed.length, 2);

      // Snapshot enthält wirklich die WAL-Daten
      final ro = sqlite3.open(b3.backupInfo!.filePath, mode: OpenMode.readOnly);
      addTearDown(ro.dispose);
      expect(
        ro
            .select(
                "SELECT label FROM media_bookmarks WHERE media_key = 'episode_1';")
            .first['label'],
        'WAL-Szene',
      );
    });

    test(
        'restore recovers series, progress, history, bookmarks, and settings while creating pre_restore backup',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      seedSampleLibrary(env.dbService);
      env.dbService.instance.execute(
        "INSERT INTO app_settings (key, value) VALUES ('custom_key', 'wert_1');",
      );
      env.dbService.instance.execute(
        "INSERT INTO media_bookmarks (media_key, position_ms, label, created_at) VALUES ('episode_1', 55000, 'Merker', 2000);",
      );
      env.dbService.instance.execute(
        "INSERT INTO watch_history (media_key, media_type, title, series_id, watched_ms, started_at, ended_at, day_key, weekday, source_device) VALUES ('episode_1', 'episode', 'Dark', 1, 900000, 1000, 901000, '2026-11-28', 6, 'PC');",
      );

      final backupService = DatabaseBackupService();
      final backup = await backupService.createBackup(env.dbService);
      expect(backup.success, isTrue);

      // Alles zurücksetzen
      env.dbService.resetDatabase();
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM series;')
            .first['c'],
        0,
      );

      final restore = await backupService.restoreBackup(
        env.dbService,
        backup.backupInfo!.filePath,
      );
      expect(restore.success, isTrue);
      expect(restore.preRestoreBackupPath, isNotNull);
      expect(File(restore.preRestoreBackupPath!).existsSync(), isTrue);

      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM series;')
            .first['c'],
        2,
      );
      expect(
        env.dbService.instance
            .select("SELECT value FROM app_settings WHERE key = 'custom_key';")
            .first['value'],
        'wert_1',
      );
      expect(
        env.dbService.instance
            .select(
                "SELECT label FROM media_bookmarks WHERE media_key = 'episode_1';")
            .first['label'],
        'Merker',
      );
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM watch_history;')
            .first['c'],
        1,
      );
    });

    test('corrupt backup is rejected and live DB remains untouched', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      seedSampleLibrary(env.dbService);
      final corruptFile = File(p.join(env.tempRoot.path, 'corrupt_backup.db'))
        ..writeAsBytesSync(const [0xDE, 0xAD, 0xBE, 0xEF, 0x00]);

      final backupService = DatabaseBackupService();
      final restore = await backupService.restoreBackup(
        env.dbService,
        corruptFile.path,
      );
      expect(restore.success, isFalse);
      expect(env.dbService.isOpen, isTrue);
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM series;')
            .first['c'],
        2,
      );
    });

    test('automatic pre_migration backup is created when opening legacy schema',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final dbDir = env.createSubdir('migration_test_dir');
      final legacyPath = p.join(dbDir.path, 'legacy.db');
      final raw = sqlite3.open(legacyPath);
      raw.execute('''
        CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE series (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, folder_path TEXT NOT NULL UNIQUE, poster_path TEXT, summary TEXT, last_watched_at INTEGER);
        CREATE TABLE seasons (id INTEGER PRIMARY KEY AUTOINCREMENT, series_id INTEGER NOT NULL, season_number INTEGER NOT NULL, folder_path TEXT NOT NULL);
        CREATE TABLE episodes (id INTEGER PRIMARY KEY AUTOINCREMENT, series_id INTEGER NOT NULL, season_id INTEGER NOT NULL, episode_number INTEGER NOT NULL, title TEXT NOT NULL, file_path TEXT NOT NULL UNIQUE, duration_ms INTEGER NOT NULL DEFAULT 0, thumb_path TEXT, sync_key TEXT, thumb_status TEXT NOT NULL DEFAULT 'pending', artist TEXT, file_size INTEGER NOT NULL DEFAULT 0, modified_at INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE movies (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, release_year INTEGER, file_path TEXT NOT NULL UNIQUE, poster_path TEXT, thumb_path TEXT, duration_ms INTEGER NOT NULL DEFAULT 0, last_watched_at INTEGER, sync_key TEXT, thumb_status TEXT NOT NULL DEFAULT 'pending', artist TEXT, file_size INTEGER NOT NULL DEFAULT 0, modified_at INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE watch_progress (media_key TEXT PRIMARY KEY, media_type TEXT NOT NULL, position_ms INTEGER NOT NULL DEFAULT 0, duration_ms INTEGER NOT NULL DEFAULT 0, completed INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL, source_device TEXT NOT NULL);
        CREATE TABLE series_preferences (series_id INTEGER PRIMARY KEY, audio_track TEXT, subtitle_track TEXT, intro_skip_seconds INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE media_bookmarks (id INTEGER PRIMARY KEY AUTOINCREMENT, media_key TEXT NOT NULL, position_ms INTEGER NOT NULL, label TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL);
        CREATE TABLE watch_history (id INTEGER PRIMARY KEY AUTOINCREMENT, media_key TEXT NOT NULL, media_type TEXT NOT NULL, title TEXT NOT NULL, series_id INTEGER, watched_ms INTEGER NOT NULL DEFAULT 0, started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL, day_key TEXT NOT NULL, weekday INTEGER NOT NULL, source_device TEXT NOT NULL);
      ''');
      raw.execute('PRAGMA user_version = 4;');
      raw.dispose();

      final service = DatabaseService();
      await service.open(dbPath: legacyPath);
      addTearDown(service.close);

      final backups = await DatabaseBackupService(
        backupDirectoryOverride: p.join(dbDir.path, 'backups'),
      ).listBackups();
      expect(backups, isNotEmpty);
      expect(backups.first.reason, 'pre_migration');
    });

    test('reset is aborted if mandatory pre_reset backup fails', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      seedSampleLibrary(env.dbService);

      // Blockiere Backup-Pfad mit einer regulären Datei
      final blockedBackupPath =
          File(p.join(env.tempRoot.path, 'blocked_backups'))
            ..writeAsStringSync('not_a_dir');

      final settings = SettingsController(
        env.dbService,
        backupService: DatabaseBackupService(
          backupDirectoryOverride: blockedBackupPath.path,
        ),
      );
      await settings.load();

      final resetRes =
          await settings.resetDatabaseWithBackup(requireBackup: true);
      expect(resetRes.success, isFalse);
      // Bestehende Daten müssen vollständig erhalten sein
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM series;')
            .first['c'],
        2,
      );
      settings.dispose();
    });
  });

  group('A03 & A09 Reset, Sync, Scan & Cache-Clear mutual exclusion', () {
    test(
        'reset during active scan cancels scan, waits for completion, leaves DB empty, and re-enables subsequent scans',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('reset_scan_root');
      createSyntheticMp4HeaderFile(root, 'Dune (2021).mkv');

      final gate = ThumbnailOperationGate();
      final syncService = ProgressSyncService(env.dbService);
      final settings = SettingsController(
        env.dbService,
        syncService: syncService,
        thumbnailGate: gate,
      );
      await settings.load();
      settings.addNasPath(root.path);

      final scanStarted = Completer<void>();
      final scanGate = Completer<void>();
      final scanner = NasScannerService(
        env.dbService,
        thumbnailGate: gate,
        tagReader: (_) async {
          if (!scanStarted.isCompleted) scanStarted.complete();
          await scanGate.future;
          return const EmbeddedMediaTags(title: 'Dune', releaseYear: 2021);
        },
      );
      final library = LibraryController(
        env.dbService,
        settings,
        scannerService: scanner,
      );
      final home = HomeController(env.dbService);
      final stats = StatsController(env.dbService);
      final shell = ShellController(
        settingsController: settings,
        libraryController: library,
        homeController: home,
        statsController: stats,
        databaseService: env.dbService,
      );

      final activeScanFuture = library.refreshLibrary();
      await scanStarted.future;

      var resetDone = false;
      final resetFuture = shell.handleResetDatabase().then((_) {
        resetDone = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resetDone, isFalse);
      expect(shell.isMaintenanceInProgress, isTrue);

      scanGate.complete();
      await Future.wait([activeScanFuture, resetFuture]);

      expect(resetDone, isTrue);
      expect(shell.isMaintenanceInProgress, isFalse);
      expect(shell.statusMessage, AppStrings.databaseResetStatus);
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM movies;')
            .first['c'],
        0,
      );
      expect(settings.latestBackup, isNotNull);

      // Danach muss ein neuer Scan wieder möglich sein
      settings.addNasPath(root.path);
      await library.refreshLibrary();
      expect(library.movieCount, 1);

      shell.dispose();
      stats.dispose();
      home.dispose();
      library.dispose();
      settings.dispose();
    });

    test(
        'clearCacheWithResult waits for active thumbnail generation, serializes parallel clears, and reports locked file warnings',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final cacheDir =
          env.createSubdir(p.join('app_base', 'cache', 'thumbnails'));
      createValidTinyJpeg(cacheDir, 'ep_existing.jpg');

      final gate = ThumbnailOperationGate();
      final cacheService = ThumbnailCacheService(gate: gate);

      // 1) Aktive Thumbnail-Generierung blockiert Cache-Clear bis zum Abschluss
      final genStarted = Completer<void>();
      final genRelease = Completer<void>();
      final genFuture = gate.trackGenerationTask(() async {
        genStarted.complete();
        await genRelease.future;
        createValidTinyJpeg(cacheDir, 'ep_generated.jpg');
      });
      await genStarted.future;

      var clearFinished = false;
      final clear1 =
          cacheService.clearCacheWithResult(env.dbService).then((res) {
        clearFinished = true;
        return res;
      });
      final clear2 = cacheService.clearCacheWithResult(env.dbService);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(clearFinished, isFalse);

      genRelease.complete();
      await genFuture;
      final results = await Future.wait([clear1, clear2]);
      expect(clearFinished, isTrue);
      expect(results[0].remainingBytes, 0);
      expect(results[1].remainingBytes, 0);

      // 2) Gesperrte Datei erzeugt Warnstatus und wird beim nächsten Clear gelöscht
      final lockedFile = createValidTinyJpeg(cacheDir, 'ep_locked.jpg');
      final lockHandle = lockedFile.openSync(mode: FileMode.append);
      var handleClosed = false;
      addTearDown(() {
        if (!handleClosed) {
          lockHandle.closeSync();
        }
      });

      final warnRes = await cacheService.clearCacheWithResult(env.dbService);
      expect(warnRes.hasWarnings, isTrue);
      expect(warnRes.failedCount, 1);
      expect(warnRes.failedPaths, contains(lockedFile.path));
      expect(warnRes.remainingBytes, greaterThan(0));

      lockHandle.closeSync();
      handleClosed = true;

      final cleanRes = await cacheService.clearCacheWithResult(env.dbService);
      expect(cleanRes.hasWarnings, isFalse);
      expect(cleanRes.deletedCount, 1);
      expect(cleanRes.remainingBytes, 0);
    });

    test('reset waits for active sync job before wiping DB', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final nasDir = env.createSubdir('sync_before_reset');
      env.dbService.instance.execute(
        "INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device) VALUES ('ep_v2_wait', 'episode', 12000, 60000, 0, 5000, 'PC');",
      );

      final syncService = ProgressSyncService(env.dbService);
      final settings = SettingsController(
        env.dbService,
        syncService: syncService,
      );
      await settings.load();

      // Starte Sync und Reset direkt nacheinander
      final syncFuture = syncService.syncWithStorage(nasDir.path);
      final resetFuture = settings.resetDatabaseWithBackup(requireBackup: true);

      final results = await Future.wait([syncFuture, resetFuture]);
      expect((results[0] as SyncResult).syncedToNas, isTrue);
      expect((results[1] as BackupResult).success, isTrue);
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM watch_progress;')
            .first['c'],
        0,
      );
      settings.dispose();
    });
  });
}
