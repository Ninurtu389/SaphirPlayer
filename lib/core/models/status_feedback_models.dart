enum StatusSeverity {
  info,
  success,
  warning,
  error,
}

class StatusBannerMessage {
  const StatusBannerMessage({
    required this.message,
    this.severity = StatusSeverity.info,
    this.detail,
  });

  final String message;
  final StatusSeverity severity;
  final String? detail;
}

enum SyncFeedbackKind {
  synced,
  localFallback,
  nasUnreachableFallback,
  conflict,
  corrupt,
  incompatibleVersion,
  cancelled,
  failed,
}

class SyncFeedbackSummary {
  const SyncFeedbackSummary({
    required this.kind,
    required this.syncedToNas,
    required this.headline,
    this.detail,
    required this.targetPath,
    required this.timestampMs,
    required this.severity,
    this.isolatedEntryCount = 0,
    this.diagnosticMessage,
  });

  final SyncFeedbackKind kind;
  final bool syncedToNas;
  final String headline;
  final String? detail;
  final String targetPath;
  final int timestampMs;
  final StatusSeverity severity;
  final int isolatedEntryCount;
  final String? diagnosticMessage;
}

class LibraryScanFeedback {
  const LibraryScanFeedback({
    required this.severity,
    required this.message,
    this.detail,
    this.canRetry = false,
    this.isPartial = false,
    this.affectedSources = const [],
  });

  final StatusSeverity severity;
  final String message;
  final String? detail;
  final bool canRetry;
  final bool isPartial;
  final List<String> affectedSources;
}
