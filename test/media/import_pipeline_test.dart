import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/features/scanner/nas_scanner_service.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('NasScannerService import pipeline & edge cases', () {
    test('imports single movie, nested series, and ignores non-video files',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('nas_root');
      final seriesDir =
          Directory(p.join(root.path, 'Serien', 'Severance', 'Season 1'))
            ..createSync(recursive: true);
      createSyntheticMp4HeaderFile(
        seriesDir,
        'Severance - S01E01 - Good News About Hell.mp4',
      );
      File(p.join(seriesDir.path, 'notes.txt')).writeAsStringSync('ignore me');
      File(p.join(seriesDir.path, 'subtitles.srt')).writeAsStringSync('1');

      final moviesDir = Directory(p.join(root.path, 'Filme'))
        ..createSync(recursive: true);
      createSyntheticMp4HeaderFile(moviesDir, 'Dune (2021).mkv');

      final scanner = NasScannerService(env.dbService);
      final result = await scanner.scanLibrary([root.path]);

      expect(result.nasReachable, isTrue);
      expect(result.seriesCount, 1);
      expect(result.movieCount, 1);
      expect(result.sourceReports.single.status, SourceScanStatus.complete);
    });

    test(
        'handles 0-byte files, corrupt containers, and missing roots without crashing',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('edge_root');
      createEmptyVideoFile(root, 'EmptyMovie (2020).mp4');
      createCorruptVideoFile(root, 'CorruptMovie (2021).mkv');

      final scanner = NasScannerService(env.dbService);
      final missingResult = await scanner.scanLibrary([
        p.join(env.tempRoot.path, 'does_not_exist'),
      ]);
      expect(missingResult.nasReachable, isFalse);
      expect(
        missingResult.sourceReports.single.status,
        SourceScanStatus.unreachable,
      );

      final emptyRootResult = await scanner.scanLibrary(['   ', '']);
      expect(emptyRootResult.nasReachable, isFalse);

      final result = await scanner.scanLibrary([root.path]);
      expect(result.nasReachable, isTrue);
      expect(result.movieCount, 2);
    });

    test(
        'removes deleted source files and cleans up orphaned series, seasons, and thumbnails',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('cleanup_root');
      final showDir = Directory(p.join(root.path, 'Dark', 'Season 1'))
        ..createSync(recursive: true);
      final epFile = createSyntheticMp4HeaderFile(showDir, 'Dark - S01E01.mkv');
      final movieFile =
          createSyntheticMp4HeaderFile(root, 'Arrival (2016).mkv');

      final scanner = NasScannerService(env.dbService);
      await scanner.scanLibrary([root.path]);

      // Attach synthetic thumbnails in cache
      final cacheDir =
          env.createSubdir(p.join('app_base', 'cache', 'thumbnails'));
      final epThumb = createValidTinyJpeg(cacheDir, 'ep_orphan.jpg');
      final mvThumb = createValidTinyJpeg(cacheDir, 'mv_orphan.jpg');
      env.dbService.instance.execute(
        'UPDATE episodes SET thumb_path = ?;',
        [epThumb.path],
      );
      env.dbService.instance.execute(
        'UPDATE movies SET thumb_path = ?;',
        [mvThumb.path],
      );

      // Delete both source files from NAS
      epFile.deleteSync();
      movieFile.deleteSync();

      final rescan = await scanner.scanLibrary([root.path]);
      expect(rescan.seriesCount, 0);
      expect(rescan.movieCount, 0);

      // Orphaned seasons & series rows should be cleaned up
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM seasons;')
            .first['c'],
        0,
      );
      expect(
        env.dbService.instance
            .select('SELECT COUNT(*) AS c FROM series;')
            .first['c'],
        0,
      );

      // Orphaned thumbnail files should be deleted from disk
      expect(epThumb.existsSync(), isFalse);
      expect(mvThumb.existsSync(), isFalse);
    });

    test('handles extremely long nested directory paths gracefully', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('long_root');
      final deepDir = Directory(
        p.join(
          root.path,
          'VeryLongSeriesName_${'X' * 60}',
          'Season 01',
        ),
      )..createSync(recursive: true);
      createSyntheticMp4HeaderFile(deepDir, 'S01E01 - LongEpisode.mp4');

      final scanner = NasScannerService(env.dbService);
      final result = await scanner.scanLibrary([root.path]);
      expect(result.nasReachable, isTrue);
      expect(result.seriesCount, 1);
    });

    test(
        'groups flat episodes in root by series title and marks failed thumbnails',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('flat_root');
      createCorruptVideoFile(root, 'Dark - S01E01 - Geheimnisse.mkv');
      createCorruptVideoFile(root, 'Andor - S01E01 - Kassa.mkv');

      final scanner = NasScannerService(env.dbService);
      final result = await scanner.scanLibrary([root.path]);

      expect(result.nasReachable, isTrue);
      expect(result.seriesCount, 2);

      final failedEps = env.dbService.instance.select(
          "SELECT thumb_status, thumb_attempts FROM episodes WHERE thumb_status = 'retry_wait';");
      expect(failedEps.length, 2);
      expect(failedEps.every((row) => row['thumb_attempts'] == 1), isTrue);
    });
  });
}
