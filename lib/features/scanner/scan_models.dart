import 'media_parser.dart';

enum SourceScanStatus {
  complete,
  partial,
  unreachable,
  cancelled,
  failed,
}

enum ScanLifecycleState {
  idle,
  running,
  pausing,
  paused,
  cancelling,
  completed,
  failed,
}

class ScanDirectoryError {
  const ScanDirectoryError({
    required this.path,
    required this.message,
  });

  final String path;
  final String message;
}

class ScanIdentityConflict {
  const ScanIdentityConflict({
    required this.mediaType,
    required this.syncKey,
    required this.filePath,
    required this.conflictingFilePath,
  });

  final String mediaType;
  final String syncKey;
  final String filePath;
  final String conflictingFilePath;
}

class SourceScanReport {
  const SourceScanReport({
    required this.rootPath,
    required this.status,
    this.errors = const [],
    this.filesExamined = 0,
    this.mediaFound = 0,
  });

  final String rootPath;
  final SourceScanStatus status;
  final List<ScanDirectoryError> errors;
  final int filesExamined;
  final int mediaFound;

  bool get isComplete => status == SourceScanStatus.complete;
  bool get isReachable =>
      status == SourceScanStatus.complete || status == SourceScanStatus.partial;
  bool get allowDeletion => status == SourceScanStatus.complete;
}

class CachedFileMeta {
  const CachedFileMeta({
    required this.isEpisode,
    required this.filePath,
    required this.fileSize,
    required this.modifiedAt,
    required this.title,
    required this.artist,
    required this.durationMs,
    required this.syncKey,
    this.seriesTitle,
    this.seriesSummary,
    this.seasonNumber,
    this.episodeNumber,
    this.releaseYear,
  });

  final bool isEpisode;
  final String filePath;
  final int fileSize;
  final int modifiedAt;
  final String title;
  final String? artist;
  final int durationMs;
  final String syncKey;
  final String? seriesTitle;
  final String? seriesSummary;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? releaseYear;

  ParsedEpisode? toParsedEpisode() {
    if (!isEpisode ||
        seriesTitle == null ||
        seasonNumber == null ||
        episodeNumber == null) {
      return null;
    }
    return ParsedEpisode(
      seriesTitle: seriesTitle!,
      seasonNumber: seasonNumber!,
      episodeNumber: episodeNumber!,
      episodeTitle: title,
      filePath: filePath,
      syncKey: syncKey,
      artist: artist,
      durationMs: durationMs,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
    );
  }

  ParsedMovie toParsedMovie() {
    return ParsedMovie(
      title: title,
      releaseYear: releaseYear,
      filePath: filePath,
      syncKey: syncKey,
      artist: artist,
      durationMs: durationMs,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
    );
  }
}

class ScannedSeriesData {
  const ScannedSeriesData({
    required this.title,
    required this.folderPath,
    required this.posterPath,
    required this.summary,
    required this.episodes,
  });

  final String title;
  final String folderPath;
  final String? posterPath;
  final String? summary;
  final List<ParsedEpisode> episodes;
}

class ScannedMovieData {
  const ScannedMovieData({
    required this.title,
    required this.releaseYear,
    required this.filePath,
    required this.posterPath,
    required this.syncKey,
    this.artist,
    this.durationMs = 0,
    this.fileSize = 0,
    this.modifiedAt = 0,
  });

  final String title;
  final int? releaseYear;
  final String filePath;
  final String? posterPath;
  final String syncKey;
  final String? artist;
  final int durationMs;
  final int fileSize;
  final int modifiedAt;
}

class ScanOutput {
  const ScanOutput({
    required this.nasReachable,
    required this.reachableRoots,
    required this.seriesList,
    required this.movies,
    this.completeRoots,
    this.sourceReports = const [],
    this.wasCancelled = false,
  });

  final bool nasReachable;
  final List<String> reachableRoots;
  final List<String>? completeRoots;
  final List<ScannedSeriesData> seriesList;
  final List<ScannedMovieData> movies;
  final List<SourceScanReport> sourceReports;
  final bool wasCancelled;

  List<String> get effectiveCompleteRoots => completeRoots ?? reachableRoots;
}

class ScanDiffSummary {
  const ScanDiffSummary({
    this.orphanedThumbnails = const [],
    this.plannedEpisodeDeletions = 0,
    this.plannedMovieDeletions = 0,
    this.deletionBlockedByThreshold = false,
    this.deletionBlockedRoots = const [],
    this.identityConflicts = const [],
  });

  final List<String> orphanedThumbnails;
  final int plannedEpisodeDeletions;
  final int plannedMovieDeletions;
  final bool deletionBlockedByThreshold;
  final List<String> deletionBlockedRoots;
  final List<ScanIdentityConflict> identityConflicts;
}

class ScanCancellationToken {
  bool _pauseRequested = false;
  bool _shutdownRequested = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isPauseRequested => _pauseRequested;
  bool get isShutdownRequested => _shutdownRequested;
  bool get isCancelled => _pauseRequested || _shutdownRequested;

  void requestPause() {
    if (_pauseRequested) return;
    _pauseRequested = true;
    _notifyListeners();
  }

  void requestShutdown() {
    if (_shutdownRequested) return;
    _shutdownRequested = true;
    _notifyListeners();
  }

  void addListener(void Function() listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}

class ScanResult {
  const ScanResult({
    required this.nasReachable,
    required this.seriesCount,
    required this.movieCount,
    required this.skippedDueToPlayback,
    this.lifecycleState = ScanLifecycleState.completed,
    this.sourceReports = const [],
    this.cancelledForShutdown = false,
    this.deletionBlockedByThreshold = false,
    this.deletionBlockedRoots = const [],
    this.identityConflicts = const [],
    this.errorMessage,
  });

  final bool nasReachable;
  final int seriesCount;
  final int movieCount;
  final bool skippedDueToPlayback;
  final ScanLifecycleState lifecycleState;
  final List<SourceScanReport> sourceReports;
  final bool cancelledForShutdown;
  final bool deletionBlockedByThreshold;
  final List<String> deletionBlockedRoots;
  final List<ScanIdentityConflict> identityConflicts;
  final String? errorMessage;

  bool get hasPartialSources =>
      sourceReports.any((report) => report.status == SourceScanStatus.partial);

  bool get hasUnreachableSources => sourceReports.any(
        (report) =>
            report.status == SourceScanStatus.unreachable ||
            report.status == SourceScanStatus.failed,
      );

  bool get hasIdentityConflicts => identityConflicts.isNotEmpty;

  bool get hasErrors =>
      errorMessage != null ||
      hasIdentityConflicts ||
      sourceReports.any((report) => report.errors.isNotEmpty);
}
