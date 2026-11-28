import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/thumbnail_cache_service.dart';
import 'package:saphir_player/features/scanner/media_parser.dart';
import 'package:saphir_player/features/scanner/nas_scan_repository.dart';
import 'package:saphir_player/features/scanner/nas_scanner_service.dart';
import 'package:saphir_player/features/scanner/thumbnail_generator_service.dart';
import 'package:saphir_player/features/scanner/thumbnail_queue_service.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('A07 Thumbnail Cache-Key, Validation & Repository Invalidation', () {
    test(
        'normalizes Windows/UNC paths and changes key when fingerprint changes',
        () {
      final keyA = ThumbnailCacheKey.buildCacheFileName(
        prefix: 'ep',
        filePath: r'D:/Serien/Dark/Season 01/../Season 01/ep1.mkv',
        fileSize: 1024,
        modifiedAt: 5000,
      );
      final keyB = ThumbnailCacheKey.buildCacheFileName(
        prefix: 'ep',
        filePath: r'd:\serien\dark\season 01\ep1.mkv',
        fileSize: 1024,
        modifiedAt: 5000,
      );
      expect(keyA, keyB);

      final uncA = ThumbnailCacheKey.buildCacheFileName(
        prefix: 'mv',
        filePath: '//NAS/Media/Movies/Dune.mkv',
        fileSize: 2048,
        modifiedAt: 7000,
      );
      final uncB = ThumbnailCacheKey.buildCacheFileName(
        prefix: 'mv',
        filePath: r'\\nas\media\movies\dune.mkv',
        fileSize: 2048,
        modifiedAt: 7000,
      );
      expect(uncA, uncB);

      final changedSize = ThumbnailCacheKey.buildCacheFileName(
        prefix: 'ep',
        filePath: r'd:\serien\dark\season 01\ep1.mkv',
        fileSize: 2048,
        modifiedAt: 5000,
      );
      final changedMtime = ThumbnailCacheKey.buildCacheFileName(
        prefix: 'ep',
        filePath: r'd:\serien\dark\season 01\ep1.mkv',
        fileSize: 1024,
        modifiedAt: 9000,
      );
      expect(changedSize, isNot(keyA));
      expect(changedMtime, isNot(keyA));
    });

    test('validates JPEG/PNG/WebP headers and rejects corrupt/short files',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);
      final dir = env.createSubdir('magic_bytes');

      final validJpeg = createValidTinyJpeg(dir, 'ok.jpg');
      final validPng = File(p.join(dir.path, 'ok.png'))
        ..writeAsBytesSync(<int>[
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
          0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
        ]);
      final validWebp = File(p.join(dir.path, 'ok.webp'))
        ..writeAsBytesSync(<int>[
          0x52, 0x49, 0x46, 0x46, 20, 0, 0, 0, //
          0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x20,
        ]);
      final textDump = createCorruptVideoFile(dir, 'bad.jpg');
      final emptyFile = createEmptyVideoFile(dir, 'empty.jpg');

      expect(await ThumbnailCacheKey.isValidImageFile(validJpeg), isTrue);
      expect(await ThumbnailCacheKey.isValidImageFile(validPng), isTrue);
      expect(await ThumbnailCacheKey.isValidImageFile(validWebp), isTrue);
      expect(await ThumbnailCacheKey.isValidImageFile(textDump), isFalse);
      expect(await ThumbnailCacheKey.isValidImageFile(emptyFile), isFalse);
    });

    test(
        'NasScanRepository preserves unchanged thumbs and invalidates only modified files',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      final repo = NasScanRepository(env.dbService);

      const epPath1 = r'D:\NAS\Dark\S01\S01E01.mkv';
      const epPath2 = r'D:\NAS\Dark\S01\S01E02.mkv';
      const mvPath = r'D:\NAS\Movies\Dune.mkv';

      repo.applyDiffWithSummary(
        ScanOutput(
          nasReachable: true,
          reachableRoots: const [r'D:\NAS'],
          completeRoots: const [r'D:\NAS'],
          seriesList: const [
            ScannedSeriesData(
              title: 'Dark',
              folderPath: r'D:\NAS\Dark',
              posterPath: null,
              summary: null,
              episodes: [
                ParsedEpisode(
                  seriesTitle: 'Dark',
                  seasonNumber: 1,
                  episodeNumber: 1,
                  episodeTitle: 'Geheimnisse',
                  filePath: epPath1,
                  fileSize: 1000,
                  modifiedAt: 5000,
                ),
                ParsedEpisode(
                  seriesTitle: 'Dark',
                  seasonNumber: 1,
                  episodeNumber: 2,
                  episodeTitle: 'Luegen',
                  filePath: epPath2,
                  fileSize: 2000,
                  modifiedAt: 6000,
                ),
              ],
            ),
          ],
          movies: const [
            ScannedMovieData(
              title: 'Dune',
              releaseYear: null,
              filePath: mvPath,
              posterPath: null,
              syncKey: 'mv_v2_dune',
              fileSize: 3000,
              modifiedAt: 7000,
            ),
          ],
        ),
      );

      final db = env.dbService.instance;
      db.execute(
        "UPDATE episodes SET thumb_path = 'ep1.jpg', thumb_status = 'ready' WHERE file_path = ?;",
        [epPath1],
      );
      db.execute(
        "UPDATE episodes SET thumb_path = 'ep2.jpg', thumb_status = 'ready' WHERE file_path = ?;",
        [epPath2],
      );
      db.execute(
        "UPDATE movies SET thumb_path = 'mv1.jpg', thumb_status = 'ready' WHERE file_path = ?;",
        [mvPath],
      );

      // Rescan: ep1 unchanged, ep2 modified size, dune modified mtime
      final rescanSummary = repo.applyDiffWithSummary(
        ScanOutput(
          nasReachable: true,
          reachableRoots: const [r'D:\NAS'],
          completeRoots: const [r'D:\NAS'],
          seriesList: const [
            ScannedSeriesData(
              title: 'Dark',
              folderPath: r'D:\NAS\Dark',
              posterPath: null,
              summary: null,
              episodes: [
                ParsedEpisode(
                  seriesTitle: 'Dark',
                  seasonNumber: 1,
                  episodeNumber: 1,
                  episodeTitle: 'Geheimnisse',
                  filePath: epPath1,
                  fileSize: 1000,
                  modifiedAt: 5000,
                ),
                ParsedEpisode(
                  seriesTitle: 'Dark',
                  seasonNumber: 1,
                  episodeNumber: 2,
                  episodeTitle: 'Luegen',
                  filePath: epPath2,
                  fileSize: 2500,
                  modifiedAt: 6000,
                ),
              ],
            ),
          ],
          movies: const [
            ScannedMovieData(
              title: 'Dune',
              releaseYear: null,
              filePath: mvPath,
              posterPath: null,
              syncKey: 'mv_v2_dune',
              fileSize: 3000,
              modifiedAt: 8000,
            ),
          ],
        ),
      );

      expect(
        rescanSummary.orphanedThumbnails,
        containsAll(['ep2.jpg', 'mv1.jpg']),
      );
      expect(rescanSummary.orphanedThumbnails, isNot(contains('ep1.jpg')));

      final ep1Row = db.select(
        'SELECT thumb_path, thumb_status FROM episodes WHERE file_path = ?;',
        [epPath1],
      ).first;
      final ep2Row = db.select(
        'SELECT thumb_path, thumb_status, thumb_attempts FROM episodes WHERE file_path = ?;',
        [epPath2],
      ).first;
      final mvRow = db.select(
        'SELECT thumb_path, thumb_status FROM movies WHERE file_path = ?;',
        [mvPath],
      ).first;

      expect(ep1Row['thumb_path'], 'ep1.jpg');
      expect(ep1Row['thumb_status'], 'ready');
      expect(ep2Row['thumb_path'], isNull);
      expect(ep2Row['thumb_status'], 'pending');
      expect(ep2Row['thumb_attempts'], 0);
      expect(mvRow['thumb_path'], isNull);
      expect(mvRow['thumb_status'], 'pending');
    });
  });

  group('A08 & A21 ThumbnailQueueService Retry, Recovery & Batching', () {
    void seedEpisodes(
      TestEnv env,
      int count, {
      String root = r'D:\NAS\Show',
    }) {
      final db = env.dbService.instance;
      db.execute(
        'INSERT INTO series (id, title, folder_path) VALUES (1, ?, ?);',
        ['Show', root],
      );
      db.execute(
        'INSERT INTO seasons (id, series_id, season_number, folder_path) VALUES (1, 1, 1, ?);',
        [p.join(root, 'S01')],
      );
      for (var i = 1; i <= count; i++) {
        db.execute(
          '''
          INSERT INTO episodes (
            series_id, season_id, episode_number, title, file_path,
            duration_ms, file_size, modified_at, thumb_status
          ) VALUES (1, 1, ?, ?, ?, 120000, 1024, 5000, 'pending');
          ''',
          [
            i,
            'Ep $i',
            p.join(root, 'S01', 'S01E${i.toString().padLeft(2, '0')}.mkv')
          ],
        );
      }
    }

    test('recovers stale processing rows on startup without losing attempts',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      seedSampleLibrary(env.dbService);

      final db = env.dbService.instance;
      db.execute(
        "UPDATE episodes SET thumb_status = 'processing', thumb_attempts = 2 WHERE id = 1;",
      );
      db.execute(
        "UPDATE movies SET thumb_status = 'processing', thumb_attempts = 1 WHERE id = 1;",
      );

      final queue = ThumbnailQueueService(env.dbService);
      addTearDown(queue.dispose);

      final recovered = queue.recoverStaleProcessingJobs();
      expect(recovered, 2);

      final ep = db
          .select(
              'SELECT thumb_status, thumb_attempts FROM episodes WHERE id = 1;')
          .first;
      final mv = db
          .select(
              'SELECT thumb_status, thumb_attempts FROM movies WHERE id = 1;')
          .first;
      expect(ep['thumb_status'], ThumbnailJobStatus.pending);
      expect(ep['thumb_attempts'], 2);
      expect(mv['thumb_status'], ThumbnailJobStatus.pending);
      expect(mv['thumb_attempts'], 1);
    });

    test(
        'retries transient failures with backoff, caps permanent failures, and never blocks healthy items',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      seedEpisodes(env, 3);

      var now = DateTime(2026, 6, 1, 12, 0, 0);
      var ep1Calls = 0;

      final queue = ThumbnailQueueService(
        env.dbService,
        nowProvider: () => now,
        maxRetryAttempts: 3,
        retryBaseSeconds: 30,
        generator: ({
          required videoFilePath,
          required durationMs,
          required prefix,
          required fileSize,
          required modifiedAt,
          required isAborted,
          mediaKitSession,
          allowMediaKitFallback = true,
        }) async {
          if (videoFilePath.endsWith('01.mkv')) {
            ep1Calls++;
            if (ep1Calls == 1) {
              return const ThumbnailGenerationOutcome(
                failureKind: ThumbnailFailureKind.transient,
                errorMessage: 'temporary timeout\non share',
              );
            }
            return const ThumbnailGenerationOutcome(fileName: 'ep_01.jpg');
          }
          if (videoFilePath.endsWith('02.mkv')) {
            return const ThumbnailGenerationOutcome(
              failureKind: ThumbnailFailureKind.transient,
              errorMessage: 'broken codec',
            );
          }
          return const ThumbnailGenerationOutcome(fileName: 'ep_03.jpg');
        },
      );
      addTearDown(queue.dispose);

      // Batch 1: Ep1 transient retry_wait, Ep2 transient retry_wait (1), Ep3 ready
      await queue.processNextBatch(autoContinueBatches: false);

      final db = env.dbService.instance;
      final r1 = db
          .select(
              'SELECT thumb_status, thumb_attempts, thumb_last_error, thumb_retry_at FROM episodes WHERE id = 1;')
          .first;
      expect(r1['thumb_status'], ThumbnailJobStatus.retryWait);
      expect(r1['thumb_attempts'], 1);
      expect(r1['thumb_last_error'], 'temporary timeout on share');
      expect(r1['thumb_retry_at'], now.millisecondsSinceEpoch + 30 * 1000);

      final r3 = db
          .select('SELECT thumb_status, thumb_path FROM episodes WHERE id = 3;')
          .first;
      expect(r3['thumb_status'], ThumbnailJobStatus.ready);
      expect(r3['thumb_path'], 'ep_03.jpg');

      // Before backoff expires -> 0 due items
      now = now.add(const Duration(seconds: 10));
      expect(await queue.processNextBatch(autoContinueBatches: false), 0);

      // At +30s -> Ep1 heals, Ep2 hits attempt 2 (60s backoff)
      now = now.add(const Duration(seconds: 25));
      await queue.processNextBatch(autoContinueBatches: false);
      expect(
        db
            .select('SELECT thumb_status FROM episodes WHERE id = 1;')
            .first['thumb_status'],
        ThumbnailJobStatus.ready,
      );
      expect(
        db
            .select(
                'SELECT thumb_status, thumb_attempts FROM episodes WHERE id = 2;')
            .first['thumb_attempts'],
        2,
      );

      // Advance past 60s -> Ep2 hits attempt 3 -> failed_permanent
      now = now.add(const Duration(seconds: 65));
      await queue.processNextBatch(autoContinueBatches: false);
      final r2Final = db
          .select(
              'SELECT thumb_status, thumb_attempts, thumb_retry_at FROM episodes WHERE id = 2;')
          .first;
      expect(r2Final['thumb_status'], ThumbnailJobStatus.failedPermanent);
      expect(r2Final['thumb_attempts'], 3);
      expect(r2Final['thumb_retry_at'], 0);

      // Selective reset only on episode 2 restores pending
      final resetSingle =
          await queue.retryMediaThumbnail(isEpisode: true, mediaId: 2);
      expect(resetSingle, 1);
      final r2Reset = db
          .select(
              'SELECT thumb_status, thumb_attempts FROM episodes WHERE id = 2;')
          .first;
      expect(r2Reset['thumb_status'], ThumbnailJobStatus.pending);
      expect(r2Reset['thumb_attempts'], 0);
    });

    test(
        'processes >40 backlog automatically in sequential batches (concurrency 1) and pauses cleanly on playback',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      seedEpisodes(env, 45);

      var concurrentNow = 0;
      var maxConcurrent = 0;
      var generatedCount = 0;

      final queue = ThumbnailQueueService(
        env.dbService,
        batchLimit: 40,
        batchContinuationDelay: const Duration(milliseconds: 10),
        generator: ({
          required videoFilePath,
          required durationMs,
          required prefix,
          required fileSize,
          required modifiedAt,
          required isAborted,
          mediaKitSession,
          allowMediaKitFallback = true,
        }) async {
          concurrentNow++;
          if (concurrentNow > maxConcurrent) {
            maxConcurrent = concurrentNow;
          }
          await Future<void>.delayed(Duration.zero);
          concurrentNow--;
          if (isAborted()) {
            return const ThumbnailGenerationOutcome(
              failureKind: ThumbnailFailureKind.cancelled,
            );
          }
          generatedCount++;
          return ThumbnailGenerationOutcome(
            fileName: 'ep_${p.basenameWithoutExtension(videoFilePath)}.jpg',
          );
        },
      );
      addTearDown(queue.dispose);

      await queue.processNextBatch(autoContinueBatches: true);
      // Batch 1 processed 40; allow continuation timer to finish remaining 5
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(maxConcurrent, 1);
      expect(generatedCount, 45);
      final stats = queue.readStats();
      expect(stats.readyCount, 45);
      expect(stats.actionablePendingCount, 0);
    });

    test(
        'playback pause prevents next batch and does not mark interrupted item failed; resume completes queue',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      seedEpisodes(env, 4);

      late ThumbnailQueueService queue;
      var callCount = 0;
      queue = ThumbnailQueueService(
        env.dbService,
        batchLimit: 2,
        batchContinuationDelay: const Duration(milliseconds: 15),
        generator: ({
          required videoFilePath,
          required durationMs,
          required prefix,
          required fileSize,
          required modifiedAt,
          required isAborted,
          mediaKitSession,
          allowMediaKitFallback = true,
        }) async {
          callCount++;
          if (callCount == 2) {
            // Simulate playback starting mid-item
            queue.setPlaybackActive(true);
            return const ThumbnailGenerationOutcome(
              failureKind: ThumbnailFailureKind.cancelled,
            );
          }
          return ThumbnailGenerationOutcome(
            fileName: 'ok_${p.basenameWithoutExtension(videoFilePath)}.jpg',
          );
        },
      );
      addTearDown(queue.dispose);

      await queue.processNextBatch(autoContinueBatches: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Episode 1 ready; Episode 2 cancelled -> restored to pending with 0 attempts
      final db = env.dbService.instance;
      final ep2 = db
          .select(
              'SELECT thumb_status, thumb_attempts FROM episodes WHERE id = 2;')
          .first;
      expect(ep2['thumb_status'], ThumbnailJobStatus.pending);
      expect(ep2['thumb_attempts'], 0);
      expect(queue.readStats().readyCount, 1);

      // Resume playback -> remaining 3 finish automatically
      queue.setPlaybackActive(false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(queue.readStats().readyCount, 4);
      expect(queue.readStats().failedPermanentCount, 0);
    });

    test(
        'selective source retry & LibraryController retryFailedThumbnails update stats reactively',
        () async {
      final env = await TestEnv.create(inMemory: true);
      addTearDown(env.dispose);
      seedSampleLibrary(env.dbService);

      final db = env.dbService.instance;
      db.execute(
        "UPDATE episodes SET thumb_status = 'failed_permanent', thumb_attempts = 3, thumb_last_error = 'timeout' WHERE id = 1;",
      );
      db.execute(
        "UPDATE movies SET thumb_status = 'retry_wait', thumb_attempts = 1, thumb_retry_at = 9999999999999 WHERE id = 1;",
      );

      final gate = ThumbnailOperationGate();
      final settings = SettingsController(env.dbService, thumbnailGate: gate);
      addTearDown(settings.dispose);
      final queue = ThumbnailQueueService(env.dbService, gate: gate);
      final scanner = NasScannerService(
        env.dbService,
        thumbnailGate: gate,
        thumbnailQueue: queue,
      );
      final library = LibraryController(
        env.dbService,
        settings,
        scannerService: scanner,
      );
      addTearDown(library.dispose);

      library.loadCountsFromCache();
      expect(library.hasRetryableThumbnails, isTrue);
      expect(library.thumbnailQueueStats.failedPermanentCount, 1);
      expect(library.thumbnailQueueStats.retryWaitCount, 1);

      // Wait: retrySourceThumbnails resets only Dark source episodes, not Movies
      final resetSource =
          await queue.retrySourceThumbnails(r'D:\NAS\Serien\Dark');
      expect(resetSource, 1);
      expect(library.thumbnailQueueStats.failedPermanentCount, 0);
      expect(library.thumbnailQueueStats.retryWaitCount, 1);

      // Retry all without immediate background run
      final resetAll = await library.retryFailedThumbnails(resumeQueue: false);
      expect(resetAll, 1);
      expect(library.hasRetryableThumbnails, isFalse);
      expect(library.thumbnailQueueStats.retryWaitCount, 0);
    });
  });
}
