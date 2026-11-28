import 'package:flutter/foundation.dart';
import '../../core/services/desktop_platform_service.dart';

class ShellWindowDelegate {
  ShellWindowDelegate({required VoidCallback onChanged})
      : _onChanged = onChanged;

  final VoidCallback _onChanged;
  Object? _windowListenerToken;
  bool _isMaximized = false;

  bool get isMaximized => _isMaximized;

  void attachWindowListener({
    required Future<void> Function() onClose,
  }) {
    if (_windowListenerToken != null) return;
    _windowListenerToken = DesktopPlatformService.registerWindowCallbacks(
      onMaximize: onWindowMaximize,
      onUnmaximize: onWindowUnmaximize,
      onClose: onClose,
    );
  }

  void detachWindowListener() {
    if (_windowListenerToken == null) return;
    DesktopPlatformService.unregisterWindowCallbacks(_windowListenerToken);
    _windowListenerToken = null;
  }

  void onWindowMaximize() => _setMaximized(true);

  void onWindowUnmaximize() => _setMaximized(false);

  void _setMaximized(bool value) {
    if (_isMaximized == value) return;
    _isMaximized = value;
    _onChanged();
  }

  Future<void> startWindowDragging() =>
      DesktopPlatformService.startWindowDragging();

  Future<void> syncMaximizedState() async =>
      _setMaximized(await DesktopPlatformService.isWindowMaximized());

  Future<void> minimizeWindow() => DesktopPlatformService.minimizeWindow();

  Future<void> toggleMaximizeWindow() async {
    final nextMaximized = !(await DesktopPlatformService.isWindowMaximized());
    await (nextMaximized
        ? DesktopPlatformService.maximizeWindow()
        : DesktopPlatformService.unmaximizeWindow());
    _setMaximized(nextMaximized);
  }

  Future<void> closeWindow() => DesktopPlatformService.closeWindow();
}
