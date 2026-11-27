import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';

class DesktopPlatformService {
  DesktopPlatformService._();

  static String get localHostname => Platform.localHostname;

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<String?> pickMediaDirectory(String dialogTitle) async {
    final selectedUri = await FilePicker.pickDirectory(
      dialogTitle: dialogTitle,
    );
    if (selectedUri == null) {
      return null;
    }
    final selectedDirectory = selectedUri.isScheme('file')
        ? selectedUri.toFilePath(windows: Platform.isWindows)
        : selectedUri.toString();
    final trimmed = selectedDirectory.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Future<String?> pickSubtitleFile(String dialogTitle) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub'],
    );
    final path = picked?.path?.trim();
    return (path == null || path.isEmpty) ? null : path;
  }

  static Object? registerWindowCallbacks({
    required VoidCallback onMaximize,
    required VoidCallback onUnmaximize,
    required Future<void> Function() onClose,
  }) {
    if (!_isDesktop) return null;
    final listener = _PlatformWindowListener(
      onMaximize: onMaximize,
      onUnmaximize: onUnmaximize,
      onClose: onClose,
    );
    windowManager.addListener(listener);
    return listener;
  }

  static void unregisterWindowCallbacks(Object? token) {
    if (_isDesktop && token is WindowListener) {
      windowManager.removeListener(token);
    }
  }

  static Future<void> setPreventClose(bool preventClose) async {
    if (_isDesktop) {
      await windowManager.setPreventClose(preventClose);
    }
  }

  static Future<void> destroyWindow() async {
    if (_isDesktop) {
      await windowManager.destroy();
    }
  }

  static Future<void> startWindowDragging() async {
    if (_isDesktop) {
      await windowManager.startDragging();
    }
  }

  static Future<void> setFullScreen(bool fullscreen) async {
    if (_isDesktop) {
      await windowManager.setFullScreen(fullscreen);
    }
  }

  static Future<bool> isWindowMaximized() async {
    if (!_isDesktop) return false;
    return windowManager.isMaximized();
  }

  static Future<void> minimizeWindow() async {
    if (_isDesktop) {
      await windowManager.minimize();
    }
  }

  static Future<void> maximizeWindow() async {
    if (_isDesktop) {
      await windowManager.maximize();
    }
  }

  static Future<void> unmaximizeWindow() async {
    if (_isDesktop) {
      await windowManager.unmaximize();
    }
  }

  static Future<void> closeWindow() async {
    if (_isDesktop) {
      await windowManager.close();
    }
  }

  static Future<void> setAlwaysOnTop(bool value) async {
    if (_isDesktop) {
      await windowManager.setAlwaysOnTop(value);
    }
  }

  static Future<Rect> getWindowBounds() async {
    if (!_isDesktop) return Rect.zero;
    return windowManager.getBounds();
  }

  static Future<void> setWindowBounds(Rect bounds) async {
    if (_isDesktop) {
      await windowManager.setBounds(bounds);
    }
  }

  static Future<void> setWindowMinimumSize(Size size) async {
    if (_isDesktop) {
      await windowManager.setMinimumSize(size);
    }
  }
}

class _PlatformWindowListener with WindowListener {
  _PlatformWindowListener({
    required this.onMaximize,
    required this.onUnmaximize,
    required this.onClose,
  });

  final VoidCallback onMaximize;
  final VoidCallback onUnmaximize;
  final Future<void> Function() onClose;

  @override
  void onWindowMaximize() => onMaximize();

  @override
  void onWindowUnmaximize() => onUnmaximize();

  @override
  void onWindowClose() {
    onClose();
  }
}
