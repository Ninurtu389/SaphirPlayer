import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/controllers/settings_controller.dart';
import 'settings_subtitle_section.dart';

class SettingsSyncCard extends StatelessWidget {
  const SettingsSyncCard({
    super.key,
    required this.settingsController,
    required this.onSyncNow,
    required this.onClearCache,
    required this.onResetDatabase,
  });

  final SettingsController settingsController;
  final VoidCallback onSyncNow;
  final VoidCallback onClearCache;
  final VoidCallback onResetDatabase;

  @override
  Widget build(BuildContext context) {
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
            subtitle: AppStrings.settingsSyncActionDesc,
            action: OutlinedButton.icon(
              onPressed: onSyncNow,
              icon: const Icon(Icons.sync, size: AppSpacing.iconSizeMd),
              label: const Text(AppStrings.syncNowButton),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ActionRowTile(
            icon: Icons.image_outlined,
            title:
                '${AppStrings.cacheSectionTitle}: ${settingsController.formattedCacheSize}',
            subtitle: AppStrings.settingsCacheActionDesc,
            action: OutlinedButton.icon(
              onPressed: onClearCache,
              icon: const Icon(
                Icons.delete_outline,
                size: AppSpacing.iconSizeMd,
              ),
              label: const Text(AppStrings.clearCacheButton),
            ),
          ),
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
              onPressed: onResetDatabase,
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget action;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;

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

          if (constraints.maxWidth < AppSpacing.settingsCompactRowBreakpoint) {
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
