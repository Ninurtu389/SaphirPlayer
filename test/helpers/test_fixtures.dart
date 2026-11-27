import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/core/storage/portable_paths.dart';

class TestEnv {
  TestEnv._({
    required this.tempRoot,
    required this.dbService,
  });

  final Directory tempRoot;
  final DatabaseService dbService;

  static Future<TestEnv> create({bool inMemory = false}) async {
    final tempRoot = Directory.systemTemp.createTempSync('saphir_qa_test_');
    PortablePaths.testBaseDirectoryOverride = p.join(tempRoot.path, 'app_base');
    await PortablePaths.warmUp();
    final dbService = DatabaseService();
    final dbPath = inMemory ? ':memory:' : p.join(tempRoot.path, 'test.db');
    await dbService.open(dbPath: dbPath);
    return TestEnv._(tempRoot: tempRoot, dbService: dbService);
  }

  Directory createSubdir(String relativePath) {
    final dir = Directory(p.join(tempRoot.path, relativePath));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  void dispose() {
    dbService.close();
    PortablePaths.testBaseDirectoryOverride = null;
    if (tempRoot.existsSync()) {
      try {
        tempRoot.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows kann geoeffnete Temp-Handles kurzzeitig sperren
      }
    }
  }
}

void seedSampleLibrary(DatabaseService dbService) {
  final db = dbService.instance;
  final now = DateTime.now().millisecondsSinceEpoch;

  db.execute(
    '''
    INSERT INTO series (id, title, folder_path, poster_path, summary, last_watched_at)
    VALUES
      (1, 'Dark', 'D:\\NAS\\Serien\\Dark', NULL, 'Zeitreise in Winden', ?),
      (2, 'Andor', 'D:\\NAS\\Serien\\Andor', NULL, 'Rebellion beginnt', NULL);
    ''',
    [now - 86400000 * 90],
  );

  db.execute(
    '''
    INSERT INTO seasons (id, series_id, season_number, folder_path)
    VALUES
      (1, 1, 1, 'D:\\NAS\\Serien\\Dark\\Season 1'),
      (2, 1, 2, 'D:\\NAS\\Serien\\Dark\\Season 2'),
      (3, 2, 1, 'D:\\NAS\\Serien\\Andor\\Season 1');
    ''',
  );

  db.execute(
    '''
    INSERT INTO episodes (id, series_id, season_id, episode_number, title, file_path, duration_ms)
    VALUES
      (1, 1, 1, 1, 'Geheimnisse', 'D:\\NAS\\Serien\\Dark\\S01E01.mkv', 3000000),
      (2, 1, 1, 2, 'Luegen', 'D:\\NAS\\Serien\\Dark\\S01E02.mkv', 3000000),
      (3, 1, 2, 1, 'Anfaenge und Enden', 'D:\\NAS\\Serien\\Dark\\S02E01.mkv', 3200000),
      (4, 2, 3, 1, 'Kassa', 'D:\\NAS\\Serien\\Andor\\S01E01.mkv', 2500000);
    ''',
  );

  db.execute(
    '''
    INSERT INTO movies (id, title, release_year, file_path, duration_ms)
    VALUES
      (1, 'Interstellar', 2014, 'D:\\NAS\\Filme\\Interstellar.mkv', 10140000),
      (2, 'Arrival', 2016, 'D:\\NAS\\Filme\\Arrival.mkv', 6960000);
    ''',
  );

  db.execute(
    '''
    INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device)
    VALUES
      ('episode_1', 'episode', 1200000, 3000000, 0, ?, 'Laptop'),
      ('movie_1', 'movie', 2400000, 10140000, 0, ?, 'Laptop');
    ''',
    [now - 1000, now - 5000],
  );
}

File createEmptyVideoFile(Directory dir, String name) {
  final file = File(p.join(dir.path, name));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(const <int>[]);
  return file;
}

File createCorruptVideoFile(Directory dir, String name) {
  final file = File(p.join(dir.path, name));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(
    Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF, 0x13, 0x37]),
  );
  return file;
}

File createSyntheticMp4HeaderFile(Directory dir, String name) {
  final file = File(p.join(dir.path, name));
  file.parent.createSync(recursive: true);
  // Minimal MP4 'ftypisom' box header without valid media tracks
  file.writeAsBytesSync(
    Uint8List.fromList([
      0x00, 0x00, 0x00, 0x14, // box size = 20
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x69, 0x73, 0x6F, 0x6D, // 'isom'
      0x00, 0x00, 0x02, 0x00, // minor version
      0x69, 0x73, 0x6F, 0x32, // 'iso2'
    ]),
  );
  return file;
}

File createSyntheticHevcStubFile(Directory dir, String name) {
  final file = File(p.join(dir.path, name));
  file.parent.createSync(recursive: true);
  // Minimal MP4 'ftyp' + 'hvc1' marker stub
  file.writeAsBytesSync(
    Uint8List.fromList([
      0x00, 0x00, 0x00, 0x14,
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x68, 0x76, 0x63, 0x31, // 'hvc1'
      0x00, 0x00, 0x00, 0x01,
      0x68, 0x65, 0x76, 0x31, // 'hev1'
    ]),
  );
  return file;
}

File createValidTinyJpeg(Directory dir, String name) {
  final file = File(p.join(dir.path, name));
  file.parent.createSync(recursive: true);
  // Valid 1x1 pixel baseline JPEG
  file.writeAsBytesSync(
    Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00,
      0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x09, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0xD2,
      0xCF, 0x20, 0xFF, 0xD9,
    ]),
  );
  return file;
}
