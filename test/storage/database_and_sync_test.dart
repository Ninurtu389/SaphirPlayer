import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/core/storage/portable_paths.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/theme/effect_mode.dart';
import 'package:saphir_player/features/scanner/nas_scanner_service.dart';
import 'package:saphir_player/features/stats/stats_controller.dart';

void main() {
  late Directory tempRoot;
  late DatabaseService dbService;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('saphir_storage_test_');
    PortablePaths.testBaseDirectoryOverride = p.join(tempRoot.path, 'app_base');
    dbService = DatabaseService();
    await dbService.open(dbPath: p.join(tempRoot.path, 'test.db'));
  });

  tearDown(() async {
    dbService.close();
    PortablePaths.testBaseDirectoryOverride = null;
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  group('SettingsController multi-folder & persistence', () {
    test('migrates legacy single nas_root_path and supports add/remove',
        () async {
      dbService.instance.execute(
        "INSERT INTO app_settings (key, value) VALUES ('nas_root_path', ?);",
        [r'\\NAS\Legacy'],
      );

      final settings = SettingsController(dbService);
      await settings.load();

      expect(settings.nasPaths, [r'\\NAS\Legacy']);
      expect(settings.nasPath, r'\\NAS\Legacy');

      // Duplicate check (case-insensitive)
      expect(settings.addNasPath(r'\\nas\legacy'), isFalse);
      expect(settings.addNasPath(''), isFalse);

      // Add second folder
      expect(settings.addNasPath(r'\\NAS\Filme'), isTrue);
      expect(settings.nasPaths, [r'\\NAS\Legacy', r'\\NAS\Filme']);

      // Reload from DB to verify persistence
      final reloaded = SettingsController(dbService);
      await reloaded.load();
      expect(reloaded.nasPaths, [r'\\NAS\Legacy', r'\\NAS\Filme']);

      // Remove first folder
      reloaded.removeNasPath(r'\\NAS\Legacy');
      expect(reloaded.nasPaths, [r'\\NAS\Filme']);
      expect(reloaded.nasPath, r'\\NAS\Filme');
    });

    test('persists EffectMode per-device and globally', () async {
      final settings = SettingsController(dbService);
      await settings.load();

      settings.updateEffectMode(EffectMode.lean);
      settings.updatePerDeviceEffect(false);
      settings.save();

      final reloaded = SettingsController(dbService);
      await reloaded.load();
      expect(reloaded.perDeviceEffect, isFalse);
      expect(reloaded.effectMode, EffectMode.lean);
    });
  });

  group('NasScannerService multi-folder scanning', () {
    test('scans multiple roots, reads metadata, and preserves offline roots',
        () async {
      final seriesRoot = Directory(p.join(tempRoot.path, 'nas_serien'))
        ..createSync(recursive: true);
      final moviesRoot = Directory(p.join(tempRoot.path, 'nas_filme'))
        ..createSync(recursive: true);

      final showDir = Directory(p.join(seriesRoot.path, 'Andor', 'Season 1'))
        ..createSync(recursive: true);
      File(p.join(seriesRoot.path, 'Andor', 'info.json'))
          .writeAsStringSync('{"summary": "Rebellion beginnt."}');
      File(p.join(showDir.path, 'Andor - S01E01 - Kassa.mkv'))
          .writeAsBytesSync([0]);

      File(p.join(moviesRoot.path, 'Arrival (2016).mkv')).writeAsBytesSync([0]);

      final scanner = NasScannerService(dbService);
      final result =
          await scanner.scanLibrary([seriesRoot.path, moviesRoot.path]);

      expect(result.nasReachable, isTrue);
      expect(result.skippedDueToPlayback, isFalse);
      expect(result.seriesCount, 1);
      expect(result.movieCount, 1);

      final seriesRow = dbService.instance
          .select('SELECT title, summary FROM series LIMIT 1;')
          .first;
      expect(seriesRow['title'], 'Andor');
      expect(seriesRow['summary'], 'Rebellion beginnt.');

      // Now scan only moviesRoot while seriesRoot is offline/unreachable
      seriesRoot.deleteSync(recursive: true);
      final partialResult =
          await scanner.scanLibrary([seriesRoot.path, moviesRoot.path]);

      expect(partialResult.nasReachable, isTrue);
      expect(partialResult.seriesCount, 1);
      expect(partialResult.movieCount, 1);
    });

    test('skips scan when playback is active', () async {
      final scanner = NasScannerService(dbService);
      scanner.setPlaybackActive(true);

      final result = await scanner.scanLibrary([tempRoot.path]);
      expect(result.skippedDueToPlayback, isTrue);
    });
  });

  group('ProgressSyncService', () {
    test('merges local and remote progress_sync.json by updated_at', () async {
      final syncDir = Directory(p.join(tempRoot.path, 'sync_root'))
        ..createSync(recursive: true);
      final syncFile = File(p.join(syncDir.path, 'progress_sync.json'));

      syncFile.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'entries': {
            'episode_1': {
              'media_type': 'episode',
              'position_ms': 45000,
              'duration_ms': 120000,
              'completed': false,
              'updated_at': 2000,
              'source_device': 'Tablet',
            },
          },
        }),
      );

      dbService.instance.execute(
        '''
        INSERT INTO watch_progress (
          media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device
        ) VALUES ('episode_1', 'episode', 10000, 120000, 0, 1000, 'Laptop');
        ''',
      );

      final syncService = ProgressSyncService(dbService);
      await syncService.syncWithRoots([
        p.join(tempRoot.path, 'non_existent'),
        syncDir.path,
      ]);

      final row = dbService.instance
          .select(
              "SELECT position_ms, source_device FROM watch_progress WHERE media_key = 'episode_1';")
          .first;
      expect(row['position_ms'], 45000);
      expect(row['source_device'], 'Tablet');
    });

    test('NasScannerService groups numeric season folders under single series',
        () async {
      final rootDir = Directory(p.join(tempRoot.path, 'Serien'));
      final s1Dir = Directory(p.join(rootDir.path, 'Dark', '01'))
        ..createSync(recursive: true);
      final s5Dir = Directory(p.join(rootDir.path, 'Dark', '05'))
        ..createSync(recursive: true);

      File(p.join(s1Dir.path, '1.01 Pilot.mkv')).writeAsStringSync('v');
      File(p.join(s5Dir.path, '5.02 Finale.mkv')).writeAsStringSync('v');

      final scanner = NasScannerService(dbService);
      final result = await scanner.scanLibrary([rootDir.path]);

      expect(result.seriesCount, 1);
      expect(result.movieCount, 0);

      final seriesRows = dbService.instance.select('SELECT title FROM series;');
      expect(seriesRows.length, 1);
      expect(seriesRows.first['title'], 'Dark');
    });

    test('StatsController aggregates watch_history and resetDatabase clears it',
        () {
      final db = dbService.instance;
      final now = DateTime.now();
      final todayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      db.execute(
        '''
        INSERT INTO watch_history (
          media_key, media_type, title, series_id, watched_ms, started_at, ended_at, day_key, weekday, source_device
        ) VALUES
          ('episode_1', 'episode', 'Dark', 1, 1800000, 1000, 1801000, ?, ?, 'PC'),
          ('movie_1', 'movie', 'Interstellar', NULL, 3600000, 2000, 3602000, ?, ?, 'PC');
        ''',
        [todayKey, now.weekday, todayKey, now.weekday],
      );

      final statsController = StatsController(dbService);
      statsController.refreshStats();

      expect(statsController.summary.totalWatchMs, 5400000);
      expect(statsController.summary.seriesWatchMs, 1800000);
      expect(statsController.summary.movieWatchMs, 3600000);
      expect(statsController.summary.currentStreakDays, 1);
      expect(statsController.summary.topSeries.first.title, 'Dark');
      expect(statsController.summary.topMovies.first.title, 'Interstellar');

      dbService.resetDatabase();
      statsController.refreshStats();
      expect(statsController.summary.totalWatchMs, 0);
      expect(statsController.summary.topSeries, isEmpty);
    });
  });
}
