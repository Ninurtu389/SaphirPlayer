import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/player/player_models.dart';
import 'package:saphir_player/features/player/saphir_player_controller.dart';
import 'package:saphir_player/features/player/saphir_player_view.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import 'package:saphir_player/features/shell/shell_view.dart';
import 'package:saphir_player/features/stats/stats_controller.dart';
import '../helpers/mock_mpv_property_bridge.dart';
import '../helpers/mock_player.dart';
import '../helpers/test_fixtures.dart';

void main() {
  late TestEnv env;
  late Directory nasRoot;
  late ProgressSyncService syncService;
  late ShellController shellController;
  late SettingsController settingsController;
  late LibraryController libraryController;
  late HomeController homeController;
  late StatsController statsController;
  late FakePlayerHarness harness;
  late MockMpvPropertyBridge bridge;
  late SaphirPlayerController playerController;

  setUp(() async {
    env = await TestEnv.create();
    nasRoot = env.createSubdir('nas_media');
    final showDir = Directory(p.join(nasRoot.path, 'Andor', 'Season 1'))
      ..createSync(recursive: true);
    createSyntheticMp4HeaderFile(showDir, 'Andor - S01E01 - Kassa.mp4');
    createSyntheticMp4HeaderFile(showDir, 'Andor - S01E02 - That Would Be Me.mp4');

    syncService = ProgressSyncService(env.dbService);
    shellController = ShellController();
    settingsController =
        SettingsController(env.dbService, syncService: syncService);
    await settingsController.load();
    libraryController = LibraryController(env.dbService, settingsController);
    homeController = HomeController(env.dbService);
    statsController = StatsController(env.dbService);
    harness = FakePlayerHarness();
    bridge = MockMpvPropertyBridge();
    bridge.chaptersToReturn = const [
      PlayerChapter(index: 0, title: 'Intro', startMs: 0),
      PlayerChapter(index: 1, title: 'Kapitel 2', startMs: 85000),
    ];
    playerController = SaphirPlayerController(
      env.dbService,
      syncService,
      () => settingsController.nasPath,
      settingsController: settingsController,
      player: harness.player,
      videoController: harness.videoController,
      mpvBridge: bridge,
      windowAdapter: harness.windowAdapter,
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
    await syncService.syncWithStorage(nasRoot.path);
    env.dispose();
  });

  testWidgets(
      'E2E: global subtitle settings -> series playback -> intro skip -> bookmark -> drawer -> sleep timer -> mini player -> close',
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
    await tester.pump(const Duration(milliseconds: 200));

    // 1. Configure global subtitle settings in SettingsView
    await tester.tap(find.text(AppStrings.settingsTab));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(
      find.text(AppStrings.settingsSubtitlesDefaultLabel),
    );
    await tester.tap(find.text(AppStrings.settingsSubtitlesDefaultLabel));
    await tester.tap(find.text(AppStrings.subtitleLangEn));
    await tester.pump();

    settingsController.addNasPath(nasRoot.path);
    await tester.runAsync(() async {
      await libraryController.refreshLibrary();
      homeController.refreshHomeFeeds();
    });
    await tester.pump(const Duration(milliseconds: 200));

    // 2. Open SeriesDetail and start Episode 1
    await tester.tap(find.text(AppStrings.homeTab));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text(AppStrings.detailsButton));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text(AppStrings.playEpisodeOneButton));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    expect(find.byType(SaphirPlayerView), findsOneWidget);

    // 3. Emit tracks -> global English subtitle auto-selected
    harness.emitTracks(
      Tracks(
        audio: [AudioTrack.auto(), AudioTrack('eng', 'English', 'en')],
        subtitle: [
          SubtitleTrack.auto(),
          SubtitleTrack('deu', 'Deutsch', 'de'),
          SubtitleTrack('eng', 'English', 'en'),
        ],
      ),
    );
    harness.emitDuration(const Duration(minutes: 30));
    harness.emitPosition(const Duration(seconds: 15));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pump();
    expect(harness.selectedSubtitleTracks.last.id, 'eng');

    // 4. Intro skip -> bookmark -> episode drawer switch -> sleep timer -> mini player -> close
    await tester.tap(find.text(AppStrings.playerIntroSkipButton));
    await tester.pump(const Duration(milliseconds: 350));
    expect(harness.seekTargets.last, const Duration(milliseconds: 85000));

    await tester.tap(find.byTooltip(AppStrings.playerBookmarkTooltip));
    await tester.pump(const Duration(milliseconds: 350));
    expect(playerController.bookmarks.length, 1);

    await tester.tap(find.byTooltip(AppStrings.playerEpisodeDrawerTooltip));
    await tester.pump(const Duration(milliseconds: 350));
    expect(playerController.isEpisodeDrawerOpen, isTrue);

    await tester.tap(find.textContaining('S1E2'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
    expect(playerController.currentEntry?.mediaKey, 'episode_2');

    playerController.setSleepTimer(SleepTimerOption.endOfEpisode);
    await tester.tap(find.byTooltip(AppStrings.playerMiniPlayerTooltip));
    await tester.pump(const Duration(milliseconds: 350));
    expect(playerController.isMiniPlayer, isTrue);
    expect(harness.alwaysOnTopStates.last, isTrue);

    await tester.tap(find.byTooltip(AppStrings.playerCloseTooltip));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(SaphirPlayerView), findsNothing);
    expect(harness.alwaysOnTopStates.last, isFalse);
  });
}
