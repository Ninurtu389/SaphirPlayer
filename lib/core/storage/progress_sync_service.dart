import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../constants/app_strings.dart';
import 'database_service.dart';
import 'portable_paths.dart';
import 'sync_lock.dart';
import 'sync_merge_store.dart';
import 'sync_models.dart';
import 'sync_validator.dart';

export 'sync_models.dart';

class ProgressSyncService {
  ProgressSyncService(
    this._databaseService, {
    StorageLayout? storageLayout,
    String? writerId,
    Duration lockStaleTimeout = SyncSchema.defaultLockStaleTimeout,
    Duration lockAcquireTimeout = SyncSchema.defaultLockAcquireTimeout,
    int maxRetries = SyncSchema.maxConflictRetries,
  })  : _storageLayout = storageLayout,
        _writerId = (writerId != null && writerId.trim().isNotEmpty)
            ? writerId.trim()
            : '${Platform.localHostname}_$pid',
        _lockStaleTimeout = lockStaleTimeout,
        _lockAcquireTimeout = lockAcquireTimeout,
        _maxRetries = maxRetries < 1 ? 1 : maxRetries;

  final DatabaseService _databaseService;
  final StorageLayout? _storageLayout;
  final String _writerId;
  final Duration _lockStaleTimeout;
  final Duration _lockAcquireTimeout;
  final int _maxRetries;

  static const String _syncFileName = 'progress_sync.json';
  Future<void> _syncQueue = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    Zone.root.run(() {
      _syncQueue = _syncQueue.then(
        (_) => _runTask(task, completer),
        onError: (_) => _runTask(task, completer),
      );
    });
    return completer.future;
  }

  Future<void> _runTask<T>(
    Future<T> Function() task,
    Completer<T> completer,
  ) async {
    try {
      final result = await task();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    } catch (e, st) {
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
    }
  }

  Future<({String path, bool isNas})> _resolveSyncTarget(
    String nasRootPath,
  ) async {
    final trimmed = nasRootPath.trim();
    if (trimmed.isNotEmpty) {
      final nasDir = Directory(trimmed);
      if (await nasDir.exists()) {
        return (path: p.join(trimmed, _syncFileName), isNas: true);
      }
    }
    final dataDir =
        _storageLayout?.dataDirectory ?? await PortablePaths.getDataDirectory();
    return (path: p.join(dataDir, _syncFileName), isNas: false);
  }

  SyncResult _cancelledResult({
    String targetPath = '',
    bool nasTargetUnreachable = false,
  }) =>
      SyncResult(
        syncedToNas: false,
        targetPath: targetPath,
        status: SyncStatus.cancelled,
        message: AppStrings.syncCancelledStatus,
        nasTargetUnreachable: nasTargetUnreachable,
      );

  Future<SyncResult> syncWithRoots(
    List<String> nasRootPaths, {
    SyncCancellationToken? cancellationToken,
  }) {
    if (cancellationToken?.isCancelled ?? false) {
      return Future<SyncResult>.value(_cancelledResult());
    }
    return _enqueue(() async {
      if (cancellationToken?.isCancelled ?? false) {
        return _cancelledResult();
      }
      var hasConfiguredRoots = false;
      for (final root in nasRootPaths) {
        if (cancellationToken?.isCancelled ?? false) {
          return _cancelledResult(nasTargetUnreachable: hasConfiguredRoots);
        }
        final trimmed = root.trim();
        if (trimmed.isEmpty) continue;
        hasConfiguredRoots = true;
        if (await Directory(trimmed).exists()) {
          return _performSyncWithRetry(
            trimmed,
            cancellationToken: cancellationToken,
          );
        }
      }
      return _performSyncWithRetry(
        '',
        nasTargetUnreachable: hasConfiguredRoots,
        cancellationToken: cancellationToken,
      );
    });
  }

  Future<SyncResult> syncWithStorage(
    String nasRootPath, {
    SyncCancellationToken? cancellationToken,
  }) {
    if (cancellationToken?.isCancelled ?? false) {
      return Future<SyncResult>.value(_cancelledResult());
    }
    return _enqueue(
      () => _performSyncWithRetry(
        nasRootPath,
        cancellationToken: cancellationToken,
      ),
    );
  }

  Future<void> waitForIdle() => _enqueue(() async {});

  Future<SyncResult> recoverValidEntriesFromFile(String filePath) {
    return _enqueue(() async {
      if (!_databaseService.isOpen) {
        return SyncResult(
          syncedToNas: false,
          targetPath: filePath,
          status: SyncStatus.failed,
          message: 'Datenbank nicht geöffnet.',
        );
      }
      final file = File(filePath);
      if (!await file.exists()) {
        return SyncResult(
          syncedToNas: false,
          targetPath: filePath,
          status: SyncStatus.failed,
          message: 'Recovery-Datei nicht gefunden.',
        );
      }
      final List<int> bytes;
      try {
        bytes = await file.readAsBytes();
      } on FileSystemException catch (error) {
        return SyncResult(
          syncedToNas: false,
          targetPath: filePath,
          status: SyncStatus.failed,
          message: error.message,
        );
      }
      final parse = SyncValidator.parseFileBytes(bytes);
      if (!parse.isOk) {
        return SyncResult(
          syncedToNas: false,
          targetPath: filePath,
          status: parse.status == SyncParseStatus.incompatibleVersion
              ? SyncStatus.incompatibleVersion
              : SyncStatus.corrupt,
          message: parse.errorMessage,
          validationIssues: parse.issues,
        );
      }
      final db = _databaseService.instance;
      final v1ToV2 = SyncMergeStore.buildLegacyV1ToV2Map(db);
      final normalizedRemote =
          SyncMergeStore.remapEntries(parse.document!.entries, v1ToV2);
      final localRows = SyncMergeStore.loadLocalEntries(db);
      final merged =
          SyncMergeStore.mergeAndPersistToDb(db, localRows, normalizedRemote);
      return SyncResult(
        syncedToNas: false,
        targetPath: filePath,
        status: SyncStatus.localOnly,
        isolatedEntryCount: parse.issues.length,
        validationIssues: parse.issues,
        generation: parse.document!.generation,
        mergedEntryCount: merged.length,
      );
    });
  }

  Future<SyncResult> _performSyncWithRetry(
    String nasRootPath, {
    bool nasTargetUnreachable = false,
    SyncCancellationToken? cancellationToken,
  }) async {
    SyncResult? lastConflict;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      if (cancellationToken?.isCancelled ?? false) {
        return _cancelledResult(nasTargetUnreachable: nasTargetUnreachable);
      }
      final res = await _performSyncOnce(
        nasRootPath,
        nasTargetUnreachable: nasTargetUnreachable,
        cancellationToken: cancellationToken,
      );
      if (res.status != SyncStatus.conflict) {
        return res;
      }
      lastConflict = res;
      await Future<void>.delayed(Duration(milliseconds: 20 * (attempt + 1)));
    }
    if (cancellationToken?.isCancelled ?? false) {
      return _cancelledResult(nasTargetUnreachable: nasTargetUnreachable);
    }
    return lastConflict ??
        SyncResult(
          syncedToNas: false,
          targetPath: '',
          status: SyncStatus.conflict,
          message: 'Sync-Lock konnte nicht erworben werden.',
          nasTargetUnreachable: nasTargetUnreachable,
        );
  }

  Future<SyncResult> _performSyncOnce(
    String nasRootPath, {
    bool nasTargetUnreachable = false,
    SyncCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return _cancelledResult(nasTargetUnreachable: nasTargetUnreachable);
    }
    if (!_databaseService.isOpen) {
      return SyncResult(
        syncedToNas: false,
        targetPath: '',
        status: SyncStatus.failed,
        message: 'Datenbank nicht geöffnet.',
        nasTargetUnreachable: nasTargetUnreachable,
      );
    }
    final target = await _resolveSyncTarget(nasRootPath);
    final effectiveNasUnreachable = nasTargetUnreachable ||
        (nasRootPath.trim().isNotEmpty && !target.isNas);
    if (cancellationToken?.isCancelled ?? false) {
      return _cancelledResult(
        targetPath: target.path,
        nasTargetUnreachable: effectiveNasUnreachable,
      );
    }
    if (!_databaseService.isOpen) {
      return SyncResult(
        syncedToNas: false,
        targetPath: target.path,
        status: SyncStatus.failed,
        nasTargetUnreachable: effectiveNasUnreachable,
      );
    }
    final syncPath = target.path;

    final lock = await SyncFileLock.acquire(
      syncPath,
      writerId: _writerId,
      staleTimeout: _lockStaleTimeout,
      acquireTimeout: _lockAcquireTimeout,
      cancellationToken: cancellationToken,
    );
    if (cancellationToken?.isCancelled ?? false) {
      await lock?.release();
      return _cancelledResult(
        targetPath: syncPath,
        nasTargetUnreachable: effectiveNasUnreachable,
      );
    }
    if (lock == null) {
      return SyncResult(
        syncedToNas: false,
        targetPath: syncPath,
        status: SyncStatus.conflict,
        message: 'Sync-Datei wird aktuell von einem anderen Gerät beschrieben.',
        nasTargetUnreachable: effectiveNasUnreachable,
      );
    }

    try {
      if (cancellationToken?.isCancelled ?? false) {
        return _cancelledResult(
          targetPath: syncPath,
          nasTargetUnreachable: effectiveNasUnreachable,
        );
      }
      if (!_databaseService.isOpen) {
        return SyncResult(
          syncedToNas: false,
          targetPath: syncPath,
          status: SyncStatus.failed,
          nasTargetUnreachable: effectiveNasUnreachable,
        );
      }

      final syncFile = File(syncPath);
      SyncDocument? remoteDoc;
      var issues = const <SyncValidationIssue>[];

      if (await syncFile.exists()) {
        final List<int> bytes;
        try {
          bytes = await syncFile.readAsBytes();
        } on FileSystemException catch (error) {
          return SyncResult(
            syncedToNas: false,
            targetPath: syncPath,
            status: SyncStatus.failed,
            message: 'Sync-Datei konnte nicht gelesen werden: ${error.message}',
            nasTargetUnreachable: effectiveNasUnreachable,
          );
        }
        if (cancellationToken?.isCancelled ?? false) {
          return _cancelledResult(
            targetPath: syncPath,
            nasTargetUnreachable: effectiveNasUnreachable,
          );
        }

        final parsed = SyncValidator.parseFileBytes(bytes);
        if (!parsed.isOk) {
          final backupPath =
              await SyncAtomicFileStore.createCorruptDiagnosticCopy(syncPath);
          final status = parsed.status == SyncParseStatus.incompatibleVersion
              ? SyncStatus.incompatibleVersion
              : SyncStatus.corrupt;
          return SyncResult(
            syncedToNas: false,
            targetPath: syncPath,
            status: status,
            message: parsed.errorMessage,
            corruptBackupPath: backupPath,
            validationIssues: parsed.issues,
            nasTargetUnreachable: effectiveNasUnreachable,
          );
        }
        remoteDoc = parsed.document!;
        issues = parsed.issues;
      }

      if (cancellationToken?.isCancelled ?? false) {
        return _cancelledResult(
          targetPath: syncPath,
          nasTargetUnreachable: effectiveNasUnreachable,
        );
      }
      if (!_databaseService.isOpen) {
        return SyncResult(
          syncedToNas: false,
          targetPath: syncPath,
          status: SyncStatus.failed,
          nasTargetUnreachable: effectiveNasUnreachable,
        );
      }

      final db = _databaseService.instance;
      SyncMergeStore.normalizeLocalLegacyKeys(db);
      final v1ToV2 = SyncMergeStore.buildLegacyV1ToV2Map(db);
      final remoteEntries = remoteDoc == null
          ? const <String, SyncEntry>{}
          : SyncMergeStore.remapEntries(remoteDoc.entries, v1ToV2);
      final localEntries = SyncMergeStore.loadLocalEntries(db);
      if (cancellationToken?.isCancelled ?? false) {
        return _cancelledResult(
          targetPath: syncPath,
          nasTargetUnreachable: effectiveNasUnreachable,
        );
      }
      final mergedEntries = SyncMergeStore.mergeAndPersistToDb(
        db,
        localEntries,
        remoteEntries,
      );

      final nextGeneration = (remoteDoc?.generation ?? 0) + 1;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final payloadJson = jsonEncode({
        'version': SyncSchema.currentVersion,
        'updated_at': nowMs,
        'generation': nextGeneration,
        'writer_id': _writerId,
        'entries': {
          for (final entry in mergedEntries.entries)
            entry.key: entry.value.toJson(),
        },
      });

      if (cancellationToken?.isCancelled ?? false) {
        return _cancelledResult(
          targetPath: syncPath,
          nasTargetUnreachable: effectiveNasUnreachable,
        );
      }

      String? writeError;
      try {
        await SyncAtomicFileStore.writeValidatedAtomically(
          syncPath: syncPath,
          payloadJson: payloadJson,
          writerId: _writerId,
        );
      } on FileSystemException catch (error) {
        writeError = error.message;
      }

      if (writeError != null) {
        return SyncResult(
          syncedToNas: false,
          targetPath: syncPath,
          status: SyncStatus.failed,
          message: writeError,
          isolatedEntryCount: issues.length,
          validationIssues: issues,
          generation: remoteDoc?.generation ?? 0,
          mergedEntryCount: mergedEntries.length,
          nasTargetUnreachable: effectiveNasUnreachable,
        );
      }

      return SyncResult(
        syncedToNas: target.isNas,
        targetPath: syncPath,
        status: target.isNas ? SyncStatus.synced : SyncStatus.localOnly,
        isolatedEntryCount: issues.length,
        validationIssues: issues,
        generation: nextGeneration,
        mergedEntryCount: mergedEntries.length,
        nasTargetUnreachable: effectiveNasUnreachable,
        completedAtMs: nowMs,
      );
    } finally {
      await lock.release();
    }
  }
}
