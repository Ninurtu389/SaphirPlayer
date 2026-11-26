import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/features/library/metadata_reader.dart';
import 'package:saphir_player/features/scanner/media_parser.dart';

void main() {
  group('MediaParser extensions', () {
    test('supports all configured video and image formats and rejects others',
        () {
      for (final ext in [
        '.mkv',
        '.mp4',
        '.avi',
        '.mov',
        '.wmv',
        '.m4v',
        '.webm',
        '.ts',
      ]) {
        expect(MediaParser.isVideoFile('video$ext'), isTrue);
        expect(MediaParser.isVideoFile('video${ext.toUpperCase()}'), isTrue);
      }
      expect(MediaParser.isVideoFile('readme.txt'), isFalse);
      expect(MediaParser.isVideoFile('archive.zip'), isFalse);
      expect(MediaParser.isVideoFile('no_extension'), isFalse);

      for (final ext in ['.jpg', '.jpeg', '.png', '.webp']) {
        expect(MediaParser.isImageFile('poster$ext'), isTrue);
      }
      expect(MediaParser.isImageFile('poster.bmp'), isFalse);
    });
  });

  group('MediaParser episodes & edge cases', () {
    test('parses specials S00E01 and German Staffel/Folge with Unicode', () {
      const root = r'D:\NAS\Serien';

      final special = MediaParser.parseEpisode(
        p.join(root, 'Dr.Who', 'Specials', 'Dr.Who.S00E01.Weihnachten.mkv'),
        root,
      );
      expect(special, isNotNull);
      expect(special!.seasonNumber, 0);
      expect(special.episodeNumber, 1);
      expect(special.seriesTitle, 'Dr Who');

      final german = MediaParser.parseEpisode(
        p.join(
          root,
          'Babylon Berlin',
          'Staffel 03',
          'Staffel 3 - Folge 12 – Großstadtträume.mp4',
        ),
        root,
      );
      expect(german, isNotNull);
      expect(german!.seriesTitle, 'Babylon Berlin');
      expect(german.seasonNumber, 3);
      expect(german.episodeNumber, 12);
      expect(german.episodeTitle, 'Großstadtträume');
    });

    test('parses technical subfolders like CD1 / Bonus without corrupting series title',
        () {
      const root = r'D:\NAS\Serien';
      final ep = MediaParser.parseEpisode(
        p.join(root, 'Chernobyl', 'Season 1', 'Disc 1', 'S01E01_1_23_45.mkv'),
        root,
      );
      expect(ep, isNotNull);
      expect(ep!.seriesTitle, 'Chernobyl');
      expect(ep.seasonNumber, 1);
      expect(ep.episodeNumber, 1);
    });

    test('handles extremely long paths without throwing', () {
      const root = r'D:\NAS\Serien';
      final longFolder = 'A' * 120;
      final ep = MediaParser.parseEpisode(
        p.join(root, longFolder, 'Season 1', 'S01E01 - Long.mkv'),
        root,
      );
      expect(ep, isNotNull);
      expect(ep!.seriesTitle, longFolder);
    });

    test('falls back to "Folge N" when episode title tail is empty', () {
      const root = r'D:\NAS\Serien';
      final ep = MediaParser.parseEpisode(
        p.join(root, 'Dark', 'S01E07.mkv'),
        root,
      );
      expect(ep, isNotNull);
      expect(ep!.episodeTitle, 'Folge 7');
    });
  });

  group('MediaParser movies', () {
    test('extracts year from parent folder and handles movies without year',
        () {
      const root = r'D:\NAS\Filme';
      final fromFolder = MediaParser.parseMovie(
        p.join(root, 'Blade Runner (1982)', 'movie.mkv'),
        root,
      );
      expect(fromFolder.title, 'Blade Runner');
      expect(fromFolder.releaseYear, 1982);

      final noYear = MediaParser.parseMovie(
        p.join(root, 'Der_Unsichtbare_Dritte.mkv'),
        root,
      );
      expect(noYear.title, 'Der Unsichtbare Dritte');
      expect(noYear.releaseYear, isNull);
    });
  });

  group('MetadataReader', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('saphir_meta_unit_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('supports plot/description keys in info.json and outline in tvshow.nfo',
        () {
      File(p.join(tempDir.path, 'info.json')).writeAsStringSync(
        '{"description": "Beschreibung aus JSON"}',
      );
      expect(
        MetadataReader.readSeriesSummary(tempDir.path),
        'Beschreibung aus JSON',
      );

      File(p.join(tempDir.path, 'info.json')).deleteSync();
      File(p.join(tempDir.path, 'tvshow.nfo')).writeAsStringSync(
        '<tvshow><outline>  Kurze   Zusammenfassung  </outline></tvshow>',
      );
      expect(
        MetadataReader.readSeriesSummary(tempDir.path),
        'Kurze Zusammenfassung',
      );
    });

    test('returns null for non-existent folder or empty summary', () {
      expect(
        MetadataReader.readSeriesSummary(p.join(tempDir.path, 'missing')),
        isNull,
      );
      File(p.join(tempDir.path, 'info.json')).writeAsStringSync('{"summary": "   "}');
      expect(MetadataReader.readSeriesSummary(tempDir.path), isNull);
    });
  });
}
