import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/features/scanner/media_tag_reader_service.dart';
import 'package:saphir_player/features/scanner/nas_scan_repository.dart';
import 'package:saphir_player/features/scanner/nas_scanner_service.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('A02 Safe scan diffs & traversal integrity', () {
    test(
        'missing root alongside reachable root updates reachable root and preserves missing root entries',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final rootA = env.createSubdir('root_a');
      final rootB = env.createSubdir('root_b');
      createSyntheticMp4HeaderFile(rootA, 'Arrival (2016).mkv');
      createSyntheticMp4HeaderFile(rootB, 'Interstellar (2014).mkv');

      final scanner = NasScannerService(env.dbService);
      final initial = await scanner.scanLibrary([rootA.path, rootB.path]);
      expect(initial.nasReachable, isTrue);
      expect(initial.movieCount, 2);

      // rootA goes offline while rootB adds a new movie
      rootA.deleteSync(recursive: true);
      createSyntheticMp4HeaderFile(rootB, 'Dune (2021).mkv');

      final second = await scanner.scanLibrary([rootA.path, rootB.path]);
      expect(second.nasReachable, isTrue);
      expect(second.hasUnreachableSources, isTrue);
      expect(second.movieCount, 3);

      final reportA =
          second.sourceReports.firstWhere((r) => r.rootPath == rootA.path);
      final reportB =
          second.sourceReports.firstWhere((r) => r.rootPath == rootB.path);
      expect(reportA.status, SourceScanStatus.unreachable);
      expect(reportB.status, SourceScanStatus.complete);
    });

    test(
        'subfolder read error marks root partial, preserves unread subfolder episodes, and upserts readable siblings',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('partial_root');
      final showDir = Directory(p.join(root.path, 'Dark'))
        ..createSync(recursive: true);
      final season1 = Directory(p.join(showDir.path, 'Season 1'))
        ..createSync(recursive: true);
      final season2 = Directory(p.join(showDir.path, 'Season 2'))
        ..createSync(recursive: true);

      createSyntheticMp4HeaderFile(season1, 'Dark - S01E01 - Geheimnisse.mkv');
      createSyntheticMp4HeaderFile(season2, 'Dark - S02E01 - Anfaenge.mkv');

      final initialScanner = NasScannerService(env.dbService);
      final initial = await initialScanner.scanLibrary([root.path]);
      expect(initial.seriesCount, 1);
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM episodes;')
            .first['c'],
        2,
      );

      // Season 2 adds a new episode, while Season 1 fails with a directory error
      createSyntheticMp4HeaderFile(season2, 'Dark - S02E02 - Dunkel.mkv');
      final partialScanner = NasScannerService(
        env.dbService,
        directoryLister: (dir) {
          if (p.equals(dir.path, season1.path)) {
            throw FileSystemException('SMB access denied', dir.path);
          }
          return dir.listSync(recursive: false, followLinks: false);
        },
      );

      final partial = await partialScanner.scanLibrary([root.path]);
      expect(partial.nasReachable, isTrue);
      expect(partial.hasPartialSources, isTrue);
      expect(partial.sourceReports.single.status, SourceScanStatus.partial);
      expect(partial.sourceReports.single.errors, isNotEmpty);

      // All 3 episodes exist: S01E01 preserved, S02E02 added!
      final epCount = env.dbService.instance
          .select('SELECT COUNT(*) AS c FROM episodes;')
          .first['c'];
      expect(epCount, 3);
    });

    test('statSync failure marks root partial and prevents destructive diff',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('stat_err_root');
      final ep1 = createSyntheticMp4HeaderFile(root, 'Andor - S01E01.mkv');
      final ep2 = createSyntheticMp4HeaderFile(root, 'Andor - S01E02.mkv');

      final scanner1 = NasScannerService(env.dbService);
      await scanner1.scanLibrary([root.path]);
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM episodes;')
            .first['c'],
        2,
      );

      // Simulate statSync failure on ep2 (e.g. transient SMB error)
      final scanner2 = NasScannerService(
        env.dbService,
        fileStatReader: (file) {
          if (p.equals(file.path, ep2.path)) {
            throw FileSystemException('Transient stat error', file.path);
          }
          return file.statSync();
        },
      );
      final res = await scanner2.scanLibrary([root.path]);
      expect(res.hasPartialSources, isTrue);
      expect(res.sourceReports.single.status, SourceScanStatus.partial);
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM episodes;')
            .first['c'],
        2,
      );
      expect(ep1.existsSync(), isTrue);
    });

    test('deletion guard blocks suspicious mass deletion above threshold',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('mass_delete_root');
      final cacheDir =
          env.createSubdir(p.join('app_base', 'cache', 'thumbnails'));
      final files = <File>[];
      for (var i = 1; i <= 10; i++) {
        files.add(createSyntheticMp4HeaderFile(root, 'Movie $i (202$i).mkv'));
      }

      final scanner = NasScannerService(env.dbService);
      await scanner.scanLibrary([root.path]);
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM movies;')
            .first['c'],
        10,
      );

      final thumb = createValidTinyJpeg(cacheDir, 'mv_keep.jpg');
      env.dbService.instance.execute(
        'UPDATE movies SET thumb_path = ?;',
        [thumb.path],
      );

      // Delete 9 out of 10 files (90% >= 85% guard)
      for (var i = 0; i < 9; i++) {
        files[i].deleteSync();
      }

      final res = await scanner.scanLibrary([root.path]);
      expect(res.deletionBlockedByThreshold, isTrue);
      expect(res.deletionBlockedRoots, contains(root.path));
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM movies;')
            .first['c'],
        10,
      );
      expect(thumb.existsSync(), isTrue);
    });

    test(
        'cancelled ScanOutput and DB rollback never perform destructive cleanup',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('rollback_root');
      createSyntheticMp4HeaderFile(root, 'Arrival (2016).mkv');
      final scanner = NasScannerService(env.dbService);
      await scanner.scanLibrary([root.path]);

      final cacheDir =
          env.createSubdir(p.join('app_base', 'cache', 'thumbnails'));
      final thumb = createValidTinyJpeg(cacheDir, 'mv_rollback.jpg');
      env.dbService.instance.execute(
        'UPDATE movies SET thumb_path = ?;',
        [thumb.path],
      );

      final repo = NasScanRepository(env.dbService);
      final cancelledSummary = repo.applyDiffWithSummary(
        ScanOutput(
          nasReachable: true,
          reachableRoots: [root.path],
          completeRoots: [root.path],
          seriesList: const [],
          movies: const [],
          wasCancelled: true,
        ),
      );
      expect(cancelledSummary.orphanedThumbnails, isEmpty);
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM movies;')
            .first['c'],
        1,
      );

      // Force rollback via SQLite trigger while inserting a movie
      env.dbService.instance.execute(
        '''
        CREATE TRIGGER fail_movie_insert BEFORE INSERT ON movies
        BEGIN
          SELECT RAISE(ABORT, 'simulated_rollback');
        END;
        ''',
      );
      expect(
        () => repo.applyDiffWithSummary(
          ScanOutput(
            nasReachable: true,
            reachableRoots: [root.path],
            completeRoots: [root.path],
            seriesList: const [],
            movies: [
              ScannedMovieData(
                title: 'Trigger Rollback Movie',
                releaseYear: 2024,
                filePath: p.join(root.path, 'RollbackMovie.mkv'),
                posterPath: null,
                syncKey: 'mv_v2_rollback',
              ),
            ],
          ),
        ),
        throwsException,
      );
      expect(thumb.existsSync(), isTrue);
    });
  });

  group('A04 ScanCoordinator lifecycle, deduplication & cancellation', () {
    test('two rapid refreshLibrary calls deduplicate to a single scan run',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('dedupe_root');
      createSyntheticMp4HeaderFile(root, 'Dune (2021).mkv');

      final settings = SettingsController(env.dbService);
      await settings.load();
      settings.addNasPath(root.path);

      final firstTagStarted = Completer<void>();
      final allowTagFinish = Completer<void>();
      var workerExecutions = 0;

      final scanner = NasScannerService(
        env.dbService,
        tagReader: (filePath) async {
          workerExecutions++;
          if (!firstTagStarted.isCompleted) {
            firstTagStarted.complete();
          }
          await allowTagFinish.future;
          return const EmbeddedMediaTags(title: 'Dune', releaseYear: 2021);
        },
      );
      final library = LibraryController(
        env.dbService,
        settings,
        scannerService: scanner,
      );

      final f1 = library.refreshLibrary();
      await firstTagStarted.future;
      expect(library.isScanning, isTrue);
      expect(library.scanState, ScanLifecycleState.running);

      final f2 = library.refreshLibrary();
      expect(identical(f1, f2), isTrue);

      allowTagFinish.complete();
      await Future.wait([f1, f2]);

      expect(workerExecutions, 1);
      expect(library.isScanning, isFalse);
      expect(library.scanState, ScanLifecycleState.completed);
      expect(library.movieCount, 1);

      library.dispose();
      settings.dispose();
    });

    test(
        'playback start pauses running scan cleanly and playback end resumes deterministically',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('pause_resume_root');
      createSyntheticMp4HeaderFile(root, 'Interstellar (2014).mkv');

      final settings = SettingsController(env.dbService);
      await settings.load();
      settings.addNasPath(root.path);

      final scanEnteredTagReader = Completer<void>();
      final releasePausedTagReader = Completer<void>();
      var calls = 0;

      final scanner = NasScannerService(
        env.dbService,
        tagReader: (filePath) async {
          calls++;
          if (calls == 1) {
            scanEnteredTagReader.complete();
            await releasePausedTagReader.future;
          }
          return const EmbeddedMediaTags(
            title: 'Interstellar',
            releaseYear: 2014,
          );
        },
      );
      final library = LibraryController(
        env.dbService,
        settings,
        scannerService: scanner,
      );

      final firstScan = library.refreshLibrary();
      await scanEnteredTagReader.future;

      // Start playback while scan is actively inside tagReader
      library.setPlaybackActive(true);
      expect(library.scanState, ScanLifecycleState.pausing);
      // isScanning remains true until worker reaches safe stop point
      expect(library.isScanning, isTrue);

      // Attempting another refresh while pausing must NOT launch a parallel scan
      final duplicateCall = library.refreshLibrary();
      expect(identical(firstScan, duplicateCall), isTrue);

      releasePausedTagReader.complete();
      await firstScan;

      expect(library.isScanning, isFalse);
      expect(library.scanState, ScanLifecycleState.paused);
      expect(library.statusMessage, AppStrings.scanPausedStatus);
      expect(library.movieCount, 0);

      // End playback -> paused scan automatically resumes and finishes
      library.setPlaybackActive(false);
      await library.waitForActiveScan();

      expect(calls, 2);
      expect(library.isScanning, isFalse);
      expect(library.scanState, ScanLifecycleState.completed);
      expect(library.movieCount, 1);

      library.dispose();
      settings.dispose();
    });

    test(
        'cancelForShutdown stops active worker (delayed hook and real controllable isolate) before completion',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('shutdown_root');
      createSyntheticMp4HeaderFile(root, 'Blade Runner (1982).mkv');

      // 1) Delayed in-process worker
      final tagEntered = Completer<void>();
      final tagGate = Completer<void>();
      final scanner1 = NasScannerService(
        env.dbService,
        tagReader: (_) async {
          tagEntered.complete();
          await tagGate.future;
          return const EmbeddedMediaTags(title: 'Blade Runner');
        },
      );

      final scanFuture1 = scanner1.scanLibrary([root.path]);
      await tagEntered.future;

      var shutdownDone = false;
      final shutdownFuture = scanner1.cancelForShutdown().then((_) {
        shutdownDone = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(shutdownDone, isFalse);
      expect(scanner1.lifecycleState, ScanLifecycleState.cancelling);

      tagGate.complete();
      await shutdownFuture;
      final res1 = await scanFuture1;
      expect(shutdownDone, isTrue);
      expect(res1.cancelledForShutdown, isTrue);
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM movies;')
            .first['c'],
        0,
      );

      // 2) Real controllable Isolate.spawn cancellation
      final isolateRoot = env.createSubdir('shutdown_isolate_root');
      for (var i = 0; i < 40; i++) {
        createSyntheticMp4HeaderFile(isolateRoot, 'Clip_$i.mkv');
      }
      final scanner2 = NasScannerService(env.dbService);
      final scanFuture2 = scanner2.scanLibrary([isolateRoot.path]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await scanner2.cancelForShutdown();
      final res2 = await scanFuture2;
      expect(res2.cancelledForShutdown, isTrue);
      expect(scanner2.isScanActive, isFalse);
    });

    test(
        'ShellController.onWindowClose does not resume paused scan before shutdown cancellation',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('shell_shutdown_root');
      createSyntheticMp4HeaderFile(root, 'Andor - S01E01.mkv');

      final settings = SettingsController(env.dbService);
      await settings.load();
      settings.addNasPath(root.path);

      var scanRuns = 0;
      final scanner = NasScannerService(
        env.dbService,
        tagReader: (_) async {
          scanRuns++;
          return const EmbeddedMediaTags(title: 'Kassa');
        },
      );
      final library = LibraryController(
        env.dbService,
        settings,
        scannerService: scanner,
      );

      // Start playback first, then trigger scan -> queued as paused
      library.setPlaybackActive(true);
      await library.refreshLibrary();
      expect(scanner.hasPendingResume, isTrue);
      expect(scanRuns, 0);

      var destroyed = false;
      final shell = ShellController(
        settingsController: settings,
        libraryController: library,
        databaseService: env.dbService,
        onHideWindow: () async {},
        onDestroyWindow: () async {
          destroyed = true;
        },
        onForceExit: () {},
      );

      await shell.onWindowClose();
      expect(destroyed, isTrue);
      expect(scanRuns, 0);
      expect(env.dbService.isOpen, isFalse);

      shell.dispose();
      library.dispose();
      settings.dispose();
    });
  });
}
