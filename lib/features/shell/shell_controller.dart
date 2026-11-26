import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

enum AppSection {
  home,
  library,
  settings,
}

class ShellController extends ChangeNotifier {
  AppSection _activeSection = AppSection.home;
  bool _isMaximized = false;

  AppSection get activeSection => _activeSection;
  bool get isMaximized => _isMaximized;

  void selectSection(AppSection section) {
    if (_activeSection == section) {
      return;
    }
    _activeSection = section;
    notifyListeners();
  }

  Future<void> syncMaximizedState() async {
    _isMaximized = await windowManager.isMaximized();
    notifyListeners();
  }

  Future<void> minimizeWindow() async {
    await windowManager.minimize();
  }

  Future<void> toggleMaximizeWindow() async {
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    _isMaximized = !maximized;
    notifyListeners();
  }

  Future<void> closeWindow() async {
    await windowManager.close();
  }
}
