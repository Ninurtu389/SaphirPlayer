import 'package:flutter_test/flutter_test.dart';
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/theme/effect_mode.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/library/library_models.dart';
import 'package:saphir_player/features/library/media_repository.dart';
import 'package:saphir_player/features/player/playback_session.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import 'package:saphir_player/features/stats/stats_controller.dart';
import 'package:saphir_player/features/stats/stats_models.dart';
import '../helpers/test_fixtures.dart';

void main() {
  late TestEnv env;
  late SettingsController settingsController;
  late LibraryController libraryController;
  late HomeController homeController;
  late StatsController statsController;

  setUp(() async {
    env = await TestEnv.create();
    settingsController = SettingsController(env.dbService);
    await settingsController.load();
    libraryController = LibraryController(env.dbService, settingsController);
    homeController = HomeController(env.dbService);
    statsController = StatsController(env.dbService);
  });

  tearDown(() {
    libraryController.dispose();
    settingsController.dispose();
    homeController.dispose();
    statsController.dispose();
    env.dispose();
  });

  group('HomeController', () {
    test('sorts continueWatching across episodes and movies by updated_at DESC',
        () {
      seedSampleLibrary(env.dbService);
      final now = DateTime.now().millisecondsSinceEpoch;
      // Make movie_1 newer than episode_1
      env.dbService.instance.execute(
        "UPDATE watch_progress SET updated_at = ? WHERE media_key = 'movie_1';",
        [now + 5000],
      );

      homeController.refreshHomeFeeds();

      expect(homeController.continueWatching.length, 2);
      expect(homeController.continueWatching.first.mediaKey, 'movie_1');
      expect(homeController.heroItem?.mediaKey, 'movie_1');
      expect(homeController.getMovieResumePositionMs('movie_1'), 2400000);
    });

    test('returns 0 resume position for completed or unknown movies', () {
      seedSampleLibrary(env.dbService);
      env.dbService.instance.execute(
        "UPDATE watch_progress SET completed = 1 WHERE media_key = 'movie_1';",
      );

      expect(homeController.getMovieResumePositionMs('movie_1'), 0);
      expect(homeController.getMovieResumePositionMs('movie_999'), 0);
    });

    test('rediscover rail respects stale 60-day cutoff and search filter works',
        () {
      seedSampleLibrary(env.dbService);
      homeController.refreshHomeFeeds();

      // Dark was watched 90 days ago, Andor + 2 movies have NULL last_watched_at -> 4 stale
      expect(homeController.rediscoverItems.length, 4);

      // Update Dark to watched today -> no longer stale (Andor + 2 movies remain)
      env.dbService.instance.execute(
        'UPDATE series SET last_watched_at = ? WHERE id = 1;',
        [DateTime.now().millisecondsSinceEpoch],
      );
      homeController.refreshHomeFeeds();
      expect(homeController.rediscoverItems.length, 3);
      expect(
        homeController.rediscoverItems.map((e) => e.title),
        containsAll(['Andor', 'Interstellar', 'Arrival']),
      );

      homeController.updateSearchQuery('  dark ');
      expect(homeController.heroItem, isNull);
      expect(homeController.seriesItems.length, 1);
      expect(homeController.seriesItems.first.title, 'Dark');
      expect(homeController.movieItems, isEmpty);
    });

    test('pickRandomItem includes movies and buildSessionForCard uses nextResumeEpisode for series',
        () {
      seedSampleLibrary(env.dbService);
      // Mark episode 1 of Dark as completed so nextResumeEpisode is episode 2
      env.dbService.instance.execute(
        "UPDATE watch_progress SET completed = 1, position_ms = 0 WHERE media_key = 'episode_1';",
      );
      homeController.refreshHomeFeeds();

      final seriesCard =
          homeController.seriesItems.firstWhere((e) => e.title == 'Dark');
      final session = homeController.buildSessionForCard(seriesCard);
      expect(session.initialIndex, 1);
      expect(session.queue[session.initialIndex].mediaKey, 'episode_2');

      // With only movies in DB, pickRandomItem still returns a movie
      env.dbService.instance.execute('DELETE FROM series;');
      homeController.refreshHomeFeeds();
      final randomMovie = homeController.pickRandomItem();
      expect(randomMovie, isNotNull);
      expect(randomMovie!.mediaType, 'movie');
    });

    test('pickRandomItem returns null when empty and an item when seeded', () {
      homeController.refreshHomeFeeds();
      expect(homeController.pickRandomItem(), isNull);

      seedSampleLibrary(env.dbService);
      homeController.refreshHomeFeeds();
      expect(homeController.pickRandomItem(), isNotNull);
    });

    test('loadSeriesDetail returns null for missing id and toggles watched',
        () {
      seedSampleLibrary(env.dbService);
      expect(homeController.loadSeriesDetail(999), isNull);

      final detail = homeController.loadSeriesDetail(1)!;
      expect(detail.seasons.length, 2);
      expect(detail.nextResumeEpisode?.id, 1);

      final ep = detail.seasons.first.episodes.first;
      homeController.toggleEpisodeWatched(ep, 'UnitTestDevice');

      final updated = homeController.loadSeriesDetail(1)!;
      expect(updated.watchedEpisodes, 1);
      expect(updated.nextResumeEpisode?.id, 2);
    });
  });

  group('LibraryController', () {
    test('handles empty DB, filters, resetLibraryState, and playback pause',
        () async {
      libraryController.loadCountsFromCache();
      expect(libraryController.seriesCount, 0);
      expect(libraryController.movieCount, 0);
      expect(libraryController.filteredItems, isEmpty);

      seedSampleLibrary(env.dbService);
      libraryController.loadCountsFromCache();
      expect(libraryController.seriesCount, 2);
      expect(libraryController.movieCount, 2);
      expect(libraryController.filteredItems.length, 4);

      libraryController.setFilter(LibraryFilter.series);
      expect(libraryController.filteredItems.length, 2);
      libraryController.setFilter(LibraryFilter.movies);
      expect(libraryController.filteredItems.length, 2);

      libraryController.setPlaybackActive(true);
      await libraryController.refreshLibrary();
      expect(libraryController.statusMessage, isNotEmpty);

      libraryController.resetLibraryState();
      expect(libraryController.seriesCount, 0);
      expect(libraryController.filteredItems, isEmpty);
      expect(libraryController.activeFilter, LibraryFilter.all);
    });

    test('concurrent refreshLibrary calls do not crash and dispose is safe',
        () async {
      final f1 = libraryController.refreshLibrary();
      final f2 = libraryController.refreshLibrary();
      await Future.wait([f1, f2]);

      expect(libraryController.isScanning, isFalse);
    });
  });

  group('SettingsController & EffectMode', () {
    test('EffectMode parses unknown values safely to glass', () {
      expect(EffectMode.fromStorage(null), EffectMode.glass);
      expect(EffectMode.fromStorage('unknown'), EffectMode.glass);
      expect(EffectMode.fromStorage('lean'), EffectMode.lean);
      expect(EffectMode.lean.toStorage(), 'lean');
      expect(EffectMode.glass.toStorage(), 'glass');
    });

    test('handles corrupt nas_root_paths JSON gracefully', () async {
      env.dbService.instance.execute(
        "INSERT INTO app_settings (key, value) VALUES ('nas_root_paths', '{not_json');",
      );
      final ctrl = SettingsController(env.dbService);
      await ctrl.load();
      expect(ctrl.nasPaths, isEmpty);
      ctrl.dispose();
    });

    test('addNasPath/removeNasPath and immediate EffectMode persistence work without save()',
        () async {
      expect(settingsController.addNasPath(r'D:\Media'), isTrue);
      expect(settingsController.nasPaths, [r'D:\Media']);
      expect(settingsController.addNasPath(r'D:\media'), isFalse);
      settingsController.removeNasPath(r'D:\Media');
      expect(settingsController.nasPaths, isEmpty);

      settingsController.updateEffectMode(EffectMode.lean);
      settingsController.updatePerDeviceEffect(false);
      final reloaded = SettingsController(env.dbService);
      await reloaded.load();
      expect(reloaded.effectMode, EffectMode.lean);
      expect(reloaded.perDeviceEffect, isFalse);
      reloaded.dispose();
    });
  });

  group('MediaRepository & ShellController orchestration', () {
    test('MediaRepository loads single-join detail and removes from continueWatching without deleting history',
        () {
      seedSampleLibrary(env.dbService);
      final repo = MediaRepository(env.dbService);
      final detail = repo.loadSeriesDetail(1)!;
      expect(detail.seasons.length, 2);
      expect(detail.totalEpisodes, 3);

      env.dbService.instance.execute(
        '''
        INSERT INTO watch_history (
          media_key, media_type, title, series_id, watched_ms, started_at, ended_at, day_key, weekday, source_device
        ) VALUES ('episode_1', 'episode', 'Dark', 1, 1200000, 1000, 1201000, '2026-11-27', 5, 'PC');
        ''',
      );

      homeController.refreshHomeFeeds();
      final epCard = homeController.continueWatching
          .firstWhere((c) => c.mediaKey == 'episode_1');
      homeController.removeFromContinueWatching(epCard, deviceName: 'TestPC');

      expect(
        homeController.continueWatching.any((c) => c.mediaKey == 'episode_1'),
        isFalse,
      );
      final histCount = env.dbService.instance
          .select('SELECT COUNT(*) AS c FROM watch_history;')
          .first['c'];
      expect(histCount, 1);
    });

    test('ShellController debounces search, manages statusMessage, and syncs window maximize callbacks',
        () async {
      final shell = ShellController(
        settingsController: settingsController,
        libraryController: libraryController,
        homeController: homeController,
        statsController: statsController,
        databaseService: env.dbService,
      );
      seedSampleLibrary(env.dbService);
      libraryController.loadCountsFromCache();
      homeController.refreshHomeFeeds();

      shell.onWindowMaximize();
      expect(shell.isMaximized, isTrue);
      shell.onWindowUnmaximize();
      expect(shell.isMaximized, isFalse);

      shell.selectSection(AppSection.settings);
      shell.updateGlobalSearch('Interstellar');
      expect(shell.activeSection, AppSection.settings);
      await Future<void>.delayed(
        const Duration(milliseconds: AppSpacing.searchDebounceMs + 40),
      );
      expect(shell.activeSection, AppSection.library);
      expect(libraryController.filteredItems.length, 1);

      shell.handleSaveSettings(r'D:\SavedMedia');
      expect(shell.statusMessage, isNotEmpty);
      expect(settingsController.nasPaths, [r'D:\SavedMedia']);

      shell.dispose();
    });
  });

  group('StatsController', () {
    test('computes streaks accurately across DST transitions and ignores future dates',
        () {
      final db = env.dbService.instance;
      final now = DateTime.now();
      final todayUtc = DateTime.utc(now.year, now.month, now.day);
      final yesterdayUtc = todayUtc.subtract(const Duration(days: 1));
      final twoDaysAgoUtc = todayUtc.subtract(const Duration(days: 2));

      String fmt(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      // Also test historical DST transition (e.g. 2026-03-28 -> 2026-03-29 -> 2026-03-30)
      db.execute(
        '''
        INSERT INTO watch_history (
          media_key, media_type, title, series_id, watched_ms, started_at, ended_at, day_key, weekday, source_device
        ) VALUES
          ('ep_1', 'episode', 'Dark', 1, 600000, 1, 2, '2026-03-28', 6, 'PC'),
          ('ep_2', 'episode', 'Dark', 1, 600000, 1, 2, '2026-03-29', 7, 'PC'),
          ('ep_3', 'episode', 'Dark', 1, 600000, 1, 2, '2026-03-30', 1, 'PC'),
          ('ep_4', 'episode', 'Dark', 1, 600000, 1, 2, '2026-03-31', 2, 'PC'),
          ('ep_5', 'episode', 'Dark', 1, 600000, 1, 2, ?, 1, 'PC'),
          ('ep_6', 'episode', 'Dark', 1, 600000, 1, 2, ?, 2, 'PC'),
          ('ep_7', 'episode', 'Dark', 1, 600000, 1, 2, ?, 3, 'PC');
        ''',
        [fmt(twoDaysAgoUtc), fmt(yesterdayUtc), fmt(todayUtc)],
      );

      statsController.refreshStats();
      expect(statsController.summary.longestStreakDays, greaterThanOrEqualTo(4));
      expect(statsController.summary.currentStreakDays, 3);
      expect(statsController.summary.hasAnyData, isTrue);

      // Future date should not produce an active streak
      db.execute('DELETE FROM watch_history;');
      final future = todayUtc.add(const Duration(days: 5));
      db.execute(
        '''
        INSERT INTO watch_history (
          media_key, media_type, title, series_id, watched_ms, started_at, ended_at, day_key, weekday, source_device
        ) VALUES ('ep_f', 'episode', 'Dark', 1, 600000, 1, 2, ?, 1, 'PC');
        ''',
        [fmt(future)],
      );
      statsController.refreshStats();
      expect(statsController.summary.currentStreakDays, 0);
    });

    test('StatsSummary.empty reports hasAnyData == false', () {
      expect(StatsSummary.empty.hasAnyData, isFalse);
    });
  });

  group('ShellController & LibraryModels', () {
    test('ShellController manages sections, series detail, and playback session',
        () {
      final shell = ShellController();
      expect(shell.activeSection, AppSection.home);
      expect(shell.isPlayerOpen, isFalse);

      shell.selectSection(AppSection.library);
      expect(shell.activeSection, AppSection.library);

      const detail = SeriesDetailData(
        seriesId: 1,
        title: 'Dark',
        folderPath: r'D:\Dark',
        posterPath: null,
        summary: null,
        seasons: [],
      );
      shell.openSeriesDetail(detail);
      expect(shell.selectedSeriesDetail, isNotNull);

      shell.selectSection(AppSection.stats);
      expect(shell.selectedSeriesDetail, isNull);

      const session = PlaybackSession(queue: [], initialIndex: 0);
      shell.openPlaybackSession(session);
      expect(shell.isPlayerOpen, isTrue);
      shell.closePlaybackSession();
      expect(shell.isPlayerOpen, isFalse);
      shell.dispose();
    });

    test('MediaCardItem.monogram and EpisodeEntry edge cases', () {
      const emptyTitle = MediaCardItem(
        mediaKey: 'm1',
        mediaType: 'movie',
        title: '   ',
        subtitle: '',
        imagePath: null,
        progressRatio: 0,
        remainingMinutes: 0,
        isCompleted: false,
        seriesId: null,
        filePath: 'a.mkv',
      );
      expect(emptyTitle.monogram, '?');

      const singleWord = MediaCardItem(
        mediaKey: 'm2',
        mediaType: 'movie',
        title: 'Andor',
        subtitle: '',
        imagePath: null,
        progressRatio: 0,
        remainingMinutes: 0,
        isCompleted: false,
        seriesId: null,
        filePath: 'a.mkv',
      );
      expect(singleWord.monogram, 'AN');

      const twoWords = MediaCardItem(
        mediaKey: 'm3',
        mediaType: 'movie',
        title: 'Blade Runner',
        subtitle: '',
        imagePath: null,
        progressRatio: 0,
        remainingMinutes: 0,
        isCompleted: false,
        seriesId: null,
        filePath: 'a.mkv',
      );
      expect(twoWords.monogram, 'BR');

      const zeroDurEp = EpisodeEntry(
        id: 1,
        seriesId: 1,
        seasonId: 1,
        seasonNumber: 1,
        episodeNumber: 1,
        title: 'Test',
        filePath: 'a.mkv',
        durationMs: 0,
        thumbPath: null,
        positionMs: 5000,
        isCompleted: false,
      );
      expect(zeroDurEp.progressRatio, 0.0);
      expect(zeroDurEp.formattedDuration, '');

      const completedEp = EpisodeEntry(
        id: 2,
        seriesId: 1,
        seasonId: 1,
        seasonNumber: 1,
        episodeNumber: 2,
        title: 'Done',
        filePath: 'b.mkv',
        durationMs: AppSpacing.millisecondsPerMinute * 45,
        thumbPath: null,
        positionMs: 100,
        isCompleted: true,
      );
      expect(completedEp.progressRatio, 1.0);
      expect(completedEp.formattedDuration, '45 Min.');
    });
  });
}
