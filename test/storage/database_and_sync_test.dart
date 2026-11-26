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
  });
}
