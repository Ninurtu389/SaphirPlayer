import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/constants/app_spacing.dart';
import 'core/constants/app_strings.dart';
import 'core/controllers/library_controller.dart';
import 'core/controllers/settings_controller.dart';
import 'core/services/desktop_platform_service.dart';
import 'core/storage/database_service.dart';
import 'core/storage/portable_paths.dart';
import 'core/storage/progress_sync_service.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_controller.dart';
import 'features/player/saphir_player_controller.dart';
import 'features/shell/shell_controller.dart';
import 'features/shell/shell_view.dart';
import 'features/stats/stats_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await PortablePaths.warmUp();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(AppSpacing.defaultWindowWidth, AppSpacing.defaultWindowHeight),
    minimumSize: Size(AppSpacing.minWindowWidth, AppSpacing.minWindowHeight),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    title: AppStrings.appTitle,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final databaseService = DatabaseService();
  await databaseService.open();

  final syncService = ProgressSyncService(databaseService);
  final settingsController =
      SettingsController(databaseService, syncService: syncService);
  await settingsController.load();

  final libraryController =
      LibraryController(databaseService, settingsController);
  libraryController.loadCountsFromCache();

  final homeController = HomeController(databaseService);
  homeController.refreshHomeFeeds();

  final statsController = StatsController(databaseService);
  statsController.refreshStats();

  final playerController = SaphirPlayerController(
    databaseService,
    syncService,
    () => settingsController.nasPaths,
    settingsController: settingsController,
  );

  final shellController = ShellController(
    settingsController: settingsController,
    libraryController: libraryController,
    homeController: homeController,
    statsController: statsController,
    playerController: playerController,
    databaseService: databaseService,
  );
  await DesktopPlatformService.setPreventClose(true);
  shellController.attachWindowListener();
  await shellController.syncMaximizedState();

  runApp(
    SaphirPlayerApp(
      shellController: shellController,
      settingsController: settingsController,
      libraryController: libraryController,
      homeController: homeController,
      statsController: statsController,
      playerController: playerController,
    ),
  );

  unawaited(
    settingsController.syncProgress().then((_) {
      if (!databaseService.isOpen) return;
      libraryController.loadCountsFromCache();
      homeController.refreshHomeFeeds();
      statsController.refreshStats();
    }),
  );
}

class SaphirPlayerApp extends StatelessWidget {
  const SaphirPlayerApp({
    super.key,
    required this.shellController,
    required this.settingsController,
    required this.libraryController,
    required this.homeController,
    required this.statsController,
    required this.playerController,
  });

  final ShellController shellController;
  final SettingsController settingsController;
  final LibraryController libraryController;
  final HomeController homeController;
  final StatsController statsController;
  final SaphirPlayerController playerController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
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
}
