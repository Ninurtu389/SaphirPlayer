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
