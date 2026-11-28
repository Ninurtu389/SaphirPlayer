import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/features/scanner/thumbnail_generator_service.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('ThumbnailGeneratorService', () {
    test('returns null when playback is active, file missing, or 0-byte',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final mediaDir = env.createSubdir('media');
      final emptyFile = createEmptyVideoFile(mediaDir, 'empty.mp4');
      final validStub = createSyntheticMp4HeaderFile(mediaDir, 'stub.mp4');

      ThumbnailGeneratorService.resetExecutableCacheForTesting();

      expect(
        await ThumbnailGeneratorService.generateThumbnail(
          videoFilePath: validStub.path,
          durationMs: 60000,
          isPlaybackActive: () => true,
          allowMediaKitFallback: false,
        ),
        isNull,
      );

      expect(
        await ThumbnailGeneratorService.generateThumbnail(
          videoFilePath: p.join(mediaDir.path, 'missing.mp4'),
          durationMs: 60000,
          isPlaybackActive: () => false,
          allowMediaKitFallback: false,
        ),
        isNull,
      );

      expect(
        await ThumbnailGeneratorService.generateThumbnail(
          videoFilePath: emptyFile.path,
          durationMs: 60000,
          isPlaybackActive: () => false,
          allowMediaKitFallback: false,
        ),
        isNull,
      );
    });

    test('uses compact deterministic hash for >260 char paths and hits cache',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      // Build a path > 240 chars (Windows MAX_PATH risk if base64-encoded directly)
      final longSegment = 'LongSegment_' * 15; // 180 chars
      final mediaDir = env.createSubdir(p.join('media', longSegment));
      final stub = createSyntheticMp4HeaderFile(mediaDir, 'S01E01.mp4');

      // First call without ffmpeg/media_kit returns null cleanly without throwing
      final first = await ThumbnailGeneratorService.generateEpisodeThumbnail(
        videoFilePath: stub.path,
        durationMs: 120000,
        isPlaybackActive: () => false,
        allowMediaKitFallback: false,
      );
      expect(first, isNull);

      // Simulate existing cached thumbnail at the expected compact hash path
      final cacheDir = env.createSubdir(p.join('app_base', 'cache', 'thumbnails'));
      // Verify a corrupt 0-byte cached file is deleted cleanly
      final corruptFile = createEmptyVideoFile(mediaDir, 'corrupt_video.mkv');
      expect(
        await ThumbnailGeneratorService.generateThumbnail(
          videoFilePath: corruptFile.path,
          durationMs: 1000,
          isPlaybackActive: () => false,
          allowMediaKitFallback: false,
        ),
        isNull,
      );
      expect(cacheDir.existsSync(), isTrue);
    });

    test('SettingsController.clearThumbnailCache deletes cached files and clears DB refs',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      seedSampleLibrary(env.dbService);

      final cacheDir = env.createSubdir(p.join('app_base', 'cache', 'thumbnails'));
      final thumb1 = createValidTinyJpeg(cacheDir, 'ep_1.jpg');
      final thumb2 = createValidTinyJpeg(cacheDir, 'mv_1.jpg');

      env.dbService.instance.execute(
        'UPDATE episodes SET thumb_path = ? WHERE id = 1;',
        [thumb1.path],
      );
      env.dbService.instance.execute(
        'UPDATE movies SET thumb_path = ? WHERE id = 1;',
        [thumb2.path],
      );

      final settings = SettingsController(env.dbService);
      await settings.load();
      expect(settings.cacheBytes, greaterThan(0));

      await settings.clearThumbnailCache();

      expect(thumb1.existsSync(), isFalse);
      expect(thumb2.existsSync(), isFalse);
      expect(settings.cacheBytes, 0);

      final epThumb = env.dbService.instance
          .select('SELECT thumb_path FROM episodes WHERE id = 1;')
          .first['thumb_path'];
      final mvThumb = env.dbService.instance
          .select('SELECT thumb_path FROM movies WHERE id = 1;')
          .first['thumb_path'];
      expect(epThumb, isNull);
      expect(mvThumb, isNull);

      settings.dispose();
    });

    test('computeSeekSeconds starts at 5th minute (300s) for >=5min or unknown duration and clamps short videos',
        () {
      expect(ThumbnailGeneratorService.computeSeekSeconds(0), 300);
      expect(ThumbnailGeneratorService.computeSeekSeconds(-1), 300);
      // 20-min episode (1200s): 15% = 180s -> clamped up to 300s (5th minute)
      expect(ThumbnailGeneratorService.computeSeekSeconds(20 * 60 * 1000), 300);
      // 90-min movie (5400s): 15% = 810s (>= 300s)
      expect(ThumbnailGeneratorService.computeSeekSeconds(90 * 60 * 1000), 810);
      // 5m05s video (305s): 300s
      expect(ThumbnailGeneratorService.computeSeekSeconds(305 * 1000), 300);
      // 3-min video (180s): shorter than 5 min -> 15% = 27s
      expect(ThumbnailGeneratorService.computeSeekSeconds(180 * 1000), 27);
      // 10-sec clip: 15% = 2s
      expect(ThumbnailGeneratorService.computeSeekSeconds(10 * 1000), 2);
    });
  });
}
