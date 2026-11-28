import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/models/media_source_models.dart';
import 'package:saphir_player/core/models/status_feedback_models.dart';
import 'package:saphir_player/core/storage/media_source_repository.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/core/theme/effect_mode.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/library/library_view.dart';
import 'package:saphir_player/features/scanner/media_tag_reader_service.dart';
import 'package:saphir_player/features/scanner/nas_scanner_service.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import 'package:saphir_player/features/shell/widgets/settings_media_card.dart';
import '../helpers/test_fixtures.dart';

class _StubProgressSyncService extends ProgressSyncService {
  _StubProgressSyncService(
    super.databaseService, {
    required this.handler,
  });

  final Future<SyncResult> Function(List<String> roots) handler;

  @override
  Future<SyncResult> syncWithRoots(
    List<String> nasRootPaths, {
    SyncCancellationToken? cancellationToken,
  }) =>
      handler(nasRootPaths);
}

class _ThrowingScannerService extends NasScannerService {
  _ThrowingScannerService(super.databaseService, this.error);

  final Object error;

  @override
  Future<ScanResult> scanLibrary(List<String> rootPaths) async {
    throw error;
  }
}

void main() {
  group('A10 Media source removal, disabling, and reactivation', () {
    test(
        'disabling a source hides its media while preserving DB rows, history, and reactivating restores same source_id',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final rootA = env.createSubdir('source_a');
      final rootB = env.createSubdir('source_b');
      final dirA = Directory(p.join(rootA.path, 'Dark', 'Season 1'))
        ..createSync(recursive: true);
      createSyntheticMp4HeaderFile(dirA, 'Dark - S01E01 - Pilot.mkv');
      createSyntheticMp4HeaderFile(rootB, 'Interstellar (2014).mkv');

      final settings = SettingsController(env.dbService);
      await settings.load();
      settings.addNasPath(rootA.path);
      settings.addNasPath(rootB.path);

      final library = LibraryController(env.dbService, settings);
      final home = HomeController(env.dbService);
      final shell = ShellController(
        settingsController: settings,
        libraryController: library,
        homeController: home,
        databaseService: env.dbService,
      );

      await library.refreshLibrary();
      home.refreshHomeFeeds();
      expect(library.seriesCount, 1);
      expect(library.movieCount, 1);

      final sourceA = settings.mediaSources
          .firstWhere((s) => p.equals(s.rootPath, rootA.path));

      // Disable source A -> media hidden, DB rows kept
      await shell.handleRemoveMediaSource(
        sourceA.sourceId,
        SourceRemovalAction.disableKeepData,
      );

      expect(library.seriesCount, 0);
      expect(library.movieCount, 1);
      expect(home.seriesItems, isEmpty);
      expect(home.movieItems.length, 1);
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM episodes;')
            .first['c'],
        1,
      );

      // Reactivate source A -> series reappears with identical source_id
      shell.handleReactivateMediaSource(sourceA.sourceId);
      expect(library.seriesCount, 1);
      expect(home.seriesItems.length, 1);
      expect(
        settings.mediaSources
            .firstWhere((s) => s.sourceId == sourceA.sourceId)
            .isActive,
        isTrue,
      );

      shell.dispose();
      library.dispose();
      home.dispose();
      settings.dispose();
    });

    test(
        'removing a source with index deletes only its index + orphaned thumbs, keeping other sources and progress intact',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final rootA = env.createSubdir('remove_a');
      final rootB = env.createSubdir('keep_b');
      final dirA = Directory(p.join(rootA.path, 'Andor', 'Season 1'))
        ..createSync(recursive: true);
      createSyntheticMp4HeaderFile(dirA, 'Andor - S01E01 - Kassa.mkv');
      createSyntheticMp4HeaderFile(rootB, 'Arrival (2016).mkv');

      final cacheDir =
          env.createSubdir(p.join('app_base', 'cache', 'thumbnails'));
      final thumbA = createValidTinyJpeg(cacheDir, 'thumb_a.jpg');
      final thumbB = createValidTinyJpeg(cacheDir, 'thumb_b.jpg');

      final settings = SettingsController(env.dbService);
      await settings.load();
      settings.addNasPath(rootA.path);
      settings.addNasPath(rootB.path);

      final library = LibraryController(env.dbService, settings);
      final home = HomeController(env.dbService);
      final shell = ShellController(
        settingsController: settings,
        libraryController: library,
        homeController: home,
        databaseService: env.dbService,
      );

      await library.refreshLibrary();
      final epRow = env.dbService.instance
          .select('SELECT id, sync_key FROM episodes LIMIT 1;')
          .first;
      final epKey = epRow['sync_key'] as String;
      env.dbService.instance.execute(
        "UPDATE episodes SET thumb_path = ?, thumb_status = 'ready';",
        [thumbA.path],
      );
      env.dbService.instance.execute(
        "UPDATE movies SET thumb_path = ?, thumb_status = 'ready';",
        [thumbB.path],
      );
      env.dbService.instance.execute(
        "INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device) VALUES (?, 'episode', 45000, 120000, 0, 5000, 'PC');",
        [epKey],
      );

      final sourceA = settings.mediaSources
          .firstWhere((s) => p.equals(s.rootPath, rootA.path));
      await shell.handleRemoveMediaSource(
        sourceA.sourceId,
        SourceRemovalAction.removeWithIndex,
      );

      expect(library.seriesCount, 0);
      expect(library.movieCount, 1);
      expect(thumbA.existsSync(), isFalse);
      expect(thumbB.existsSync(), isTrue);
      // Progress & history remain preserved per retention contract
      expect(
        env.dbService.instance.select(
          'SELECT position_ms FROM watch_progress WHERE media_key = ?;',
          [epKey],
        ).first['position_ms'],
        45000,
      );

      // Re-adding the same path preserves the identical source_id
      expect(settings.addNasPath(rootA.path), isTrue);
      final reAdded = settings.mediaSources
          .firstWhere((s) => p.equals(s.rootPath, rootA.path));
      expect(reAdded.sourceId, sourceA.sourceId);

      await library.refreshLibrary();
      expect(library.seriesCount, 1);
      final restoredKey = env.dbService.instance
          .select('SELECT sync_key FROM episodes LIMIT 1;')
          .first['sync_key'];
      expect(restoredKey, epKey);

      shell.dispose();
      library.dispose();
      home.dispose();
      settings.dispose();
    });
  });

  group('A11 SyncResult evaluation & accurate UI status feedback', () {
    test(
        'reports distinct banner severity and message for all SyncResult outcomes',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      late SyncResult nextResult;
      var shouldThrow = false;
      final stubSync = _StubProgressSyncService(
        env.dbService,
        handler: (_) async {
          if (shouldThrow) {
            throw const FileSystemException('Write error', r'\\NAS\sync.json');
          }
          return nextResult;
        },
      );

      final settings = SettingsController(env.dbService, syncService: stubSync);
      await settings.load();
      final library = LibraryController(env.dbService, settings);
      final shell = ShellController(
        settingsController: settings,
        libraryController: library,
        databaseService: env.dbService,
      );

      // 1. NAS synced -> success
      nextResult = const SyncResult(
        syncedToNas: true,
        targetPath: r'\\NAS\Serien\progress_sync.json',
        status: SyncStatus.synced,
      );
      await shell.handleSyncNow();
      expect(shell.statusBanner?.severity, StatusSeverity.success);
      expect(shell.statusMessage, AppStrings.syncNasCompletedStatus);
      expect(settings.lastSuccessfulNasSync, isNotNull);

      // 2. NAS unreachable -> local fallback warning, never success
      nextResult = const SyncResult(
        syncedToNas: false,
        targetPath: r'C:\Users\Test\data\progress_sync.json',
        status: SyncStatus.localOnly,
        nasTargetUnreachable: true,
      );
      await shell.handleSyncNow();
      expect(shell.statusBanner?.severity, StatusSeverity.warning);
      expect(shell.statusMessage, AppStrings.syncNasUnreachableStatus);
      expect(shell.statusBanner?.detail, contains('progress_sync.json'));

      // 3. Corrupt sync file -> error
      nextResult = const SyncResult(
        syncedToNas: false,
        targetPath: r'\\NAS\Serien\progress_sync.json',
        status: SyncStatus.corrupt,
        corruptBackupPath: r'\\NAS\Serien\progress_sync.corrupt.json',
      );
      await shell.handleSyncNow();
      expect(shell.statusBanner?.severity, StatusSeverity.error);
      expect(shell.statusMessage, AppStrings.syncCorruptStatus);

      // 4. Write exception -> error + diagnostic log, never false success
      shouldThrow = true;
      await shell.handleSyncNow();
      expect(shell.statusBanner?.severity, StatusSeverity.error);
      expect(shell.statusMessage, AppStrings.syncFailedStatus);
      expect(settings.diagnosticLog, isNotEmpty);

      shell.dispose();
      library.dispose();
      settings.dispose();
    });
  });

  group('A13 LibraryController error handling & sync/scan separation', () {
    test(
        'scanner exception clears isScanning, sets failed state, and logs diagnostic',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final settings = SettingsController(env.dbService);
      await settings.load();
      final throwingScanner = _ThrowingScannerService(
        env.dbService,
        StateError('Simulated SMB read failure'),
      );
      final library = LibraryController(
        env.dbService,
        settings,
        scannerService: throwingScanner,
      );

      await library.refreshLibrary();
      expect(library.isScanning, isFalse);
      expect(library.scanPhase, ScanPhase.failed);
      expect(library.hasScanError, isTrue);
      expect(library.statusMessage, AppStrings.scanFailedStatus);
      expect(library.scanFeedback?.canRetry, isTrue);
      expect(
          library.diagnosticLog.last, contains('Simulated SMB read failure'));

      library.dispose();
      settings.dispose();
    });

    test(
        'partial scan shows warning instead of success and keeps sync errors separate',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('partial_a13');
      final subErr = Directory(p.join(root.path, 'Season 1'))
        ..createSync(recursive: true);
      final subOk = Directory(p.join(root.path, 'Season 2'))
        ..createSync(recursive: true);
      createSyntheticMp4HeaderFile(subOk, 'Dark - S02E01.mkv');

      final stubSync = _StubProgressSyncService(
        env.dbService,
        handler: (_) async => const SyncResult(
          syncedToNas: false,
          targetPath: r'C:\data\progress_sync.json',
          status: SyncStatus.failed,
          message: 'SMB write denied',
        ),
      );
      final settings = SettingsController(env.dbService, syncService: stubSync);
      await settings.load();
      settings.addNasPath(root.path);

      final scanner = NasScannerService(
        env.dbService,
        directoryLister: (dir) {
          if (p.equals(dir.path, subErr.path)) {
            throw FileSystemException('Access denied', dir.path);
          }
          return dir.listSync(recursive: false, followLinks: false);
        },
      );
      final library = LibraryController(
        env.dbService,
        settings,
        scannerService: scanner,
      );

      await library.syncAndRefreshLibrary();
      expect(library.hasSyncIssue, isTrue);
      expect(library.lastSyncStatusMessage, AppStrings.syncFailedStatus);
      expect(library.hasScanWarning, isTrue);
      expect(library.statusMessage, AppStrings.scanPartialStatus);
      expect(library.scanFeedback?.canRetry, isTrue);

      library.dispose();
      settings.dispose();
    });

    test(
        'disposing LibraryController mid-scan never throws notifyListeners after dispose',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('dispose_scan');
      createSyntheticMp4HeaderFile(root, 'Dune (2021).mkv');

      final settings = SettingsController(env.dbService);
      await settings.load();
      settings.addNasPath(root.path);

      final enteredTag = Completer<void>();
      final releaseTag = Completer<void>();
      final scanner = NasScannerService(
        env.dbService,
        tagReader: (_) async {
          if (!enteredTag.isCompleted) enteredTag.complete();
          await releaseTag.future;
          return const EmbeddedMediaTags(title: 'Dune', releaseYear: 2021);
        },
      );
      final library = LibraryController(
        env.dbService,
        settings,
        scannerService: scanner,
      );

      final future = library.refreshLibrary();
      await enteredTag.future;
      library.dispose();
      releaseTag.complete();
      await expectLater(future, completes);
      settings.dispose();
    });
  });

  group('A24 Per-source scan status, phase reporting & long UNC UI', () {
    test(
        'records distinct complete, partial, and unreachable states per source, emits phases, and supports single-source rescan',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final rootOk = env.createSubdir('source_ok');
      final rootPartial = env.createSubdir('source_partial');
      final rootMissing = p.join(env.tempRoot.path, 'missing_nas_share');

      createSyntheticMp4HeaderFile(rootOk, 'Arrival (2016).mkv');
      final brokenSub = Directory(p.join(rootPartial.path, 'Broken'))
        ..createSync(recursive: true);
      createSyntheticMp4HeaderFile(rootPartial, 'Dune (2021).mkv');

      final settings = SettingsController(env.dbService);
      await settings.load();
      settings.addNasPath(rootOk.path);
      settings.addNasPath(rootPartial.path);
      settings.addNasPath(rootMissing);

      final phases = <ScanPhase>[];
      final scanner = NasScannerService(
        env.dbService,
        directoryLister: (dir) {
          if (p.equals(dir.path, brokenSub.path)) {
            throw FileSystemException('Read timeout', dir.path);
          }
          return dir.listSync(recursive: false, followLinks: false);
        },
      );
      scanner.addPhaseListener(phases.add);

      final library = LibraryController(
        env.dbService,
        settings,
        scannerService: scanner,
      );
      await library.refreshLibrary();

      expect(
        phases,
        containsAllInOrder([
          ScanPhase.enumerating,
          ScanPhase.readingMetadata,
          ScanPhase.applyingDiff,
          ScanPhase.generatingThumbnails,
          ScanPhase.completed,
        ]),
      );

      final sources = MediaSourceRepository(env.dbService).loadSources();
      final okEntry =
          sources.firstWhere((s) => p.equals(s.rootPath, rootOk.path));
      final partialEntry =
          sources.firstWhere((s) => p.equals(s.rootPath, rootPartial.path));
      final missingEntry =
          sources.firstWhere((s) => p.equals(s.rootPath, rootMissing));

      expect(okEntry.lastScanStatus, 'complete');
      expect(okEntry.lastSuccessScanAt, isNotNull);
      expect(okEntry.lastMediaFound, 1);

      expect(partialEntry.lastScanStatus, 'partial');
      expect(partialEntry.lastSuccessScanAt, isNull);
      expect(partialEntry.lastErrorCount, 1);
      expect(partialEntry.lastScanError, isNotNull);

      expect(missingEntry.lastScanStatus, 'unreachable');
      expect(missingEntry.lastSuccessScanAt, isNull);

      // Single-source rescan updates okEntry without wiping partial/missing diagnostics
      createSyntheticMp4HeaderFile(rootOk, 'Interstellar (2014).mkv');
      await library.refreshSingleSource(rootOk.path);
      final updatedOk =
          MediaSourceRepository(env.dbService).findById(okEntry.sourceId)!;
      expect(updatedOk.lastMediaFound, 2);

      library.dispose();
      settings.dispose();
    });

    testWidgets(
        'SettingsMediaCard & LibraryView render long UNC paths, error status, and retry without overflow',
        (tester) async {
      late TestEnv env;
      late SettingsController settings;
      late LibraryController library;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        settings = SettingsController(env.dbService);
        await settings.load();
        const longUnc =
            r'\\NAS-ARCHIV-01\Medienbibliothek\Serien\Dokumentationen\2026\Staffel_Sammlung';
        settings.addNasPath(longUnc);

        final throwingScanner = _ThrowingScannerService(
          env.dbService,
          StateError('SMB offline'),
        );
        library = LibraryController(
          env.dbService,
          settings,
          scannerService: throwingScanner,
        );
        await library.refreshLibrary();
      });

      const longUnc =
          r'\\NAS-ARCHIV-01\Medienbibliothek\Serien\Dokumentationen\2026\Staffel_Sammlung';
      final nasInput = TextEditingController();
      addTearDown(nasInput.dispose);
      var retried = 0;

      for (final size in const [
        Size(1280, 800),
        Size(800, 500),
        Size(390, 844),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.buildDarkTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    SettingsMediaCard(
                      settingsController: settings,
                      libraryController: library,
                      nasInputController: nasInput,
                      onAddFolderFromInput: () {},
                      onAddFolderFromPicker: () {},
                      onRemoveFolder: (_) {},
                      onTriggerScan: () => retried++,
                    ),
                    SizedBox(
                      height: 360,
                      child: LibraryView(
                        libraryController: library,
                        effectMode: EffectMode.lean,
                        onSelectItem: (_) {},
                        onOpenSeries: (_) {},
                        onRetryScan: () => retried++,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byTooltip(longUnc), findsOneWidget);
        expect(find.text(AppStrings.scanRetryButton), findsWidgets);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.text(AppStrings.scanRetryButton).first);
      expect(retried, 1);

      library.dispose();
      settings.dispose();
      env.dispose();
    });
  });
}
