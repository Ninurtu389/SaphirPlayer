import '../constants/app_strings.dart';
import '../models/status_feedback_models.dart';
import '../utils/formatters.dart';
import 'sync_models.dart';

class SyncFeedbackMapper {
  SyncFeedbackMapper._();

  static SyncFeedbackSummary fromResult(SyncResult result) {
    final nowMs = result.completedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final compactTarget = Formatters.formatCompactPath(result.targetPath);
    final detailPath = result.targetPath.trim().isNotEmpty
        ? '${AppStrings.syncTargetPathPrefix} $compactTarget'
        : null;

    if (result.status == SyncStatus.synced && result.syncedToNas) {
      return SyncFeedbackSummary(
        kind: SyncFeedbackKind.synced,
        syncedToNas: true,
        headline: AppStrings.syncNasCompletedStatus,
        detail: detailPath,
        targetPath: result.targetPath,
        timestampMs: nowMs,
        severity: StatusSeverity.success,
        isolatedEntryCount: result.isolatedEntryCount,
        diagnosticMessage: result.message,
      );
    }

    if (result.status == SyncStatus.localOnly ||
        (result.status == SyncStatus.synced && !result.syncedToNas)) {
      final isUnreachable = result.nasTargetUnreachable;
      return SyncFeedbackSummary(
        kind: isUnreachable
            ? SyncFeedbackKind.nasUnreachableFallback
            : SyncFeedbackKind.localFallback,
        syncedToNas: false,
        headline: isUnreachable
            ? AppStrings.syncNasUnreachableStatus
            : AppStrings.syncLocalFallbackStatus,
        detail: detailPath,
        targetPath: result.targetPath,
        timestampMs: nowMs,
        severity: StatusSeverity.warning,
        isolatedEntryCount: result.isolatedEntryCount,
        diagnosticMessage: result.message,
      );
    }

    switch (result.status) {
      case SyncStatus.conflict:
        return SyncFeedbackSummary(
          kind: SyncFeedbackKind.conflict,
          syncedToNas: false,
          headline: AppStrings.syncConflictStatus,
          detail: detailPath,
          targetPath: result.targetPath,
          timestampMs: nowMs,
          severity: StatusSeverity.warning,
          isolatedEntryCount: result.isolatedEntryCount,
          diagnosticMessage: result.message,
        );
      case SyncStatus.corrupt:
        return SyncFeedbackSummary(
          kind: SyncFeedbackKind.corrupt,
          syncedToNas: false,
          headline: AppStrings.syncCorruptStatus,
          detail: result.corruptBackupPath != null
              ? Formatters.formatCompactPath(result.corruptBackupPath!)
              : detailPath,
          targetPath: result.targetPath,
          timestampMs: nowMs,
          severity: StatusSeverity.error,
          isolatedEntryCount: result.isolatedEntryCount,
          diagnosticMessage: result.message,
        );
      case SyncStatus.incompatibleVersion:
        return SyncFeedbackSummary(
          kind: SyncFeedbackKind.incompatibleVersion,
          syncedToNas: false,
          headline: AppStrings.syncIncompatibleVersionStatus,
          detail: detailPath,
          targetPath: result.targetPath,
          timestampMs: nowMs,
          severity: StatusSeverity.error,
          isolatedEntryCount: result.isolatedEntryCount,
          diagnosticMessage: result.message,
        );
      case SyncStatus.cancelled:
        return SyncFeedbackSummary(
          kind: SyncFeedbackKind.cancelled,
          syncedToNas: false,
          headline: AppStrings.syncCancelledStatus,
          detail: detailPath,
          targetPath: result.targetPath,
          timestampMs: nowMs,
          severity: StatusSeverity.warning,
          isolatedEntryCount: result.isolatedEntryCount,
          diagnosticMessage: result.message,
        );
      case SyncStatus.failed:
      case SyncStatus.synced:
      case SyncStatus.localOnly:
        return SyncFeedbackSummary(
          kind: SyncFeedbackKind.failed,
          syncedToNas: false,
          headline: AppStrings.syncFailedStatus,
          detail: detailPath,
          targetPath: result.targetPath,
          timestampMs: nowMs,
          severity: StatusSeverity.error,
          isolatedEntryCount: result.isolatedEntryCount,
          diagnosticMessage: result.message,
        );
    }
  }

  static SyncFeedbackSummary fromException(Object error) {
    return SyncFeedbackSummary(
      kind: SyncFeedbackKind.failed,
      syncedToNas: false,
      headline: AppStrings.syncFailedStatus,
      targetPath: '',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      severity: StatusSeverity.error,
      diagnosticMessage: error.toString(),
    );
  }

  static SyncFeedbackSummary? restoredNasSync(
    int? timestampMs,
    String? targetPath,
  ) {
    if (timestampMs == null || timestampMs <= 0) return null;
    return SyncFeedbackSummary(
      kind: SyncFeedbackKind.synced,
      syncedToNas: true,
      headline: AppStrings.syncNasCompletedStatus,
      targetPath: targetPath ?? '',
      timestampMs: timestampMs,
      severity: StatusSeverity.success,
    );
  }
}
