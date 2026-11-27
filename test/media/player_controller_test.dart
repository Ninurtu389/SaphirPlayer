import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/features/player/playback_session.dart';
import 'package:saphir_player/features/player/saphir_player_controller.dart';
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
      () => [mediaDir.path],
      player: harness.player,
      videoController: harness.videoController,
      onSetFullScreen: harness.onSetFullScreen,
    );
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await harness.close();
    env.dispose();
  });

  group('SaphirPlayerController playback & controls', () {
    test('ignores empty queue safely without RangeError', () async {
      await controller.startSession(
        const PlaybackSession(queue: [], initialIndex: 0),
      );
      expect(controller.currentEntry, isNull);
      expect(harness.openedMedia, isEmpty);
    });

    test('opens valid file, seeks to startPositionMs, and handles play/pause/seek/volume/speed',
        () async {
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
      final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');
      env.dbService.instance.execute(
        "UPDATE watch_progress SET position_ms = 45000 WHERE media_key = 'episode_1';",
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
              startPositionMs: 45000,
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

      expect(harness.openedMedia.length, 1);
      expect(
        harness.openedMedia.first.start,
        const Duration(milliseconds: 45000),
      );
      expect(harness.seekTargets, isEmpty);
      expect(controller.hasNextEpisode, isTrue);
      expect(controller.hasPreviousEpisode, isFalse);

      harness.emitDuration(const Duration(minutes: 45));
      await Future<void>.delayed(Duration.zero);
      expect(harness.seekTargets.first, const Duration(milliseconds: 45000));

      harness.emitPosition(const Duration(minutes: 10));
      await Future<void>.delayed(Duration.zero);

      await controller.togglePlayPause();
      expect(harness.playOrPauseCount, 1);

      await controller.seekRelativeSeconds(10);
      expect(harness.seekTargets.last, const Duration(minutes: 10, seconds: 10));

      await controller.seekToRatio(0.5);
      expect(harness.seekTargets.last, const Duration(minutes: 22, seconds: 30));

      await controller.adjustVolume(-30);
      expect(controller.volume, 70.0);

      await controller.toggleMute();
      expect(controller.isMuted, isTrue);
      await controller.toggleMute();
      expect(controller.volume, 70.0);

      await controller.setPlaybackSpeed(1.5);
      expect(controller.playbackSpeed, 1.5);
      expect(harness.rates, [1.5]);

      await controller.toggleFullscreen();
      expect(controller.isFullscreen, isTrue);
      expect(harness.fullscreenStates, [true]);

      await controller.playNextEpisode();
      expect(controller.currentEntry?.mediaKey, 'episode_2');
      expect(controller.hasPreviousEpisode, isTrue);

      await controller.playPreviousEpisode();
      expect(controller.currentEntry?.mediaKey, 'episode_1');
    });

    test('auto-next countdown, dismiss, and auto-advance on completion',
        () async {
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
      final ep2 = createSyntheticMp4HeaderFile(mediaDir, 'ep2.mp4');
      env.dbService.instance.execute(
        "UPDATE watch_progress SET position_ms = 0 WHERE media_key = 'episode_1';",
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
      );

      harness.emitDuration(const Duration(seconds: 100));
      harness.emitPosition(
        Duration(seconds: 100 - AppSpacing.autoNextLeadSeconds + 2),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.showAutoNextCard, isTrue);
      expect(controller.autoNextRemainingSeconds, 10);

      // Completed triggers auto-next without overwriting completed = 1
      harness.emitCompleted(true);
      for (var i = 0;
          i < 10 && controller.currentEntry?.mediaKey != 'episode_2';
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(controller.currentEntry?.mediaKey, 'episode_2');
      final ep1Prog = env.dbService.instance
          .select("SELECT completed FROM watch_progress WHERE media_key = 'episode_1';")
          .first;
      expect(ep1Prog['completed'], 1);

      // Dismiss prevents auto-next on completion
      await controller.playPreviousEpisode();
      controller.dismissAutoNext();
      expect(controller.showAutoNextCard, isFalse);
      harness.emitCompleted(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.currentEntry?.mediaKey, 'episode_1');
    });

    test('persists progress >= 92% as completed and updates movie last_watched_at',
        () async {
      final movieFile = createSyntheticMp4HeaderFile(mediaDir, 'movie.mp4');

      await controller.startSession(
        PlaybackSession(
          queue: [
            PlaybackQueueEntry(
              mediaKey: 'movie_1',
              mediaType: 'movie',
              title: 'Interstellar',
              subtitle: '2014',
              filePath: movieFile.path,
              seriesId: null,
              startPositionMs: 0,
            ),
          ],
          initialIndex: 0,
        ),
      );

      harness.emitDuration(const Duration(seconds: 1000));
      harness.emitPosition(const Duration(seconds: 930)); // 93% >= 92%
      await Future<void>.delayed(Duration.zero);

      await controller.stopAndClose();

      final row = env.dbService.instance
          .select(
              "SELECT completed, position_ms FROM watch_progress WHERE media_key = 'movie_1';")
          .first;
      expect(row['completed'], 1);
      expect(row['position_ms'], 0);

      final movieRow = env.dbService.instance
          .select('SELECT last_watched_at FROM movies WHERE id = 1;')
          .first;
      expect(movieRow['last_watched_at'], isNotNull);
    });

    test('remembers and restores audio/subtitle tracks per series', () async {
      final ep1 = createSyntheticMp4HeaderFile(mediaDir, 'ep1.mp4');
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
              startPositionMs: 0,
            ),
          ],
          initialIndex: 0,
        ),
      );

      final audioDe = AudioTrack('deu', 'Deutsch', 'de');
      final subOff = SubtitleTrack.no();

      await controller.selectAudioTrack(audioDe);
      await controller.selectSubtitleTrack(subOff);

      // Verify saved in DB
      final prefRow = env.dbService.instance
          .select(
              'SELECT audio_track, subtitle_track FROM series_preferences WHERE series_id = 1;')
          .first;
      expect(prefRow['audio_track'], 'deu');
      expect(prefRow['subtitle_track'], 'no');

      // Emitting tracks on next episode (when active track is auto) restores saved preference
      harness.emitTrack(
        Track(audio: AudioTrack.auto(), subtitle: SubtitleTrack.auto()),
      );
      await Future<void>.delayed(Duration.zero);
      harness.emitTracks(
        Tracks(
          audio: [AudioTrack.auto(), audioDe],
          subtitle: [SubtitleTrack.auto(), SubtitleTrack('eng', 'English', 'en')],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(harness.selectedAudioTracks.any((t) => t.id == 'deu'), isTrue);
      expect(harness.selectedSubtitleTracks.any((t) => t.id == 'no'), isTrue);
    });
  });

  group('SaphirPlayerController codec & error fallbacks', () {
    test('reports missing file error without calling player.open', () async {
      await controller.startSession(
        PlaybackSession(
          queue: [
            PlaybackQueueEntry(
              mediaKey: 'episode_99',
              mediaType: 'episode',
              title: 'Missing',
              subtitle: '',
              filePath: p.join(mediaDir.path, 'non_existent.mkv'),
              seriesId: 1,
              startPositionMs: 0,
            ),
          ],
          initialIndex: 0,
        ),
      );

      expect(controller.errorMessage, AppStrings.playerFileMissingError);
      expect(harness.openedMedia, isEmpty);
    });

    test('reports empty file error for 0-byte video files', () async {
      final empty = createEmptyVideoFile(mediaDir, 'zero.mp4');
      await controller.startSession(
        PlaybackSession(
          queue: [
            PlaybackQueueEntry(
              mediaKey: 'movie_empty',
              mediaType: 'movie',
              title: 'Zero',
              subtitle: '',
              filePath: empty.path,
              seriesId: null,
              startPositionMs: 0,
            ),
          ],
          initialIndex: 0,
        ),
      );

      expect(controller.errorMessage, AppStrings.playerEmptyFileError);
      expect(harness.openedMedia, isEmpty);
    });

    for (final codecCase in [
      ('HEVC/H.265', 'Failed to open hevc decoder'),
      ('AV1', 'Unsupported codec av01'),
      ('VP9', 'vp9 hardware decode error'),
      ('NoAudioTrack', 'Audio stream initialization failed'),
      ('CorruptContainer', 'Invalid data found when processing input'),
    ]) {
      test('shows clean fallback error on ${codecCase.$1} stream error',
          () async {
        final hevcStub =
            createSyntheticHevcStubFile(mediaDir, '${codecCase.$1}.mp4');
        await controller.startSession(
          PlaybackSession(
            queue: [
              PlaybackQueueEntry(
                mediaKey: 'movie_codec',
                mediaType: 'movie',
                title: codecCase.$1,
                subtitle: '',
                filePath: hevcStub.path,
                seriesId: null,
                startPositionMs: 0,
              ),
            ],
            initialIndex: 0,
          ),
        );

        harness.emitError(codecCase.$2);
        await Future<void>.delayed(Duration.zero);

        expect(controller.errorMessage, AppStrings.playerPlaybackError);
      });
    }

    test('catches exception thrown by player.open() on corrupt container',
        () async {
      final corrupt = createCorruptVideoFile(mediaDir, 'corrupt.mkv');
      harness.throwOnOpen = true;
      harness.openError = StateError('demuxer failed');

      await controller.startSession(
        PlaybackSession(
          queue: [
            PlaybackQueueEntry(
              mediaKey: 'movie_corrupt',
              mediaType: 'movie',
              title: 'Corrupt',
              subtitle: '',
              filePath: corrupt.path,
              seriesId: null,
              startPositionMs: 0,
            ),
          ],
          initialIndex: 0,
        ),
      );

      expect(controller.errorMessage, AppStrings.playerPlaybackError);
    });

    test('dispose cancels subscriptions/timers and ignores late stream events',
        () async {
      final localHarness = FakePlayerHarness();
      final localController = SaphirPlayerController(
        env.dbService,
        syncService,
        () => [mediaDir.path],
        player: localHarness.player,
        videoController: localHarness.videoController,
        onSetFullScreen: localHarness.onSetFullScreen,
      );

      localController.dispose();
      expect(localHarness.disposed, isTrue);

      // Late stream emissions must not throw after dispose
      localHarness.emitPlaying(true);
      localHarness.emitPosition(const Duration(seconds: 5));
      localHarness.emitError('late error');
      await Future<void>.delayed(Duration.zero);
      await localHarness.close();
    });
  });
}
