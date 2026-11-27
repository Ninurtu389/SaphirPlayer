import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saphir_player/core/constants/app_colors.dart';
import 'package:saphir_player/core/constants/app_spacing.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/controllers/library_controller.dart';
import 'package:saphir_player/core/controllers/settings_controller.dart';
import 'package:saphir_player/core/storage/progress_sync_service.dart';
import 'package:saphir_player/core/theme/app_theme.dart';
import 'package:saphir_player/core/theme/effect_mode.dart';
import 'package:saphir_player/features/home/home_controller.dart';
import 'package:saphir_player/features/home/home_view.dart';
import 'package:saphir_player/features/library/library_view.dart';
import 'package:saphir_player/features/player/saphir_player_controller.dart';
import 'package:saphir_player/features/shell/shell_controller.dart';
import 'package:saphir_player/features/shell/shell_view.dart';
import 'package:saphir_player/features/stats/stats_controller.dart';
import 'package:saphir_player/features/stats/stats_view.dart';
import '../helpers/mock_player.dart';
import '../helpers/test_fixtures.dart';

void main() {
  late TestEnv env;
  late ShellController shellController;
  late SettingsController settingsController;
  late LibraryController libraryController;
  late HomeController homeController;
  late StatsController statsController;
  late ProgressSyncService syncService;
  late FakePlayerHarness harness;
  late SaphirPlayerController playerController;

  setUp(() async {
    env = await TestEnv.create();
    shellController = ShellController();
    syncService = ProgressSyncService(env.dbService);
    settingsController =
        SettingsController(env.dbService, syncService: syncService);
    await settingsController.load();
    libraryController = LibraryController(env.dbService, settingsController);
    homeController = HomeController(env.dbService);
    statsController = StatsController(env.dbService);
    harness = FakePlayerHarness();
    playerController = SaphirPlayerController(
      env.dbService,
      syncService,
      () => settingsController.nasPaths,
      player: harness.player,
      videoController: harness.videoController,
      onSetFullScreen: harness.onSetFullScreen,
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

  Widget buildShellApp() {
    return MaterialApp(
      theme: AppTheme.buildDarkTheme(),
      home: ShellView(
        shellController: shellController,
        settingsController: settingsController,
        libraryController: libraryController,
        homeController: homeController,
        statsController: statsController,
        playerController: playerController,
      ),
    );
  }

  group('Empty states & Dark Theme consistency', () {
    testWidgets('HomeView, LibraryView, and StatsView show clear empty states',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildShellApp());
      await tester.pumpAndSettle();

      // Verify OLED dark theme
      final theme = AppTheme.buildDarkTheme();
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.oledBackground);

      // Home empty state
      expect(find.text(AppStrings.emptyHomeMessage), findsOneWidget);

      // Library empty state
      await tester.tap(find.text(AppStrings.libraryTab));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.emptyLibraryMessage), findsOneWidget);

      // Stats empty state
      await tester.tap(find.text(AppStrings.statsTab));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.statsEmptyMessage), findsOneWidget);
    });
  });

  group('ShellView navigation, search, and settings UX', () {
    testWidgets(
        'navigates all sections, adds/removes folder, toggles EffectMode, and handles DB reset dialog',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      seedSampleLibrary(env.dbService);
      libraryController.loadCountsFromCache();
      homeController.refreshHomeFeeds();
      statsController.refreshStats();

      await tester.pumpWidget(buildShellApp());
      await tester.pumpAndSettle();

      // Open Settings
      await tester.tap(find.text(AppStrings.settingsTab));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.noFoldersConfigured), findsOneWidget);

      // Enter folder path and submit
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == AppStrings.nasPathLabel,
        ),
        r'D:\TestMedien',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text(r'D:\TestMedien'), findsOneWidget);

      // Toggle EffectMode to lean
      await tester.tap(find.text(AppStrings.effectLeanLabel));
      await tester.pumpAndSettle();
      expect(settingsController.effectMode, EffectMode.lean);

      // Remove folder
      await tester.tap(find.byTooltip(AppStrings.removeFolderTooltip));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.noFoldersConfigured), findsOneWidget);

      // Open DB reset dialog and cancel
      await tester.ensureVisible(find.text(AppStrings.resetDatabaseButton));
      await tester.tap(find.text(AppStrings.resetDatabaseButton));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.resetDatabaseConfirmTitle), findsOneWidget);

      await tester.tap(find.text(AppStrings.cancelAction));
      await tester.pumpAndSettle();
      expect(libraryController.seriesCount, 2);

      // Confirm DB reset
      await tester.tap(find.text(AppStrings.resetDatabaseButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.resetDatabaseConfirmAction));
      await tester.pumpAndSettle();
      for (var i = 0; i < 60 && libraryController.seriesCount > 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(libraryController.seriesCount, 0);
      expect(find.text(AppStrings.databaseResetStatus), findsOneWidget);
    });

    testWidgets('global search navigates from Settings to Library and filters',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      seedSampleLibrary(env.dbService);
      libraryController.loadCountsFromCache();
      homeController.refreshHomeFeeds();

      await tester.pumpWidget(buildShellApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.settingsTab));
      await tester.pumpAndSettle();

      // Type in global search bar
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == AppStrings.searchHint,
        ),
        'Interstellar',
      );
      await tester.pump(
        const Duration(milliseconds: AppSpacing.searchDebounceMs + 20),
      );
      await tester.pumpAndSettle();

      expect(shellController.activeSection, AppSection.library);
      expect(
        find.descendant(
          of: find.byType(LibraryView),
          matching: find.text('Interstellar'),
        ),
        findsOneWidget,
      );
      expect(find.text('Dark'), findsNothing);
    });
  });

  group('Responsive layout & overflow checks across screen sizes', () {
    for (final size in [
      const Size(1280, 800), // Desktop
      const Size(800, 500), // Min Desktop
      const Size(768, 1024), // Tablet
      const Size(390, 844), // Compact Smartphone
    ]) {
      testWidgets('ShellView + HomeView renders without overflow at $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        seedSampleLibrary(env.dbService);
        libraryController.loadCountsFromCache();
        homeController.refreshHomeFeeds();

        await tester.pumpWidget(buildShellApp());
        await tester.pumpAndSettle();

        expect(find.byType(HomeView), findsOneWidget);
      });

      testWidgets('LibraryView & StatsView render without overflow at $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        seedSampleLibrary(env.dbService);
        libraryController.loadCountsFromCache();
        statsController.refreshStats();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.buildDarkTheme(),
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: LibraryView(
                      libraryController: libraryController,
                      effectMode: EffectMode.glass,
                      onSelectItem: (_) {},
                      onOpenSeries: (_) {},
                    ),
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
      });
    }
  });
}
