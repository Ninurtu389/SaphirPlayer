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
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(AppSpacing.defaultWindowWidth, AppSpacing.defaultWindowHeight),
    minimumSize: Size(AppSpacing.minWindowWidth, AppSpacing.minWindowHeight),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    title: AppStrings.appTitle,
  );

  final databaseService = DatabaseService();
  Object? startupError;

  try {
    await PortablePaths.warmUp();
    await databaseService.open();
  } catch (error) {
    startupError = error;
  }

  if (startupError != null) {
    runApp(_StartupErrorApp(errorDetail: startupError.toString()));
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    return;
  }

  final syncService = ProgressSyncService(databaseService);
  final settingsController =
      SettingsController(databaseService, syncService: syncService);
  try {
    await settingsController.load();
  } catch (_) {}

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
  shellController.attachWindowListener();

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

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    try {
      await DesktopPlatformService.setPreventClose(true);
      await shellController.syncMaximizedState();
    } catch (_) {}
    await windowManager.show();
    await windowManager.focus();
  });

  unawaited(
    settingsController.syncProgress().then((_) {
      if (!databaseService.isOpen || shellController.isClosing) return;
      libraryController.loadCountsFromCache();
      homeController.refreshHomeFeeds();
      statsController.refreshStats();
    }),
  );
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.errorDetail});

  final String errorDetail;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.startupErrorTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppStrings.startupErrorMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                SelectableText(
                  errorDetail,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
