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
      () => [mediaDir.path],
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

  test('subtitle priority: series preference overrides global setting and passive emitTrack preserves global defaults',
      () async {
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
    // Passive stream.track emission must NOT write series_preferences
    harness.emitTrack(Track(audio: AudioTrack.auto(), subtitle: subEn));
    await Future<void>.delayed(Duration.zero);
    expect(harness.selectedSubtitleTracks.last.id, 'eng');
    expect(
      env.dbService.instance
          .select('SELECT * FROM series_preferences WHERE series_id = 1;'),
      isEmpty,
    );

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
    expect(bridge.commands.last, ['af', 'add', 'lavfi=[dynaudnorm=f=150:g=15]']);

    await controller.toggleNightMode();
    expect(bridge.commands.last, ['af', 'remove', 'lavfi=[dynaudnorm=f=150:g=15]']);

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
    expect(bridge.properties['video-aspect-override'], 'no');
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

  test('chapters, intro skip, dismissIntroSkip, bookmarks, and 1-click screenshot',
      () async {
    final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
    final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');
    env.dbService.instance.execute(
      "UPDATE watch_progress SET position_ms = 0 WHERE media_key = 'episode_1';",
    );
    bridge.chaptersToReturn = const [
      PlayerChapter(index: 0, title: 'Part 1', startMs: 0),
      PlayerChapter(index: 1, title: 'Intro', startMs: 15000),
      PlayerChapter(index: 2, title: 'Handlung', startMs: 85000),
    ];

    await controller.startSession(makeEpisodeSession([ep1.path, ep2.path]));
    harness.emitDuration(const Duration(minutes: 30));
    harness.emitPosition(const Duration(seconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.chapters.length, 3);
    expect(controller.showIntroSkipButton, isTrue);

    await controller.skipIntro();
    expect(harness.seekTargets.last, const Duration(milliseconds: 85000));
    expect(controller.showIntroSkipButton, isFalse);

    // Test dismissIntroSkip without seeking
    await controller.playNextEpisode();
    harness.emitDuration(const Duration(minutes: 30));
    harness.emitPosition(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prevSeekCount = harness.seekTargets.length;
    expect(controller.showIntroSkipButton, isTrue);
    controller.dismissIntroSkip();
    expect(controller.showIntroSkipButton, isFalse);
    expect(harness.seekTargets.length, prevSeekCount);

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

  test('episode drawer switch, sleep timer, mini-player from maximized, hwdec, and stopAndClose reset',
      () async {
    final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
    final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');

    settingsController.updateHardwareAcceleration(false);
    await controller.startSession(makeEpisodeSession([ep1.path, ep2.path]));
    expect(bridge.hwdecHistory.last, isFalse);

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

    // Set non-default speed/delays/aspect before mini-player & close
    await controller.setPlaybackSpeed(1.5);
    await controller.adjustAudioDelay(200);
    await controller.adjustSubtitleDelay(-100);
    await controller.setAspectMode(VideoAspectMode.ratio16x9);

    // Mini-player from maximized state unmaximizes on enter and restores maximize on close
    harness.isWindowMaximizedState = true;
    await controller.toggleMiniPlayer();
    expect(controller.isMiniPlayer, isTrue);
    expect(harness.unmaximizeCount, 1);
    expect(harness.alwaysOnTopStates.last, isTrue);

    await controller.stopAndClose();
    expect(controller.isMiniPlayer, isFalse);
    expect(harness.maximizeCount, 1);
    expect(harness.alwaysOnTopStates.last, isFalse);
    expect(harness.windowBoundsHistory.last, const Rect.fromLTWH(100, 100, 1280, 800));
    expect(controller.playbackSpeed, 1.0);
    expect(controller.audioDelayMs, 0);
    expect(controller.subtitleDelayMs, 0);
    expect(controller.aspectMode, VideoAspectMode.original);
    expect(controller.progressListenable.value.position, Duration.zero);
    expect(controller.progressListenable.value.duration, Duration.zero);
  });

  test('intro skip hides after configured seconds, progressListenable decouples position notifications, and duration_ms backfills',
      () async {
    final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
    final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');
    env.dbService.instance.execute(
      "UPDATE watch_progress SET position_ms = 120000 WHERE media_key = 'episode_1';",
    );
    env.dbService.instance.execute(
      'UPDATE episodes SET duration_ms = 0 WHERE id = 2;',
    );

    await controller.startSession(
      PlaybackSession(
        queue: [
          PlaybackQueueEntry(
            mediaKey: 'episode_1',
            mediaType: 'episode',
            title: 'Dark',
            subtitle: 'S1E1',
            filePath: ep1.path,
            seriesId: 1,
            startPositionMs: 120000,
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
    );

    expect(harness.openedMedia.first.start, const Duration(milliseconds: 120000));
    expect(bridge.properties['start'], 'none');

    // Switch to episode 2 starting at 0, verify intro skip auto-hides after configured duration
    await controller.playNextEpisode();
    expect(harness.openedMedia.last.start, isNull);
    controller.setSeriesIntroSkipSeconds(60);
    harness.emitDuration(const Duration(minutes: 30));
    await Future<void>.delayed(Duration.zero);

    // Count controller notifications while emitting position ticks within intro window
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);
    harness.emitPosition(const Duration(seconds: 40));
    harness.emitPosition(const Duration(seconds: 40, milliseconds: 100));
    harness.emitPosition(const Duration(seconds: 40, milliseconds: 200));
    await Future<void>.delayed(Duration.zero);
    expect(notifyCount, 0);
    expect(controller.progressListenable.value.position, const Duration(seconds: 40));
    expect(controller.showIntroSkipButton, isTrue);

    harness.emitPosition(const Duration(seconds: 41));
    await Future<void>.delayed(Duration.zero);
    expect(notifyCount, 0);
    expect(controller.progressListenable.value.position, const Duration(seconds: 41));

    harness.emitPosition(const Duration(seconds: 60));
    await Future<void>.delayed(Duration.zero);
    expect(notifyCount, 1);
    expect(controller.showIntroSkipButton, isFalse);

    // setMenuOrDialogOpen keeps HUD open while playing
    controller.setMenuOrDialogOpen(true);
    expect(controller.isHudVisible, isTrue);
    controller.setMenuOrDialogOpen(false);

    // stopAndClose persists duration_ms back into episodes table when previously 0
    await controller.stopAndClose();
    final ep2Dur = env.dbService.instance
        .select('SELECT duration_ms FROM episodes WHERE id = 2;')
        .first['duration_ms'];
    expect(ep2Dur, const Duration(minutes: 30).inMilliseconds);
  });
}
