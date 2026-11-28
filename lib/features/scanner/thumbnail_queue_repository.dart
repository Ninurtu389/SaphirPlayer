import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import '../../core/constants/app_strings.dart';
import '../../core/storage/database_service.dart';
import '../../core/storage/portable_paths.dart';
import 'thumbnail_cache_key.dart';

/// Statuswerte für die persistente Thumbnail-Queue (A08 / A21).
class ThumbnailJobStatus {
  ThumbnailJobStatus._();

  static const String pending = 'pending';
  static const String processing = 'processing';
  static const String retryWait = 'retry_wait';
  static const String ready = 'ready';
  static const String failedPermanent = 'failed_permanent';
}

/// Aggregierte Statuszählung über alle Episoden und Filme.
class ThumbnailQueueStats {
  const ThumbnailQueueStats({
    this.readyCount = 0,
    this.pendingCount = 0,
    this.processingCount = 0,
    this.retryWaitCount = 0,
    this.failedPermanentCount = 0,
  });

  final int readyCount;
  final int pendingCount;
  final int processingCount;
  final int retryWaitCount;
  final int failedPermanentCount;

  int get actionablePendingCount =>
      pendingCount + processingCount + retryWaitCount;

  int get totalCount =>
      readyCount + actionablePendingCount + failedPermanentCount;

  String formattedSummary() {
    return '$readyCount ${AppStrings.thumbQueueReadyLabel} · '
        '$actionablePendingCount ${AppStrings.thumbQueuePendingLabel} · '
        '$failedPermanentCount ${AppStrings.thumbQueueFailedLabel}';
  }
}

/// Einzelner Datenbankauftrag innerhalb der Thumbnail-Warteschlange.
class QueuedThumbnailJob {
  const QueuedThumbnailJob({
    required this.table,
    required this.prefix,
    required this.id,
    required this.filePath,
    required this.durationMs,
    required this.fileSize,
    required this.modifiedAt,
    required this.priorStatus,
    required this.priorAttempts,
    required this.priorRetryAt,
    required this.priorError,
  });

  factory QueuedThumbnailJob.fromRow(
    Map<String, Object?> row,
    String table,
    String prefix,
  ) {
    return QueuedThumbnailJob(
      table: table,
      prefix: prefix,
      id: row['id'] as int,
      filePath: row['file_path'] as String,
      durationMs: (row['duration_ms'] as int?) ?? 0,
      fileSize: (row['file_size'] as int?) ?? 0,
      modifiedAt: (row['modified_at'] as int?) ?? 0,
      priorStatus:
          (row['thumb_status'] as String?) ?? ThumbnailJobStatus.pending,
      priorAttempts: (row['thumb_attempts'] as int?) ?? 0,
      priorRetryAt: (row['thumb_retry_at'] as int?) ?? 0,
      priorError: row['thumb_last_error'] as String?,
    );
  }

  final String table;
  final String prefix;
  final int id;
  final String filePath;
  final int durationMs;
  final int fileSize;
  final int modifiedAt;
  final String priorStatus;
  final int priorAttempts;
  final int priorRetryAt;
  final String? priorError;
}

/// SQLite-Persistenz für die persistente Thumbnail-Warteschlange.
class ThumbnailQueueRepository {
  ThumbnailQueueRepository(this._databaseService);

  final DatabaseService _databaseService;

  int recoverStaleProcessingJobs() {
    if (!_databaseService.isOpen) return 0;
    final db = _databaseService.instance;
    final staleEp = db
        .select(
          "SELECT COUNT(*) AS c FROM episodes WHERE thumb_status = 'processing';",
        )
        .first['c'] as int;
    final staleMv = db
        .select(
          "SELECT COUNT(*) AS c FROM movies WHERE thumb_status = 'processing';",
        )
        .first['c'] as int;
    if (staleEp + staleMv == 0) return 0;

    db.execute(
      "UPDATE episodes SET thumb_status = 'pending' WHERE thumb_status = 'processing';",
    );
    db.execute(
      "UPDATE movies SET thumb_status = 'pending' WHERE thumb_status = 'processing';",
    );
    return staleEp + staleMv;
  }

  ThumbnailQueueStats readStats() {
    if (!_databaseService.isOpen) return const ThumbnailQueueStats();
    final db = _databaseService.instance;
    final counts = <String, int>{};
    for (final table in const ['episodes', 'movies']) {
      final rows = db.select(
        '''
        SELECT t.thumb_status, COUNT(*) AS c
        FROM $table t
        LEFT JOIN media_sources ms ON ms.source_id = t.source_id
        WHERE (ms.status IS NULL OR ms.status = 'active')
        GROUP BY t.thumb_status;
        ''',
      );
      for (final row in rows) {
        final status =
            (row['thumb_status'] as String?) ?? ThumbnailJobStatus.pending;
        counts[status] = (counts[status] ?? 0) + (row['c'] as int);
      }
    }
    return ThumbnailQueueStats(
      readyCount: counts[ThumbnailJobStatus.ready] ?? 0,
      pendingCount: counts[ThumbnailJobStatus.pending] ?? 0,
      processingCount: counts[ThumbnailJobStatus.processing] ?? 0,
      retryWaitCount: counts[ThumbnailJobStatus.retryWait] ?? 0,
      failedPermanentCount: counts[ThumbnailJobStatus.failedPermanent] ?? 0,
    );
  }

  List<QueuedThumbnailJob> loadDueJobs(int nowMs, int batchLimit) {
    final db = _databaseService.instance;
    final epRows = _selectDueRows(db, 'episodes', nowMs, batchLimit);
    final remaining = batchLimit - epRows.length;
    final mvRows = remaining > 0
        ? _selectDueRows(db, 'movies', nowMs, remaining)
        : const <Map<String, Object?>>[];

    return <QueuedThumbnailJob>[
      for (final row in epRows)
        QueuedThumbnailJob.fromRow(row, 'episodes', 'ep'),
      for (final row in mvRows) QueuedThumbnailJob.fromRow(row, 'movies', 'mv'),
    ];
  }

  bool hasDueJobs(int nowMs) {
    if (!_databaseService.isOpen) return false;
    final db = _databaseService.instance;
    for (final table in const ['episodes', 'movies']) {
      final count = db.select(
        '''
        SELECT COUNT(*) AS c FROM $table t
        LEFT JOIN media_sources ms ON ms.source_id = t.source_id
        WHERE (ms.status IS NULL OR ms.status = 'active')
          AND t.thumb_status IN ('pending', 'retry_wait')
          AND (t.thumb_path IS NULL OR t.thumb_path = '')
          AND t.thumb_retry_at <= ?;
        ''',
        [nowMs],
      ).first['c'] as int;
      if (count > 0) return true;
    }
    return false;
  }

  void markProcessing(QueuedThumbnailJob job) {
    _databaseService.instance.execute(
      "UPDATE ${job.table} SET thumb_status = 'processing' WHERE id = ?;",
      [job.id],
    );
  }

  void restoreInterruptedJob(QueuedThumbnailJob job) {
    _databaseService.instance.execute(
      '''
      UPDATE ${job.table}
      SET thumb_status = ?, thumb_attempts = ?, thumb_retry_at = ?, thumb_last_error = ?
      WHERE id = ?;
      ''',
      [
        job.priorStatus == ThumbnailJobStatus.processing
            ? ThumbnailJobStatus.pending
            : job.priorStatus,
        job.priorAttempts,
        job.priorRetryAt,
        job.priorError,
        job.id,
      ],
    );
  }

  Future<void> markReady(
    QueuedThumbnailJob job,
    ThumbnailGenerationOutcome outcome,
  ) async {
    final nextDur = (job.durationMs == 0 && (outcome.durationMs ?? 0) > 0)
        ? outcome.durationMs!
        : job.durationMs;
    try {
      _databaseService.instance.execute(
        '''
        UPDATE ${job.table}
        SET thumb_path = ?, thumb_status = 'ready',
            thumb_attempts = 0, thumb_last_error = NULL,
            thumb_retry_at = 0, duration_ms = ?
        WHERE id = ?;
        ''',
        [outcome.fileName, nextDur, job.id],
      );
    } on SqliteException {
      final resolved = PortablePaths.resolveThumbnailPath(outcome.fileName);
      if (resolved != null) {
        try {
          final file = File(resolved);
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // Gesperrte Cache-Datei beim Rollback ignorieren
        }
      }
      rethrow;
    }
  }

  void markFailedPermanent(
    QueuedThumbnailJob job,
    int attempts,
    String errorMessage,
  ) {
    _databaseService.instance.execute(
      '''
      UPDATE ${job.table}
      SET thumb_status = 'failed_permanent',
          thumb_attempts = ?, thumb_last_error = ?, thumb_retry_at = 0
      WHERE id = ?;
      ''',
      [attempts, errorMessage, job.id],
    );
  }

  void markRetryWait(
    QueuedThumbnailJob job,
    int attempts,
    String errorMessage,
    int retryAtMs,
  ) {
    _databaseService.instance.execute(
      '''
      UPDATE ${job.table}
      SET thumb_status = 'retry_wait',
          thumb_attempts = ?, thumb_last_error = ?, thumb_retry_at = ?
      WHERE id = ?;
      ''',
      [attempts, errorMessage, retryAtMs, job.id],
    );
  }

  int resetMediaThumbnail({required bool isEpisode, required int mediaId}) {
    if (!_databaseService.isOpen) return 0;
    final table = isEpisode ? 'episodes' : 'movies';
    _databaseService.instance.execute(
      '''
      UPDATE $table
      SET thumb_path = NULL, thumb_status = 'pending',
          thumb_attempts = 0, thumb_last_error = NULL, thumb_retry_at = 0
      WHERE id = ?;
      ''',
      [mediaId],
    );
    return _databaseService.instance.updatedRows;
  }

  int resetSourceThumbnails(String sourceRoot) {
    if (!_databaseService.isOpen) return 0;
    final normRoot = _normalizePrefix(sourceRoot);
    if (normRoot.isEmpty) return 0;

    final db = _databaseService.instance;
    var updated = 0;
    for (final table in const ['episodes', 'movies']) {
      final rows = db.select(
        '''
        SELECT id, file_path FROM $table
        WHERE thumb_status IN ('failed_permanent', 'retry_wait');
        ''',
      );
      for (final row in rows) {
        final filePath = _normalizePrefix(row['file_path'] as String);
        if (filePath == normRoot || filePath.startsWith('$normRoot/')) {
          db.execute(
            '''
            UPDATE $table
            SET thumb_path = NULL, thumb_status = 'pending',
                thumb_attempts = 0, thumb_last_error = NULL, thumb_retry_at = 0
            WHERE id = ?;
            ''',
            [row['id'] as int],
          );
          updated += db.updatedRows;
        }
      }
    }
    return updated;
  }

  int resetAllFailedThumbnails() {
    if (!_databaseService.isOpen) return 0;
    final db = _databaseService.instance;
    var updated = 0;
    for (final table in const ['episodes', 'movies']) {
      db.execute(
        '''
        UPDATE $table
        SET thumb_path = NULL, thumb_status = 'pending',
            thumb_attempts = 0, thumb_last_error = NULL, thumb_retry_at = 0
        WHERE thumb_status IN ('failed_permanent', 'retry_wait');
        ''',
      );
      updated += db.updatedRows;
    }
    return updated;
  }

  static List<Map<String, Object?>> _selectDueRows(
    Database db,
    String table,
    int nowMs,
    int limit,
  ) {
    return db.select(
      '''
      SELECT t.id, t.file_path, t.duration_ms, t.file_size, t.modified_at,
             t.thumb_status, t.thumb_attempts, t.thumb_retry_at, t.thumb_last_error
      FROM $table t
      LEFT JOIN media_sources ms ON ms.source_id = t.source_id
      WHERE (ms.status IS NULL OR ms.status = 'active')
        AND t.thumb_status IN ('pending', 'retry_wait')
        AND (t.thumb_path IS NULL OR t.thumb_path = '')
        AND t.thumb_retry_at <= ?
      ORDER BY CASE WHEN t.thumb_status = 'pending' THEN 0 ELSE 1 END,
               t.thumb_retry_at ASC, t.id ASC
      LIMIT ?;
      ''',
      [nowMs, limit],
    );
  }

  static String _normalizePrefix(String rawPath) {
    final normalized =
        ThumbnailCacheKey.normalizeSourcePath(rawPath).replaceAll('\\', '/');
    return normalized.endsWith('/') && normalized.length > 1
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }
}
