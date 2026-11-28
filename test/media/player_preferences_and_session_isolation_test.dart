import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/features/player/playback_session.dart';
import 'package:saphir_player/features/player/player_models.dart';
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

  PlaybackQueueEntry epEntry(
    String key,
    File file, {
    int? seriesId = 1,
    String title = 'Dark',
    String subtitle = 'S1E1',
  }) =>
      PlaybackQueueEntry(
        mediaKey: key,
        mediaType: 'episode',
        title: title,
        subtitle: subtitle,
        filePath: file.path,
        seriesId: seriesId,
        startPositionMs: 0,
      );

  group('A14 Track preference persistence & MPV error handling', () {
    test(
        'explicit auto resets previous series preference and restores global default',
        () async {
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
      final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');

      settingsController.updateSubtitlesDefaultEnabled(true);
      settingsController
          .updatePreferredSubtitleLanguage(AppStrings.subtitleLangCodeEn);

      await controller.startSession(
        PlaybackSession(
          queue: [
            epEntry('episode_1', ep1),
            epEntry('episode_2', ep2, subtitle: 'S1E2')
          ],
          initialIndex: 0,
        ),
      );

      // Persist explicit German audio + off subtitle for series 1
      await controller
          .selectAudioTrack(const AudioTrack('2', 'Deutsch', 'deu'));
      await controller.selectSubtitleTrack(SubtitleTrack.no());

      // Explicitly reset both back to auto -> DB must overwrite prior preference!
      await controller.selectAudioTrack(AudioTrack.auto());
      await controller.selectSubtitleTrack(SubtitleTrack.auto());

      final row = env.dbService.instance
          .select(
              'SELECT audio_track, subtitle_track FROM series_preferences WHERE series_id = 1;')
          .first;
      expect(row['audio_track'], 'auto');
      expect(row['subtitle_track'], 'auto');

      // Switch to Episode 2 -> global English subtitle should now apply
      await controller.playNextEpisode();
      harness.selectedSubtitleTracks.clear();
      harness.emitTracks(
        Tracks(
          audio: [AudioTrack.auto(), const AudioTrack('1', 'Deutsch', 'deu')],
          subtitle: [
            SubtitleTrack.auto(),
            SubtitleTrack.no(),
            const SubtitleTrack('1', 'Deutsch', 'deu'),
            const SubtitleTrack('2', 'English', 'eng'),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(harness.selectedSubtitleTracks.last.id, '2');
    });

    test(
        'missing saved series subtitle language falls back to global preference while off stays off',
        () async {
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
      final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');

      settingsController.updateSubtitlesDefaultEnabled(true);
      settingsController
          .updatePreferredSubtitleLanguage(AppStrings.subtitleLangCodeDe);

      await controller.startSession(
        PlaybackSession(
          queue: [
            epEntry('episode_1', ep1),
            epEntry('episode_2', ep2, subtitle: 'S1E2')
          ],
          initialIndex: 0,
        ),
      );

      // Series wants Japanese, which is absent in Episode 2 -> falls back to global German
      await controller
          .selectSubtitleTrack(const SubtitleTrack('9', 'Japanese', 'jpn'));
      await controller.playNextEpisode();
      harness.selectedSubtitleTracks.clear();
      harness.emitTracks(
        Tracks(
          audio: [AudioTrack.auto()],
          subtitle: [
            SubtitleTrack.auto(),
            SubtitleTrack.no(),
            const SubtitleTrack('3', 'Deutsch', 'deu'),
            const SubtitleTrack('4', 'English', 'eng'),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(harness.selectedSubtitleTracks.last.id, '3');

      // Explicit off overrides global subtitlesEnabledByDefault = true on next episode
      await controller.selectSubtitleTrack(SubtitleTrack.no());
      await controller.playPreviousEpisode();
      harness.selectedSubtitleTracks.clear();
      harness.emitTracks(
        Tracks(
          audio: [AudioTrack.auto()],
          subtitle: [
            SubtitleTrack.auto(),
            SubtitleTrack.no(),
            const SubtitleTrack('3', 'Deutsch', 'deu'),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(harness.selectedSubtitleTracks.last.id, 'no');
    });

    test(
        'failed MPV track switch keeps prior state, does not persist, and shows OSD feedback',
        () async {
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
      await controller.startSession(
        PlaybackSession(queue: [epEntry('episode_1', ep1)], initialIndex: 0),
      );

      await controller
          .selectAudioTrack(const AudioTrack('1', 'English', 'eng'));
      await controller
          .selectSubtitleTrack(const SubtitleTrack('2', 'English', 'eng'));

      harness.setAudioTrackError = StateError('mpv audio error');
      await controller
          .selectAudioTrack(const AudioTrack('3', 'Deutsch', 'deu'));
      expect(controller.activeAudioTrack.id, '1');
      expect(controller.osdKind, PlayerActionOsdKind.error);
      expect(controller.osdMessage, AppStrings.playerAudioTrackSwitchFailedOsd);

      harness.setAudioTrackError = null;
      harness.setSubtitleTrackError = StateError('mpv sub error');
      await controller
          .selectSubtitleTrack(const SubtitleTrack('4', 'Deutsch', 'deu'));
      expect(controller.activeSubtitleTrack.id, '2');
      expect(controller.osdKind, PlayerActionOsdKind.error);
      expect(
          controller.osdMessage, AppStrings.playerSubtitleTrackSwitchFailedOsd);

      final row = env.dbService.instance
          .select(
              'SELECT audio_track, subtitle_track FROM series_preferences WHERE series_id = 1;')
          .first;
      expect(row['audio_track'], '1');
      expect(row['subtitle_track'], '2');
    });
  });

  group('A15 Generation guards for async chapters & diagnostics', () {
    test(
        'delayed chapter load from previous episode cannot overwrite current episode',
        () async {
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
      final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');

      final ep1ChaptersCompleter = Completer<List<PlayerChapter>>();
      var callCount = 0;
      bridge.onReadChapters = () {
        callCount++;
        if (callCount == 1) {
          return ep1ChaptersCompleter.future;
        }
        return Future.value(const [
          PlayerChapter(index: 0, title: 'Ep2 Start', startMs: 0),
        ]);
      };

      await controller.startSession(
        PlaybackSession(
          queue: [
            epEntry('episode_1', ep1),
            epEntry('episode_2', ep2, subtitle: 'S1E2')
          ],
          initialIndex: 0,
        ),
      );
      harness.emitDuration(const Duration(minutes: 25));
      await Future<void>.delayed(Duration.zero);

      // Switch to Episode 2 BEFORE Episode 1 chapters resolve
      await controller.playNextEpisode();
      harness.emitDuration(const Duration(minutes: 30));
      await Future<void>.delayed(Duration.zero);
      expect(controller.chapters.map((c) => c.title).toList(), ['Ep2 Start']);

      // Now stale Episode 1 chapters resolve -> must be ignored!
      ep1ChaptersCompleter.complete(const [
        PlayerChapter(index: 0, title: 'Stale Ep1 Intro', startMs: 0),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.chapters.map((c) => c.title).toList(), ['Ep2 Start']);
    });

    test(
        'dispose during pending readChapters prevents notify and state update; readChapters error stays non-fatal',
        () async {
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
      final completer = Completer<List<PlayerChapter>>();
      final localBridge = MockMpvPropertyBridge()
        ..onReadChapters = () => completer.future;
      final localHarness = FakePlayerHarness();
      final localController = SaphirPlayerController(
        env.dbService,
        syncService,
        () => [mediaDir.path],
        player: localHarness.player,
        videoController: localHarness.videoController,
        mpvBridge: localBridge,
        windowAdapter: localHarness.windowAdapter,
      );

      await localController.startSession(
        PlaybackSession(queue: [epEntry('episode_1', ep1)], initialIndex: 0),
      );
      var notificationsAfterDispose = 0;
      var disposed = false;
      localController.addListener(() {
        if (disposed) notificationsAfterDispose++;
      });

      localHarness.emitDuration(const Duration(minutes: 20));
      await Future<void>.delayed(Duration.zero);

      disposed = true;
      localController.dispose();
      completer
          .complete(const [PlayerChapter(index: 0, title: 'Late', startMs: 0)]);
      await Future<void>.delayed(Duration.zero);
      expect(notificationsAfterDispose, 0);
      await localHarness.close();

      // Fresh controller: readChapters throws -> clean empty chapters, no fatal error
      final bridge2 = MockMpvPropertyBridge()
        ..onReadChapters =
            () => Future<List<PlayerChapter>>.error(Exception('no chapters'));
      final harness2 = FakePlayerHarness();
      final controller2 = SaphirPlayerController(
        env.dbService,
        syncService,
        () => [mediaDir.path],
        player: harness2.player,
        videoController: harness2.videoController,
        mpvBridge: bridge2,
        windowAdapter: harness2.windowAdapter,
      );
      await controller2.startSession(
        PlaybackSession(queue: [epEntry('episode_1', ep1)], initialIndex: 0),
      );
      harness2.emitDuration(const Duration(minutes: 20));
      await Future<void>.delayed(Duration.zero);
      expect(controller2.chapters, isEmpty);
      expect(controller2.errorMessage, isNull);
      controller2.dispose();
      await harness2.close();
    });

    test('stale diagnostics response after closing overlay is discarded',
        () async {
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
      final diagCompleter = Completer<PlayerDiagnostics>();
      bridge.onReadDiagnostics = () => diagCompleter.future;

      await controller.startSession(
        PlaybackSession(queue: [epEntry('episode_1', ep1)], initialIndex: 0),
      );

      controller.toggleDiagnostics();
      expect(controller.showDiagnostics, isTrue);
      controller.toggleDiagnostics();
      expect(controller.showDiagnostics, isFalse);

      diagCompleter.complete(
        const PlayerDiagnostics(
          videoCodec: 'hevc',
          audioCodec: 'eac3',
          resolution: '3840x2160',
          fps: '23.976',
          hwdec: 'd3d11va',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.diagnostics, isNull);
    });
  });

  group('A16 Session state matrix & isolation', () {
    test(
        'movie -> series1 ep1 -> ep2 -> sleep timer -> new session -> stopAndClose isolates state',
        () async {
      final mvFile = createSyntheticMp4HeaderFile(mediaDir, 'movie.mp4');
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 's1e1.mp4');
      final ep2 = createSyntheticMp4HeaderFile(mediaDir, 's1e2.mp4');
      final ep3 = createSyntheticMp4HeaderFile(mediaDir, 's1e3.mp4');
      final s2ep1 = createSyntheticMp4HeaderFile(mediaDir, 's2e1.mp4');

      // Ensure Series 99 row exists in DB
      env.dbService.instance.execute(
        "INSERT INTO series (id, title, folder_path) VALUES (99, 'Andor', 'D:\\NAS\\Andor');",
      );

      // 1. Movie session with non-default nightMode, boost, speed, aspect, delays
      await controller.startSession(
        PlaybackSession(
          queue: [
            PlaybackQueueEntry(
              mediaKey: 'movie_1',
              mediaType: 'movie',
              title: 'Interstellar',
              subtitle: '2014',
              filePath: mvFile.path,
              seriesId: null,
              startPositionMs: 0,
            ),
          ],
          initialIndex: 0,
        ),
      );
      await controller.toggleNightMode();
      await controller.toggleVolumeBoost();
      await controller.adjustVolume(35);
      await controller.setPlaybackSpeed(1.5);
      await controller.setAspectMode(VideoAspectMode.ratio21x9);
      await controller.adjustAudioDelay(200);
      await controller.adjustSubtitleDelay(-100);
      controller.toggleShortcutSheet();
      controller.setSleepTimer(
        SleepTimerOption.minutes30,
        customDuration: const Duration(milliseconds: 50),
      );

      // 2. Immediately start a new Series 1 session without calling stopAndClose first
      await controller.startSession(
        PlaybackSession(
          queue: [
            epEntry('episode_1', ep1),
            epEntry('episode_2', ep2, subtitle: 'S1E2'),
            epEntry('episode_3', ep3, subtitle: 'S1E3'),
          ],
          initialIndex: 0,
        ),
      );

      // Session-scoped values must be clean & previous sleep timer must not pause Ep1
      expect(controller.isNightMode, isFalse);
      expect(controller.isVolumeBoostEnabled, isFalse);
      expect(controller.volume, AppSpacing.volumeMax);
      expect(controller.playbackSpeed, 1.0);
      expect(controller.aspectMode, VideoAspectMode.original);
      expect(controller.audioDelayMs, 0);
      expect(controller.subtitleDelayMs, 0);
      expect(controller.isShortcutSheetOpen, isFalse);
      expect(controller.sleepTimerOption, SleepTimerOption.off);

      // Wait longer than movie's 50ms sleep timer -> Ep1 must stay playing
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(controller.isPlaying, isTrue);

      // Dismiss auto-next & set delays in Ep1, then switch to Ep2 -> entry state resets
      harness.emitDuration(const Duration(seconds: 100));
      harness.emitPosition(const Duration(seconds: 95));
      await Future<void>.delayed(Duration.zero);
      controller.dismissAutoNext();
      expect(controller.showAutoNextCard, isFalse);
      await controller.adjustAudioDelay(100);
      await controller.adjustSubtitleDelay(100);
      bridge.chaptersToReturn = const [
        PlayerChapter(index: 0, title: 'Ep2 Intro', startMs: 0),
      ];

      await controller.playNextEpisode();
      expect(controller.audioDelayMs, 0);
      expect(controller.subtitleDelayMs, 0);
      harness.emitDuration(const Duration(seconds: 100));
      harness.emitPosition(const Duration(seconds: 95));
      await Future<void>.delayed(Duration.zero);
      expect(controller.showAutoNextCard, isTrue);

      // 3. Switch to Series 99 -> pause -> stopAndClose
      await controller.startSession(
        PlaybackSession(
          queue: [epEntry('s2_e1', s2ep1, seriesId: 99, title: 'Andor')],
          initialIndex: 0,
        ),
      );
      await controller.togglePlayPause();
      expect(controller.isPlaying, isFalse);
      await controller.stopAndClose();
      expect(controller.currentEntry, isNull);
      expect(controller.playbackSpeed, 1.0);
      expect(controller.aspectMode, VideoAspectMode.original);
    });

    test('no timer or stream callback notifies after dispose()', () async {
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
      final localHarness = FakePlayerHarness();
      final localBridge = MockMpvPropertyBridge();
      final localController = SaphirPlayerController(
        env.dbService,
        syncService,
        () => [mediaDir.path],
        settingsController: settingsController,
        player: localHarness.player,
        videoController: localHarness.videoController,
        mpvBridge: localBridge,
        windowAdapter: localHarness.windowAdapter,
      );
      await localController.startSession(
        PlaybackSession(queue: [epEntry('episode_1', ep1)], initialIndex: 0),
      );

      localController.setSleepTimer(
        SleepTimerOption.minutes30,
        customDuration: const Duration(milliseconds: 30),
      );
      localController.showActionOsd(PlayerActionOsdKind.volume, '80%');
      localController.toggleDiagnostics();

      var notificationsAfterDispose = 0;
      var disposed = false;
      localController.addListener(() {
        if (disposed) notificationsAfterDispose++;
      });

      disposed = true;
      localController.dispose();

      // Emit late stream events & let timers elapse
      localHarness.emitPlaying(true);
      localHarness.emitPosition(const Duration(seconds: 12));
      localHarness.emitDuration(const Duration(minutes: 10));
      localHarness.emitTracks(const Tracks());
      localHarness.emitTrack(const Track());
      localHarness.emitError('late error');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notificationsAfterDispose, 0);
      await localHarness.close();
    });
  });
}
