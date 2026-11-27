import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/core/storage/portable_paths.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/library/library_models.dart';

void main() {
  late Directory tempRoot;
  late DatabaseService dbService;
  late SettingsController settingsController;
  late LibraryController libraryController;
  late HomeController homeController;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('saphir_ctrl_test_');
    PortablePaths.testBaseDirectoryOverride = p.join(tempRoot.path, 'app_base');
    dbService = DatabaseService();
    await dbService.open(dbPath: p.join(tempRoot.path, 'ctrl.db'));

    settingsController = SettingsController(dbService);
    await settingsController.load();
    libraryController = LibraryController(dbService, settingsController);
    homeController = HomeController(dbService);

    _seedSampleData(dbService);
  });

  tearDown(() {
    dbService.close();
    PortablePaths.testBaseDirectoryOverride = null;
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test('HomeController builds rails, hero, search, and toggles watched', () {
    homeController.refreshHomeFeeds();

    expect(homeController.continueWatching.length, 2);
    expect(homeController.heroItem, isNotNull);
    expect(homeController.recentlyAdded.length, 2);
    expect(homeController.rediscoverItems.length, 2);

    homeController.updateSearchQuery('interstellar');
    expect(homeController.continueWatching.length, 1);
    expect(homeController.continueWatching.first.title, 'Interstellar');
    homeController.updateSearchQuery('');

    final detail = homeController.loadSeriesDetail(1);
    expect(detail, isNotNull);
    expect(detail!.title, 'Dark');
    expect(detail.summary, 'Zeitreise in Winden');
    expect(detail.totalEpisodes, 2);
    expect(detail.watchedEpisodes, 0);

    final firstEp = detail.seasons.first.episodes.first;
    homeController.toggleEpisodeWatched(firstEp, 'TestPC');

    final updatedDetail = homeController.loadSeriesDetail(1);
    expect(updatedDetail!.watchedEpisodes, 1);
    expect(updatedDetail.overallProgress, closeTo(0.5, 0.01));
  });

  test('LibraryController loads series and movies and filters by type/query',
      () {
    libraryController.loadCountsFromCache();

    expect(libraryController.seriesCount, 1);
    expect(libraryController.movieCount, 1);
    expect(libraryController.filteredItems.length, 2);

    libraryController.setFilter(LibraryFilter.series);
    expect(libraryController.filteredItems.length, 1);
    expect(libraryController.filteredItems.first.mediaType, 'series');

    libraryController.setFilter(LibraryFilter.movies);
    expect(libraryController.filteredItems.length, 1);
    expect(libraryController.filteredItems.first.mediaType, 'movie');

    libraryController.setFilter(LibraryFilter.all);
    libraryController.updateSearchQuery('dark');
    expect(libraryController.filteredItems.length, 1);
    expect(libraryController.filteredItems.first.title, 'Dark');
  });
}

void _seedSampleData(DatabaseService dbService) {
  final db = dbService.instance;
  final now = DateTime.now().millisecondsSinceEpoch;

  db.execute(
    '''
    INSERT INTO series (id, title, folder_path, poster_path, summary, last_watched_at)
    VALUES (1, 'Dark', 'D:\\NAS\\Serien\\Dark', NULL, 'Zeitreise in Winden', NULL);
    ''',
  );
  db.execute(
    '''
    INSERT INTO seasons (id, series_id, season_number, folder_path)
    VALUES (1, 1, 1, 'D:\\NAS\\Serien\\Dark\\Season 1');
    ''',
  );
  db.execute(
    '''
    INSERT INTO episodes (id, series_id, season_id, episode_number, title, file_path, duration_ms)
    VALUES
      (1, 1, 1, 1, 'Geheimnisse', 'D:\\NAS\\Serien\\Dark\\S01E01.mkv', 3000000),
      (2, 1, 1, 2, 'Luegen', 'D:\\NAS\\Serien\\Dark\\S01E02.mkv', 3000000);
    ''',
  );
  db.execute(
    '''
    INSERT INTO movies (id, title, release_year, file_path, duration_ms)
    VALUES (1, 'Interstellar', 2014, 'D:\\NAS\\Filme\\Interstellar.mkv', 10140000);
    ''',
  );
  db.execute(
    '''
    INSERT INTO watch_progress (media_key, media_type, position_ms, duration_ms, completed, updated_at, source_device)
    VALUES
      ('episode_1', 'episode', 1200000, 3000000, 0, ?, 'Laptop'),
      ('movie_1', 'movie', 2400000, 10140000, 0, ?, 'Laptop');
    ''',
    [now, now - 1000],
  );
}
