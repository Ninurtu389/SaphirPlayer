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
  Timer? _diagnosticsTimer;
  Timer? _sleepTimer;
  Timer? _sleepTicker;

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
  bool get showDiagnostics => _showDiagnostics;
  PlayerDiagnostics? get diagnostics => _diagnostics;
  bool get isEpisodeDrawerOpen => _isEpisodeDrawerOpen;
  bool get isShortcutSheetOpen => _isShortcutSheetOpen;
  SleepTimerOption get sleepTimerOption => _sleepTimerOption;
  Duration? get sleepTimerRemaining => _sleepTimerRemaining;
  bool get hasOpenOverlay =>
      _isShortcutSheetOpen || _isEpisodeDrawerOpen || _showDiagnostics;

  void showActionOsd(PlayerActionOsdKind kind, String message) {
    _osdTimer?.cancel();
    _osdKind = kind;
    _osdMessage = message;
    _onChanged();
    _osdTimer = Timer(
      const Duration(milliseconds: AppSpacing.osdDurationMs),
      () {
        _osdMessage = null;
        _osdKind = null;
        _onChanged();
      },
    );
  }

  void toggleDiagnostics() {
    _showDiagnostics = !_showDiagnostics;
    if (_showDiagnostics) {
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
    final diag = await _mpvBridge.readDiagnostics();
    if (!_showDiagnostics) {
      return;
    }
    _diagnostics = diag;
    _onChanged();
  }

  void stopDiagnostics() {
    _showDiagnostics = false;
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;
  }

  void toggleEpisodeDrawer() {
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
    cancelSleepTimer(notify: false);
    _sleepTimerOption = option;

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
      cancelSleepTimer(notify: false);
      await onExpired();
      _onChanged();
    });

    _sleepTicker = Timer.periodic(
      const Duration(seconds: AppSpacing.sleepTimerTickSeconds),
      (_) {
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
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepTimerOption = SleepTimerOption.off;
    _sleepEndsAt = null;
    _sleepTimerRemaining = null;
    if (notify) {
      _onChanged();
    }
  }

  void resetForClose() {
    _osdTimer?.cancel();
    _osdTimer = null;
    _osdMessage = null;
    _osdKind = null;
    stopDiagnostics();
    _isEpisodeDrawerOpen = false;
    _isShortcutSheetOpen = false;
    cancelSleepTimer(notify: false);
  }

  void dispose() {
    resetForClose();
  }
}
