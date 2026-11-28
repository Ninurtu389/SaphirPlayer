import 'dart:async';
import 'dart:io';
import '../../core/constants/app_spacing.dart';

/// Zentrale Erfassung laufender Kindprozesse (FFmpeg/FFprobe), um beim Pause-
/// oder Shutdown-Fall deterministisch alle Prozesse zu beenden.
class ActiveProcessRegistry {
  ActiveProcessRegistry._();

  static final Set<Process> _activeProcesses = <Process>{};

  static int get activeCount => _activeProcesses.length;

  static void register(Process process) {
    _activeProcesses.add(process);
  }

  static void unregister(Process process) {
    _activeProcesses.remove(process);
  }

  static void killAllImmediate() {
    for (final process in _activeProcesses.toList()) {
      try {
        process.kill();
      } catch (_) {
        // Prozess möglicherweise bereits beendet
      }
    }
    _activeProcesses.clear();
  }

  /// Beendet alle aktiven Prozesse: zuerst graceful, danach per Hard-Kill und
  /// wartet auf bestätigtes `exitCode`. Gibt die Zahl noch nicht beendeter
  /// Prozesse zurück (`0` im Normalfall).
  static Future<int> terminateAll({
    Duration gracePeriod = const Duration(
      milliseconds: AppSpacing.shutdownProcessGraceMs,
    ),
    Duration hardKillTimeout = const Duration(
      milliseconds: AppSpacing.shutdownProcessKillTimeoutMs,
    ),
  }) async {
    final snapshot = _activeProcesses.toList();
    if (snapshot.isEmpty) {
      return 0;
    }

    var remaining = 0;
    for (final process in snapshot) {
      final exited = await _terminateSingle(
        process,
        gracePeriod: gracePeriod,
        hardKillTimeout: hardKillTimeout,
      );
      if (exited) {
        _activeProcesses.remove(process);
      } else {
        remaining++;
      }
    }
    return remaining;
  }

  static Future<bool> _terminateSingle(
    Process process, {
    required Duration gracePeriod,
    required Duration hardKillTimeout,
  }) async {
    try {
      process.kill(ProcessSignal.sigterm);
    } catch (_) {
      try {
        process.kill();
      } catch (_) {}
    }

    if (await _waitForExit(process, gracePeriod)) {
      return true;
    }

    try {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {
      try {
        process.kill();
      } catch (_) {}
    }

    return _waitForExit(process, hardKillTimeout);
  }

  static Future<bool> _waitForExit(Process process, Duration timeout) async {
    try {
      await process.exitCode.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return true;
    }
  }
}
