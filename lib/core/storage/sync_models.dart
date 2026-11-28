class SyncSchema {
  SyncSchema._();

  static const int currentVersion = 2;
  static const int minSupportedVersion = 1;
  static const int maxFileSizeBytes = 10 * 1024 * 1024;
  static const int maxEntriesCount = 100000;
  static const int maxKeyLength = 256;
  static const int maxDeviceNameLength = 128;
  static const int maxDurationMs = 48 * 3600 * 1000;
  static const int maxPlausibleTimestampMs = 4102444800000;
  static const Set<String> allowedMediaTypes = {'episode', 'movie'};
  static const Duration defaultLockStaleTimeout = Duration(seconds: 30);
  static const Duration defaultLockAcquireTimeout = Duration(seconds: 3);
  static const int maxConflictRetries = 3;
  static const int maxRotationBackups = 3;
}

enum SyncStatus {
  synced,
  localOnly,
  conflict,
  corrupt,
  incompatibleVersion,
  failed,
}

class SyncValidationIssue {
  const SyncValidationIssue({
    this.entryKey,
    required this.reason,
  });

  final String? entryKey;
  final String reason;
}

class SyncEntry {
  const SyncEntry({
    required this.mediaKey,
    required this.mediaType,
    required this.positionMs,
    required this.durationMs,
    required this.completed,
    required this.updatedAt,
    required this.sourceDevice,
    this.revision = 0,
  });

  final String mediaKey;
  final String mediaType;
  final int positionMs;
  final int durationMs;
  final bool completed;
  final int updatedAt;
  final String sourceDevice;
  final int revision;

  SyncEntry copyWith({
    int? positionMs,
    int? durationMs,
    bool? completed,
    int? updatedAt,
    String? sourceDevice,
    int? revision,
  }) {
    return SyncEntry(
      mediaKey: mediaKey,
      mediaType: mediaType,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      completed: completed ?? this.completed,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceDevice: sourceDevice ?? this.sourceDevice,
      revision: revision ?? this.revision,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'media_type': mediaType,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'completed': completed,
      'updated_at': updatedAt,
      'source_device': sourceDevice,
      'revision': revision,
    };
  }

  /// Deterministische Konfliktlösung:
  /// 1. neuerer Zeitstempel (`updatedAt`)
  /// 2. höhere `revision`
  /// 3. abgeschlossener Zustand (`completed`)
  /// 4. weiter fortgeschrittene Position (`positionMs`)
  /// 5. lexikographisch höheres `sourceDevice`
  static SyncEntry resolveConflict(SyncEntry a, SyncEntry b) {
    if (a.updatedAt != b.updatedAt) {
      return a.updatedAt > b.updatedAt ? a : b;
    }
    if (a.revision != b.revision) {
      return a.revision > b.revision ? a : b;
    }
    if (a.completed != b.completed) {
      return a.completed ? a : b;
    }
    if (a.positionMs != b.positionMs) {
      return a.positionMs > b.positionMs ? a : b;
    }
    return a.sourceDevice.compareTo(b.sourceDevice) >= 0 ? a : b;
  }

  bool samePayloadAs(SyncEntry other) {
    return mediaType == other.mediaType &&
        positionMs == other.positionMs &&
        durationMs == other.durationMs &&
        completed == other.completed &&
        updatedAt == other.updatedAt &&
        sourceDevice == other.sourceDevice;
  }
}

class SyncDocument {
  const SyncDocument({
    required this.version,
    required this.updatedAt,
    required this.generation,
    required this.writerId,
    required this.entries,
    this.isolatedIssues = const [],
  });

  final int version;
  final int updatedAt;
  final int generation;
  final String writerId;
  final Map<String, SyncEntry> entries;
  final List<SyncValidationIssue> isolatedIssues;
}

class SyncResult {
  const SyncResult({
    required this.syncedToNas,
    required this.targetPath,
    this.status = SyncStatus.synced,
    this.message,
    this.corruptBackupPath,
    this.isolatedEntryCount = 0,
    this.validationIssues = const [],
    this.generation = 0,
    this.mergedEntryCount = 0,
  });

  final bool syncedToNas;
  final String targetPath;
  final SyncStatus status;
  final String? message;
  final String? corruptBackupPath;
  final int isolatedEntryCount;
  final List<SyncValidationIssue> validationIssues;
  final int generation;
  final int mergedEntryCount;
}
