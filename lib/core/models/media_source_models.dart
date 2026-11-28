enum MediaSourceStatus {
  active,
  disabled,
  removed;

  String toStorage() => name;

  static MediaSourceStatus fromStorage(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'disabled':
        return MediaSourceStatus.disabled;
      case 'removed':
        return MediaSourceStatus.removed;
      case 'active':
      default:
        return MediaSourceStatus.active;
    }
  }
}

enum SourceRemovalAction {
  disableKeepData,
  removeWithIndex,
}

enum SourceBadgeKind {
  disabled,
  complete,
  warning,
  error,
  active,
}

class MediaSourceEntry {
  const MediaSourceEntry({
    required this.sourceId,
    required this.rootPath,
    required this.label,
    required this.status,
    required this.createdAt,
    this.lastScanAt,
    this.lastSuccessScanAt,
    this.lastScanStatus,
    this.lastScanError,
    this.lastFilesExamined = 0,
    this.lastMediaFound = 0,
    this.lastErrorCount = 0,
  });

  final String sourceId;
  final String rootPath;
  final String label;
  final MediaSourceStatus status;
  final int createdAt;
  final int? lastScanAt;
  final int? lastSuccessScanAt;
  final String? lastScanStatus;
  final String? lastScanError;
  final int lastFilesExamined;
  final int lastMediaFound;
  final int lastErrorCount;

  bool get isActive => status == MediaSourceStatus.active;
  bool get isDisabled => status == MediaSourceStatus.disabled;

  SourceBadgeKind get badgeKind {
    if (isDisabled) return SourceBadgeKind.disabled;
    switch (lastScanStatus) {
      case 'complete':
        return SourceBadgeKind.complete;
      case 'partial':
      case 'unreachable':
        return SourceBadgeKind.warning;
      case 'failed':
        return SourceBadgeKind.error;
      default:
        return SourceBadgeKind.active;
    }
  }
}

class SourceRemovalResult {
  const SourceRemovalResult({
    required this.sourceId,
    required this.rootPath,
    required this.action,
    this.deletedEpisodes = 0,
    this.deletedMovies = 0,
    this.deletedSeries = 0,
    this.orphanedThumbnails = const [],
  });

  final String sourceId;
  final String rootPath;
  final SourceRemovalAction action;
  final int deletedEpisodes;
  final int deletedMovies;
  final int deletedSeries;
  final List<String> orphanedThumbnails;
}
