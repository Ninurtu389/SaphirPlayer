import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/services/local_file_service.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/core/theme/effect_mode.dart';
import 'package:saphir_player/features/library/library_models.dart';
import 'package:saphir_player/features/library/widgets/episode_row.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import 'package:saphir_player/widgets/media_tile.dart';
import 'package:saphir_player/widgets/window_title_bar.dart';

void main() {
  testWidgets(
      'MediaTile shows remove X on hover and invokes only onRemove when clicked',
      (tester) async {
    const item = MediaCardItem(
      mediaKey: 'episode_1',
      mediaType: 'episode',
      title: 'Andor',
      subtitle: 'S1E1 · Kassa',
      imagePath: null,
      progressRatio: 0.4,
      remainingMinutes: 25,
      isCompleted: false,
      seriesId: 1,
      filePath: r'D:\NAS\Andor\S01E01.mkv',
      artist: 'Tony Gilroy',
    );

    var tapped = 0;
    var removed = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildDarkTheme(),
        home: Scaffold(
          body: Center(
            child: MediaTile(
              item: item,
              effectMode: EffectMode.glass,
              onTap: () => tapped++,
              onRemove: () => removed++,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byTooltip(AppStrings.removeFromContinueWatchingTooltip),
      findsNothing,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(MediaTile)));
    await tester.pumpAndSettle();

    final removeFinder =
        find.byTooltip(AppStrings.removeFromContinueWatchingTooltip);
    expect(removeFinder, findsOneWidget);

    await tester.tap(removeFinder);
    await tester.pumpAndSettle();

    expect(removed, 1);
    expect(tapped, 0);
  });

  testWidgets(
      'WindowTitleBar renders at 390px without overflow and clear button updates via ValueListenableBuilder',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final shellController = ShellController();
    addTearDown(shellController.dispose);
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    var cleared = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildDarkTheme(),
        home: Scaffold(
          body: WindowTitleBar(
            shellController: shellController,
            searchController: searchController,
            onSearchChanged: (_) {},
            onClearSearch: () {
              cleared = true;
              searchController.clear();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip(AppStrings.clearSearchTooltip), findsNothing);

    await tester.enterText(find.byType(TextField), 'Nolan');
    await tester.pump();
    expect(find.byTooltip(AppStrings.clearSearchTooltip), findsOneWidget);

    await tester.tap(find.byTooltip(AppStrings.clearSearchTooltip));
    await tester.pump();
    expect(cleared, isTrue);
    expect(searchController.text, isEmpty);
    expect(find.byTooltip(AppStrings.clearSearchTooltip), findsNothing);

    // Escape clears active search text too
    await tester.enterText(find.byType(TextField), 'Andor');
    await tester.pump();
    expect(find.byTooltip(AppStrings.clearSearchTooltip), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(searchController.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'MediaTile & EpisodeRow show tag title/artist and fallback safely on missing image path',
      (tester) async {
    expect(
      LocalFileService.imageProviderForPath(r'Z:\non_existent\thumb.jpg'),
      isNotNull,
    );

    const card = MediaCardItem(
      mediaKey: 'series_1',
      mediaType: 'series',
      title: 'Universum',
      subtitle: 'Serie · 3 Episoden',
      imagePath: r'Z:\non_existent\poster.jpg',
      progressRatio: 0.0,
      remainingMinutes: 0,
      isCompleted: false,
      seriesId: 1,
      filePath: r'Z:\non_existent\ep1.mkv',
      artist: 'Prof. Harald Lesch',
    );

    const episode = EpisodeEntry(
      id: 1,
      seriesId: 1,
      seasonId: 1,
      seasonNumber: 1,
      episodeNumber: 2,
      title: 'Schwarze Loecher',
      filePath: r'Z:\non_existent\ep2.mkv',
      durationMs: 2700000,
      thumbPath: r'Z:\non_existent\ep2.jpg',
      positionMs: 0,
      isCompleted: false,
      artist: 'Prof. Harald Lesch',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildDarkTheme(),
        home: Scaffold(
          body: Column(
            children: [
              MediaTile(
                item: card,
                effectMode: EffectMode.lean,
                onTap: () {},
              ),
              EpisodeRow(
                episode: episode,
                onPlay: () {},
                onToggleWatched: () {},
              ),
            ],
          ),
        ),
      ),
    );

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(find.text('Universum'), findsOneWidget);
    expect(find.textContaining('Prof. Harald Lesch'), findsNWidgets(2));
    expect(find.text('2. Schwarze Loecher'), findsOneWidget);
    expect(find.textContaining('45 ${AppStrings.statsMinutesShort}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
