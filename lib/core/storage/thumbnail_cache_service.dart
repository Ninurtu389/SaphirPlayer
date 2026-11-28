import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'database_service.dart';
import 'portable_paths.dart';

class CacheClearResult {
  const CacheClearResult({
    required this.deletedCount,
    required this.failedCount,
    required this.failedPaths,
    required this.remainingBytes,
  });

  final int deletedCount;
  final int failedCount;
  final List<String> failedPaths;
  final int remainingBytes;

  bool get hasWarnings => failedCount > 0;
}

/// Gegenseitige Sperre (A09) zwischen Thumbnail-Generierung und Cache-Bereinigung/Reset.
class ThumbnailOperationGate {
  Future<void> _maintenanceChain = Future<void>.value();
  int _activeGenerationCount = 0;
  Completer<void>? _generationIdleCompleter;
  bool _generationBlocked = false;

  bool get isGenerationBlocked => _generationBlocked;
  bool get hasActiveGeneration => _activeGenerationCount > 0;

  Future<T> trackGenerationTask<T>(Future<T> Function() task) async {
    if (_generationBlocked) {
      throw StateError(
        'Thumbnail-Generierung während aktiver Cache-Wartung gesperrt.',
      );
    }
    _activeGenerationCount++;
    _generationIdleCompleter ??= Completer<void>();
    try {
      return await task();
    } finally {
      _activeGenerationCount--;
      if (_activeGenerationCount == 0) {
        final completer = _generationIdleCompleter;
        _generationIdleCompleter = null;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
      }
    }
  }

  Future<T> runExclusiveMaintenance<T>(
    Future<T> Function() action, {
    Future<void> Function()? onCancelActiveGeneration,
  }) {
    final completer = Completer<T>();
    _maintenanceChain = _maintenanceChain.then((_) async {
      _generationBlocked = true;
      try {
        if (onCancelActiveGeneration != null) {
          await onCancelActiveGeneration();
        }
        final idle = _generationIdleCompleter;
        if (idle != null && !idle.isCompleted) {
          await idle.future;
        }
        final result = await action();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      } finally {
        _generationBlocked = false;
      }
    });
    return completer.future;
  }
}

class ThumbnailCacheService {
  ThumbnailCacheService({
    this.storageLayout,
    ThumbnailOperationGate? gate,
  }) : _gate = gate ?? ThumbnailOperationGate();

  final StorageLayout? storageLayout;
  final ThumbnailOperationGate _gate;

  ThumbnailOperationGate get gate => _gate;

  Future<int> calculateCacheBytes() async {
    final cachePath = storageLayout?.cacheDirectory ??
        await PortablePaths.getCacheDirectory();
    final cacheDir = Directory(cachePath);
    var totalBytes = 0;

    if (await cacheDir.exists()) {
      await for (final entity
          in cacheDir.list(recursive: false, followLinks: false)) {
        if (entity is File) {
          try {
            totalBytes += await entity.length();
          } on FileSystemException {
            // Einzelne gesperrte Datei ignorieren
          }
        }
      }
    }
    return totalBytes;
  }

  Future<void> clearCache(DatabaseService databaseService) async {
    await clearCacheWithResult(databaseService);
  }

  Future<CacheClearResult> clearCacheWithResult(
    DatabaseService databaseService, {
    Future<void> Function()? onStopGeneration,
  }) {
    return _gate.runExclusiveMaintenance<CacheClearResult>(
      () async {
        final cachePath = storageLayout?.cacheDirectory ??
            await PortablePaths.getCacheDirectory();
        final cacheDir = Directory(cachePath);
        var deletedCount = 0;
        final failedPaths = <String>[];

        if (await cacheDir.exists()) {
          final canonicalDir = p.canonicalize(cacheDir.path).toLowerCase();
          await for (final entity
              in cacheDir.list(recursive: false, followLinks: false)) {
            if (entity is Link || entity is! File) {
              continue;
            }
            final canonicalParent =
                p.canonicalize(p.dirname(entity.path)).toLowerCase();
            if (canonicalParent != canonicalDir) {
              continue;
            }
            try {
              await entity.delete();
              deletedCount++;
            } on FileSystemException {
              failedPaths.add(entity.path);
            }
          }
        }

        if (databaseService.isOpen) {
          final db = databaseService.instance;
          db.execute('BEGIN TRANSACTION;');
          try {
            db.execute(
              "UPDATE episodes SET thumb_path = NULL, thumb_status = 'pending', thumb_attempts = 0, thumb_last_error = NULL, thumb_retry_at = 0;",
            );
            db.execute(
              "UPDATE movies SET thumb_path = NULL, thumb_status = 'pending', thumb_attempts = 0, thumb_last_error = NULL, thumb_retry_at = 0;",
            );
            db.execute('COMMIT;');
          } catch (_) {
            db.execute('ROLLBACK;');
            rethrow;
          }
        }

        final remainingBytes = await calculateCacheBytes();
        return CacheClearResult(
          deletedCount: deletedCount,
          failedCount: failedPaths.length,
          failedPaths: failedPaths,
          remainingBytes: remainingBytes,
        );
      },
      onCancelActiveGeneration: onStopGeneration,
    );
  }
}
