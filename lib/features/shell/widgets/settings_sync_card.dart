import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/controllers/library_controller.dart';
import '../../../core/controllers/settings_controller.dart';
import 'settings_subtitle_section.dart';

class SettingsSyncCard extends StatelessWidget {
  const SettingsSyncCard({
    super.key,
    required this.settingsController,
    required this.onSyncNow,
    required this.onClearCache,
    required this.onResetDatabase,
    this.libraryController,
    this.onRetryFailedThumbnails,
    this.onCreateBackup,
    this.onRestoreBackup,
    this.isBusy = false,
  });

  final SettingsController settingsController;
  final LibraryController? libraryController;
  final VoidCallback onSyncNow;
  final VoidCallback onClearCache;
  final VoidCallback onResetDatabase;
  final VoidCallback? onRetryFailedThumbnails;
  final VoidCallback? onCreateBackup;
  final VoidCallback? onRestoreBackup;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final busy = isBusy || settingsController.isMaintenanceInProgress;
    return SettingsSectionCard(
      icon: Icons.sync_outlined,
      title: AppStrings.settingsSyncSectionTitle,
      description: AppStrings.settingsSyncSectionDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActionRowTile(
            icon: Icons.sync,
            title: AppStrings.settingsSyncActionTitle,
            subtitle: _syncSubtitle(),
            action: OutlinedButton.icon(
              onPressed: busy ? null : onSyncNow,
              icon: const Icon(Icons.sync, size: AppSpacing.iconSizeMd),
              label: const Text(AppStrings.syncNowButton),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ActionRowTile(
            icon: Icons.image_outlined,
            title:
                '${AppStrings.cacheSectionTitle}: ${settingsController.formattedCacheSize}',
            subtitle: _cacheSubtitle(),
            stackActions:
                (libraryController?.hasRetryableThumbnails ?? false) &&
                    onRetryFailedThumbnails != null,
            action: _buildCacheActions(busy),
          ),
          const SizedBox(height: AppSpacing.sm),
          _BackupRowTile(
            subtitle: settingsController.formattedLatestBackup,
            onCreateBackup: busy ? null : onCreateBackup,
            onRestoreBackup: (busy || settingsController.latestBackup == null)
                ? null
                : onRestoreBackup,
          ),
          if (settingsController.storageDataPath.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _StorageInfoTile(
              modeLabel: settingsController.isPortableMode
                  ? AppStrings.storageModePortableLabel
                  : AppStrings.storageModeStandardLabel,
              dataPath: settingsController.storageDataPath,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _ActionRowTile(
            icon: Icons.warning_amber_rounded,
            iconColor: AppColors.errorRed,
            backgroundColor: AppColors.dangerTileFill,
            borderColor: AppColors.dangerTileBorder,
            title: AppStrings.settingsDangerZoneTitle,
            subtitle: AppStrings.settingsDangerZoneDesc,
            action: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.errorRed,
                side: const BorderSide(color: AppColors.errorRed),
              ),
              onPressed: busy ? null : onResetDatabase,
              icon: const Icon(
                Icons.delete_forever_outlined,
                size: AppSpacing.iconSizeMd,
              ),
              label: const Text(AppStrings.resetDatabaseButton),
            ),
          ),
        ],
      ),
    );
  }

  String _syncSubtitle() {
    final parts = <String>[AppStrings.settingsSyncActionDesc];
    final lastFeedback = settingsController.lastSyncFeedback;
    if (lastFeedback != null) {
      final line = lastFeedback.detail != null
          ? '${lastFeedback.headline} (${lastFeedback.detail})'
          : lastFeedback.headline;
      parts.add(line);
    }
    parts.add(settingsController.formattedLastSuccessfulSync);
    return parts.join('\n');
  }

  String _cacheSubtitle() {
    final queueStats = libraryController?.thumbnailQueueStats;
    if (queueStats == null || queueStats.totalCount == 0) {
      return AppStrings.settingsCacheActionDesc;
    }
    return '${AppStrings.settingsCacheActionDesc}\n'
        '${libraryController!.formattedThumbnailQueueStatus}';
  }

  Widget _buildCacheActions(bool busy) {
    final canRetry = (libraryController?.hasRetryableThumbnails ?? false) &&
        onRetryFailedThumbnails != null;
    final clearButton = OutlinedButton.icon(
      onPressed: busy ? null : onClearCache,
      icon: const Icon(Icons.delete_outline, size: AppSpacing.iconSizeMd),
      label: const Text(AppStrings.clearCacheButton),
    );
    if (!canRetry) return clearButton;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        clearButton,
        OutlinedButton.icon(
          onPressed: busy ? null : onRetryFailedThumbnails,
          icon: const Icon(Icons.refresh, size: AppSpacing.iconSizeMd),
          label: const Text(AppStrings.retryThumbnailsButton),
        ),
      ],
    );
  }
}

class _ActionRowTile extends StatelessWidget {
  const _ActionRowTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    this.iconColor = AppColors.sapphireBright,
    this.backgroundColor = AppColors.elevatedSurface,
    this.borderColor = AppColors.borderSubtle,
    this.stackActions = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget action;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final bool stackActions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: AppSpacing.iconSizeMd, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          );

          if (stackActions ||
              constraints.maxWidth < AppSpacing.settingsCompactRowBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: AppSpacing.sm),
                action,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: AppSpacing.sm),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _BackupRowTile extends StatelessWidget {
  const _BackupRowTile({
    required this.subtitle,
    required this.onCreateBackup,
    required this.onRestoreBackup,
  });

  final String subtitle;
  final VoidCallback? onCreateBackup;
  final VoidCallback? onRestoreBackup;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.backup_outlined,
                size: AppSpacing.iconSizeMd,
                color: AppColors.sapphireBright,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.backupSectionTitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                onPressed: onCreateBackup,
                icon: const Icon(Icons.save_alt, size: AppSpacing.iconSizeMd),
                label: const Text(AppStrings.backupCreateButton),
              ),
              OutlinedButton.icon(
                onPressed: onRestoreBackup,
                icon: const Icon(Icons.restore, size: AppSpacing.iconSizeMd),
                label: const Text(AppStrings.backupRestoreButton),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageInfoTile extends StatelessWidget {
  const _StorageInfoTile({
    required this.modeLabel,
    required this.dataPath,
  });

  final String modeLabel;
  final String dataPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.folder_special_outlined,
            size: AppSpacing.iconSizeMd,
            color: AppColors.sapphireBright,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${AppStrings.storageLocationTitle}: $modeLabel',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                SelectableText(
                  dataPath,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
