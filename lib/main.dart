import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/constants/app_strings.dart';
import 'core/controllers/library_controller.dart';
import 'core/controllers/settings_controller.dart';
import 'core/storage/database_service.dart';
import 'core/storage/progress_sync_service.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_controller.dart';
import 'features/player/saphir_player_controller.dart';
import 'features/shell/shell_controller.dart';
import 'features/shell/shell_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(800, 500),
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

  final settingsController = SettingsController(databaseService);
  await settingsController.load();

  final syncService = ProgressSyncService(databaseService);
  await syncService.syncWithRoots(settingsController.nasPaths);

  final libraryController =
      LibraryController(databaseService, settingsController);
  libraryController.loadCountsFromCache();

  final homeController = HomeController(databaseService);
  homeController.refreshHomeFeeds();

  final playerController = SaphirPlayerController(
    databaseService,
    syncService,
    () => settingsController.nasPath,
  );

  final shellController = ShellController();
  await shellController.syncMaximizedState();

  runApp(
    SaphirPlayerApp(
      shellController: shellController,
      settingsController: settingsController,
      libraryController: libraryController,
      homeController: homeController,
      playerController: playerController,
      syncService: syncService,
    ),
  );
}

class SaphirPlayerApp extends StatelessWidget {
  const SaphirPlayerApp({
    super.key,
    required this.shellController,
    required this.settingsController,
    required this.libraryController,
    required this.homeController,
    required this.playerController,
    required this.syncService,
  });

  final ShellController shellController;
  final SettingsController settingsController;
  final LibraryController libraryController;
  final HomeController homeController;
  final SaphirPlayerController playerController;
  final ProgressSyncService syncService;

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
        playerController: playerController,
        syncService: syncService,
      ),
    );
  }
}
