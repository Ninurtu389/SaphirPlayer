import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/storage/sync_key_utils.dart';
import 'package:saphir_player/core/storage/sync_validator.dart';
import 'package:saphir_player/features/scanner/nas_scan_repository.dart';
import 'package:saphir_player/features/scanner/nas_scanner_service.dart';
import 'package:sqlite3/sqlite3.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('A06 Stable source identity & conflict protection', () {
    test(
        'two roots with identical relative structure produce distinct v2 keys and scan without collision',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final shareA = env.createSubdir('ShareA');
      final shareB = env.createSubdir('ShareB');
      final dirA = Directory(p.join(shareA.path, 'Dark', 'Season 1'))
        ..createSync(recursive: true);
      final dirB = Directory(p.join(shareB.path, 'Dark', 'Season 1'))
        ..createSync(recursive: true);

      final epA =
          createSyntheticMp4HeaderFile(dirA, 'Dark - S01E01 - Pilot.mkv');
      final epB =
          createSyntheticMp4HeaderFile(dirB, 'Dark - S01E01 - Pilot.mkv');

      final scanner = NasScannerService(env.dbService);
      final result = await scanner.scanLibrary([shareA.path, shareB.path]);

      expect(result.nasReachable, isTrue);
      expect(result.hasIdentityConflicts, isFalse);

      final epRows = env.dbService.instance
          .select('SELECT file_path, sync_key FROM episodes ORDER BY id ASC;');
      expect(epRows.length, 2);
      expect(
          SyncKeyUtils.isV2SyncKey(epRows[0]['sync_key'] as String?), isTrue);
      expect(
          SyncKeyUtils.isV2SyncKey(epRows[1]['sync_key'] as String?), isTrue);
      expect(epRows[0]['sync_key'], isNot(epRows[1]['sync_key']));
      expect(epA.existsSync() && epB.existsSync(), isTrue);

      // Even identically named folders under different paths get disambiguated source_ids
      final nested1 = env.createSubdir(p.join('Disk1', 'Serien'));
      final nested2 = env.createSubdir(p.join('Disk2', 'Serien'));
      final id1 = env.dbService.ensureMediaSource(nested1.path);
      final id2 = env.dbService.ensureMediaSource(nested2.path);
      expect(id1, isNot(id2));
    });

    test(
        'same share mounted via UNC or drive letter generates identical v2 key',
        () {
      final uncKey = SyncKeyUtils.buildStableSyncKey(
        'ep',
        r'\\NAS\Serien\Dark\Season 1\S01E01.mkv',
        r'\\NAS\Serien',
      );
      final driveKey = SyncKeyUtils.buildStableSyncKey(
        'ep',
        r'Z:\Serien\Dark\Season 1\S01E01.mkv',
        r'Z:\Serien',
      );
      expect(SyncKeyUtils.isV2SyncKey(uncKey), isTrue);
      expect(uncKey, driveKey);

      final explicitKeyA = SyncKeyUtils.buildStableSyncKey(
        'mv',
        r'\\NAS\ShareOne\Arrival (2016).mkv',
        r'\\NAS\ShareOne',
        sourceId: 'home_movies',
      );
      final explicitKeyB = SyncKeyUtils.buildStableSyncKey(
        'mv',
        r'M:\Arrival (2016).mkv',
        r'M:\',
        sourceId: 'home_movies',
      );
      expect(explicitKeyA, explicitKeyB);
    });

    test(
        'migrates DB v4 v1 sync_keys to v5 v2 keys preserving progress, history and bookmarks',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final v4Path = p.join(env.tempRoot.path, 'legacy_v4.db');
      final raw = sqlite3.open(v4Path);
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

      const root = r'\\NAS\Serien';
      const epPath = r'\\NAS\Serien\Dark\S01E01.mkv';
      final oldV1Key = SyncKeyUtils.buildLegacyV1SyncKey('ep', epPath, root);

      raw.execute(
        "INSERT INTO app_settings (key, value) VALUES ('nas_root_paths', ?);",
        [
          jsonEncode([root])
        ],
      );
      raw.execute(
        "INSERT INTO series (id, title, folder_path) VALUES (1, 'Dark', '\\\\NAS\\Serien\\Dark');",
      );
      raw.execute(
        "INSERT INTO seasons (id, series_id, season_number, folder_path) VALUES (1, 1, 1, '\\\\NAS\\Serien\\Dark');",
      );
      raw.execute(
        "INSERT INTO episodes (id, series_id, season_id, episode_number, title, file_path, sync_key) VALUES (1, 1, 1, 1, 'Pilot', ?, ?);",
        [epPath, oldV1Key],
      );
      raw.execute(
        "INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device) VALUES (?, 'episode', 120000, 300000, 0, 5000, 'DeviceA');",
        [oldV1Key],
      );
      raw.execute(
        "INSERT INTO media_bookmarks (media_key, position_ms, label, created_at) VALUES (?, 60000, 'Intro', 5000);",
        [oldV1Key],
      );
      raw.execute(
        "INSERT INTO watch_history (media_key, media_type, title, series_id, watched_ms, started_at, ended_at, day_key, weekday, source_device) VALUES (?, 'episode', 'Dark', 1, 120000, 1000, 2000, '2026-11-28', 6, 'DeviceA');",
        [oldV1Key],
      );
      raw.execute('PRAGMA user_version = 4;');
      raw.dispose();

      final service = DatabaseService();
      await service.open(dbPath: v4Path);
      addTearDown(service.close);

      final expectedV2Key = SyncKeyUtils.buildStableSyncKey('ep', epPath, root);
      final epRow = service.instance
          .select('SELECT sync_key FROM episodes WHERE id = 1;')
          .first;
      expect(epRow['sync_key'], expectedV2Key);

      final sources = service.loadSourceIdsByRoot();
      expect(sources[root], 'serien');

      expect(
        service.instance.select(
          'SELECT position_ms FROM watch_progress WHERE media_key = ?;',
          [expectedV2Key],
        ).first['position_ms'],
        120000,
      );
      expect(
        service.instance.select(
          'SELECT label FROM media_bookmarks WHERE media_key = ?;',
          [expectedV2Key],
        ).first['label'],
        'Intro',
      );
      expect(
        service.instance.select(
          'SELECT watched_ms FROM watch_history WHERE media_key = ?;',
          [expectedV2Key],
        ).first['watched_ms'],
        120000,
      );
    });

    test(
        'duplicate sync_key in scan output is reported as identityConflict without aborting DB transaction',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('conflict_root');
      final repo = NasScanRepository(env.dbService);

      final summary = repo.applyDiffWithSummary(
        ScanOutput(
          nasReachable: true,
          reachableRoots: [root.path],
          completeRoots: [root.path],
          seriesList: const [],
          movies: [
            ScannedMovieData(
              title: 'Movie One',
              releaseYear: 2020,
              filePath: p.join(root.path, 'MovieOne.mkv'),
              posterPath: null,
              syncKey: 'mv_v2_shared_collision',
            ),
            ScannedMovieData(
              title: 'Movie Two',
              releaseYear: 2021,
              filePath: p.join(root.path, 'MovieTwo.mkv'),
              posterPath: null,
              syncKey: 'mv_v2_shared_collision',
            ),
          ],
        ),
      );

      expect(summary.identityConflicts.length, 1);
      expect(summary.identityConflicts.first.syncKey, 'mv_v2_shared_collision');
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM movies;')
            .first['c'],
        1,
      );
    });
  });

  group('A05 Multi-device sync concurrency, locking & tie-breakers', () {
    test(
        'two independent ProgressSyncService instances write different episodes concurrently without lost updates',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final nasDir = env.createSubdir('shared_nas_sync');
      final dbA = DatabaseService();
      final dbB = DatabaseService();
      await dbA.open(dbPath: p.join(env.tempRoot.path, 'a.db'));
      await dbB.open(dbPath: p.join(env.tempRoot.path, 'b.db'));
      addTearDown(dbA.close);
      addTearDown(dbB.close);

      dbA.instance.execute(
        "INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device) VALUES ('ep_v2_1', 'episode', 15000, 100000, 0, 5000, 'DeviceA');",
      );
      dbB.instance.execute(
        "INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device) VALUES ('ep_v2_2', 'episode', 45000, 100000, 0, 5000, 'DeviceB');",
      );

      final syncA = ProgressSyncService(dbA, writerId: 'writer_a');
      final syncB = ProgressSyncService(dbB, writerId: 'writer_b');

      final results = await Future.wait([
        syncA.syncWithStorage(nasDir.path),
        syncB.syncWithStorage(nasDir.path),
      ]);
      expect(results[0].syncedToNas, isTrue);
      expect(results[1].syncedToNas, isTrue);
      expect(results[0].status, SyncStatus.synced);
      expect(results[1].status, SyncStatus.synced);

      // Final pull on both ensures both entries exist everywhere
      await syncA.syncWithStorage(nasDir.path);
      await syncB.syncWithStorage(nasDir.path);

      expect(
        dbA.instance
            .select('SELECT COUNT(*) AS c FROM watch_progress;')
            .first['c'],
        2,
      );
      expect(
        dbB.instance
            .select('SELECT COUNT(*) AS c FROM watch_progress;')
            .first['c'],
        2,
      );
      expect(
        Directory(p.join(nasDir.path, 'progress_sync.json.lock.d'))
            .existsSync(),
        isFalse,
      );
      final tempFiles =
          nasDir.listSync().where((e) => p.basename(e.path).contains('.tmp.'));
      expect(tempFiles, isEmpty);
    });

    test(
        'concurrent updates on same key resolve deterministically on equal timestamps',
        () {
      const a = SyncEntry(
        mediaKey: 'ep_v2_same',
        mediaType: 'episode',
        positionMs: 30000,
        durationMs: 100000,
        completed: false,
        updatedAt: 10000,
        sourceDevice: 'Alpha',
        revision: 1,
      );
      const b = SyncEntry(
        mediaKey: 'ep_v2_same',
        mediaType: 'episode',
        positionMs: 60000,
        durationMs: 100000,
        completed: false,
        updatedAt: 10000,
        sourceDevice: 'Beta',
        revision: 2,
      );
      expect(SyncEntry.resolveConflict(a, b).revision, 2);

      const c = SyncEntry(
        mediaKey: 'ep_v2_same',
        mediaType: 'episode',
        positionMs: 10000,
        durationMs: 100000,
        completed: true,
        updatedAt: 10000,
        sourceDevice: 'Alpha',
        revision: 2,
      );
      expect(SyncEntry.resolveConflict(b, c).completed, isTrue);
    });

    test('stale lock directory left by crashed writer is recovered safely',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final nasDir = env.createSubdir('stale_lock_nas');
      final lockDir =
          Directory(p.join(nasDir.path, 'progress_sync.json.lock.d'))
            ..createSync(recursive: true);
      File(p.join(lockDir.path, 'owner.json')).writeAsStringSync(
        jsonEncode({
          'writer_id': 'crashed_pc',
          'pid': 99999,
          'acquired_at': 1000,
          'expires_at': 2000, // already expired
        }),
      );

      env.dbService.instance.execute(
        "INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device) VALUES ('mv_v2_ok', 'movie', 25000, 90000, 0, 5000, 'PC');",
      );

      final sync = ProgressSyncService(env.dbService, writerId: 'survivor');
      final res = await sync.syncWithStorage(nasDir.path);
      expect(res.syncedToNas, isTrue);
      expect(res.status, SyncStatus.synced);
      expect(lockDir.existsSync(), isFalse);
    });
  });

  group('A12 & A32 Corrupt sync protection, schema validation & recovery', () {
    test(
        'invalid JSON is preserved untouched, backed up for diagnostics, and never overwritten',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final nasDir = env.createSubdir('corrupt_nas');
      final syncFile = File(p.join(nasDir.path, 'progress_sync.json'));
      const corruptPayload = '{broken_json_from_other_device';
      syncFile.writeAsStringSync(corruptPayload);

      env.dbService.instance.execute(
        "INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device) VALUES ('ep_v2_local', 'episode', 10000, 60000, 0, 1000, 'PC');",
      );

      final sync = ProgressSyncService(env.dbService);
      final res = await sync.syncWithStorage(nasDir.path);

      expect(res.syncedToNas, isFalse);
      expect(res.status, SyncStatus.corrupt);
      expect(res.corruptBackupPath, isNotNull);
      expect(File(res.corruptBackupPath!).existsSync(), isTrue);
      expect(syncFile.readAsStringSync(), corruptPayload);
    });

    test(
        'unknown future sync version is preserved and reported as incompatibleVersion',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final nasDir = env.createSubdir('future_version_nas');
      final syncFile = File(p.join(nasDir.path, 'progress_sync.json'));
      final futurePayload = jsonEncode({'version': 99, 'entries': {}});
      syncFile.writeAsStringSync(futurePayload);

      final sync = ProgressSyncService(env.dbService);
      final res = await sync.syncWithStorage(nasDir.path);

      expect(res.syncedToNas, isFalse);
      expect(res.status, SyncStatus.incompatibleVersion);
      expect(syncFile.readAsStringSync(), futurePayload);
    });

    test(
        'A32 rejects negative values, unknown media_type, oversized keys, and oversized payloads while importing valid entries and legacy v1',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final nasDir = env.createSubdir('validation_nas');
      final syncFile = File(p.join(nasDir.path, 'progress_sync.json'));
      syncFile.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'entries': {
            'ep_valid_v1': {
              'media_type': 'episode',
              'position_ms': 45000,
              'duration_ms': 120000,
              'completed': false,
              'updated_at': 5000,
              'source_device': 'LegacyPC',
            },
            'bad_negative_pos': {
              'media_type': 'episode',
              'position_ms': -10,
              'duration_ms': 120000,
              'completed': false,
              'updated_at': 5000,
              'source_device': 'BadPC',
            },
            'bad_unknown_type': {
              'media_type': 'podcast',
              'position_ms': 1000,
              'duration_ms': 120000,
              'completed': false,
              'updated_at': 5000,
              'source_device': 'BadPC',
            },
            'bad_unplausible_duration': {
              'media_type': 'movie',
              'position_ms': 1000,
              'duration_ms': 999999999,
              'completed': false,
              'updated_at': 5000,
              'source_device': 'BadPC',
            },
            'x' * 300: {
              'media_type': 'movie',
              'position_ms': 1000,
              'duration_ms': 120000,
              'completed': false,
              'updated_at': 5000,
              'source_device': 'BadPC',
            },
          },
        }),
      );

      final sync = ProgressSyncService(env.dbService);
      final res = await sync.syncWithStorage(nasDir.path);

      expect(res.syncedToNas, isTrue);
      expect(res.status, SyncStatus.synced);
      expect(res.isolatedEntryCount, 4);

      final rows = env.dbService.instance
          .select('SELECT media_key, position_ms FROM watch_progress;');
      expect(rows.length, 1);
      expect(rows.first['media_key'], 'ep_valid_v1');
      expect(rows.first['position_ms'], 45000);

      // Recovery API extracts valid entries from backup/external file
      final backupFile = File(p.join(nasDir.path, 'recovery_source.json'));
      backupFile.writeAsStringSync(
        jsonEncode({
          'version': 2,
          'entries': {
            'mv_recovered': {
              'media_type': 'movie',
              'position_ms': 88000,
              'duration_ms': 200000,
              'completed': false,
              'updated_at': 9000,
              'source_device': 'BackupDevice',
              'revision': 1,
            },
            'mv_invalid': {
              'media_type': 42,
              'position_ms': 10,
              'duration_ms': 100,
              'completed': false,
              'updated_at': 9000,
              'source_device': 'Bad',
            },
          },
        }),
      );
      final recoveryRes =
          await sync.recoverValidEntriesFromFile(backupFile.path);
      expect(recoveryRes.isolatedEntryCount, 1);
      expect(
        env.dbService.instance
            .select(
              "SELECT position_ms FROM watch_progress WHERE media_key = 'mv_recovered';",
            )
            .first['position_ms'],
        88000,
      );

      // Oversized payload is rejected before JSON decode
      final oversized = Uint8List(SyncSchema.maxFileSizeBytes + 1);
      final oversizedParse = SyncValidator.parseFileBytes(oversized);
      expect(oversizedParse.status, SyncParseStatus.oversized);
    });
  });
}
