import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/storage/sync_key_utils.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/player/saphir_player_controller.dart';
import 'package:saphir_player/features/player/saphir_player_view.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import 'package:saphir_player/features/shell/shell_view.dart';
import 'package:saphir_player/features/stats/stats_controller.dart';
import '../helpers/mock_player.dart';
import '../helpers/test_fixtures.dart';

void main() {
  late TestEnv env;
  late Directory nasRoot;
  late ShellController shellController;
  late SettingsController settingsController;
  late LibraryController libraryController;
  late HomeController homeController;
  late StatsController statsController;
  late ProgressSyncService syncService;
  late FakePlayerHarness harness;
  late SaphirPlayerController playerController;

  setUp(() async {
    env = await TestEnv.create();
    nasRoot = env.createSubdir('nas_media');
    final showDir = Directory(p.join(nasRoot.path, 'Andor', 'Season 1'))
      ..createSync(recursive: true);
    createSyntheticMp4HeaderFile(showDir, 'Andor - S01E01 - Kassa.mp4');
    createSyntheticMp4HeaderFile(nasRoot, 'Arrival (2016).mkv');

    syncService = ProgressSyncService(env.dbService);
    shellController = ShellController();
    settingsController =
        SettingsController(env.dbService, syncService: syncService);
    await settingsController.load();
    libraryController = LibraryController(env.dbService, settingsController);
    homeController = HomeController(env.dbService);
    statsController = StatsController(env.dbService);
    harness = FakePlayerHarness();
    playerController = SaphirPlayerController(
      env.dbService,
      syncService,
      () => settingsController.nasPaths,
      player: harness.player,
      videoController: harness.videoController,
      onSetFullScreen: harness.onSetFullScreen,
    );
  });

  tearDown(() async {
    playerController.dispose();
    await harness.close();
    shellController.dispose();
    libraryController.dispose();
    settingsController.dispose();
    homeController.dispose();
    statsController.dispose();
    env.dispose();
  });

  testWidgets(
      'End-to-End flow: configure folder -> scan -> detail -> play -> sync -> stats -> reset',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildDarkTheme(),
        home: ShellView(
          shellController: shellController,
          settingsController: settingsController,
          libraryController: libraryController,
          homeController: homeController,
          statsController: statsController,
          playerController: playerController,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 1. Add NAS folder & trigger scan
    await tester.tap(find.text(AppStrings.settingsTab));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == AppStrings.nasPathLabel,
      ),
      nasRoot.path,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 300));

    // Trigger scan in real async zone so Isolate.run & Directory.list do not deadlock FakeAsync
    await tester.runAsync(() async {
      await syncService.syncWithRoots(settingsController.nasPaths);
      await libraryController.refreshLibrary();
      homeController.refreshHomeFeeds();
      statsController.refreshStats();
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      libraryController.seriesCount,
      1,
      reason:
          'status=${libraryController.statusMessage}, paths=${settingsController.nasPaths}, movies=${libraryController.movieCount}, scanning=${libraryController.isScanning}',
    );
    expect(libraryController.movieCount, 1);

    // 2. Navigate to Home and open SeriesDetail
    await tester.tap(find.text(AppStrings.homeTab));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Andor'), findsWidgets);

    await tester.tap(find.text(AppStrings.detailsButton));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('${AppStrings.seasonPrefix} 1'), findsOneWidget);

    // 3. Start playback
    await tester.tap(find.text(AppStrings.playEpisodeOneButton));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byType(SaphirPlayerView), findsOneWidget);

    // Simulate playback progress & completion
    harness.emitDuration(const Duration(seconds: 100));
    harness.emitPosition(const Duration(seconds: 95));
    await tester.pump();

    await tester.tap(find.byTooltip(AppStrings.playerCloseTooltip));
    await tester.pump();
    for (var i = 0; i < 10 && shellController.isPlayerOpen; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SaphirPlayerView), findsNothing);

    // 4. Verify progress_sync.json written on NAS
    await tester.runAsync(
      () => syncService.syncWithRoots(settingsController.nasPaths),
    );
    final syncFile = File(p.join(nasRoot.path, 'progress_sync.json'));
    expect(syncFile.existsSync(), isTrue);
    final decoded =
        jsonDecode(syncFile.readAsStringSync()) as Map<String, dynamic>;
    final entries = decoded['entries'] as Map<String, dynamic>;
    final expectedSyncKey = SyncKeyUtils.buildStableSyncKey(
      'ep',
      p.join(nasRoot.path, 'Andor', 'Season 1', 'Andor - S01E01 - Kassa.mp4'),
      nasRoot.path,
    );
    expect(entries.containsKey(expectedSyncKey), isTrue);

    // 5. Verify Stats tab reflects completed episode
    await tester.tap(find.text(AppStrings.statsTab));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(AppStrings.statsEmptyMessage), findsNothing);

    // 6. Reset DB via Settings dialog
    await tester.tap(find.text(AppStrings.settingsTab));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text(AppStrings.resetDatabaseButton));
    await tester.tap(find.text(AppStrings.resetDatabaseButton));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(AppStrings.resetDatabaseConfirmAction));
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 60 && libraryController.seriesCount > 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text(AppStrings.homeTab));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(AppStrings.emptyHomeMessage), findsOneWidget);

    // 7. Verify automatic pre_reset backup was created and can restore the library
    expect(settingsController.latestBackup, isNotNull);
    expect(settingsController.latestBackup!.reason, 'pre_reset');
    await tester.runAsync(() => shellController.handleRestoreBackup());
    await tester.pump(const Duration(milliseconds: 300));
    expect(libraryController.seriesCount, 1);
  });
}
