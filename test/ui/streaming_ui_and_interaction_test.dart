import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/database_service.dart';
import 'package:saphir_player/core/storage/portable_paths.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/core/theme/effect_mode.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/home/home_view.dart';
import 'package:saphir_player/features/library/library_models.dart';
import 'package:saphir_player/features/library/library_view.dart';
import 'package:saphir_player/features/library/series_detail_view.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import 'package:saphir_player/features/stats/stats_controller.dart';
import 'package:saphir_player/features/stats/stats_view.dart';
import 'package:saphir_player/widgets/media_tile.dart';
import 'package:saphir_player/widgets/window_title_bar.dart';

void main() {
  late Directory tempRoot;
  late DatabaseService dbService;
  late SettingsController settingsController;
  late LibraryController libraryController;
  late HomeController homeController;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('saphir_ui_test_');
    PortablePaths.testBaseDirectoryOverride = p.join(tempRoot.path, 'app_base');
    dbService = DatabaseService();
    await dbService.open(dbPath: p.join(tempRoot.path, 'ui_test.db'));

    settingsController = SettingsController(dbService);
    await settingsController.load();
    libraryController = LibraryController(dbService, settingsController);
    homeController = HomeController(dbService);
    _seedUiTestData(dbService);
    libraryController.loadCountsFromCache();
    homeController.refreshHomeFeeds();
  });

  tearDown(() {
    dbService.close();
    PortablePaths.testBaseDirectoryOverride = null;
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  Widget wrapWithApp(Widget child) {
    return MaterialApp(
      theme: AppTheme.buildDarkTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }

  for (final size in [const Size(1280, 800), const Size(800, 500)]) {
    testWidgets('HomeView renders hero, rails, and handles actions at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      MediaCardItem? playedItem;
      int? openedSeriesId;

      await tester.pumpWidget(
        wrapWithApp(
          HomeView(
            homeController: homeController,
            effectMode: EffectMode.glass,
            onSelectItem: (item) => playedItem = item,
            onOpenSeries: (id) => openedSeriesId = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.continueWatchingTitle), findsOneWidget);
      expect(find.text(AppStrings.resumeButton), findsOneWidget);
      expect(find.text(AppStrings.detailsButton), findsOneWidget);

      await tester.tap(find.text(AppStrings.resumeButton));
      expect(playedItem, isNotNull);

      await tester.tap(find.text(AppStrings.detailsButton));
      expect(openedSeriesId, 1);
    });

    testWidgets('LibraryView filters series and movies without overflow at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      int? openedSeriesId;
      MediaCardItem? selectedMovie;

      await tester.pumpWidget(
        wrapWithApp(
          LibraryView(
            libraryController: libraryController,
            effectMode: EffectMode.lean,
            onSelectItem: (item) => selectedMovie = item,
            onOpenSeries: (id) => openedSeriesId = id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Interstellar'), findsOneWidget);
      expect(find.text(AppStrings.libraryOverviewTitle), findsOneWidget);

      await tester.tap(find.text(AppStrings.filterMoviesLabel));
      await tester.pumpAndSettle();
      expect(find.text('Dark'), findsNothing);
      expect(find.text('Interstellar'), findsOneWidget);

      await tester.tap(find.text('Interstellar'));
      expect(selectedMovie?.title, 'Interstellar');

      await tester.tap(find.text(AppStrings.filterSeriesLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      expect(openedSeriesId, 1);
    });
  }

  testWidgets('MediaTile supports hover in glass and lean modes',
      (tester) async {
    const item = MediaCardItem(
      mediaKey: 'movie_1',
      mediaType: 'movie',
      title: 'Blade Runner 2049',
      subtitle: 'Film · 2017',
      imagePath: null,
      progressRatio: 0.45,
      remainingMinutes: 42,
      isCompleted: false,
      seriesId: null,
      filePath: r'D:\Movies\BR2049.mkv',
    );

    var tapped = false;
    await tester.pumpWidget(
      wrapWithApp(
        Center(
          child: MediaTile(
            item: item,
            effectMode: EffectMode.glass,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Blade Runner 2049'), findsOneWidget);
    expect(find.text('42 ${AppStrings.remainingMinutesSuffix}'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(MediaTile)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MediaTile));
    expect(tapped, isTrue);
  });

  testWidgets('SeriesDetailView switches seasons and toggles watched state',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final detail = homeController.loadSeriesDetail(1)!;
    EpisodeEntry? toggledEp;

    await tester.pumpWidget(
      wrapWithApp(
        SeriesDetailView(
          detail: detail,
          effectMode: EffectMode.glass,
          onBack: () {},
          onPlayEpisode: (_) {},
          onToggleWatched: (ep) => toggledEp = ep,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Zeitreise in Winden'), findsOneWidget);
    expect(find.text('${AppStrings.seasonPrefix} 1'), findsOneWidget);

    await tester.tap(find.byTooltip(AppStrings.toggleWatchedAction).first);
    expect(toggledEp, isNotNull);
    expect(toggledEp!.episodeNumber, 1);
  });

  testWidgets('HomeView hides scroll arrows when rail fits without scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      wrapWithApp(
        HomeView(
          homeController: homeController,
          effectMode: EffectMode.glass,
          onSelectItem: (_) {},
          onOpenSeries: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(MediaTile).first));
    await tester.pumpAndSettle();

    expect(find.byTooltip(AppStrings.scrollLeftTooltip), findsNothing);
    expect(find.byTooltip(AppStrings.scrollRightTooltip), findsNothing);
  });

  testWidgets('StatsView and WindowTitleBar render cleanly at 1280x800 and 800x500',
      (tester) async {
    final statsController = StatsController(dbService);
    statsController.refreshStats();
    final shellController = ShellController();
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);

    for (final size in [const Size(1280, 800), const Size(800, 500)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildDarkTheme(),
          home: Scaffold(
            body: Column(
              children: [
                WindowTitleBar(
                  shellController: shellController,
                  searchController: searchController,
                  onSearchChanged: (_) {},
                  onClearSearch: () {},
                ),
                Expanded(
                  child: StatsView(
                    statsController: statsController,
                    effectMode: EffectMode.glass,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.statsPageTitle), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      final maxIcon = tester.widget<Icon>(find.byIcon(Icons.crop_square));
      expect(maxIcon.size, AppSpacing.windowMaximizeIconSize);
      expect(maxIcon.size! < AppSpacing.windowControlIconSize, isTrue);
    }
  });
}

void _seedUiTestData(DatabaseService dbService) {
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
    VALUES (1, 1, 1, 1, 'Geheimnisse', 'D:\\NAS\\Serien\\Dark\\S01E01.mkv', 3000000);
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
    VALUES ('episode_1', 'episode', 1200000, 3000000, 0, ?, 'Laptop');
    ''',
    [now],
  );
}
