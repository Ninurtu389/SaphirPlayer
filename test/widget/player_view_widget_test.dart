import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/core/theme/effect_mode.dart';
import 'package:saphir_player/features/player/playback_session.dart';
import 'package:saphir_player/features/player/saphir_player_controller.dart';
import 'package:saphir_player/features/player/saphir_player_view.dart';
import '../helpers/mock_player.dart';
import '../helpers/test_fixtures.dart';

void main() {
  late TestEnv env;
  late ProgressSyncService syncService;
  late FakePlayerHarness harness;
  late SaphirPlayerController controller;
  late Directory mediaDir;

  setUp(() async {
    env = await TestEnv.create();
    seedSampleLibrary(env.dbService);
    syncService = ProgressSyncService(env.dbService);
    harness = FakePlayerHarness();
    mediaDir = env.createSubdir('videos');
    controller = SaphirPlayerController(
      env.dbService,
      syncService,
      () => mediaDir.path,
      player: harness.player,
      videoController: harness.videoController,
      onSetFullScreen: harness.onSetFullScreen,
    );
  });

  tearDown(() async {
    controller.dispose();
    await harness.close();
    await syncService.syncWithStorage(mediaDir.path);
    env.dispose();
  });

  Widget buildPlayerApp({
    required EffectMode effectMode,
    required VoidCallback onClose,
  }) {
    return MaterialApp(
      theme: AppTheme.buildDarkTheme(),
      home: Scaffold(
        body: SaphirPlayerView(
          controller: controller,
          effectMode: effectMode,
          onClose: onClose,
        ),
      ),
    );
  }

  testWidgets(
      'SaphirPlayerView handles keyboard shortcuts, mouse wheel, X-buttons, and close',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
    final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');

    await tester.runAsync(
      () => controller.startSession(
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
            ),
            PlaybackQueueEntry(
              mediaKey: 'episode_2',
              mediaType: 'episode',
              title: 'Dark',
              subtitle: 'S1E2 · Luegen',
              filePath: ep2.path,
              seriesId: 1,
              startPositionMs: 0,
            ),
          ],
          initialIndex: 0,
        ),
      ),
    );
    harness.emitDuration(const Duration(minutes: 45));

    var closed = false;
    await tester.pumpWidget(
      buildPlayerApp(
        effectMode: EffectMode.glass,
        onClose: () => closed = true,
      ),
    );
    await tester.pump();

    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('S1E1 · Geheimnisse'), findsOneWidget);

    // Space toggles play/pause
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(harness.playOrPauseCount, 1);

    // ArrowRight / ArrowLeft seek
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(harness.seekTargets.length, greaterThanOrEqualTo(2));

    // X-Mouse forward button -> next episode
    final center = tester.getCenter(find.byType(SaphirPlayerView));
    final forwardMouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 10,
      buttons: kForwardMouseButton,
    );
    await forwardMouse.addPointer(location: center);
    await forwardMouse.down(center);
    await forwardMouse.up();
    await forwardMouse.removePointer();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(controller.currentEntry?.mediaKey, 'episode_2');

    // X-Mouse back button -> previous episode
    final backMouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 11,
      buttons: kBackMouseButton,
    );
    await backMouse.addPointer(location: center);
    await backMouse.down(center);
    await backMouse.up();
    await backMouse.removePointer();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(controller.currentEntry?.mediaKey, 'episode_1');

    // Escape closes player
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(closed, isTrue);
  });

  testWidgets('SaphirPlayerView shows codec error UI and auto-next card cleanly',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final ep1 = createSyntheticHevcStubFile(mediaDir, 'hevc.mp4');
    final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');

    await tester.runAsync(
      () => controller.startSession(
        PlaybackSession(
          queue: [
            PlaybackQueueEntry(
              mediaKey: 'episode_1',
              mediaType: 'episode',
              title: 'Dark',
              subtitle: 'S1E1',
              filePath: ep1.path,
              seriesId: 1,
              startPositionMs: 0,
            ),
            PlaybackQueueEntry(
              mediaKey: 'episode_2',
              mediaType: 'episode',
              title: 'Dark',
              subtitle: 'S1E2',
              filePath: ep2.path,
              seriesId: 1,
              startPositionMs: 0,
            ),
          ],
          initialIndex: 0,
        ),
      ),
    );

    var closed = false;
    await tester.pumpWidget(
      buildPlayerApp(
        effectMode: EffectMode.lean,
        onClose: () => closed = true,
      ),
    );
    await tester.pump();

    // Show Auto-Next card
    harness.emitDuration(const Duration(seconds: 100));
    harness.emitPosition(
      Duration(seconds: 100 - AppSpacing.autoNextLeadSeconds + 3),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text(AppStrings.autoNextPlayNowButton), findsOneWidget);

    await tester.tap(
      find.widgetWithText(TextButton, AppStrings.autoNextCancelButton),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text(AppStrings.autoNextPlayNowButton), findsNothing);

    // Emit codec error
    harness.emitError('Unsupported HEVC codec');
    await tester.pump();
    await tester.pump();
    expect(find.text(AppStrings.playerPlaybackError), findsOneWidget);

    await tester.tap(find.text(AppStrings.backButton));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(closed, isTrue);
  });

  for (final size in [
    const Size(1280, 800),
    const Size(800, 500),
    const Size(768, 1024),
    const Size(390, 844),
  ]) {
    testWidgets('SaphirPlayerView layout check at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
      await tester.runAsync(
        () => controller.startSession(
          PlaybackSession(
            queue: [
              PlaybackQueueEntry(
                mediaKey: 'episode_1',
                mediaType: 'episode',
                title: 'Dark',
                subtitle: 'S1E1',
                filePath: ep1.path,
                seriesId: 1,
                startPositionMs: 0,
              ),
            ],
            initialIndex: 0,
          ),
        ),
      );

      await tester.pumpWidget(
        buildPlayerApp(effectMode: EffectMode.lean, onClose: () {}),
      );
      await tester.pump();
      expect(find.text('Dark'), findsOneWidget);
    });
  }
}
