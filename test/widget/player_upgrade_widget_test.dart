import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/core/theme/effect_mode.dart';
import 'package:saphir_player/features/player/playback_session.dart';
import 'package:saphir_player/features/player/player_models.dart';
import 'package:saphir_player/features/player/saphir_player_controller.dart';
import 'package:saphir_player/features/player/saphir_player_view.dart';
import 'package:saphir_player/features/shell/widgets/settings_view.dart';
import '../helpers/mock_mpv_property_bridge.dart';
import '../helpers/mock_player.dart';
import '../helpers/test_fixtures.dart';

void main() {
  late TestEnv env;
  late ProgressSyncService syncService;
  late SettingsController settingsController;
  late LibraryController libraryController;
  late FakePlayerHarness harness;
  late MockMpvPropertyBridge bridge;
  late SaphirPlayerController controller;
  late Directory mediaDir;

  setUp(() async {
    env = await TestEnv.create();
    seedSampleLibrary(env.dbService);
    syncService = ProgressSyncService(env.dbService);
    settingsController = SettingsController(env.dbService);
    await settingsController.load();
    libraryController = LibraryController(env.dbService, settingsController);
    harness = FakePlayerHarness();
    bridge = MockMpvPropertyBridge();
    mediaDir = env.createSubdir('videos');
    controller = SaphirPlayerController(
      env.dbService,
      syncService,
      () => mediaDir.path,
      settingsController: settingsController,
      player: harness.player,
      videoController: harness.videoController,
      mpvBridge: bridge,
      windowAdapter: harness.windowAdapter,
    );
  });

  tearDown(() async {
    controller.dispose();
    libraryController.dispose();
    settingsController.dispose();
    await harness.close();
    await syncService.syncWithStorage(mediaDir.path);
    env.dispose();
  });

  testWidgets('SettingsView renders subtitle & hwdec controls and updates controller',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final nasInput = TextEditingController();
    addTearDown(nasInput.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildDarkTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: settingsController,
            builder: (context, _) => SettingsView(
              settingsController: settingsController,
              libraryController: libraryController,
              nasInputController: nasInput,
              effectMode: settingsController.effectMode,
              statusMessage: null,
              onAddFolderFromInput: () {},
              onAddFolderFromPicker: () {},
              onRemoveFolder: (_) {},
              onTriggerScan: () {},
              onSaveSettings: () {},
              onSyncNow: () {},
              onClearCache: () {},
              onResetDatabase: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsHwdecLabel), findsOneWidget);
    expect(find.text(AppStrings.settingsSubtitlesSectionTitle), findsOneWidget);

    await tester.ensureVisible(find.text(AppStrings.settingsSubtitlesDefaultLabel));
    await tester.tap(find.text(AppStrings.settingsSubtitlesDefaultLabel));
    await tester.pump();
    expect(settingsController.subtitlesEnabledByDefault, isTrue);

    await tester.tap(find.text(AppStrings.subtitleLangEn));
    await tester.pump();
    expect(settingsController.preferredSubtitleLanguage, AppStrings.subtitleLangCodeEn);
  });

  testWidgets('SaphirPlayerView handles extended shortcuts and tiered Esc',
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
    harness.emitDuration(const Duration(minutes: 30));

    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildDarkTheme(),
        home: Scaffold(
          body: SaphirPlayerView(
            controller: controller,
            effectMode: EffectMode.glass,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pump();

    // Time display toggle
    expect(find.text('30:00'), findsOneWidget);
    await tester.tap(find.text('30:00'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('-30:00'), findsOneWidget);

    // Shortcuts: F, M, A, B, S, ., ,, E, I, H
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(controller.isEpisodeDrawerOpen, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(controller.isShortcutSheetOpen, isTrue);
    expect(find.text(AppStrings.playerShortcutsTitle), findsOneWidget);

    // First Esc closes overlay, does NOT close player
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.isShortcutSheetOpen, isFalse);
    expect(closed, isFalse);

    // Second Esc closes player
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(closed, isTrue);
  });

  for (final mode in [EffectMode.glass, EffectMode.lean]) {
    for (final size in [
      const Size(1280, 800),
      const Size(480, 270),
      const Size(390, 844),
    ]) {
      testWidgets('All player overlays render without overflow at $size ($mode)',
          (tester) async {
        tester.view.physicalSize = size;
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
        harness.emitDuration(const Duration(minutes: 30));
        harness.emitPosition(const Duration(seconds: 15));
        controller.toggleDiagnostics();
        controller.toggleEpisodeDrawer();
        controller.showActionOsd(PlayerActionOsdKind.volume, '85%');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.buildDarkTheme(),
            home: Scaffold(
              body: SaphirPlayerView(
                controller: controller,
                effectMode: mode,
                onClose: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(SaphirPlayerView), findsOneWidget);

        await tester.runAsync(() => controller.stopAndClose());
        await tester.pump(const Duration(milliseconds: 200));
      });
    }
  }
}
