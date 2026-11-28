import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/utils/formatters.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/scanner/media_parser.dart';
import 'package:saphir_player/features/scanner/media_tag_reader_service.dart';
import 'package:saphir_player/features/scanner/nas_scanner_service.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('MediaTagReaderService ffprobe JSON & tag aliases', () {
    test('parses ffprobe JSON with case-insensitive tags and duration', () {
      const jsonOutput = '''
      {
        "format": {
          "duration": "2700.5",
          "tags": {
            "TITLE": "Das Geheimnis",
            "artist": "Max Mustermann",
            "SHOW": "Zeitreise",
            "SEASON_NUMBER": "2",
            "EPISODE_SORT": "03/12",
            "DATE_RELEASED": "2024-05-10",
            "DESCRIPTION": "Erste   Beschreibung\\nmit Zeilenumbruch"
          }
        }
      }
      ''';

      final tags = MediaTagReaderService.parseFfprobeJson(jsonOutput);
      expect(tags, isNotNull);
      expect(tags!.hasAnyMetadata, isTrue);
      expect(tags.title, 'Das Geheimnis');
      expect(tags.artist, 'Max Mustermann');
      expect(tags.seriesTitle, 'Zeitreise');
      expect(tags.seasonNumber, 2);
      expect(tags.episodeNumber, 3);
      expect(tags.releaseYear, 2024);
      expect(tags.summary, 'Erste Beschreibung mit Zeilenumbruch');
      expect(tags.durationMs, 2700500);

      expect(MediaTagReaderService.parseFfprobeJson(''), isNull);
      expect(MediaTagReaderService.parseFfprobeJson('{invalid'), isNull);
      expect(MediaTagReaderService.parseFfprobeJson('{"format": {}}'), isNull);
    });

    test('maps tag aliases and limits album fallback to series context', () {
      final movieAliases = MediaTagReaderService.mapRawTags(
        {
          'Title': 'Dune: Part Two',
          'Director': 'Denis Villeneuve',
          'Album': 'Soundtrack Collection',
          'Creation_Time': '2024-03-01T12:00:00Z',
          'Synopsis': 'Wuestenplanet Arrakis.',
        },
      );
      expect(movieAliases, isNotNull);
      expect(movieAliases!.title, 'Dune: Part Two');
      expect(movieAliases.artist, 'Denis Villeneuve');
      expect(movieAliases.seriesTitle, isNull);
      expect(movieAliases.releaseYear, 2024);
      expect(movieAliases.summary, 'Wuestenplanet Arrakis.');

      final seriesAliases = MediaTagReaderService.mapRawTags(
        {
          'album': 'Mein Podcast',
          'album_artist': 'Sprecherteam',
          'tvseason': '0',
          'track': '04/10',
          'comment': 'Folgenbeschreibung',
        },
      );
      expect(seriesAliases, isNotNull);
      expect(seriesAliases!.seriesTitle, 'Mein Podcast');
      expect(seriesAliases.artist, 'Sprecherteam');
      expect(seriesAliases.seasonNumber, 0);
      expect(seriesAliases.episodeNumber, 4);
      expect(seriesAliases.summary, 'Folgenbeschreibung');
    });
  });

  group('MediaTagReaderService MKV EBML parser', () {
    test('parses SegmentInfo and SimpleTags from synthetic MKV bytes & file',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final mkvBytes = _buildSyntheticMkvBytes(
        infoTitle: 'Segment Fallback Title',
        durationSeconds: 125.0,
        simpleTags: {
          'TITLE': 'Tag Titel',
          'ARTIST': 'Clara Schumann',
          'SHOW': 'Konzertreihe',
          'SEASON': '1',
          'EPISODE': '5',
          'YEAR': '2023',
          'SUMMARY': 'Liveaufnahme aus Leipzig',
        },
      );

      final fromBytes = MediaTagReaderService.parseMkvBytes(mkvBytes);
      expect(fromBytes, isNotNull);
      expect(fromBytes!.title, 'Tag Titel');
      expect(fromBytes.artist, 'Clara Schumann');
      expect(fromBytes.seriesTitle, 'Konzertreihe');
      expect(fromBytes.seasonNumber, 1);
      expect(fromBytes.episodeNumber, 5);
      expect(fromBytes.releaseYear, 2023);
      expect(fromBytes.summary, 'Liveaufnahme aus Leipzig');
      expect(fromBytes.durationMs, 125000);

      final mkvFile = File(p.join(env.tempRoot.path, 'sample.mkv'))
        ..writeAsBytesSync(mkvBytes);
      final fromFile = MediaTagReaderService.readMkvTags(mkvFile.path);
      expect(fromFile, isNotNull);
      expect(fromFile!.title, 'Tag Titel');
      expect(fromFile.artist, 'Clara Schumann');
      expect(fromFile.durationMs, 125000);

      // Corrupt or truncated bytes return null safely
      expect(
        MediaTagReaderService.parseMkvBytes(Uint8List.fromList([0x01, 0x02])),
        isNull,
      );
      expect(
        MediaTagReaderService.parseMkvBytes(
          mkvBytes.sublist(0, 20),
        ),
        isNull,
      );
    });

    test('resolves Tags located after Cluster via SeekHead in file', () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final mkvBytes = _buildSyntheticMkvBytes(
        infoTitle: 'Film per SeekHead',
        durationSeconds: 5400.0,
        simpleTags: {
          'ARTIST': 'Studio Ghibli',
          'DATE_RELEASED': '2001',
        },
        putTagsAfterCluster: true,
      );

      final mkvFile = File(p.join(env.tempRoot.path, 'seekhead.mkv'))
        ..writeAsBytesSync(mkvBytes);
      final parsed = MediaTagReaderService.readMkvTags(mkvFile.path);
      expect(parsed, isNotNull);
      expect(parsed!.title, 'Film per SeekHead');
      expect(parsed.artist, 'Studio Ghibli');
      expect(parsed.releaseYear, 2001);
      expect(parsed.durationMs, 5400000);
    });
  });

  group('MediaParser tag priority & fallback', () {
    test('prefers embedded tags and falls back to filename for missing fields',
        () {
      const root = r'D:\NAS\Serien';
      final path = p.join(root, 'FallbackShow', 'Season 2', 'S02E03 - Alt.mkv');
      final parsed = MediaParser.parseEpisodeWithTags(
        path,
        root,
        const EmbeddedMediaTags(
          title: 'Neuer Tag-Titel',
          artist: 'Regie X',
          durationMs: 1800000,
        ),
        fileSize: 1024,
        modifiedAt: 99999,
      );
      expect(parsed, isNotNull);
      expect(parsed!.seriesTitle, 'FallbackShow');
      expect(parsed.seasonNumber, 2);
      expect(parsed.episodeNumber, 3);
      expect(parsed.episodeTitle, 'Neuer Tag-Titel');
      expect(parsed.artist, 'Regie X');
      expect(parsed.durationMs, 1800000);
      expect(parsed.fileSize, 1024);
      expect(parsed.modifiedAt, 99999);
    });

    test('detects episode purely via tags without SxxExx in filename', () {
      const root = r'D:\NAS\Medien';
      final path = p.join(root, 'unsorted', 'video_abc.mkv');
      final parsed = MediaParser.parseEpisodeWithTags(
        path,
        root,
        const EmbeddedMediaTags(
          seriesTitle: 'Tag Serie',
          seasonNumber: 3,
          episodeNumber: 7,
          title: 'Episode Sieben',
        ),
        fileSize: 2048,
        modifiedAt: 12345,
      );
      expect(parsed, isNotNull);
      expect(parsed!.seriesTitle, 'Tag Serie');
      expect(parsed.seasonNumber, 3);
      expect(parsed.episodeNumber, 7);
      expect(parsed.episodeTitle, 'Episode Sieben');

      // Isolated track tag without series/season must NOT turn a movie into episode
      final moviePath = p.join(root, 'Inception (2010).mkv');
      expect(
        MediaParser.parseEpisodeWithTags(
          moviePath,
          root,
          const EmbeddedMediaTags(episodeNumber: 1, title: 'Inception'),
          fileSize: 500,
          modifiedAt: 500,
        ),
        isNull,
      );
      final parsedMovie = MediaParser.parseMovieWithTags(
        moviePath,
        root,
        const EmbeddedMediaTags(
          title: 'Inception (Tag)',
          artist: 'Christopher Nolan',
          durationMs: 8880000,
        ),
        fileSize: 500,
        modifiedAt: 500,
      );
      expect(parsedMovie.title, 'Inception (Tag)');
      expect(parsedMovie.releaseYear, 2010);
      expect(parsedMovie.artist, 'Christopher Nolan');
      expect(parsedMovie.durationMs, 8880000);
    });
  });

  group('Incremental NAS scan & isolate pipeline', () {
    test(
        'skips tagReader when file_size and modified_at are unchanged and re-reads on change',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('inc_nas');
      final movieFile = createSyntheticMp4HeaderFile(root, 'BladeRunner.mp4');

      var readCalls = 0;
      var currentTags = const EmbeddedMediaTags(
        title: 'Blade Runner',
        artist: 'Ridley Scott',
        releaseYear: 1982,
        durationMs: 7020000,
      );

      final scanner = NasScannerService(
        env.dbService,
        tagReader: (filePath) async {
          readCalls++;
          return currentTags;
        },
      );

      // Scan 1: new file -> tagReader called once
      final scan1 = await scanner.scanLibrary([root.path]);
      expect(scan1.movieCount, 1);
      expect(readCalls, 1);

      final row1 = env.dbService.instance
          .select(
              'SELECT title, artist, duration_ms, file_size, modified_at FROM movies;')
          .first;
      expect(row1['title'], 'Blade Runner');
      expect(row1['artist'], 'Ridley Scott');
      expect(row1['duration_ms'], 7020000);
      expect(row1['file_size'], greaterThan(0));
      expect(row1['modified_at'], greaterThan(0));

      // Scan 2: unchanged file -> tagReader NOT called again
      final scan2 = await scanner.scanLibrary([root.path]);
      expect(scan2.movieCount, 1);
      expect(readCalls, 1);

      // Modify file size and timestamp -> Scan 3 must re-read tags
      currentTags = const EmbeddedMediaTags(
        title: 'Blade Runner (Final Cut)',
        artist: 'Ridley Scott HD',
        releaseYear: 2007,
        durationMs: 7050000,
      );
      movieFile.writeAsBytesSync(
        Uint8List.fromList([...movieFile.readAsBytesSync(), 1, 2, 3, 4]),
        flush: true,
      );
      movieFile.setLastModifiedSync(
        DateTime.now().add(const Duration(seconds: 5)),
      );

      final scan3 = await scanner.scanLibrary([root.path]);
      expect(scan3.movieCount, 1);
      expect(readCalls, 2);

      final row3 = env.dbService.instance
          .select(
              'SELECT title, artist, release_year, duration_ms FROM movies;')
          .first;
      expect(row3['title'], 'Blade Runner (Final Cut)');
      expect(row3['artist'], 'Ridley Scott HD');
      expect(row3['release_year'], 2007);
      expect(row3['duration_ms'], 7050000);
    });

    test(
        'reads synthetic MKV tags inside real Isolate.run and writes series summary fallback',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      final root = env.createSubdir('iso_nas');
      final showDir = Directory(p.join(root.path, 'Doku'))
        ..createSync(recursive: true);
      final mkvBytes = _buildSyntheticMkvBytes(
        durationSeconds: 1800.0,
        simpleTags: {
          'SHOW': 'Universum',
          'SEASON': '1',
          'EPISODE': '2',
          'TITLE': 'Schwarze Loecher',
          'ARTIST': 'Prof. Harald Lesch',
          'DESCRIPTION': 'Kosmische Phaenomene erklaert.',
        },
      );
      File(p.join(showDir.path, 'part_two.mkv')).writeAsBytesSync(mkvBytes);

      final scanner = NasScannerService(env.dbService);
      final res = await scanner.scanLibrary([root.path]);
      expect(res.nasReachable, isTrue);
      expect(res.seriesCount, 1);
      expect(res.sourceReports, hasLength(1));
      expect(res.sourceReports.single.status, SourceScanStatus.complete);

      final seriesRow = env.dbService.instance
          .select('SELECT title, summary FROM series;')
          .first;
      expect(seriesRow['title'], 'Universum');
      expect(seriesRow['summary'], 'Kosmische Phaenomene erklaert.');

      final epRow = env.dbService.instance
          .select('SELECT title, artist, duration_ms FROM episodes;')
          .first;
      expect(epRow['title'], 'Schwarze Loecher');
      expect(epRow['artist'], 'Prof. Harald Lesch');
      expect(epRow['duration_ms'], 1800000);
    });
  });

  group('Formatters & artist search in HomeController / LibraryController', () {
    test(
        'formatMovieSubtitle, formatEpisodeSubtitle, formatEpisodeRowMeta, formatPlayerHudSubtitle',
        () {
      expect(
        Formatters.formatMovieSubtitle(2024, 'Denis Villeneuve'),
        '${AppStrings.movieTypeBadge}${AppStrings.metadataSeparator}2024${AppStrings.metadataSeparator}Denis Villeneuve',
      );
      expect(
        Formatters.formatMovieSubtitle(null, 'Hans Zimmer'),
        '${AppStrings.movieTypeBadge}${AppStrings.metadataSeparator}Hans Zimmer',
      );
      expect(
        Formatters.formatMovieSubtitle(null, null),
        AppStrings.movieTypeBadge,
      );
      expect(
        Formatters.formatEpisodeSubtitle(1, 2, 'Pilot', artist: 'Regie'),
        'S1E2${AppStrings.metadataSeparator}Pilot${AppStrings.metadataSeparator}Regie',
      );
      expect(
        Formatters.formatEpisodeRowMeta(2700000, 'Clara'),
        '45 ${AppStrings.statsMinutesShort}${AppStrings.metadataSeparator}Clara',
      );
      expect(
        Formatters.formatPlayerHudSubtitle('Film · 2024 · Nolan', 'Nolan'),
        'Film · 2024 · Nolan',
      );
      expect(
        Formatters.formatPlayerHudSubtitle('S1E1 · Pilot', 'Nolan'),
        'S1E1 · Pilot${AppStrings.metadataSeparator}Nolan',
      );
    });

    test('HomeController and LibraryController search finds items by artist',
        () async {
      final env = await TestEnv.create();
      addTearDown(env.dispose);

      env.dbService.instance.execute('''
        INSERT INTO series (id, title, folder_path) VALUES (1, 'Planet Erde', 'D:\\S\\PE');
        INSERT INTO seasons (id, series_id, season_number, folder_path) VALUES (1, 1, 1, 'D:\\S\\PE\\S1');
        INSERT INTO episodes (id, series_id, season_id, episode_number, title, file_path, duration_ms, artist)
        VALUES (1, 1, 1, 1, 'Wuesten', 'D:\\S\\PE\\S01E01.mkv', 3000000, 'David Attenborough');
        INSERT INTO movies (id, title, release_year, file_path, duration_ms, artist)
        VALUES (1, 'Oppenheimer', 2023, 'D:\\F\\Opp.mkv', 10800000, 'Christopher Nolan');
      ''');

      final settings = SettingsController(env.dbService);
      await settings.load();
      final library = LibraryController(env.dbService, settings);
      final home = HomeController(env.dbService);

      library.loadCountsFromCache();
      home.refreshHomeFeeds();

      library.updateSearchQuery('nolan');
      expect(library.filteredItems.length, 1);
      expect(library.filteredItems.first.title, 'Oppenheimer');

      library.updateSearchQuery('attenborough');
      expect(library.filteredItems.length, 1);
      expect(library.filteredItems.first.title, 'Planet Erde');

      home.updateSearchQuery('christopher nolan');
      expect(home.movieItems.length, 1);
      expect(home.movieItems.first.title, 'Oppenheimer');
      expect(home.seriesItems, isEmpty);

      home.dispose();
      library.dispose();
      settings.dispose();
    });
  });
}

Uint8List _buildSyntheticMkvBytes({
  String? infoTitle,
  required double durationSeconds,
  required Map<String, String> simpleTags,
  bool putTagsAfterCluster = false,
}) {
  final ebmlHeader = _ebmlElement(
    0x1A45DFA3,
    _ebmlElement(0x4286, [0x01]),
  );

  final infoChildren = <int>[
    ..._ebmlElement(0x2AD7B1, [0x0F, 0x42, 0x40]), // TimestampScale = 1_000_000
    ..._ebmlElement(0x4489, _float64Bytes(durationSeconds * 1000.0)),
    if (infoTitle != null) ..._ebmlElement(0x7BA9, utf8.encode(infoTitle)),
  ];
  final infoElem = _ebmlElement(0x1549A966, infoChildren);

  final simpleTagElems = <int>[];
  for (final entry in simpleTags.entries) {
    final nameBytes = _ebmlElement(0x45A3, utf8.encode(entry.key));
    final valBytes = _ebmlElement(0x4487, utf8.encode(entry.value));
    simpleTagElems.addAll(_ebmlElement(0x67C8, [...nameBytes, ...valBytes]));
  }
  final tagElem = _ebmlElement(0x7373, simpleTagElems);
  final tagsElem = _ebmlElement(0x1254C367, tagElem);
  final clusterElem = _ebmlElement(0x1F43B675, _ebmlElement(0xE7, [0x00]));

  Uint8List segmentBody;
  if (putTagsAfterCluster) {
    // Compute SeekHead placeholder size with fixed 2-byte SeekPosition values
    List<int> buildSeekHead(int tagsRelPos) {
      final seekTags = _ebmlElement(0x4DBB, [
        ..._ebmlElement(0x53AB, [0x12, 0x54, 0xC3, 0x67]),
        ..._ebmlElement(0x53AC, [
          (tagsRelPos >> 8) & 0xFF,
          tagsRelPos & 0xFF,
        ]),
      ]);
      return _ebmlElement(0x114D9B74, seekTags);
    }

    final initialSeekHead = buildSeekHead(0);
    final tagsPos =
        initialSeekHead.length + infoElem.length + clusterElem.length;
    final seekHead = buildSeekHead(tagsPos);
    segmentBody = Uint8List.fromList([
      ...seekHead,
      ...infoElem,
      ...clusterElem,
      ...tagsElem,
    ]);
  } else {
    segmentBody = Uint8List.fromList([
      ...infoElem,
      ...tagsElem,
      ...clusterElem,
    ]);
  }

  final segment = _ebmlElement(0x18538067, segmentBody);
  return Uint8List.fromList([...ebmlHeader, ...segment]);
}

List<int> _ebmlElement(int id, List<int> payload) {
  final idBytes = <int>[];
  if (id <= 0xFF) {
    idBytes.add(id);
  } else if (id <= 0xFFFF) {
    idBytes.addAll([(id >> 8) & 0xFF, id & 0xFF]);
  } else if (id <= 0xFFFFFF) {
    idBytes.addAll([(id >> 16) & 0xFF, (id >> 8) & 0xFF, id & 0xFF]);
  } else {
    idBytes.addAll([
      (id >> 24) & 0xFF,
      (id >> 16) & 0xFF,
      (id >> 8) & 0xFF,
      id & 0xFF,
    ]);
  }

  final len = payload.length;
  final List<int> sizeBytes;
  if (len < 127) {
    sizeBytes = [0x80 | len];
  } else if (len < 16383) {
    sizeBytes = [0x40 | ((len >> 8) & 0x3F), len & 0xFF];
  } else {
    sizeBytes = [
      0x10 | ((len >> 24) & 0x0F),
      (len >> 16) & 0xFF,
      (len >> 8) & 0xFF,
      len & 0xFF,
    ];
  }
  return [...idBytes, ...sizeBytes, ...payload];
}

List<int> _float64Bytes(double value) {
  final data = ByteData(8)..setFloat64(0, value, Endian.big);
  return data.buffer.asUint8List();
}
