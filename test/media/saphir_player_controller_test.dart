import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/portable_paths.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/features/player/player_models.dart';
import 'package:saphir_player/features/player/playback_session.dart';
import 'package:saphir_player/features/player/saphir_player_controller.dart';
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
    syncService = ProgressSyncService(env.dbService);
    settingsController = SettingsController(env.dbService);
    await settingsController.load();
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
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.dispose();
    settingsController.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await harness.close();
    env.dispose();
  });

  PlaybackSession makeEpisodeSession(List<String> paths) {
    return PlaybackSession(
      queue: [
        for (var i = 0; i < paths.length; i++)
          PlaybackQueueEntry(
            mediaKey: 'episode_${i + 1}',
            mediaType: 'episode',
            title: 'Dark',
            subtitle: 'S1E${i + 1}',
            filePath: paths[i],
            seriesId: 1,
            startPositionMs: 0,
          ),
      ],
      initialIndex: 0,
    );
  }

  test('subtitle priority: series preference overrides global setting', () async {
    final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
    settingsController.updateSubtitlesDefaultEnabled(true);
    settingsController.updatePreferredSubtitleLanguage(AppStrings.subtitleLangCodeEn);

    await controller.startSession(makeEpisodeSession([ep1.path]));

    final subDe = SubtitleTrack('deu', 'Deutsch', 'de');
    final subEn = SubtitleTrack('eng', 'English', 'en');
    // No series preference yet -> global picks English
    harness.emitTracks(Tracks(
      audio: [AudioTrack.auto()],
      subtitle: [SubtitleTrack.auto(), subDe, subEn],
    ));
    await Future<void>.delayed(Duration.zero);
    expect(harness.selectedSubtitleTracks.last.id, 'eng');

    // Now save series preference to Deutsch -> overrides global English
    env.dbService.instance.execute(
      "INSERT INTO series_preferences (series_id, audio_track, subtitle_track) VALUES (1, 'auto', 'deu');",
    );
    harness.selectedSubtitleTracks.clear();
    harness.emitTracks(Tracks(
      audio: [AudioTrack.auto()],
      subtitle: [SubtitleTrack.auto(), subDe, subEn],
    ));
    await Future<void>.delayed(Duration.zero);
    expect(harness.selectedSubtitleTracks.last.id, 'deu');
  });

  test('audio/video modes: night mode, 150% boost, aspect modes, sync, external sub, style',
      () async {
    final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
    await controller.startSession(makeEpisodeSession([ep1.path]));

    await controller.toggleNightMode();
    expect(controller.isNightMode, isTrue);
    expect(bridge.nightModeHistory, [true]);

    await controller.toggleVolumeBoost();
    expect(controller.isVolumeBoostEnabled, isTrue);
    expect(controller.maxVolume, AppSpacing.volumeBoostMax);
    await controller.adjustVolume(40);
    expect(controller.volume, 140.0);

    // Turning off boost clamps volume back to 100
    await controller.toggleVolumeBoost();
    expect(controller.maxVolume, AppSpacing.volumeMax);
    expect(controller.volume, 100.0);

    await controller.cycleAspectMode();
    expect(controller.aspectMode, VideoAspectMode.fillCrop);
    expect(bridge.properties['panscan'], '1.0');
    await controller.setAspectMode(VideoAspectMode.ratio21x9);
    expect(bridge.properties['video-aspect-override'], '21:9');

    await controller.adjustAudioDelay(200);
    expect(controller.audioDelayMs, 200);
    await controller.resetAudioDelay();
    expect(controller.audioDelayMs, 0);

    await controller.adjustSubtitleDelay(-100);
    expect(controller.subtitleDelayMs, -100);
    await controller.resetSubtitleDelay();
    expect(controller.subtitleDelayMs, 0);

    harness.pickedSubtitlePath = r'D:\Subs\ep1.srt';
    await controller.loadExternalSubtitle('Pick');
    expect(harness.selectedSubtitleTracks.last.id, r'D:\Subs\ep1.srt');

    await controller.updateLiveSubtitleStyle(scale: 1.5, position: 80, bgOpacity: 0.4);
    expect(bridge.subtitleStyleHistory.last.scale, 1.5);
    expect(bridge.subtitleStyleHistory.last.pos, 80);
  });

  test('chapters, intro skip, bookmarks, and 1-click screenshot', () async {
    final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
    bridge.chaptersToReturn = const [
      PlayerChapter(index: 0, title: 'Intro', startMs: 0),
      PlayerChapter(index: 1, title: 'Handlung', startMs: 85000),
    ];

    await controller.startSession(makeEpisodeSession([ep1.path]));
    harness.emitDuration(const Duration(minutes: 30));
    harness.emitPosition(const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.chapters.length, 2);
    expect(controller.showIntroSkipButton, isTrue);

    await controller.skipIntro();
    expect(harness.seekTargets.last, const Duration(milliseconds: 85000));
    controller.setSeriesIntroSkipSeconds(90);
    expect(controller.seriesIntroSkipSeconds, 90);

    controller.addBookmarkAtCurrentPosition(label: 'Szene');
    expect(controller.bookmarks.length, 1);
    await controller.seekToBookmark(controller.bookmarks.first);
    controller.deleteBookmark(controller.bookmarks.first.id);
    expect(controller.bookmarks, isEmpty);

    final shotPath = await controller.captureScreenshot();
    expect(shotPath, isNotNull);
    expect(File(shotPath!).existsSync(), isTrue);
    final shotDir = await PortablePaths.getScreenshotsDirectory();
    expect(shotPath.startsWith(shotDir), isTrue);
  });

  test('episode drawer switch, sleep timer, mini-player, OSD, and diagnostics',
      () async {
    final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
    final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');
    await controller.startSession(makeEpisodeSession([ep1.path, ep2.path]));
    harness.emitDuration(const Duration(seconds: 100));
    harness.emitPosition(const Duration(seconds: 95));
    await Future<void>.delayed(Duration.zero);

    // Sleep timer endOfEpisode suppresses auto-next & pauses on completion
    controller.setSleepTimer(SleepTimerOption.endOfEpisode);
    expect(controller.showAutoNextCard, isFalse);
    harness.emitCompleted(true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.currentEntry?.mediaKey, 'episode_1');
    expect(controller.sleepTimerOption, SleepTimerOption.off);

    // Timed sleep timer pauses on expiration
    controller.setSleepTimer(
      SleepTimerOption.minutes30,
      customDuration: const Duration(milliseconds: 40),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.sleepTimerOption, SleepTimerOption.off);

    // Drawer switches episode
    controller.toggleEpisodeDrawer();
    expect(controller.isEpisodeDrawerOpen, isTrue);
    await controller.playEntryAtIndex(1);
    expect(controller.isEpisodeDrawerOpen, isFalse);
    expect(controller.currentEntry?.mediaKey, 'episode_2');

    // Diagnostics polls while open and stops on close
    controller.toggleDiagnostics();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.showDiagnostics, isTrue);
    expect(bridge.readDiagnosticsCount, greaterThanOrEqualTo(1));
    controller.toggleDiagnostics();
    expect(controller.showDiagnostics, isFalse);

    // Mini-player saves and restores bounds & alwaysOnTop on stopAndClose
    await controller.toggleMiniPlayer();
    expect(controller.isMiniPlayer, isTrue);
    expect(harness.alwaysOnTopStates.last, isTrue);
    await controller.stopAndClose();
    expect(controller.isMiniPlayer, isFalse);
    expect(harness.alwaysOnTopStates.last, isFalse);
    expect(harness.windowBoundsHistory.last, const Rect.fromLTWH(100, 100, 1280, 800));
  });
}
