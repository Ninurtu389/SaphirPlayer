import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_spacing.dart';
import 'mpv_property_bridge.dart';
import 'player_models.dart';

class PlayerOverlaysController {
  PlayerOverlaysController({
    required IMpvPropertyBridge mpvBridge,
    required VoidCallback onChanged,
  })  : _mpvBridge = mpvBridge,
        _onChanged = onChanged;

  final IMpvPropertyBridge _mpvBridge;
  final VoidCallback _onChanged;

  Timer? _osdTimer;
  Timer? _hudHideTimer;
  Timer? _diagnosticsTimer;
  Timer? _sleepTimer;
  Timer? _sleepTicker;
  bool _isDisposed = false;
  bool _isHudVisible = true;
  bool _isMenuOrDialogOpen = false;
  int _diagnosticsGeneration = 0;
  int _sleepTimerGeneration = 0;

  String? _osdMessage;
  PlayerActionOsdKind? _osdKind;
  bool _showDiagnostics = false;
  PlayerDiagnostics? _diagnostics;
  bool _isEpisodeDrawerOpen = false;
  bool _isShortcutSheetOpen = false;
  SleepTimerOption _sleepTimerOption = SleepTimerOption.off;
  DateTime? _sleepEndsAt;
  Duration? _sleepTimerRemaining;

  String? get osdMessage => _osdMessage;
  PlayerActionOsdKind? get osdKind => _osdKind;
  bool get isHudVisible => _isHudVisible;
  bool get showDiagnostics => _showDiagnostics;
  PlayerDiagnostics? get diagnostics => _diagnostics;
  bool get isEpisodeDrawerOpen => _isEpisodeDrawerOpen;
  bool get isShortcutSheetOpen => _isShortcutSheetOpen;
  SleepTimerOption get sleepTimerOption => _sleepTimerOption;
  Duration? get sleepTimerRemaining => _sleepTimerRemaining;
  bool get hasOpenOverlay =>
      _isShortcutSheetOpen || _isEpisodeDrawerOpen || _showDiagnostics;

  void showActionOsd(PlayerActionOsdKind kind, String message) {
    if (_isDisposed) return;
    _osdTimer?.cancel();
    _osdKind = kind;
    _osdMessage = message;
    _onChanged();
    _osdTimer = Timer(
      const Duration(milliseconds: AppSpacing.osdDurationMs),
      () {
        if (_isDisposed) return;
        _osdMessage = null;
        _osdKind = null;
        _onChanged();
      },
    );
  }

  void clearOsd() {
    _osdTimer?.cancel();
    _osdTimer = null;
    _osdMessage = null;
    _osdKind = null;
  }

  void toggleDiagnostics() {
    if (_isDisposed) return;
    _showDiagnostics = !_showDiagnostics;
    if (_showDiagnostics) {
      _diagnosticsGeneration++;
      unawaited(_pollDiagnostics());
      _diagnosticsTimer?.cancel();
      _diagnosticsTimer = Timer.periodic(
        const Duration(seconds: AppSpacing.diagnosticsPollSeconds),
        (_) => unawaited(_pollDiagnostics()),
      );
    } else {
      stopDiagnostics();
    }
    _onChanged();
  }

  Future<void> _pollDiagnostics() async {
    final gen = _diagnosticsGeneration;
    try {
      final diag = await _mpvBridge.readDiagnostics();
      if (_isDisposed || !_showDiagnostics || gen != _diagnosticsGeneration) {
        return;
      }
      _diagnostics = diag;
      _onChanged();
    } catch (_) {
      // Diagnose-Abruf ist optional und darf keinen Wiedergabeabbruch auslösen.
    }
  }

  void stopDiagnostics() {
    _showDiagnostics = false;
    _diagnosticsGeneration++;
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;
  }

  void toggleEpisodeDrawer() {
    if (_isDisposed) return;
    _isEpisodeDrawerOpen = !_isEpisodeDrawerOpen;
    if (_isEpisodeDrawerOpen) {
      _isShortcutSheetOpen = false;
    }
    _onChanged();
  }

  void closeEpisodeDrawer() {
    if (_isEpisodeDrawerOpen) {
      _isEpisodeDrawerOpen = false;
      _onChanged();
    }
  }

  void toggleShortcutSheet() {
    if (_isDisposed) return;
    _isShortcutSheetOpen = !_isShortcutSheetOpen;
    if (_isShortcutSheetOpen) {
      _isEpisodeDrawerOpen = false;
    }
    _onChanged();
  }

  bool closeTopOverlay() {
    if (_isShortcutSheetOpen) {
      _isShortcutSheetOpen = false;
      _onChanged();
      return true;
    }
    if (_isEpisodeDrawerOpen) {
      _isEpisodeDrawerOpen = false;
      _onChanged();
      return true;
    }
    if (_showDiagnostics) {
      stopDiagnostics();
      _onChanged();
      return true;
    }
    return false;
  }

  void setSleepTimer(
    SleepTimerOption option, {
    Duration? customDuration,
    required Future<void> Function() onExpired,
  }) {
    if (_isDisposed) return;
    cancelSleepTimer(notify: false);
    _sleepTimerOption = option;
    final sleepGen = _sleepTimerGeneration;

    if (option == SleepTimerOption.off ||
        option == SleepTimerOption.endOfEpisode) {
      _onChanged();
      return;
    }

    final duration = customDuration ??
        Duration(
          minutes: option == SleepTimerOption.minutes30
              ? AppSpacing.sleepTimer30Minutes
              : AppSpacing.sleepTimer60Minutes,
        );
    _sleepEndsAt = DateTime.now().add(duration);
    _sleepTimerRemaining = duration;

    _sleepTimer = Timer(duration, () async {
      if (_isDisposed || sleepGen != _sleepTimerGeneration) {
        return;
      }
      cancelSleepTimer(notify: false);
      await onExpired();
      if (_isDisposed) {
        return;
      }
      _onChanged();
    });

    _sleepTicker = Timer.periodic(
      const Duration(seconds: AppSpacing.sleepTimerTickSeconds),
      (_) {
        if (_isDisposed || sleepGen != _sleepTimerGeneration) {
          return;
        }
        final endsAt = _sleepEndsAt;
        if (endsAt == null) {
          return;
        }
        final left = endsAt.difference(DateTime.now());
        _sleepTimerRemaining = left.isNegative ? Duration.zero : left;
        _onChanged();
      },
    );
    _onChanged();
  }

  void cancelSleepTimer({bool notify = true}) {
    _sleepTimerGeneration++;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepTimerOption = SleepTimerOption.off;
    _sleepEndsAt = null;
    _sleepTimerRemaining = null;
    if (notify && !_isDisposed) {
      _onChanged();
    }
  }

  void setMenuOrDialogOpen(bool open, {required bool isPlaying}) {
    _isMenuOrDialogOpen = open;
    if (open) {
      _hudHideTimer?.cancel();
      _isHudVisible = true;
      _onChanged();
    } else {
      registerUserActivity(isPlaying: isPlaying);
    }
  }

  void registerUserActivity({required bool isPlaying}) =>
      showHud(isPlaying: isPlaying, keepVisibleWhilePaused: !isPlaying);

  void showHud({required bool isPlaying, bool keepVisibleWhilePaused = false}) {
    if (_isDisposed) return;
    if (!_isHudVisible) {
      _isHudVisible = true;
      _onChanged();
    }
    _hudHideTimer?.cancel();
    if (keepVisibleWhilePaused || _isMenuOrDialogOpen) return;
    _hudHideTimer = Timer(
      const Duration(seconds: AppSpacing.hudAutoHideSeconds),
      () {
        if (!_isDisposed &&
            isPlaying &&
            _isHudVisible &&
            !_isMenuOrDialogOpen) {
          _isHudVisible = false;
          _onChanged();
        }
      },
    );
  }

  void resetForEntry() {
    clearOsd();
    _diagnostics = null;
    _diagnosticsGeneration++;
    if (_showDiagnostics && !_isDisposed) {
      unawaited(_pollDiagnostics());
    }
  }

  void resetForClose() {
    _isMenuOrDialogOpen = false;
    _hudHideTimer?.cancel();
    _hudHideTimer = null;
    clearOsd();
    stopDiagnostics();
    _diagnostics = null;
    _isEpisodeDrawerOpen = false;
    _isShortcutSheetOpen = false;
    cancelSleepTimer(notify: false);
  }

  void dispose() {
    _isDisposed = true;
    resetForClose();
  }
}
