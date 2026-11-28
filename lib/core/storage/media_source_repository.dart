import 'dart:io';
import '../../features/scanner/scan_models.dart';
import '../models/media_source_models.dart';
import 'database_service.dart';
import 'portable_paths.dart';
import 'sync_key_utils.dart';

/// Verwaltet Medienquellen (`media_sources`), deren Scan-Diagnose (A24)
/// und quellenbezogene Deaktivierung/Index-Bereinigung (A10).
///
/// Datenaufbewahrungsvertrag bei `removeSourceIndex`:
/// - Entfernt werden ausschließlich lokale Index-Tabellen der Quelle
///   (`episodes`, `movies`, sowie leer gewordene `seasons` und `series`)
///   innerhalb einer atomaren SQLite-Transaktion.
/// - `media_sources` behält die Zeile mit `status = 'removed'`, damit ein
///   späteres Wiederhinzufügen derselben Quelle dieselbe `source_id` erhält.
/// - `watch_progress`, `watch_history` und `media_bookmarks` bleiben erhalten,
///   sodass Statistiken intakt bleiben und Fortschritte beim erneuten Scannen
///   nahtlos wieder verknüpft werden.
class MediaSourceRepository {
  MediaSourceRepository(this._databaseService);

  final DatabaseService _databaseService;

  static const int _maxStoredErrorLength = 220;

  List<MediaSourceEntry> loadSources({bool includeRemoved = false}) {
    if (!_databaseService.isOpen) return const [];
    final db = _databaseService.instance;
    final whereClause = includeRemoved ? '' : "WHERE status != 'removed'";
    final rows = db.select(
      '''
      SELECT source_id, root_path, label, status, created_at,
             last_scan_at, last_success_scan_at, last_scan_status,
             last_scan_error, last_files_examined, last_media_found,
             last_error_count
      FROM media_sources
      $whereClause
      ORDER BY created_at ASC;
      ''',
    );
    return rows.map(_rowToEntry).toList();
  }

  MediaSourceEntry? findById(String sourceId) {
    if (!_databaseService.isOpen) return null;
    final rows = _databaseService.instance.select(
      '''
      SELECT source_id, root_path, label, status, created_at,
             last_scan_at, last_success_scan_at, last_scan_status,
             last_scan_error, last_files_examined, last_media_found,
             last_error_count
      FROM media_sources
      WHERE source_id = ?
      LIMIT 1;
      ''',
      [sourceId],
    );
    return rows.isEmpty ? null : _rowToEntry(rows.first);
  }

  MediaSourceEntry? findByRootPath(String rootPath) {
    if (!_databaseService.isOpen) return null;
    final normTarget = SyncKeyUtils.normalizeRootPath(rootPath);
    if (normTarget.isEmpty) return null;
    for (final entry in loadSources(includeRemoved: true)) {
      if (SyncKeyUtils.normalizeRootPath(entry.rootPath) == normTarget) {
        return entry;
      }
    }
    return null;
  }

  String ensureActiveSource(
    String rootPath, {
    String? preferredSourceId,
    String? label,
  }) {
    return _databaseService.ensureMediaSource(
      rootPath,
      preferredSourceId: preferredSourceId,
      label: label,
    );
  }

  bool setSourceStatus(String sourceId, MediaSourceStatus status) {
    if (!_databaseService.isOpen) return false;
    final db = _databaseService.instance;
    db.execute(
      'UPDATE media_sources SET status = ? WHERE source_id = ?;',
      [status.toStorage(), sourceId],
    );
    return db.updatedRows > 0;
  }

  SourceRemovalResult removeSourceIndex(String sourceId) {
    final existing = findById(sourceId);
    if (existing == null || !_databaseService.isOpen) {
      return SourceRemovalResult(
        sourceId: sourceId,
        rootPath: existing?.rootPath ?? '',
        action: SourceRemovalAction.removeWithIndex,
      );
    }

    final db = _databaseService.instance;
    final normRoot = SyncKeyUtils.normalizeRootPath(existing.rootPath);
    final orphanedThumbs = <String>[];
    var deletedEpisodes = 0;
    var deletedMovies = 0;
    var deletedSeries = 0;

    db.execute('BEGIN TRANSACTION;');
    try {
      final epRows = db.select(
        'SELECT id, file_path, thumb_path, source_id FROM episodes;',
      );
      for (final row in epRows) {
        if (_matchesSource(
          rowSourceId: row['source_id'] as String?,
          filePath: row['file_path'] as String,
          targetSourceId: sourceId,
          normRoot: normRoot,
        )) {
          final thumb = row['thumb_path'] as String?;
          if (thumb != null && thumb.isNotEmpty) {
            orphanedThumbs.add(thumb);
          }
          db.execute('DELETE FROM episodes WHERE id = ?;', [row['id'] as int]);
          deletedEpisodes += db.updatedRows;
        }
      }

      final mvRows = db.select(
        'SELECT id, file_path, thumb_path, source_id FROM movies;',
      );
      for (final row in mvRows) {
        if (_matchesSource(
          rowSourceId: row['source_id'] as String?,
          filePath: row['file_path'] as String,
          targetSourceId: sourceId,
          normRoot: normRoot,
        )) {
          final thumb = row['thumb_path'] as String?;
          if (thumb != null && thumb.isNotEmpty) {
            orphanedThumbs.add(thumb);
          }
          db.execute('DELETE FROM movies WHERE id = ?;', [row['id'] as int]);
          deletedMovies += db.updatedRows;
        }
      }

      db.execute(
        'DELETE FROM seasons WHERE NOT EXISTS (SELECT 1 FROM episodes e WHERE e.season_id = seasons.id);',
      );
      db.execute(
        'DELETE FROM series WHERE NOT EXISTS (SELECT 1 FROM episodes e WHERE e.series_id = series.id);',
      );
      deletedSeries = db.updatedRows;

      db.execute(
        "UPDATE media_sources SET status = 'removed' WHERE source_id = ?;",
        [sourceId],
      );
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }

    return SourceRemovalResult(
      sourceId: sourceId,
      rootPath: existing.rootPath,
      action: SourceRemovalAction.removeWithIndex,
      deletedEpisodes: deletedEpisodes,
      deletedMovies: deletedMovies,
      deletedSeries: deletedSeries,
      orphanedThumbnails: orphanedThumbs,
    );
  }

  void recordScanReports(List<SourceScanReport> reports) {
    if (!_databaseService.isOpen || reports.isEmpty) return;
    final db = _databaseService.instance;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    db.execute('BEGIN TRANSACTION;');
    try {
      for (final report in reports) {
        if (report.status == SourceScanStatus.cancelled) {
          continue;
        }
        final source = report.sourceId != null
            ? findById(report.sourceId!)
            : findByRootPath(report.rootPath);
        if (source == null) {
          continue;
        }
        final scanAt = report.finishedAtMs ?? nowMs;
        final isSuccess = report.status == SourceScanStatus.complete;
        final sanitizedErr = _sanitizeError(report.lastErrorMessage);
        db.execute(
          '''
          UPDATE media_sources
          SET last_scan_at = ?,
              last_success_scan_at = CASE
                WHEN ? = 1 THEN ?
                ELSE last_success_scan_at
              END,
              last_scan_status = ?,
              last_scan_error = ?,
              last_files_examined = ?,
              last_media_found = ?,
              last_error_count = ?
          WHERE source_id = ?;
          ''',
          [
            scanAt,
            isSuccess ? 1 : 0,
            scanAt,
            report.status.name,
            sanitizedErr,
            report.filesExamined,
            report.mediaFound,
            report.errors.length,
            source.sourceId,
          ],
        );
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  static Future<void> deleteOrphanedThumbnails(
    List<String> orphanedThumbs,
  ) async {
    for (final stored in orphanedThumbs) {
      final resolved = PortablePaths.resolveThumbnailPath(stored);
      if (resolved == null || resolved.isEmpty) {
        continue;
      }
      try {
        final thumbFile = File(resolved);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      } on FileSystemException {
        // Gesperrte Cache-Datei ignorieren
      }
    }
  }

  static bool _matchesSource({
    required String? rowSourceId,
    required String filePath,
    required String targetSourceId,
    required String normRoot,
  }) {
    if (rowSourceId != null && rowSourceId.isNotEmpty) {
      return rowSourceId == targetSourceId;
    }
    if (normRoot.isEmpty) return false;
    final normFile = SyncKeyUtils.normalizeRootPath(filePath);
    return normFile == normRoot || normFile.startsWith('$normRoot/');
  }

  static String? _sanitizeError(String? raw) {
    if (raw == null) return null;
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return null;
    if (collapsed.length <= _maxStoredErrorLength) return collapsed;
    return '${collapsed.substring(0, _maxStoredErrorLength - 3)}...';
  }

  static MediaSourceEntry _rowToEntry(Map<String, Object?> row) {
    return MediaSourceEntry(
      sourceId: row['source_id'] as String,
      rootPath: row['root_path'] as String,
      label: row['label'] as String,
      status: MediaSourceStatus.fromStorage(row['status'] as String?),
      createdAt: (row['created_at'] as int?) ?? 0,
      lastScanAt: row['last_scan_at'] as int?,
      lastSuccessScanAt: row['last_success_scan_at'] as int?,
      lastScanStatus: row['last_scan_status'] as String?,
      lastScanError: row['last_scan_error'] as String?,
      lastFilesExamined: (row['last_files_examined'] as int?) ?? 0,
      lastMediaFound: (row['last_media_found'] as int?) ?? 0,
      lastErrorCount: (row['last_error_count'] as int?) ?? 0,
    );
  }
}
