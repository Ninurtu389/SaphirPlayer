import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/models/status_feedback_models.dart';
import 'package:saphir_player/core/storage/app_settings_store.dart';
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/storage/sync_lock.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/core/theme/effect_mode.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/player/playback_session.dart';
import 'package:saphir_player/features/player/saphir_player_controller.dart';
import 'package:saphir_player/features/scanner/active_process_registry.dart';
import 'package:saphir_player/features/scanner/nas_scanner_service.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import 'package:saphir_player/features/shell/shell_shutdown_runner.dart';
import 'package:saphir_player/features/shell/shell_view.dart';
import 'package:saphir_player/features/shell/widgets/shell_startup_banner.dart';
import 'package:saphir_player/features/stats/stats_controller.dart';
import '../helpers/mock_player.dart';
import '../helpers/test_fixtures.dart';

class _HangingCancelScannerService extends NasScannerService {
  _HangingCancelScannerService(super.databaseService, this._neverCompletes);

  final Completer<void> _neverCompletes;

  @override
  Future<void> cancelForShutdown() => _neverCompletes.future;
}

class _SlowCancelableScannerService extends NasScannerService {
  _SlowCancelableScannerService(
    super.databaseService, {
    required super.tagReader,
  });

  bool shutdownCancelCalled = false;

  @override
  Future<void> cancelForShutdown() {
    shutdownCancelCalled = true;
    return super.cancelForShutdown();
  }
}

class _CountingStartupSettingsController extends SettingsController {
  _CountingStartupSettingsController(
    super.databaseService, {
    Completer<SyncResult>? customSyncCompleter,
  }) : _customSyncCompleter = customSyncCompleter;

  final Completer<SyncResult>? _customSyncCompleter;
  int syncCallCount = 0;

  @override
  Future<SyncResult> syncProgress({SyncCancellationToken? cancellationToken}) {
    syncCallCount++;
    final customSyncCompleter = _customSyncCompleter;
    if (customSyncCompleter != null) {
      return customSyncCompleter.future;
    }
    return super.syncProgress(cancellationToken: cancellationToken);
  }
}

void main() {
  const fastTimeouts = ShutdownTimeouts(
    playerDispose: Duration(milliseconds: 80),
    scanStop: Duration(milliseconds: 80),
    sync: Duration(milliseconds: 80),
    syncCancelGrace: Duration(milliseconds: 120),
    nativeDrainDelay: Duration.zero,
    processGracePeriod: Duration(milliseconds: 50),
    processKillTimeout: Duration(milliseconds: 80),
  );

  group('A17 Shutdown & ActiveProcessRegistry', () {
    test('terminateAll kills active child process and empties registry',
        () async {
      final process = Platform.isWindows
          ? await Process.start(
              'ping',
              const ['-n', '15', '127.0.0.1'],
              runInShell: false,
            )
          : await Process.start('sleep', const ['15'], runInShell: false);

      unawaited(process.stdout.drain<void>().catchError((_) {}));
      unawaited(process.stderr.drain<void>().catchError((_) {}));
      ActiveProcessRegistry.register(process);
      expect(ActiveProcessRegistry.activeCount, 1);

      final remaining = await ActiveProcessRegistry.terminateAll(
        gracePeriod: const Duration(milliseconds: 100),
        hardKillTimeout: const Duration(milliseconds: 500),
      );
      expect(remaining, 0);
      expect(ActiveProcessRegistry.activeCount, 0);
    });

    test('closing during active NAS scan cancels cleanly before closing DB',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      final mediaDir = env.createSubdir('nas_media');
      createSyntheticMp4HeaderFile(mediaDir, 'Movie (2024).mp4');

      final settings = SettingsController(env.dbService);
      await settings.load();
      settings.addNasPath(mediaDir.path);

      final scanStarted = Completer<void>();
      final scanner = _SlowCancelableScannerService(
        env.dbService,
        tagReader: (_) async {
          if (!scanStarted.isCompleted) scanStarted.complete();
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return null;
        },
      );
      final library =
          LibraryController(env.dbService, settings, scannerService: scanner);
      final events = <String>[];
      final shell = ShellController(
        settingsController: settings,
        libraryController: library,
        databaseService: env.dbService,
        onHideWindow: () async => events.add('hide'),
        onDestroyWindow: () async => events.add('destroy'),
        onForceExit: () => events.add('forceExit'),
        shutdownTimeouts: const ShutdownTimeouts(
          scanStop: Duration(seconds: 2),
          sync: Duration(seconds: 2),
          nativeDrainDelay: Duration.zero,
        ),
      );

      final scanFuture = library.refreshLibrary();
      await scanStarted.future;
      await shell.onWindowClose();
      await scanFuture;

      expect(scanner.shutdownCancelCalled, isTrue);
      expect(events, ['hide', 'destroy']);
      expect(
          shell.lastShutdownReport?.scanOutcome, ShutdownStepOutcome.completed);
      expect(shell.lastShutdownReport?.databaseClosed, isTrue);
      expect(env.dbService.isOpen, isFalse);

      library.dispose();
      settings.dispose();
      shell.dispose();
    });

    test(
        'hanging scan past timeout skips closing DB under worker and requests forceExit',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      final settings = SettingsController(env.dbService);
      await settings.load();

      final hangingCompleter = Completer<void>();
      final library = LibraryController(
        env.dbService,
        settings,
        scannerService:
            _HangingCancelScannerService(env.dbService, hangingCompleter),
      );
      final events = <String>[];
      final shell = ShellController(
        settingsController: settings,
        libraryController: library,
        databaseService: env.dbService,
        onHideWindow: () async => events.add('hide'),
        onDestroyWindow: () async => events.add('destroy'),
        onForceExit: () => events.add('forceExit'),
        shutdownTimeouts: fastTimeouts,
      );

      await shell.onWindowClose();

      expect(events, ['hide', 'forceExit']);
      expect(env.dbService.isOpen, isTrue);
      expect(
        shell.lastShutdownReport?.scanOutcome,
        ShutdownStepOutcome.timedOut,
      );
      expect(shell.lastShutdownReport?.databaseClosed, isFalse);
      expect(shell.lastShutdownReport?.usedForceExit, isTrue);
      expect(
        shell.lastShutdownReport?.pendingTasks,
        contains('libraryController.cancelScanForShutdown'),
      );

      library.dispose();
      settings.dispose();
      shell.dispose();
    });

    test(
        'closing during active playback flushes progress, disposes player once, and runs single shutdown for duplicate close events',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      seedSampleLibrary(env.dbService);
      final mediaDir = env.createSubdir('videos');
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');

      final settings = SettingsController(env.dbService);
      await settings.load();
      final harness = FakePlayerHarness();
      addTearDown(harness.close);
      final player = SaphirPlayerController(
        env.dbService,
        ProgressSyncService(env.dbService),
        () => [mediaDir.path],
        settingsController: settings,
        player: harness.player,
        videoController: harness.videoController,
        windowAdapter: harness.windowAdapter,
      );
      final disposeGate = Completer<void>();
      when(() => harness.player.dispose()).thenAnswer((_) async {
        harness.disposed = true;
        await disposeGate.future;
      });

      await player.startSession(
        PlaybackSession(
          queue: [
            PlaybackQueueEntry(
              mediaKey: 'episode_2',
              mediaType: 'episode',
              title: 'Dark',
              subtitle: 'S1E2',
              filePath: ep1.path,
              seriesId: 1,
              startPositionMs: 0,
            ),
          ],
          initialIndex: 0,
        ),
      );
      harness.emitDuration(const Duration(minutes: 40));
      harness.emitPosition(const Duration(minutes: 12));
      await Future<void>.delayed(Duration.zero);

      final events = <String>[];
      final shell = ShellController(
        settingsController: settings,
        playerController: player,
        databaseService: env.dbService,
        onHideWindow: () async => events.add('hide'),
        onDestroyWindow: () async => events.add('destroy'),
        onForceExit: () => events.add('forceExit'),
        shutdownTimeouts: const ShutdownTimeouts(
          playerDispose: Duration(seconds: 2),
          nativeDrainDelay: Duration.zero,
        ),
      );
      final dbPath = env.dbService.currentDbPath!;
      shell.openPlaybackSession(player.session!);

      var firstDone = false;
      var secondDone = false;
      final f1 = shell.onWindowClose().then((_) => firstDone = true);
      final f2 = shell.onWindowClose().then((_) => secondDone = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(firstDone, isFalse);
      expect(secondDone, isFalse);

      disposeGate.complete();
      await Future.wait([f1, f2]);
      expect(firstDone, isTrue);
      expect(secondDone, isTrue);
      expect(events, ['hide', 'destroy']);
      verify(() => harness.player.dispose()).called(1);

      // Verify progress flushed before DB closed
      final verifyDb = DatabaseService();
      await verifyDb.open(dbPath: dbPath);
      addTearDown(verifyDb.close);
      final row = verifyDb.instance
          .select(
              "SELECT position_ms FROM watch_progress WHERE media_key = 'episode_2';")
          .first;
      expect(row['position_ms'], const Duration(minutes: 12).inMilliseconds);

      player.dispose();
      settings.dispose();
      shell.dispose();
    });
  });

  group('A18 Sync timeout, cancellation & offline recovery on shutdown', () {
    test(
        'hanging sync lock cancels cleanly via SyncCancellationToken within grace and closes DB without forceExit',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      final nasDir = env.createSubdir('nas_locked');
      final syncPath = p.join(nasDir.path, 'progress_sync.json');

      // Hold external lock so ProgressSyncService enters lock retry loop
      final holder = await SyncFileLock.acquire(
        syncPath,
        writerId: 'other_device',
        staleTimeout: const Duration(seconds: 30),
        acquireTimeout: const Duration(seconds: 1),
      );
      expect(holder, isNotNull);
      addTearDown(() async => holder?.release());

      final syncService = ProgressSyncService(
        env.dbService,
        lockAcquireTimeout: const Duration(seconds: 10),
        lockStaleTimeout: const Duration(seconds: 30),
      );
      final settings = SettingsController(
        env.dbService,
        syncService: syncService,
      );
      await settings.load();
      settings.addNasPath(nasDir.path);

      final events = <String>[];
      final shell = ShellController(
        settingsController: settings,
        databaseService: env.dbService,
        onHideWindow: () async => events.add('hide'),
        onDestroyWindow: () async => events.add('destroy'),
        onForceExit: () => events.add('forceExit'),
        shutdownTimeouts: const ShutdownTimeouts(
          sync: Duration(milliseconds: 50),
          syncCancelGrace: Duration(milliseconds: 300),
          nativeDrainDelay: Duration.zero,
        ),
      );

      await shell.onWindowClose();

      expect(events, ['hide', 'destroy']);
      expect(
        shell.lastShutdownReport?.syncOutcome,
        ShutdownStepOutcome.cancelled,
      );
      expect(shell.lastShutdownReport?.syncResultStatus, SyncStatus.cancelled);
      expect(shell.lastShutdownReport?.databaseClosed, isTrue);
      expect(shell.lastShutdownReport?.usedForceExit, isFalse);
      expect(env.dbService.isOpen, isFalse);

      settings.dispose();
      shell.dispose();
    });

    test(
        'completely hung sync exceeding grace keeps DB open for safety and triggers forceExit',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      final hungCompleter = Completer<SyncResult>();
      final settings = _CountingStartupSettingsController(
        env.dbService,
        customSyncCompleter: hungCompleter,
      );
      await settings.load();

      final events = <String>[];
      final shell = ShellController(
        settingsController: settings,
        databaseService: env.dbService,
        onHideWindow: () async => events.add('hide'),
        onDestroyWindow: () async => events.add('destroy'),
        onForceExit: () => events.add('forceExit'),
        shutdownTimeouts: fastTimeouts,
      );

      await shell.onWindowClose();

      expect(events, ['hide', 'forceExit']);
      expect(
        shell.lastShutdownReport?.syncOutcome,
        ShutdownStepOutcome.timedOut,
      );
      expect(shell.lastShutdownReport?.databaseClosed, isFalse);
      expect(env.dbService.isOpen, isTrue);
      expect(
        shell.lastShutdownReport?.pendingTasks,
        contains('settingsController.syncProgress'),
      );

      settings.dispose();
      shell.dispose();
    });

    test(
        'unreachable NAS during shutdown finishes quickly and preserves local progress for next startup sync',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      seedSampleLibrary(env.dbService);
      final dbPath = env.dbService.currentDbPath!;
      final offlineNasPath = p.join(env.tempRoot.path, 'nas_offline_target');

      env.dbService.instance.execute(
        "UPDATE watch_progress SET position_ms = 240000, updated_at = 999999 WHERE media_key = 'episode_1';",
      );

      final settings = SettingsController(env.dbService);
      await settings.load();
      settings.addNasPath(offlineNasPath);

      final events = <String>[];
      final shell = ShellController(
        settingsController: settings,
        databaseService: env.dbService,
        onHideWindow: () async => events.add('hide'),
        onDestroyWindow: () async => events.add('destroy'),
        onForceExit: () => events.add('forceExit'),
      );

      await shell.onWindowClose();
      expect(events, ['hide', 'destroy']);
      expect(shell.lastShutdownReport?.databaseClosed, isTrue);
      settings.dispose();
      shell.dispose();

      // Next startup: NAS comes online -> startup sync pushes preserved progress
      Directory(offlineNasPath).createSync(recursive: true);
      final restartedDb = DatabaseService();
      await restartedDb.open(dbPath: dbPath);
      addTearDown(restartedDb.close);
      final restartedSettings = SettingsController(restartedDb);
      await restartedSettings.load();
      final res = await restartedSettings.runStartupSync();
      expect(res.syncedToNas, isTrue);
      expect(
        File(p.join(offlineNasPath, 'progress_sync.json')).existsSync(),
        isTrue,
      );
      restartedSettings.dispose();
    });
  });

  group('A19 Startup settings error handling & deduplicated startup sync', () {
    test(
        'DB settings load failure surfaces settingsLoadError and startup banner',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      env.dbService.instance.execute('DROP TABLE app_settings;');

      final settings = SettingsController(env.dbService);
      await settings.load();

      expect(settings.hasSettingsLoadError, isTrue);
      expect(settings.settingsLoadError, AppStrings.settingsLoadErrorStatus);
      expect(settings.diagnosticLog, isNotEmpty);

      final shell = ShellController(
        settingsController: settings,
        databaseService: env.dbService,
      );
      shell.initializeStartupState();
      expect(shell.startupBanner, isNotNull);
      expect(shell.startupBanner?.severity, StatusSeverity.error);
      expect(shell.startupBanner?.message, AppStrings.settingsLoadErrorStatus);

      shell.dispose();
      settings.dispose();
    });

    test(
        'corrupt individual setting falls back per field while preserving remaining valid settings',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      final db = env.dbService.instance;

      AppSettingsStore.upsertSetting(
          db, AppSettingsStore.nasPathsKey, '{bad json');
      AppSettingsStore.upsertSetting(
        db,
        AppSettingsStore.nasPathKey,
        r'D:\ValidFallback',
      );
      AppSettingsStore.upsertSetting(
          db, AppSettingsStore.subtitlesDefaultKey, '1');
      AppSettingsStore.upsertSetting(
          db, AppSettingsStore.subtitleScaleKey, 'abc');
      AppSettingsStore.upsertSetting(
          db, AppSettingsStore.globalEffectKey, 'broken');

      final settings = SettingsController(env.dbService);
      await settings.load();

      expect(settings.hasSettingsLoadError, isFalse);
      expect(settings.settingsLoadWarnings.length, greaterThanOrEqualTo(3));
      expect(settings.nasPaths, [r'D:\ValidFallback']);
      expect(settings.subtitlesEnabledByDefault, isTrue);
      expect(settings.subtitleScale, AppSpacing.subtitleScaleDefault);
      expect(settings.effectMode, EffectMode.glass);

      final shell = ShellController(
        settingsController: settings,
        databaseService: env.dbService,
      );
      shell.initializeStartupState();
      expect(shell.startupBanner?.severity, StatusSeverity.warning);
      expect(
        shell.startupBanner?.message,
        AppStrings.settingsFieldFallbackWarning,
      );

      shell.dispose();
      settings.dispose();
    });

    test(
        'offline NAS startup shows local library, deduplicates startup sync, shows retry banner, and clears on retry',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      seedSampleLibrary(env.dbService);
      final nasPath = p.join(env.tempRoot.path, 'nas_initially_offline');

      final settings = _CountingStartupSettingsController(env.dbService);
      await settings.load();
      settings.addNasPath(nasPath);

      final library = LibraryController(env.dbService, settings);
      final home = HomeController(env.dbService);
      final stats = StatsController(env.dbService);
      library.loadCountsFromCache();
      home.refreshHomeFeeds();
      expect(library.seriesCount, 2);

      final shell = ShellController(
        settingsController: settings,
        libraryController: library,
        homeController: home,
        statsController: stats,
        databaseService: env.dbService,
      );
      shell.initializeStartupState();

      // Parallel calls must deduplicate to a single startup sync run
      await Future.wait([
        shell.runStartupSync(),
        shell.runStartupSync(),
      ]);
      expect(settings.syncCallCount, 1);
      expect(shell.startupBanner, isNotNull);
      expect(shell.canRetryStartupSync, isTrue);

      // Now bring NAS online and retry
      Directory(nasPath).createSync(recursive: true);
      await shell.retryStartupSync();
      expect(settings.syncCallCount, 2);
      expect(shell.startupBanner, isNull);
      expect(shell.canRetryStartupSync, isFalse);

      shell.dispose();
      stats.dispose();
      home.dispose();
      library.dispose();
      settings.dispose();
    });

    testWidgets(
        'ShellView renders ShellStartupBanner cleanly at desktop & mobile sizes and supports retry',
        (tester) async {
      late TestEnv env;
      late _CountingStartupSettingsController settings;
      late LibraryController library;
      late HomeController home;
      late StatsController stats;
      late FakePlayerHarness harness;
      late SaphirPlayerController player;
      late ShellController shell;
      late String nasPath;

      await tester.runAsync(() async {
        env = await TestEnv.create();
        seedSampleLibrary(env.dbService);
        nasPath = p.join(env.tempRoot.path, 'nas_widget_offline');

        settings = _CountingStartupSettingsController(env.dbService);
        await settings.load();
        settings.addNasPath(nasPath);

        library = LibraryController(env.dbService, settings);
        home = HomeController(env.dbService);
        stats = StatsController(env.dbService);
        harness = FakePlayerHarness();
        player = SaphirPlayerController(
          env.dbService,
          ProgressSyncService(env.dbService),
          () => settings.nasPaths,
          settingsController: settings,
          player: harness.player,
          videoController: harness.videoController,
        );
        shell = ShellController(
          settingsController: settings,
          libraryController: library,
          homeController: home,
          statsController: stats,
          playerController: player,
          databaseService: env.dbService,
        );

        await shell.runStartupSync();
      });
      addTearDown(() async {
        await tester.runAsync(harness.close);
        env.dispose();
      });
      expect(shell.startupBanner, isNotNull);

      for (final size in [const Size(1280, 800), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.buildDarkTheme(),
            home: ShellView(
              shellController: shell,
              settingsController: settings,
              libraryController: library,
              homeController: home,
              statsController: stats,
              playerController: player,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(ShellStartupBanner), findsOneWidget);
        expect(find.text(AppStrings.startupSyncRetryButton), findsOneWidget);
      }

      Directory(nasPath).createSync(recursive: true);
      await tester.tap(find.text(AppStrings.startupSyncRetryButton));
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (
            shell.startupBanner != null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(settings.syncCallCount, 2);
      expect(find.byType(ShellStartupBanner), findsNothing);

      // Unmount tree before disposing controllers
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      shell.dispose();
      player.dispose();
      stats.dispose();
      home.dispose();
      library.dispose();
      settings.dispose();
    });
  });
}
