import 'package:flutter/foundation.dart';
import '../../core/services/desktop_platform_service.dart';
import '../library/library_models.dart';
import '../player/playback_session.dart';

enum AppSection {
  home,
  library,
  stats,
  settings,
}

class ShellController extends ChangeNotifier {
  AppSection _activeSection = AppSection.home;
  bool _isMaximized = false;
  SeriesDetailData? _selectedSeriesDetail;
  PlaybackSession? _activePlaybackSession;

  AppSection get activeSection => _activeSection;
  bool get isMaximized => _isMaximized;
  SeriesDetailData? get selectedSeriesDetail => _selectedSeriesDetail;
  PlaybackSession? get activePlaybackSession => _activePlaybackSession;
  bool get isPlayerOpen => _activePlaybackSession != null;

  void selectSection(AppSection section) {
    _selectedSeriesDetail = null;
    if (_activeSection == section) {
      notifyListeners();
      return;
    }
    _activeSection = section;
    notifyListeners();
  }

  void openSeriesDetail(SeriesDetailData detail) {
    _selectedSeriesDetail = detail;
    notifyListeners();
  }

  void closeSeriesDetail() {
    _selectedSeriesDetail = null;
    notifyListeners();
  }

  void openPlaybackSession(PlaybackSession session) {
    _activePlaybackSession = session;
    notifyListeners();
  }

  void closePlaybackSession() {
    _activePlaybackSession = null;
    notifyListeners();
  }

  Future<void> startWindowDragging() =>
      DesktopPlatformService.startWindowDragging();

  Future<void> syncMaximizedState() async {
    _isMaximized = await DesktopPlatformService.isWindowMaximized();
    notifyListeners();
  }

  Future<void> minimizeWindow() async {
    await DesktopPlatformService.minimizeWindow();
  }

  Future<void> toggleMaximizeWindow() async {
    final maximized = await DesktopPlatformService.isWindowMaximized();
    if (maximized) {
      await DesktopPlatformService.unmaximizeWindow();
    } else {
      await DesktopPlatformService.maximizeWindow();
    }
    _isMaximized = !maximized;
    notifyListeners();
  }

  Future<void> closeWindow() async {
    await DesktopPlatformService.closeWindow();
  }
}
