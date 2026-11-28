import 'dart:ui';
import '../../core/services/desktop_platform_service.dart';

class PlayerChapter {
  const PlayerChapter({
    required this.index,
    required this.title,
    required this.startMs,
  });

  final int index;
  final String title;
  final int startMs;
}

class MediaBookmark {
  const MediaBookmark({
    required this.id,
    required this.mediaKey,
    required this.positionMs,
    required this.label,
    required this.createdAt,
  });

  final int id;
  final String mediaKey;
  final int positionMs;
  final String label;
  final int createdAt;
}

class PlayerDiagnostics {
  const PlayerDiagnostics({
    required this.videoCodec,
    required this.audioCodec,
    required this.resolution,
    required this.fps,
    required this.hwdec,
  });

  final String videoCodec;
  final String audioCodec;
  final String resolution;
  final String fps;
  final String hwdec;
}

enum TimeDisplayMode {
  total,
  remaining,
  finishTime,
}

enum VideoAspectMode {
  original,
  fillCrop,
  ratio16x9,
  ratio21x9,
}

enum SleepTimerOption {
  off,
  endOfEpisode,
  minutes30,
  minutes60,
}

enum PlayerActionOsdKind {
  volume,
  mute,
  seekBack,
  seekForward,
  speed,
  aspectMode,
  screenshot,
  bookmark,
  audioDelay,
  subtitleDelay,
  nightMode,
  volumeBoost,
  sleepTimer,
  frameStep,
  chapter,
  introSkip,
  subtitle,
  error,
}

class PlayerWindowAdapter {
  const PlayerWindowAdapter({
    Future<void> Function(bool fullscreen)? setFullScreen,
    Future<void> Function(bool alwaysOnTop)? setAlwaysOnTop,
    Future<Rect> Function()? getWindowBounds,
    Future<void> Function(Rect bounds)? setWindowBounds,
    Future<void> Function(Size size)? setWindowMinimumSize,
    Future<bool> Function()? isWindowMaximized,
    Future<void> Function()? unmaximizeWindow,
    Future<void> Function()? maximizeWindow,
    Future<String?> Function(String dialogTitle)? pickSubtitleFile,
    Future<void> Function()? startWindowDragging,
  })  : _setFullScreen = setFullScreen,
        _setAlwaysOnTop = setAlwaysOnTop,
        _getWindowBounds = getWindowBounds,
        _setWindowBounds = setWindowBounds,
        _setWindowMinimumSize = setWindowMinimumSize,
        _isWindowMaximized = isWindowMaximized,
        _unmaximizeWindow = unmaximizeWindow,
        _maximizeWindow = maximizeWindow,
        _pickSubtitleFile = pickSubtitleFile,
        _startWindowDragging = startWindowDragging;

  final Future<void> Function(bool fullscreen)? _setFullScreen;
  final Future<void> Function(bool alwaysOnTop)? _setAlwaysOnTop;
  final Future<Rect> Function()? _getWindowBounds;
  final Future<void> Function(Rect bounds)? _setWindowBounds;
  final Future<void> Function(Size size)? _setWindowMinimumSize;
  final Future<bool> Function()? _isWindowMaximized;
  final Future<void> Function()? _unmaximizeWindow;
  final Future<void> Function()? _maximizeWindow;
  final Future<String?> Function(String dialogTitle)? _pickSubtitleFile;
  final Future<void> Function()? _startWindowDragging;

  Future<void> setFullScreen(bool fullscreen) =>
      (_setFullScreen ?? DesktopPlatformService.setFullScreen)(fullscreen);

  Future<void> setAlwaysOnTop(bool alwaysOnTop) =>
      (_setAlwaysOnTop ?? DesktopPlatformService.setAlwaysOnTop)(alwaysOnTop);

  Future<Rect> getWindowBounds() =>
      (_getWindowBounds ?? DesktopPlatformService.getWindowBounds)();

  Future<void> setWindowBounds(Rect bounds) =>
      (_setWindowBounds ?? DesktopPlatformService.setWindowBounds)(bounds);

  Future<void> setWindowMinimumSize(Size size) =>
      (_setWindowMinimumSize ?? DesktopPlatformService.setWindowMinimumSize)(
        size,
      );

  Future<bool> isWindowMaximized() =>
      (_isWindowMaximized ?? DesktopPlatformService.isWindowMaximized)();

  Future<void> unmaximizeWindow() =>
      (_unmaximizeWindow ?? DesktopPlatformService.unmaximizeWindow)();

  Future<void> maximizeWindow() =>
      (_maximizeWindow ?? DesktopPlatformService.maximizeWindow)();

  Future<String?> pickSubtitleFile(String dialogTitle) =>
      (_pickSubtitleFile ?? DesktopPlatformService.pickSubtitleFile)(
        dialogTitle,
      );

  Future<void> startWindowDragging() =>
      (_startWindowDragging ?? DesktopPlatformService.startWindowDragging)();
}
