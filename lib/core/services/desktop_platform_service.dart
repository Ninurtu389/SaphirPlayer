import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';

class DesktopPlatformService {
  DesktopPlatformService._();

  static String get localHostname => Platform.localHostname;

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

  static Future<void> startWindowDragging() => windowManager.startDragging();

  static Future<void> setFullScreen(bool fullscreen) =>
      windowManager.setFullScreen(fullscreen);

  static Future<bool> isWindowMaximized() => windowManager.isMaximized();

  static Future<void> minimizeWindow() => windowManager.minimize();

  static Future<void> maximizeWindow() => windowManager.maximize();

  static Future<void> unmaximizeWindow() => windowManager.unmaximize();

  static Future<void> closeWindow() => windowManager.close();

  static Future<String?> pickSubtitleFile(String dialogTitle) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub'],
    );
    final path = picked?.path?.trim();
    return (path == null || path.isEmpty) ? null : path;
  }

  static Future<void> setAlwaysOnTop(bool value) =>
      windowManager.setAlwaysOnTop(value);

  static Future<Rect> getWindowBounds() => windowManager.getBounds();

  static Future<void> setWindowBounds(Rect bounds) =>
      windowManager.setBounds(bounds);

  static Future<void> setWindowMinimumSize(Size size) =>
      windowManager.setMinimumSize(size);

  static Future<void> resetWindowDefaults(
    Rect? bounds,
    Size minSize,
  ) async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMinimumSize(minSize);
    if (bounds != null) {
      await windowManager.setBounds(bounds);
    }
  }
}
