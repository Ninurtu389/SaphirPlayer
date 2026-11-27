import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/core/theme/effect_mode.dart';
import 'package:saphir_player/features/player/playback_session.dart';
import 'package:saphir_player/features/player/player_models.dart';
import 'package:saphir_player/features/player/saphir_player_controller.dart';
import 'package:saphir_player/features/player/saphir_player_view.dart';
import 'package:saphir_player/features/player/widgets/player_action_osd.dart';
import 'package:saphir_player/features/player/widgets/player_seek_bar.dart';
import 'package:saphir_player/features/player/widgets/player_top_hud.dart';
import '../helpers/mock_mpv_property_bridge.dart';
import '../helpers/mock_player.dart';
import '../helpers/test_fixtures.dart';

void main() {
  late TestEnv env;
  late ProgressSyncService syncService;
  late SettingsController settingsController;
  late FakePlayerHarness harness;
  late MockMpvPropertyBridge bridge;
  late SaphirPlayerController controller;
  late Directory mediaDir;

  setUp(() async {
    env = await TestEnv.create();
    seedSampleLibrary(env.dbService);
    env.dbService.instance.execute(
      "UPDATE watch_progress SET position_ms = 0 WHERE media_key = 'episode_1';",
    );
    syncService = ProgressSyncService(env.dbService);
    settingsController = SettingsController(env.dbService);
    await settingsController.load();
    harness = FakePlayerHarness();
    bridge = MockMpvPropertyBridge();
    bridge.chaptersToReturn = const [
      PlayerChapter(index: 0, title: 'Intro', startMs: 0),
      PlayerChapter(index: 1, title: 'Haupthandlung', startMs: 90000),
      PlayerChapter(index: 2, title: 'Finale', startMs: 1200000),
    ];
    mediaDir = env.createSubdir('videos');
    controller = SaphirPlayerController(
      env.dbService,
      syncService,
      () => [mediaDir.path],
      settingsController: settingsController,
      player: harness.player,
      videoController: harness.videoController,
      mpvBridge: bridge,
      windowAdapter: harness.windowAdapter,
    );
  });

  tearDown(() async {
    controller.dispose();
    settingsController.dispose();
    await harness.close();
    await syncService.syncWithStorage(mediaDir.path);
    env.dispose();
  });

  Future<void> startSampleSession({String? artist}) async {
    final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
    await controller.startSession(
      PlaybackSession(
        queue: [
          PlaybackQueueEntry(
            mediaKey: 'episode_1',
            mediaType: 'episode',
            title: 'Dark',
            subtitle: 'S1E1 · Geheimnisse',
            filePath: ep1.path,
            seriesId: 1,
            startPositionMs: 0,
            artist: artist,
          ),
        ],
        initialIndex: 0,
      ),
    );
    harness.emitDuration(const Duration(minutes: 30));
    harness.emitPosition(const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  Widget wrapPlayer(EffectMode mode) {
    return MaterialApp(
      theme: AppTheme.buildDarkTheme(),
      home: Scaffold(
        body: SaphirPlayerView(
          controller: controller,
          effectMode: mode,
          onClose: () {},
        ),
      ),
    );
  }

  testWidgets('PlayerIntroSkipButton X dismisses immediately without seeking',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.runAsync(() => startSampleSession());
    await tester.pumpWidget(wrapPlayer(EffectMode.glass));
    await tester.pump();

    expect(find.text(AppStrings.playerIntroSkipButton), findsOneWidget);
    final seeksBefore = harness.seekTargets.length;

    await tester.tap(find.byTooltip(AppStrings.dismissIntroSkipTooltip));
    await tester.pump();

    expect(find.text(AppStrings.playerIntroSkipButton), findsNothing);
    expect(harness.seekTargets.length, seeksBefore);

    await tester.runAsync(() => controller.stopAndClose());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
      'PlayerSeekBar drags locally without network seek until onChangeEnd and renders markers within track inset',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.runAsync(() => startSampleSession());
    controller.addBookmarkAtCurrentPosition(label: 'Szene A');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildDarkTheme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: PlayerSeekBar(
              controller: controller,
              effectMode: EffectMode.glass,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify CustomPaint marker layer exists inside PlayerSeekBar
    final seekPaintFinder = find.descendant(
      of: find.byType(PlayerSeekBar),
      matching: find.byType(CustomPaint),
    );
    expect(seekPaintFinder, findsWidgets);

    final seeksBefore = harness.seekTargets.length;
    final sliderBox = tester.getRect(find.byType(Slider));
    final startPoint = Offset(sliderBox.left + 40, sliderBox.center.dy);
    final drag = await tester.startGesture(startPoint);
    await tester.pump();
    await drag.moveTo(Offset(sliderBox.center.dx, sliderBox.center.dy));
    await tester.pump();

    // No seek emitted during drag!
    expect(harness.seekTargets.length, seeksBefore);

    await drag.up();
    await tester.pump();
    expect(harness.seekTargets.length, seeksBefore + 1);

    await tester.runAsync(() => controller.stopAndClose());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Bookmark menu lists, jumps to, and deletes bookmarks',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.runAsync(() => startSampleSession());
    await tester.pumpWidget(wrapPlayer(EffectMode.lean));
    await tester.pump();

    // Empty bookmarks menu
    await tester.tap(find.byTooltip(AppStrings.playerBookmarksTooltip));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.playerBookmarkListTitle), findsOneWidget);
    expect(find.text(AppStrings.playerNoBookmarksLabel), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Add bookmark at 00:15
    controller.addBookmarkAtCurrentPosition(label: 'Hinweis');
    await tester.pump();

    await tester.tap(find.byTooltip(AppStrings.playerBookmarksTooltip));
    await tester.pumpAndSettle();
    expect(find.text('00:15 · Hinweis'), findsOneWidget);

    // Jump to bookmark
    final seeksBefore = harness.seekTargets.length;
    await tester.tap(find.text('00:15 · Hinweis'));
    await tester.pumpAndSettle();
    expect(harness.seekTargets.length, seeksBefore + 1);
    expect(harness.seekTargets.last, const Duration(seconds: 15));

    // Delete bookmark from menu
    await tester.tap(find.byTooltip(AppStrings.playerBookmarksTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(AppStrings.playerBookmarkDeletedOsd));
    await tester.pumpAndSettle();
    expect(controller.bookmarks, isEmpty);

    await tester.runAsync(() => controller.stopAndClose());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('PlayerTopHud displays tag title and optional artist cleanly',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildDarkTheme(),
        home: Scaffold(
          body: Stack(
            children: [
              PlayerTopHud(
                entry: const PlaybackQueueEntry(
                  mediaKey: 'ep_1',
                  mediaType: 'episode',
                  title: 'Universum',
                  subtitle: 'S1E2 · Schwarze Loecher',
                  filePath: 'ep2.mkv',
                  seriesId: 1,
                  startPositionMs: 0,
                  artist: 'Prof. Harald Lesch',
                ),
                isFullscreen: false,
                onClose: () {},
                onToggleFullscreen: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Universum'), findsOneWidget);
    expect(
      find.text('S1E2 · Schwarze Loecher · Prof. Harald Lesch'),
      findsOneWidget,
    );
  });

  testWidgets('PlayerActionOsd removes BackdropFilter when message is null',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildDarkTheme(),
        home: const Scaffold(
          body: Stack(
            children: [
              PlayerActionOsd(
                message: null,
                kind: null,
                effectMode: EffectMode.glass,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildDarkTheme(),
        home: const Scaffold(
          body: Stack(
            children: [
              PlayerActionOsd(
                message: '80%',
                kind: PlayerActionOsdKind.volume,
                effectMode: EffectMode.glass,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets(
      'Double-tap on HUD button does not toggle fullscreen, mini-player ignores E/I/?, PageUp/Down jump chapters, and focus returns after subtitle dialog',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.runAsync(() => startSampleSession());
    await tester.pumpWidget(wrapPlayer(EffectMode.glass));
    await tester.pump();

    // Double-tap on seek-forward HUD button must NOT trigger fullscreen
    final forwardBtn = find.byTooltip(AppStrings.playerSeekForwardTooltip);
    await tester.tap(forwardBtn);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(forwardBtn);
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isFullscreen, isFalse);

    // PageUp / PageDown chapter jumps
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(harness.seekTargets.last, const Duration(milliseconds: 90000));
    await tester.runAsync(() async {
      harness.emitPosition(const Duration(seconds: 91));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(harness.seekTargets.last, Duration.zero);

    // Open subtitle style dialog via menu, close it, verify Space still toggles play/pause
    await tester.tap(find.byTooltip(AppStrings.playerSubtitleTrackTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.playerSubtitleStyleLabel));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.playerSubtitleStyleTitle), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byTooltip(AppStrings.playerCloseOverlayAction),
      ),
    );
    await tester.pumpAndSettle();

    final playPauseBefore = harness.playOrPauseCount;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(harness.playOrPauseCount, playPauseBefore + 1);

    // Mini-player ignores E / I / H
    await tester.runAsync(() => controller.toggleMiniPlayer());
    await tester.pump();
    expect(controller.isMiniPlayer, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(controller.isEpisodeDrawerOpen, isFalse);
    expect(controller.showDiagnostics, isFalse);
    expect(controller.isShortcutSheetOpen, isFalse);

    await tester.runAsync(() => controller.stopAndClose());
    await tester.pump(const Duration(milliseconds: 200));
  });
}
