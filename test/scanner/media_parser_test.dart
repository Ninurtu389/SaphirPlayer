import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/features/library/metadata_reader.dart';
import 'package:saphir_player/features/scanner/media_parser.dart';

void main() {
  group('MediaParser', () {
    test('recognizes supported video and image extensions case-insensitively',
        () {
      expect(MediaParser.isVideoFile('episode.MKV'), isTrue);
      expect(MediaParser.isVideoFile('movie.mp4'), isTrue);
      expect(MediaParser.isVideoFile('notes.txt'), isFalse);

      expect(MediaParser.isImageFile('poster.JPG'), isTrue);
      expect(MediaParser.isImageFile('cover.webp'), isTrue);
      expect(MediaParser.isImageFile('movie.mp4'), isFalse);
    });

    test('parses SxxExx episode with series folder and episode title', () {
      const root = r'D:\NAS\Serien';
      final file = p.join(
        root,
        'Dark',
        'Staffel 01',
        'Dark - S01E02 - Luegen.mkv',
      );

      final parsed = MediaParser.parseEpisode(file, root);
      expect(parsed, isNotNull);
      expect(parsed!.seriesTitle, 'Dark');
      expect(parsed.seasonNumber, 1);
      expect(parsed.episodeNumber, 2);
      expect(parsed.episodeTitle, 'Luegen');
    });

    test('parses 1x03 format and Staffel folder fallback for Ep format', () {
      const root = r'D:\NAS\Serien';
      final xFile = p.join(root, 'Andor', '1x03_Reckoning.mp4');
      final xParsed = MediaParser.parseEpisode(xFile, root);
      expect(xParsed, isNotNull);
      expect(xParsed!.seriesTitle, 'Andor');
      expect(xParsed.seasonNumber, 1);
      expect(xParsed.episodeNumber, 3);

      final epFile = p.join(root, 'Severance', 'Staffel 2', 'Ep 04 - Woe.mkv');
      final epParsed = MediaParser.parseEpisode(epFile, root);
      expect(epParsed, isNotNull);
      expect(epParsed!.seriesTitle, 'Severance');
      expect(epParsed.seasonNumber, 2);
      expect(epParsed.episodeNumber, 4);
    });

    test('parses underscore, German Folge/Staffel, and leading-number episodes',
        () {
      const root = r'D:\NAS\Medien';

      final underscoreEp = MediaParser.parseEpisode(
        p.join(root, 'Serien', 'Dark', 'Staffel 01', 'Dark_Ep01_Pilot.mkv'),
        root,
      );
      expect(underscoreEp, isNotNull);
      expect(underscoreEp!.seriesTitle, 'Dark');
      expect(underscoreEp.seasonNumber, 1);
      expect(underscoreEp.episodeNumber, 1);
      expect(underscoreEp.episodeTitle, 'Pilot');

      final folgeEp = MediaParser.parseEpisode(
        p.join(root, 'Serien', 'Tatort', 'Folge 05 - Schatten.mp4'),
        root,
      );
      expect(folgeEp, isNotNull);
      expect(folgeEp!.seriesTitle, 'Tatort');
      expect(folgeEp.episodeNumber, 5);
      expect(folgeEp.episodeTitle, 'Schatten');

      final leadingEp = MediaParser.parseEpisode(
        p.join(root, 'Serien', 'Andor', 'Season 02', '03 - Erwachen.mkv'),
        root,
      );
      expect(leadingEp, isNotNull);
      expect(leadingEp!.seriesTitle, 'Andor');
      expect(leadingEp.seasonNumber, 2);
      expect(leadingEp.episodeNumber, 3);
      expect(leadingEp.episodeTitle, 'Erwachen');

      final dottedEp = MediaParser.parseEpisode(
        p.join(root, 'Serien', 'Lost', '1.01 Pilotenfolge.mkv'),
        root,
      );
      expect(dottedEp, isNotNull);
      expect(dottedEp!.seriesTitle, 'Lost');
      expect(dottedEp.seasonNumber, 1);
      expect(dottedEp.episodeNumber, 1);
      expect(dottedEp.episodeTitle, 'Pilotenfolge');

      final numericFolderEp = MediaParser.parseEpisode(
        p.join(root, 'Serien', 'Dark', '05', '02 - Geheimnisse.mkv'),
        root,
      );
      expect(numericFolderEp, isNotNull);
      expect(numericFolderEp!.seriesTitle, 'Dark');
      expect(numericFolderEp.seasonNumber, 5);
      expect(numericFolderEp.episodeNumber, 2);
      expect(numericFolderEp.episodeTitle, 'Geheimnisse');

      final epSubfolderEp = MediaParser.parseEpisode(
        p.join(root, 'Serien', 'Dark', 'S01E05', 'video.mkv'),
        root,
      );
      expect(epSubfolderEp, isNull);

      final movieWithDecimal = MediaParser.parseEpisode(
        p.join(root, 'Filme', 'Spider-Man 2.1 (2004).mkv'),
        root,
      );
      expect(movieWithDecimal, isNull);
    });

    test('parses movie title and release year from filename or parent folder',
        () {
      const root = r'D:\NAS\Filme';
      final file = p.join(root, 'Dune Part Two (2024).mkv');
      final parsed = MediaParser.parseMovie(file, root);

      expect(parsed.title, 'Dune Part Two');
      expect(parsed.releaseYear, 2024);
      expect(MediaParser.parseEpisode(file, root), isNull);
    });
  });

  group('MetadataReader', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('saphir_meta_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('reads summary from info.json', () {
      File(p.join(tempDir.path, 'info.json')).writeAsStringSync(
        '{"summary": "Eine geheimnisvolle Kleinstadt."}',
      );

      expect(
        MetadataReader.readSeriesSummary(tempDir.path),
        'Eine geheimnisvolle Kleinstadt.',
      );
    });

    test('reads plot from tvshow.nfo and normalizes whitespace', () {
      File(p.join(tempDir.path, 'tvshow.nfo')).writeAsStringSync(
        '<tvshow><plot>Zeile eins\n  Zeile zwei</plot></tvshow>',
      );

      expect(
        MetadataReader.readSeriesSummary(tempDir.path),
        'Zeile eins Zeile zwei',
      );
    });

    test('handles malformed json gracefully and returns null when missing', () {
      File(p.join(tempDir.path, 'info.json')).writeAsStringSync('{broken');
      expect(MetadataReader.readSeriesSummary(tempDir.path), isNull);
    });
  });
}
