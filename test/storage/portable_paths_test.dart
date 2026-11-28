import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/core/storage/portable_paths.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/storage/thumbnail_cache_service.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('saphir_portable_test_');
    PortablePaths.resetForTesting();
  });

  tearDown(() {
    PortablePaths.resetForTesting();
    if (tempRoot.existsSync()) {
      try {
        tempRoot.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows kann geöffnete Temp-Handles kurzzeitig sperren
      }
    }
  });

  Directory createFakeExeDir({
    bool withFlutterData = true,
    bool withPortableFlag = false,
  }) {
    final exeDir = Directory(p.join(tempRoot.path, 'install_dir'))
      ..createSync(recursive: true);
    if (withFlutterData) {
      final assetsDir = Directory(p.join(exeDir.path, 'data', 'flutter_assets'))
        ..createSync(recursive: true);
      File(p.join(exeDir.path, 'data', 'icudtl.dat'))
          .writeAsBytesSync(const [1, 2, 3]);
      File(p.join(exeDir.path, 'data', 'app.so'))
          .writeAsBytesSync(const [4, 5, 6]);
      File(p.join(assetsDir.path, 'AssetManifest.bin'))
          .writeAsBytesSync(const [7, 8]);
    }
    if (withPortableFlag) {
      File(p.join(exeDir.path, PortablePaths.portableFlagFileName))
          .writeAsStringSync('');
    }
    return exeDir;
  }

  group('PortablePaths & StorageLayout (A01)', () {
    test('data/flutter_assets without portable.flag stays in standard mode',
        () async {
      final exeDir = createFakeExeDir(
        withFlutterData: true,
        withPortableFlag: false,
      );
      final supportDir = Directory(p.join(tempRoot.path, 'app_support'))
        ..createSync(recursive: true);

      final layout = await PortablePaths.resolveLayout(
        executablePath: p.join(exeDir.path, 'saphir_player.exe'),
        appSupportDirectoryProvider: () async => supportDir,
      );

      expect(layout.mode, StorageMode.standard);
      expect(layout.isPortable, isFalse);
      expect(layout.baseDirectory, p.join(supportDir.path, 'SaphirPlayer'));
      expect(layout.baseDirectory, isNot(exeDir.path));
      expect(
        layout.databaseFilePath,
        p.join(supportDir.path, 'SaphirPlayer', 'data', 'saphir_player.db'),
      );
      expect(layout.hasLegacyMigrationCandidate, isFalse);
    });

    test('portable.flag alongside exe activates portable mode', () async {
      final exeDir = createFakeExeDir(
        withFlutterData: true,
        withPortableFlag: true,
      );
      final supportDir = Directory(p.join(tempRoot.path, 'app_support'))
        ..createSync(recursive: true);

      final layout = await PortablePaths.resolveLayout(
        executablePath: p.join(exeDir.path, 'saphir_player.exe'),
        appSupportDirectoryProvider: () async => supportDir,
      );

      expect(layout.mode, StorageMode.portable);
      expect(layout.isPortable, isTrue);
      expect(layout.baseDirectory, exeDir.path);
      expect(layout.dataDirectory, p.join(exeDir.path, 'data'));
      expect(
        layout.cacheDirectory,
        p.join(exeDir.path, 'cache', 'thumbnails'),
      );
      expect(layout.screenshotsDirectory, p.join(exeDir.path, 'screenshots'));
      expect(
        layout.databaseFilePath,
        p.join(exeDir.path, 'data', 'saphir_player.db'),
      );
      expect(layout.hasLegacyMigrationCandidate, isFalse);
    });

    test('standard mode creates and writes DB/data/cache in support directory',
        () async {
      final exeDir = createFakeExeDir(
        withFlutterData: true,
        withPortableFlag: false,
      );
      final supportDir = Directory(p.join(tempRoot.path, 'app_support'))
        ..createSync(recursive: true);

      final layout = await PortablePaths.initialize(
        executablePath: p.join(exeDir.path, 'saphir_player.exe'),
        appSupportDirectoryProvider: () async => supportDir,
      );

      final db = DatabaseService(storageLayout: layout);
      await db.open();
      addTearDown(db.close);

      db.instance.execute(
        "INSERT INTO app_settings (key, value) VALUES ('probe', 'ok');",
      );
      final rows = db.instance.select(
        "SELECT value FROM app_settings WHERE key = 'probe';",
      );

      expect(rows.first['value'], 'ok');
      expect(File(layout.databaseFilePath).existsSync(), isTrue);
      expect(Directory(layout.cacheDirectory).existsSync(), isTrue);
      expect(
        File(p.join(exeDir.path, 'data', 'saphir_player.db')).existsSync(),
        isFalse,
      );
    });

    test(
        'inaccessible or obstructed exe directory does not break standard mode',
        () async {
      final supportDir = Directory(p.join(tempRoot.path, 'app_support'))
        ..createSync(recursive: true);
      final nonExistentProtectedExe = p.join(
        tempRoot.path,
        'protected_program_files',
        'SaphirPlayer',
        'saphir_player.exe',
      );

      final layout = await PortablePaths.initialize(
        executablePath: nonExistentProtectedExe,
        appSupportDirectoryProvider: () async => supportDir,
      );

      expect(layout.mode, StorageMode.standard);
      expect(layout.baseDirectory, p.join(supportDir.path, 'SaphirPlayer'));
      expect(Directory(layout.dataDirectory).existsSync(), isTrue);
    });

    test(
        'non-writable target directory throws StorageAccessException with resolved path and no silent fallback',
        () async {
      final exeDir = createFakeExeDir(
        withFlutterData: true,
        withPortableFlag: true,
      );
      // Blockiere data/ als reguläre Datei (unter Windows/POSIX nicht als Ordner erstellbar)
      final blockingFile = File(p.join(exeDir.path, 'data'));
      if (Directory(blockingFile.path).existsSync()) {
        Directory(blockingFile.path).deleteSync(recursive: true);
      }
      blockingFile.writeAsStringSync('not_a_directory');

      final supportDir = Directory(p.join(tempRoot.path, 'app_support'))
        ..createSync(recursive: true);

      await expectLater(
        PortablePaths.initialize(
          executablePath: p.join(exeDir.path, 'saphir_player.exe'),
          appSupportDirectoryProvider: () async => supportDir,
        ),
        throwsA(
          isA<StorageAccessException>()
              .having((e) => e.mode, 'mode', StorageMode.portable)
              .having((e) => e.path, 'path', p.join(exeDir.path, 'data'))
              .having(
                (e) => e.toString(),
                'toString',
                contains(p.join(exeDir.path, 'data')),
              ),
        ),
      );
      expect(
        Directory(p.join(supportDir.path, 'SaphirPlayer', 'data')).existsSync(),
        isFalse,
      );
    });

    test('initialize freezes activeLayout against later portable.flag changes',
        () async {
      final exeDir = createFakeExeDir(
        withFlutterData: true,
        withPortableFlag: false,
      );
      final supportDir = Directory(p.join(tempRoot.path, 'app_support'))
        ..createSync(recursive: true);

      final layout = await PortablePaths.initialize(
        executablePath: p.join(exeDir.path, 'saphir_player.exe'),
        appSupportDirectoryProvider: () async => supportDir,
      );
      expect(layout.mode, StorageMode.standard);

      // Späteres Anlegen von portable.flag darf den laufenden Modus nicht ändern
      File(p.join(exeDir.path, PortablePaths.portableFlagFileName))
          .writeAsStringSync('');

      expect(PortablePaths.activeLayout?.mode, StorageMode.standard);
      expect(
        await PortablePaths.resolveBaseDirectory(),
        p.join(supportDir.path, 'SaphirPlayer'),
      );
      expect(
        await PortablePaths.getDataDirectory(),
        p.join(supportDir.path, 'SaphirPlayer', 'data'),
      );
    });

    test(
        'detects legacy database next to exe, backs up and copies safely without deleting original',
        () async {
      final exeDir = createFakeExeDir(
        withFlutterData: true,
        withPortableFlag: false,
      );
      final supportDir = Directory(p.join(tempRoot.path, 'app_support'))
        ..createSync(recursive: true);

      final legacyDbPath = p.join(exeDir.path, 'data', 'saphir_player.db');
      final legacyDb = DatabaseService();
      await legacyDb.open(dbPath: legacyDbPath);
      legacyDb.instance.execute(
        "INSERT INTO series (title, folder_path) VALUES ('Dark', 'D:\\Dark');",
      );
      legacyDb.close();

      // Simuliere vorhandene WAL-Datei neben Legacy-DB
      File('$legacyDbPath-wal').writeAsBytesSync(const [9, 8, 7]);

      final layout = await PortablePaths.initialize(
        executablePath: p.join(exeDir.path, 'saphir_player.exe'),
        appSupportDirectoryProvider: () async => supportDir,
      );

      expect(layout.mode, StorageMode.standard);
      expect(layout.hasLegacyMigrationCandidate, isTrue);
      expect(layout.legacyPortableDbPath, legacyDbPath);

      final backupDirPath = await PortablePaths.migrateLegacyDatabase(layout);

      expect(File(legacyDbPath).existsSync(), isTrue);
      expect(File('$legacyDbPath-wal').existsSync(), isTrue);
      expect(File(layout.databaseFilePath).existsSync(), isTrue);
      expect(File('${layout.databaseFilePath}-wal').existsSync(), isTrue);
      expect(
        File(p.join(backupDirPath, 'saphir_player.db')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(backupDirPath, 'saphir_player.db-wal')).existsSync(),
        isTrue,
      );

      // Wenn Ziel-DB danach existiert, wird kein Migrationskandidat mehr gemeldet
      final secondResolve = await PortablePaths.resolveLayout(
        executablePath: p.join(exeDir.path, 'saphir_player.exe'),
        appSupportDirectoryProvider: () async => supportDir,
      );
      expect(secondResolve.hasLegacyMigrationCandidate, isFalse);

      // Migrierte Daten prüfen (WAL-Dummy-Datei vorher entfernen, damit SQLite sauber öffnet)
      File('${layout.databaseFilePath}-wal').deleteSync();
      final migratedDb = DatabaseService(storageLayout: layout);
      await migratedDb.open();
      addTearDown(migratedDb.close);
      final seriesRows =
          migratedDb.instance.select('SELECT title FROM series;');
      expect(seriesRows.map((r) => r['title']).toList(), ['Dark']);
    });

    test(
        'DatabaseService, ProgressSyncService, ThumbnailCacheService and SettingsController use injected StorageLayout',
        () async {
      final customBase = Directory(p.join(tempRoot.path, 'injected_base'))
        ..createSync(recursive: true);
      final layout = StorageLayout(
        mode: StorageMode.portable,
        baseDirectory: customBase.path,
        dataDirectory: p.join(customBase.path, 'data'),
        cacheDirectory: p.join(customBase.path, 'cache', 'thumbnails'),
        screenshotsDirectory: p.join(customBase.path, 'screenshots'),
        databaseFilePath: p.join(customBase.path, 'data', 'saphir_player.db'),
      );

      final db = DatabaseService(storageLayout: layout);
      await db.open();
      addTearDown(db.close);

      final thumbCache = ThumbnailCacheService(storageLayout: layout);
      Directory(layout.cacheDirectory).createSync(recursive: true);
      File(p.join(layout.cacheDirectory, 'ep_1.jpg'))
          .writeAsBytesSync(const [1, 2, 3, 4]);
      expect(await thumbCache.calculateCacheBytes(), 4);

      final syncService = ProgressSyncService(db, storageLayout: layout);
      final syncResult = await syncService.syncWithRoots(const []);
      expect(
        syncResult.targetPath,
        p.join(layout.dataDirectory, 'progress_sync.json'),
      );
      expect(File(syncResult.targetPath).existsSync(), isTrue);

      final settings = SettingsController(
        db,
        syncService: syncService,
        cacheService: thumbCache,
        storageLayout: layout,
      );
      await settings.load();
      expect(settings.isPortableMode, isTrue);
      expect(settings.storageDataPath, layout.dataDirectory);
      expect(settings.cacheBytes, 4);
    });
  });
}
