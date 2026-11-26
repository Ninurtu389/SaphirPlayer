import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'core/constants/app_spacing.dart';
import 'core/constants/app_strings.dart';
import 'core/controllers/settings_controller.dart';
import 'core/storage/database_service.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/shell_controller.dart';
import 'features/shell/shell_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  final shellController = ShellController();
  await shellController.syncMaximizedState();

  runApp(
    SaphirPlayerApp(
      shellController: shellController,
      settingsController: settingsController,
    ),
  );
}

class SaphirPlayerApp extends StatelessWidget {
  const SaphirPlayerApp({
    super.key,
    required this.shellController,
    required this.settingsController,
  });

  final ShellController shellController;
  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildDarkTheme(),
      home: ShellView(
        shellController: shellController,
        settingsController: settingsController,
      ),
    );
  }
}
