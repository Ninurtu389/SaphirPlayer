import 'dart:async';
import 'scan_models.dart';

class ScanCoordinator {
  ScanLifecycleState _state = ScanLifecycleState.idle;
  bool _isPlaybackActive = false;
  bool _isShutdownCancelled = false;
  bool _isMaintenanceLocked = false;
  Future<ScanResult>? _activeScanFuture;
  ScanCancellationToken? _activeToken;
  List<String>? _activeRoots;
  List<String>? _pendingResumeRoots;
  List<String>? _queuedRoots;
  final List<void Function(ScanLifecycleState)> _stateListeners =
      <void Function(ScanLifecycleState)>[];

  ScanLifecycleState get state => _state;
  bool get isActive =>
      _state == ScanLifecycleState.running ||
      _state == ScanLifecycleState.pausing ||
      _state == ScanLifecycleState.cancelling;
  bool get isPlaybackActive => _isPlaybackActive;
  bool get isShutdownCancelled => _isShutdownCancelled;
  bool get isMaintenanceLocked => _isMaintenanceLocked;
  bool get hasPendingResume =>
      _pendingResumeRoots != null &&
      !_isShutdownCancelled &&
      !_isMaintenanceLocked;
  Future<ScanResult>? get activeScanFuture => _activeScanFuture;

  void addStateListener(void Function(ScanLifecycleState) listener) {
    if (!_stateListeners.contains(listener)) {
      _stateListeners.add(listener);
    }
  }

  void removeStateListener(void Function(ScanLifecycleState) listener) {
    _stateListeners.remove(listener);
  }

  void _setState(ScanLifecycleState next) {
    if (_state == next) return;
    _state = next;
    for (final listener in List<void Function(ScanLifecycleState)>.of(
      _stateListeners,
    )) {
      listener(next);
    }
  }

  List<String>? consumePendingResumeRoots() {
    final pending = _pendingResumeRoots;
    _pendingResumeRoots = null;
    return pending;
  }

  Future<ScanResult> runOrDeduplicate({
    required List<String> rootPaths,
    required Future<ScanResult> Function(
      List<String> roots,
      ScanCancellationToken token,
    ) executor,
    required ScanResult Function(
      ScanLifecycleState state, {
      required bool skippedDueToPlayback,
      required bool cancelledForShutdown,
    }) emptyResultBuilder,
  }) {
    if (_isShutdownCancelled || _isMaintenanceLocked) {
      return Future<ScanResult>.value(
        emptyResultBuilder(
          ScanLifecycleState.idle,
          skippedDueToPlayback: false,
          cancelledForShutdown: _isShutdownCancelled,
        ),
      );
    }

    final existing = _activeScanFuture;
    if (existing != null) {
      if (!_listsEqual(_activeRoots ?? const [], rootPaths)) {
        _queuedRoots = List<String>.of(rootPaths);
      }
      return existing;
    }

    if (_isPlaybackActive) {
      _pendingResumeRoots = List<String>.of(rootPaths);
      _setState(ScanLifecycleState.paused);
      return Future<ScanResult>.value(
        emptyResultBuilder(
          ScanLifecycleState.paused,
          skippedDueToPlayback: true,
          cancelledForShutdown: false,
        ),
      );
    }

    final future = _executeLoop(
      initialRoots: List<String>.of(rootPaths),
      executor: executor,
      emptyResultBuilder: emptyResultBuilder,
    );
    _activeScanFuture = future;
    return future;
  }

  Future<ScanResult> _executeLoop({
    required List<String> initialRoots,
    required Future<ScanResult> Function(
      List<String> roots,
      ScanCancellationToken token,
    ) executor,
    required ScanResult Function(
      ScanLifecycleState state, {
      required bool skippedDueToPlayback,
      required bool cancelledForShutdown,
    }) emptyResultBuilder,
  }) async {
    var currentRoots = initialRoots;
    try {
      while (true) {
        if (_isShutdownCancelled || _isMaintenanceLocked) {
          _setState(ScanLifecycleState.idle);
          return emptyResultBuilder(
            ScanLifecycleState.idle,
            skippedDueToPlayback: false,
            cancelledForShutdown: _isShutdownCancelled,
          );
        }

        if (_isPlaybackActive) {
          _pendingResumeRoots = List<String>.of(currentRoots);
          _setState(ScanLifecycleState.paused);
          return emptyResultBuilder(
            ScanLifecycleState.paused,
            skippedDueToPlayback: true,
            cancelledForShutdown: false,
          );
        }

        final token = ScanCancellationToken();
        _activeToken = token;
        _activeRoots = List<String>.of(currentRoots);
        _setState(ScanLifecycleState.running);

        late final ScanResult result;
        try {
          result = await executor(currentRoots, token);
        } finally {
          _activeToken = null;
          _activeRoots = null;
        }

        if (_isShutdownCancelled ||
            _isMaintenanceLocked ||
            token.isShutdownRequested ||
            result.cancelledForShutdown) {
          _queuedRoots = null;
          _pendingResumeRoots = null;
          _setState(ScanLifecycleState.idle);
          return result;
        }

        if (token.isPauseRequested || result.skippedDueToPlayback) {
          if (_isPlaybackActive) {
            _pendingResumeRoots ??= List<String>.of(currentRoots);
            _setState(ScanLifecycleState.paused);
            return result;
          }
          // Wiedergabe endete während des Stoppens -> deterministisch neu anlaufen
          _pendingResumeRoots = null;
          continue;
        }

        final nextQueued = _queuedRoots;
        _queuedRoots = null;
        if (nextQueued != null) {
          currentRoots = nextQueued;
          continue;
        }

        _setState(ScanLifecycleState.completed);
        return result;
      }
    } catch (_) {
      _queuedRoots = null;
      _setState(
        _isShutdownCancelled
            ? ScanLifecycleState.idle
            : ScanLifecycleState.failed,
      );
      rethrow;
    } finally {
      _activeScanFuture = null;
      _activeToken = null;
      _activeRoots = null;
    }
  }

  void setPlaybackActive(bool active) {
    _isPlaybackActive = active;
    if (active && _activeToken != null && !_isShutdownCancelled) {
      _pendingResumeRoots = _activeRoots != null
          ? List<String>.of(_activeRoots!)
          : _pendingResumeRoots;
      _setState(ScanLifecycleState.pausing);
      _activeToken!.requestPause();
    }
  }

  Future<void> cancelForMaintenance({
    required void Function() onKillActiveResources,
  }) async {
    _isMaintenanceLocked = true;
    _pendingResumeRoots = null;
    _queuedRoots = null;
    final active = _activeScanFuture;
    if (active != null) {
      _setState(ScanLifecycleState.cancelling);
      _activeToken?.requestShutdown();
      onKillActiveResources();
      await active.catchError(
        (_) => const ScanResult(
          nasReachable: false,
          seriesCount: 0,
          movieCount: 0,
          skippedDueToPlayback: false,
          lifecycleState: ScanLifecycleState.idle,
        ),
      );
    } else {
      onKillActiveResources();
    }
    _setState(ScanLifecycleState.idle);
  }

  void endMaintenance() {
    _isMaintenanceLocked = false;
  }

  Future<void> cancelForShutdown({
    required void Function() onKillActiveResources,
  }) async {
    _isShutdownCancelled = true;
    _pendingResumeRoots = null;
    _queuedRoots = null;
    final active = _activeScanFuture;
    if (active != null) {
      _setState(ScanLifecycleState.cancelling);
      _activeToken?.requestShutdown();
      onKillActiveResources();
      await active.catchError(
        (_) => const ScanResult(
          nasReachable: false,
          seriesCount: 0,
          movieCount: 0,
          skippedDueToPlayback: true,
          lifecycleState: ScanLifecycleState.idle,
          cancelledForShutdown: true,
        ),
      );
    } else {
      onKillActiveResources();
    }
    _setState(ScanLifecycleState.idle);
  }

  static bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].trim().toLowerCase() != b[i].trim().toLowerCase()) {
        return false;
      }
    }
    return true;
  }
}
