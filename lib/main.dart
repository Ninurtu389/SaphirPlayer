import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/constants/app_colors.dart';
import 'core/constants/app_spacing.dart';
import 'core/constants/app_strings.dart';
import 'core/controllers/library_controller.dart';
import 'core/controllers/settings_controller.dart';
import 'core/services/desktop_platform_service.dart';
import 'core/storage/database_backup_service.dart';
import 'core/storage/database_service.dart';
import 'core/storage/portable_paths.dart';
import 'core/storage/progress_sync_service.dart';
import 'core/storage/thumbnail_cache_service.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_controller.dart';
import 'features/player/saphir_player_controller.dart';
import 'features/scanner/nas_scanner_service.dart';
import 'features/scanner/thumbnail_queue_service.dart';
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

  StorageLayout? storageLayout;
  DatabaseService? databaseService;
  Object? startupError;
  var windowShown = false;

  try {
    final layout = await PortablePaths.initialize();
    storageLayout = layout;

    if (layout.hasLegacyMigrationCandidate) {
      final decision = Completer<bool>();
      runApp(
        _LegacyMigrationApp(
          sourcePath: layout.legacyPortableDbPath!,
          targetPath: layout.databaseFilePath,
          onDecision: (shouldMigrate) {
            if (!decision.isCompleted) {
              decision.complete(shouldMigrate);
            }
          },
        ),
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      windowShown = true;

      final shouldMigrate = await decision.future;
      if (shouldMigrate) {
        await PortablePaths.migrateLegacyDatabase(layout);
      }
    }

    final db = DatabaseService(storageLayout: layout);
    await db.open();
    databaseService = db;
  } catch (error) {
    startupError = error;
  }

  if (startupError != null ||
      storageLayout == null ||
      databaseService == null) {
    runApp(_StartupErrorApp(errorDetail: '${startupError ?? ''}'));
    if (!windowShown) {
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
    return;
  }

  final syncService =
      ProgressSyncService(databaseService, storageLayout: storageLayout);
  final thumbnailGate = ThumbnailOperationGate();
  final cacheService = ThumbnailCacheService(
    storageLayout: storageLayout,
    gate: thumbnailGate,
  );
  final backupService = DatabaseBackupService(storageLayout: storageLayout);
  final settingsController = SettingsController(
    databaseService,
    syncService: syncService,
    cacheService: cacheService,
    backupService: backupService,
    thumbnailGate: thumbnailGate,
    storageLayout: storageLayout,
  );
  await settingsController.load();

  final thumbnailQueue = ThumbnailQueueService(
    databaseService,
    gate: thumbnailGate,
  );
  thumbnailQueue.recoverStaleProcessingJobs();

  final libraryController = LibraryController(
    databaseService,
    settingsController,
    scannerService: NasScannerService(
      databaseService,
      thumbnailGate: thumbnailGate,
      thumbnailQueue: thumbnailQueue,
    ),
  );
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
  shellController.initializeStartupState();
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

  Future<void> configureWindow() async {
    try {
      await DesktopPlatformService.setPreventClose(true);
      await shellController.syncMaximizedState();
    } catch (_) {}
  }

  if (!windowShown) {
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await configureWindow();
      await windowManager.show();
      await windowManager.focus();
    });
  } else {
    await configureWindow();
  }

  unawaited(
    shellController.runStartupSync(
      onPostSyncThumbnailBatch: () => thumbnailQueue.processNextBatch(),
    ),
  );
}

class _LegacyMigrationApp extends StatefulWidget {
  const _LegacyMigrationApp({
    required this.sourcePath,
    required this.targetPath,
    required this.onDecision,
  });

  final String sourcePath;
  final String targetPath;
  final ValueChanged<bool> onDecision;

  @override
  State<_LegacyMigrationApp> createState() => _LegacyMigrationAppState();
}

class _LegacyMigrationAppState extends State<_LegacyMigrationApp> {
  bool _submitting = false;

  void _choose(bool migrate) {
    if (_submitting) return;
    setState(() => _submitting = true);
    widget.onDecision(migrate);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.maxSettingsWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.anthraciteSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.legacyMigrationTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      AppStrings.legacyMigrationMessage,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '${AppStrings.legacyMigrationSourceLabel}: ${widget.sourcePath}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${AppStrings.legacyMigrationTargetLabel}: ${widget.targetPath}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _submitting ? null : () => _choose(false),
                          child:
                              const Text(AppStrings.legacyMigrationSkipButton),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ElevatedButton(
                          onPressed: _submitting ? null : () => _choose(true),
                          child: const Text(
                            AppStrings.legacyMigrationImportButton,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
