import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/controllers/library_controller.dart';
import '../../core/controllers/settings_controller.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/progress_sync_service.dart';
import '../player/saphir_player_controller.dart';
import '../scanner/active_process_registry.dart';

enum ShutdownPhase {
  idle,
  blockingInputs,
  stoppingPlayer,
  stoppingWorkers,
  syncing,
  closingDatabase,
  destroyingWindow,
  completed,
  forcedExit,
}

enum ShutdownStepOutcome {
  skipped,
  completed,
  timedOut,
  cancelled,
  failed,
}

class ShutdownTimeouts {
  const ShutdownTimeouts({
    this.playerDispose = const Duration(
      milliseconds: AppSpacing.shutdownPlayerDisposeTimeoutMs,
    ),
    this.scanStop = const Duration(
      milliseconds: AppSpacing.shutdownScanStopTimeoutMs,
    ),
    this.sync = const Duration(
      milliseconds: AppSpacing.shutdownSyncTimeoutMs,
    ),
    this.syncCancelGrace = const Duration(
      milliseconds: AppSpacing.shutdownSyncCancelGraceMs,
    ),
    this.nativeDrainDelay = const Duration(
      milliseconds: AppSpacing.shutdownNativeDrainDelayMs,
    ),
    this.processGracePeriod = const Duration(
      milliseconds: AppSpacing.shutdownProcessGraceMs,
    ),
    this.processKillTimeout = const Duration(
      milliseconds: AppSpacing.shutdownProcessKillTimeoutMs,
    ),
  });

  final Duration playerDispose;
  final Duration scanStop;
  final Duration sync;
  final Duration syncCancelGrace;
  final Duration nativeDrainDelay;
  final Duration processGracePeriod;
  final Duration processKillTimeout;
}

class ShutdownReport {
  const ShutdownReport({
    required this.finalPhase,
    required this.playerOutcome,
    required this.scanOutcome,
    required this.processTerminationRemaining,
    required this.syncOutcome,
    this.syncResultStatus,
    required this.databaseClosed,
    required this.usedForceExit,
    this.pendingTasks = const [],
    this.diagnosticLog = const [],
  });

  final ShutdownPhase finalPhase;
  final ShutdownStepOutcome playerOutcome;
  final ShutdownStepOutcome scanOutcome;
  final int processTerminationRemaining;
  final ShutdownStepOutcome syncOutcome;
  final SyncStatus? syncResultStatus;
  final bool databaseClosed;
  final bool usedForceExit;
  final List<String> pendingTasks;
  final List<String> diagnosticLog;
}

class ShellShutdownRunner {
  ShellShutdownRunner._();

  static Future<ShutdownReport> execute({
    required bool isPlayerOpen,
    required VoidCallback onClosePlaybackSession,
    required SettingsController? settingsController,
    required LibraryController? libraryController,
    required SaphirPlayerController? playerController,
    required DatabaseService? databaseService,
    required Future<void> Function() onHideWindow,
    required Future<void> Function() onDestroyWindow,
    required VoidCallback onForceExit,
    void Function(ShutdownPhase phase)? onPhaseChanged,
    ShutdownTimeouts timeouts = const ShutdownTimeouts(),
  }) async {
    final playerDisposeTimeout = timeouts.playerDispose;
    final scanStopTimeout = timeouts.scanStop;
    final syncTimeout = timeouts.sync;
    final syncCancelGrace = timeouts.syncCancelGrace;
    final nativeDrainDelay = timeouts.nativeDrainDelay;
    final processGracePeriod = timeouts.processGracePeriod;
    final processKillTimeout = timeouts.processKillTimeout;
    final log = <String>[];
    final pendingTasks = <String>[];

    onPhaseChanged?.call(ShutdownPhase.blockingInputs);
    try {
      await onHideWindow();
    } catch (error) {
      log.add('hideWindow failed: $error');
    }

    var playerOutcome = ShutdownStepOutcome.skipped;
    var scanOutcome = ShutdownStepOutcome.skipped;
    var processRemaining = 0;
    var syncOutcome = ShutdownStepOutcome.skipped;
    SyncStatus? syncResultStatus;
    var playerTimedOut = false;
    var scanTimedOut = false;
    var syncStillRunning = false;
    var databaseClosed = false;
    var usedForceExit = false;
    var finalPhase = ShutdownPhase.completed;

    try {
      if (isPlayerOpen) {
        libraryController?.setPlaybackActive(false, resumePausedScan: false);
        onClosePlaybackSession();
      }

      if (playerController != null) {
        onPhaseChanged?.call(ShutdownPhase.stoppingPlayer);
        final res = await _runAwaitableStep(
          playerController.disposeForShutdown(),
          playerDisposeTimeout,
        );
        playerOutcome = res.outcome;
        playerTimedOut = res.outcome == ShutdownStepOutcome.timedOut;
        if (playerTimedOut) {
          pendingTasks.add('player.disposeForShutdown');
          log.add(
              'Player dispose timed out after ${playerDisposeTimeout.inMilliseconds} ms');
        } else if (res.error != null) {
          log.add('Player dispose failed: ${res.error}');
        } else if (nativeDrainDelay > Duration.zero) {
          await Future<void>.delayed(nativeDrainDelay);
        }
      }

      onPhaseChanged?.call(ShutdownPhase.stoppingWorkers);
      if (libraryController != null) {
        final res = await _runAwaitableStep(
          libraryController.cancelScanForShutdown(),
          scanStopTimeout,
        );
        scanOutcome = res.outcome;
        scanTimedOut = res.outcome == ShutdownStepOutcome.timedOut;
        if (scanTimedOut) {
          pendingTasks.add('libraryController.cancelScanForShutdown');
          log.add(
              'Scan cancellation timed out after ${scanStopTimeout.inMilliseconds} ms');
        } else if (res.error != null) {
          log.add('Scan cancellation error: ${res.error}');
        }
      }

      processRemaining = await ActiveProcessRegistry.terminateAll(
        gracePeriod: processGracePeriod,
        hardKillTimeout: processKillTimeout,
      );
      if (processRemaining > 0) {
        pendingTasks.add('activeProcesses($processRemaining)');
        log.add('$processRemaining child process(es) did not confirm exit');
      }

      final canAttemptSync = settingsController != null &&
          !scanTimedOut &&
          (databaseService == null || databaseService.isOpen);
      if (canAttemptSync) {
        onPhaseChanged?.call(ShutdownPhase.syncing);
        final token = SyncCancellationToken();
        final syncFuture =
            settingsController.syncProgress(cancellationToken: token);
        final syncRes = await _awaitSyncWithCancellation(
          syncFuture,
          token: token,
          timeout: syncTimeout,
          cancelGrace: syncCancelGrace,
        );
        syncOutcome = syncRes.outcome;
        syncResultStatus = syncRes.status;
        syncStillRunning = syncRes.stillRunning;
        if (syncStillRunning) {
          pendingTasks.add('settingsController.syncProgress');
          log.add(
            'Sync exceeded timeout (${syncTimeout.inMilliseconds} ms) and did not stop within grace (${syncCancelGrace.inMilliseconds} ms)',
          );
        } else if (syncOutcome == ShutdownStepOutcome.cancelled) {
          log.add(
              'Shutdown sync timed out and cancelled cleanly; will retry on next startup');
        } else if (syncRes.error != null) {
          log.add('Shutdown sync error: ${syncRes.error}');
        }
      } else if (settingsController != null && scanTimedOut) {
        syncOutcome = ShutdownStepOutcome.skipped;
        log.add('Shutdown sync skipped because scan cancellation timed out');
      }

      onPhaseChanged?.call(ShutdownPhase.closingDatabase);
      if (!scanTimedOut && !syncStillRunning) {
        try {
          databaseService?.close();
          databaseClosed = !(databaseService?.isOpen ?? false);
        } catch (error) {
          log.add('Database close failed: $error');
        }
      } else {
        log.add(
          'Skipped closing database because background work is still active: ${pendingTasks.join(', ')}',
        );
      }
    } finally {
      final requiresForceExit = playerTimedOut ||
          scanTimedOut ||
          syncStillRunning ||
          processRemaining > 0;
      if (requiresForceExit) {
        usedForceExit = true;
        finalPhase = ShutdownPhase.forcedExit;
        onPhaseChanged?.call(ShutdownPhase.forcedExit);
        debugPrint(
          '[ShellShutdownRunner] Forced exit requested. Pending tasks: ${pendingTasks.join(', ')}. Log: ${log.join(' | ')}',
        );
        onForceExit();
      } else {
        onPhaseChanged?.call(ShutdownPhase.destroyingWindow);
        await onDestroyWindow();
        finalPhase = ShutdownPhase.completed;
        onPhaseChanged?.call(ShutdownPhase.completed);
      }
    }

    return ShutdownReport(
      finalPhase: finalPhase,
      playerOutcome: playerOutcome,
      scanOutcome: scanOutcome,
      processTerminationRemaining: processRemaining,
      syncOutcome: syncOutcome,
      syncResultStatus: syncResultStatus,
      databaseClosed: databaseClosed,
      usedForceExit: usedForceExit,
      pendingTasks: List.unmodifiable(pendingTasks),
      diagnosticLog: List.unmodifiable(log),
    );
  }

  static Future<({ShutdownStepOutcome outcome, Object? error})>
      _runAwaitableStep(
    Future<void> future,
    Duration timeout,
  ) async {
    try {
      await future.timeout(timeout);
      return (outcome: ShutdownStepOutcome.completed, error: null);
    } on TimeoutException {
      return (outcome: ShutdownStepOutcome.timedOut, error: null);
    } catch (error) {
      return (outcome: ShutdownStepOutcome.failed, error: error);
    }
  }

  static Future<
      ({
        ShutdownStepOutcome outcome,
        SyncStatus? status,
        bool stillRunning,
        Object? error,
      })> _awaitSyncWithCancellation(
    Future<SyncResult> syncFuture, {
    required SyncCancellationToken token,
    required Duration timeout,
    required Duration cancelGrace,
  }) async {
    try {
      final result = await syncFuture.timeout(timeout);
      if (result.status == SyncStatus.cancelled) {
        return (
          outcome: ShutdownStepOutcome.cancelled,
          status: result.status,
          stillRunning: false,
          error: null,
        );
      }
      final ok = result.status == SyncStatus.synced ||
          result.status == SyncStatus.localOnly;
      return (
        outcome:
            ok ? ShutdownStepOutcome.completed : ShutdownStepOutcome.failed,
        status: result.status,
        stillRunning: false,
        error: ok ? null : result.message,
      );
    } on TimeoutException {
      token.cancel();
      try {
        final settled = await syncFuture.timeout(cancelGrace);
        return (
          outcome: ShutdownStepOutcome.cancelled,
          status: settled.status,
          stillRunning: false,
          error: null,
        );
      } on TimeoutException {
        return (
          outcome: ShutdownStepOutcome.timedOut,
          status: null,
          stillRunning: true,
          error: null,
        );
      } catch (error) {
        return (
          outcome: ShutdownStepOutcome.failed,
          status: SyncStatus.failed,
          stillRunning: false,
          error: error,
        );
      }
    } catch (error) {
      return (
        outcome: ShutdownStepOutcome.failed,
        status: SyncStatus.failed,
        stillRunning: false,
        error: error,
      );
    }
  }
}
