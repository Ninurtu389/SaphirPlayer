import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'sync_models.dart';
import 'sync_validator.dart';

class SyncLockHandle {
  const SyncLockHandle({
    required this.lockDir,
    required this.ownerFile,
    required this.writerId,
  });

  final Directory lockDir;
  final File ownerFile;
  final String writerId;

  Future<void> release() async {
    try {
      if (await ownerFile.exists()) {
        await ownerFile.delete();
      }
    } on FileSystemException {
      // Best-effort Cleanup
    }
    try {
      if (await lockDir.exists()) {
        await lockDir.delete(recursive: true);
      }
    } on FileSystemException {
      // Best-effort Cleanup auf SMB/Windows
    }
  }
}

class SyncFileLock {
  SyncFileLock._();

  static Future<SyncLockHandle?> acquire(
    String syncPath, {
    required String writerId,
    Duration staleTimeout = SyncSchema.defaultLockStaleTimeout,
    Duration acquireTimeout = SyncSchema.defaultLockAcquireTimeout,
  }) async {
    final parentDir = Directory(p.dirname(syncPath));
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final lockDir = Directory('$syncPath.lock.d');
    final ownerFile = File(p.join(lockDir.path, 'owner.json'));
    final ownerTmpFile = File(p.join(lockDir.path, 'owner.json.tmp'));
    final deadline = DateTime.now().add(acquireTimeout);

    while (true) {
      try {
        await lockDir.create(recursive: false);
        final now = DateTime.now().millisecondsSinceEpoch;
        await ownerTmpFile.writeAsString(
          jsonEncode({
            'writer_id': writerId,
            'pid': pid,
            'acquired_at': now,
            'expires_at': now + staleTimeout.inMilliseconds,
          }),
          flush: true,
        );
        await ownerTmpFile.rename(ownerFile.path);
        return SyncLockHandle(
          lockDir: lockDir,
          ownerFile: ownerFile,
          writerId: writerId,
        );
      } on FileSystemException {
        if (await _isStaleLock(lockDir, ownerFile, staleTimeout)) {
          try {
            if (await lockDir.exists()) {
              await lockDir.delete(recursive: true);
            }
          } on FileSystemException {
            // Konkurrierender Recovery-Versuch eines anderen Writers
          }
          continue;
        }
        if (DateTime.now().isAfter(deadline)) {
          return null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  }

  static Future<bool> _isStaleLock(
    Directory lockDir,
    File ownerFile,
    Duration staleTimeout,
  ) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    try {
      if (await ownerFile.exists()) {
        try {
          final raw = await ownerFile.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            final expiresAt = decoded['expires_at'];
            if (expiresAt is int) {
              return nowMs > expiresAt;
            }
          }
        } on FormatException {
          // Owner-Datei noch im Schreibvorgang -> über Alter prüfen statt sofort zu brechen
        }
      }
      if (!await lockDir.exists()) {
        return false;
      }
      final stat = await lockDir.stat();
      final ageMs = nowMs - stat.modified.millisecondsSinceEpoch;
      return ageMs > staleTimeout.inMilliseconds;
    } on FileSystemException {
      return false;
    }
  }
}

class SyncAtomicFileStore {
  SyncAtomicFileStore._();

  static final Random _random = Random();

  static Future<String?> createCorruptDiagnosticCopy(String syncPath) async {
    final file = File(syncPath);
    try {
      if (!await file.exists()) {
        return null;
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final copyPath = '$syncPath.corrupt_$stamp.bak';
      await file.copy(copyPath);
      return copyPath;
    } on FileSystemException {
      return null;
    }
  }

  static Future<void> writeValidatedAtomically({
    required String syncPath,
    required String payloadJson,
    required String writerId,
    int maxRotationBackups = SyncSchema.maxRotationBackups,
  }) async {
    final safeWriter = writerId
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final jobId =
        '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}';
    final tmpFile = File('$syncPath.tmp.${safeWriter}_$jobId');
    final targetFile = File(syncPath);
    final primaryBackup = File('$syncPath.bak.1');

    try {
      await tmpFile.writeAsString(payloadJson, flush: true);
      final writtenBytes = await tmpFile.readAsBytes();
      final validation = SyncValidator.parseFileBytes(writtenBytes);
      if (!validation.isOk) {
        throw FileSystemException(
          'Validierung der temporären Sync-Datei fehlgeschlagen: ${validation.errorMessage}',
          tmpFile.path,
        );
      }

      if (await targetFile.exists() && maxRotationBackups > 0) {
        await _rotateBackups(syncPath, maxRotationBackups);
      }

      try {
        await tmpFile.rename(syncPath);
      } on FileSystemException {
        await tmpFile.copy(syncPath);
        final verifyBytes = await targetFile.readAsBytes();
        if (!SyncValidator.parseFileBytes(verifyBytes).isOk) {
          if (await primaryBackup.exists()) {
            await primaryBackup.copy(syncPath);
          }
          throw FileSystemException(
            'Zieldatei nach SMB-Fallback ungültig',
            syncPath,
          );
        }
      }
    } finally {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } on FileSystemException {
          // Best-effort Cleanup
        }
      }
    }
  }

  static Future<void> _rotateBackups(String syncPath, int maxBackups) async {
    for (var i = maxBackups; i >= 2; i--) {
      final src = File('$syncPath.bak.${i - 1}');
      final dst = File('$syncPath.bak.$i');
      if (await src.exists()) {
        try {
          if (await dst.exists()) {
            await dst.delete();
          }
          await src.rename(dst.path);
        } on FileSystemException {
          await src.copy(dst.path);
        }
      }
    }
    final target = File(syncPath);
    final firstBackup = File('$syncPath.bak.1');
    if (await target.exists()) {
      await target.copy(firstBackup.path);
    }
  }
}
