import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/portable_paths.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/home/home_view.dart';
import 'package:saphir_player/features/player/saphir_player_controller.dart';
import 'package:saphir_player/features/player/saphir_player_view.dart';
import 'package:saphir_player/features/scanner/media_tag_reader_service.dart';
import 'package:saphir_player/features/scanner/nas_scanner_service.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import 'package:saphir_player/features/shell/shell_view.dart';
import 'package:saphir_player/features/stats/stats_controller.dart';
import 'package:saphir_player/widgets/media_tile.dart';
import '../helpers/mock_mpv_property_bridge.dart';
import '../helpers/mock_player.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('Phase 8 End-to-End Integration Flows', () {
    late TestEnv env;
    late Directory nasRoot;
    late ProgressSyncService syncService;
    late ShellController shellController;
    late SettingsController settingsController;
    late LibraryController libraryController;
    late HomeController homeController;
    late StatsController statsController;
    late FakePlayerHarness harness;
    late MockMpvPropertyBridge bridge;
    late SaphirPlayerController playerController;

    setUp(() async {
      env = await TestEnv.create();
      nasRoot = env.createSubdir('nas_media');
      syncService = ProgressSyncService(env.dbService);
      shellController = ShellController();
      settingsController =
          SettingsController(env.dbService, syncService: syncService);
      await settingsController.load();
      libraryController = LibraryController(env.dbService, settingsController);
      homeController = HomeController(env.dbService);
      statsController = StatsController(env.dbService);
      harness = FakePlayerHarness();
      bridge = MockMpvPropertyBridge();
      playerController = SaphirPlayerController(
        env.dbService,
        syncService,
        () => settingsController.nasPaths,
        settingsController: settingsController,
        player: harness.player,
        videoController: harness.videoController,
        mpvBridge: bridge,
        windowAdapter: harness.windowAdapter,
      );
    });

    tearDown(() async {
      playerController.dispose();
      await harness.close();
      shellController.dispose();
      libraryController.dispose();
      settingsController.dispose();
      homeController.dispose();
      statsController.dispose();
      env.dispose();
    });

    testWidgets(
        'Flow 1: Scan (Series + WALL-E + MKV tags override filename) -> Home (Hero + 5 Rails) -> Artist search -> Play/Pause -> Remove X -> Sync',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Prepare media: WALL-E movie + series with MKV tags overriding filename
      createSyntheticMp4HeaderFile(nasRoot, 'WALL-E (2008).mp4');
      final docDir = Directory(p.join(nasRoot.path, 'Unsorted'))
        ..createSync(recursive: true);
      final mkvBytes = _buildSyntheticMkvBytes(
        durationSeconds: 1800.0,
        simpleTags: {
          'SHOW': 'Kosmos',
          'SEASON': '1',
          'EPISODE': '3',
          'TITLE': 'Am Rand der Unendlichkeit',
          'ARTIST': 'Carl Sagan',
        },
      );
      File(p.join(docDir.path, 'raw_clip_99.mkv')).writeAsBytesSync(mkvBytes);

      settingsController.addNasPath(nasRoot.path);
      await tester.runAsync(() async {
        await libraryController.refreshLibrary();
        homeController.refreshHomeFeeds();
        statsController.refreshStats();
      });

      expect(libraryController.seriesCount, 1);
      expect(libraryController.movieCount, 1);
      expect(homeController.seriesItems.first.title, 'Kosmos');
      expect(homeController.movieItems.first.title, 'WALL-E');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildDarkTheme(),
          home: ShellView(
            shellController: shellController,
            settingsController: settingsController,
            libraryController: libraryController,
            homeController: homeController,
            statsController: statsController,
            playerController: playerController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Search by artist finds Kosmos
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.decoration?.hintText == AppStrings.searchHint,
        ),
        'Carl Sagan',
      );
      await tester.pump(
        const Duration(milliseconds: AppSpacing.searchDebounceMs + 30),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kosmos'), findsWidgets);
      expect(find.text('WALL-E'), findsNothing);

      // Clear search and return to Home
      await tester.tap(find.byTooltip(AppStrings.clearSearchTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.homeTab));
      await tester.pumpAndSettle();

      // Start playback of Kosmos, emit progress, pause and close -> enters Continue Watching
      await tester.tap(find.text(AppStrings.playNowButton));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(find.byType(SaphirPlayerView), findsOneWidget);

      await tester.runAsync(() async {
        harness.emitDuration(const Duration(minutes: 30));
        harness.emitPosition(const Duration(minutes: 5));
        harness.emitPlaying(false);
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump();

      await tester.tap(find.byTooltip(AppStrings.playerCloseTooltip));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SaphirPlayerView), findsNothing);

      // Hero + all 5 Rails are populated on HomeView
      expect(homeController.heroItem, isNotNull);
      expect(homeController.continueWatching, isNotEmpty);
      expect(homeController.recentlyAdded, isNotEmpty);
      expect(homeController.rediscoverItems, isNotEmpty);
      expect(homeController.seriesItems, isNotEmpty);
      expect(homeController.movieItems, isNotEmpty);

      expect(find.text(AppStrings.continueWatchingTitle), findsOneWidget);
      expect(find.text(AppStrings.recentlyAddedTitle), findsOneWidget);

      final homeScrollable = find
          .descendant(
            of: find.byType(HomeView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text(AppStrings.rediscoverTitle),
        200,
        scrollable: homeScrollable,
      );
      expect(find.text(AppStrings.rediscoverTitle), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text(AppStrings.continueWatchingTitle),
        -200,
        scrollable: homeScrollable,
      );

      // Hover first tile in Continue Watching rail and click X to remove
      final continueTile = find.byType(MediaTile).first;
      await tester.ensureVisible(continueTile);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(continueTile));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip(AppStrings.removeFromContinueWatchingTooltip),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();

      expect(homeController.continueWatching, isEmpty);
      final syncFile = File(p.join(nasRoot.path, 'progress_sync.json'));
      expect(syncFile.existsSync(), isTrue);
      final decoded =
          jsonDecode(syncFile.readAsStringSync()) as Map<String, dynamic>;
      final entries = decoded['entries'] as Map<String, dynamic>;
      expect(entries.values.any((v) => (v as Map)['position_ms'] == 0), isTrue);
    });

    testWidgets(
        'Flow 2: Series start -> Intro-Skip X hides popup -> Auto-Next completes Ep1 -> Ep2 inherits global subtitle default',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final showDir = Directory(p.join(nasRoot.path, 'Andor', 'Season 1'))
        ..createSync(recursive: true);
      createSyntheticMp4HeaderFile(showDir, 'Andor - S01E01 - Kassa.mp4');
      createSyntheticMp4HeaderFile(
        showDir,
        'Andor - S01E02 - That Would Be Me.mp4',
      );

      settingsController.addNasPath(nasRoot.path);
      settingsController.updateSubtitlesDefaultEnabled(true);
      settingsController
          .updatePreferredSubtitleLanguage(AppStrings.subtitleLangCodeEn);

      await tester.runAsync(() async {
        await libraryController.refreshLibrary();
        homeController.refreshHomeFeeds();
      });

      shellController.attachDependencies(
        settingsController: settingsController,
        libraryController: libraryController,
        homeController: homeController,
        statsController: statsController,
        playerController: playerController,
      );
      final detail = homeController.loadSeriesDetail(1)!;
      final session =
          homeController.buildSessionForEpisode(detail, detail.seasons.first.episodes.first);

      await tester.runAsync(() => shellController.launchPlayer(session));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.buildDarkTheme(),
          home: Scaffold(
            body: SaphirPlayerView(
              controller: playerController,
              effectMode: settingsController.effectMode,
              onClose: shellController.handlePlayerClosed,
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        harness.emitDuration(const Duration(minutes: 30));
        harness.emitPosition(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump();

      // Dismiss Intro Skip popup via X
      expect(find.text(AppStrings.playerIntroSkipButton), findsOneWidget);
      await tester.tap(find.byTooltip(AppStrings.dismissIntroSkipTooltip));
      await tester.pump();
      expect(find.text(AppStrings.playerIntroSkipButton), findsNothing);

      // Episode 1 completes -> Auto-Next switches to Episode 2 and marks Episode 1 completed = 1
      await tester.runAsync(() async {
        harness.emitCompleted(true);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();

      expect(playerController.currentIndex, 1);
      final ep1Key = detail.seasons.first.episodes.first.mediaKey;
      final ep1Completed = env.dbService.instance
          .select(
            'SELECT completed FROM watch_progress WHERE media_key = ?;',
            [ep1Key],
          )
          .first['completed'];
      expect(ep1Completed, 1);

      // Episode 2 inherits global English subtitle default (since no manual series preference was saved)
      harness.selectedSubtitleTracks.clear();
      await tester.runAsync(() async {
        harness.emitTracks(
          Tracks(
            audio: [AudioTrack.auto()],
            subtitle: [
              SubtitleTrack.auto(),
              SubtitleTrack('deu', 'Deutsch', 'de'),
              SubtitleTrack('eng', 'English', 'en'),
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(harness.selectedSubtitleTracks.last.id, 'eng');

      await tester.runAsync(() => playerController.stopAndClose());
      await tester.pump(const Duration(milliseconds: 100));
    });

    test(
        'Flow 3: Portable mode relative thumbnail path survives base folder relocation & incremental scan skips tagReader for unchanged files',
        () async {
      // Portable path relocation test
      final baseA = env.createSubdir('portable_drive_a');
      final baseB = env.createSubdir('portable_drive_b');
      PortablePaths.testBaseDirectoryOverride = baseA.path;
      await PortablePaths.warmUp();
      final resolvedA = PortablePaths.resolveThumbnailPath('ep_101.jpg');
      expect(resolvedA, p.join(baseA.path, 'cache', 'thumbnails', 'ep_101.jpg'));

      PortablePaths.testBaseDirectoryOverride = baseB.path;
      await PortablePaths.warmUp();
      final resolvedB = PortablePaths.resolveThumbnailPath('ep_101.jpg');
      expect(resolvedB, p.join(baseB.path, 'cache', 'thumbnails', 'ep_101.jpg'));

      // Incremental scan skips tagReader for unchanged file_size + modified_at
      final movieFile = createSyntheticMp4HeaderFile(nasRoot, 'Arrival (2016).mp4');
      expect(movieFile.existsSync(), isTrue);
      var tagReadCount = 0;
      final scanner = NasScannerService(
        env.dbService,
        tagReader: (_) async {
          tagReadCount++;
          return const EmbeddedMediaTags(
            title: 'Arrival',
            artist: 'Denis Villeneuve',
            releaseYear: 2016,
            durationMs: 6960000,
          );
        },
      );

      final res1 = await scanner.scanLibrary([nasRoot.path]);
      expect(res1.movieCount, 1);
      expect(tagReadCount, 1);

      final res2 = await scanner.scanLibrary([nasRoot.path]);
      expect(res2.movieCount, 1);
      expect(tagReadCount, 1);
    });
  });
}

Uint8List _buildSyntheticMkvBytes({
  required double durationSeconds,
  required Map<String, String> simpleTags,
}) {
  final ebmlHeader = _ebmlElement(
    0x1A45DFA3,
    _ebmlElement(0x4286, [0x01]),
  );
  final infoElem = _ebmlElement(0x1549A966, [
    ..._ebmlElement(0x2AD7B1, [0x0F, 0x42, 0x40]),
    ..._ebmlElement(0x4489, _float64Bytes(durationSeconds * 1000.0)),
  ]);
  final simpleTagElems = <int>[];
  for (final entry in simpleTags.entries) {
    final nameBytes = _ebmlElement(0x45A3, utf8.encode(entry.key));
    final valBytes = _ebmlElement(0x4487, utf8.encode(entry.value));
    simpleTagElems.addAll(_ebmlElement(0x67C8, [...nameBytes, ...valBytes]));
  }
  final tagsElem = _ebmlElement(0x1254C367, _ebmlElement(0x7373, simpleTagElems));
  final clusterElem = _ebmlElement(0x1F43B675, _ebmlElement(0xE7, [0x00]));
  final segment = _ebmlElement(0x18538067, [
    ...infoElem,
    ...tagsElem,
    ...clusterElem,
  ]);
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
