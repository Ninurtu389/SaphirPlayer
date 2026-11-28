import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/controllers/library_controller.dart';
import '../../../core/controllers/settings_controller.dart';
import '../../../core/models/media_source_models.dart';
import '../../../core/models/status_feedback_models.dart';
import '../../../core/theme/effect_mode.dart';
import 'settings_cards.dart';
import 'settings_media_card.dart';
import 'settings_subtitle_section.dart';
import 'settings_sync_card.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.settingsController,
    required this.libraryController,
    required this.nasInputController,
    required this.effectMode,
    required this.statusMessage,
    required this.onAddFolderFromInput,
    required this.onAddFolderFromPicker,
    required this.onRemoveFolder,
    required this.onTriggerScan,
    required this.onSaveSettings,
    required this.onSyncNow,
    required this.onClearCache,
    required this.onResetDatabase,
    this.statusBanner,
    this.onRemoveSource,
    this.onReactivateSource,
    this.onRescanSource,
    this.onRetryFailedThumbnails,
    this.onCreateBackup,
    this.onRestoreBackup,
    this.isBusy = false,
  });

  final SettingsController settingsController;
  final LibraryController libraryController;
  final TextEditingController nasInputController;
  final EffectMode effectMode;
  final String? statusMessage;
  final StatusBannerMessage? statusBanner;
  final VoidCallback onAddFolderFromInput;
  final VoidCallback onAddFolderFromPicker;
  final ValueChanged<String> onRemoveFolder;
  final VoidCallback onTriggerScan;
  final VoidCallback onSaveSettings;
  final VoidCallback onSyncNow;
  final VoidCallback onClearCache;
  final VoidCallback onResetDatabase;
  final ValueChanged<MediaSourceEntry>? onRemoveSource;
  final ValueChanged<String>? onReactivateSource;
  final ValueChanged<String>? onRescanSource;
  final VoidCallback? onRetryFailedThumbnails;
  final VoidCallback? onCreateBackup;
  final VoidCallback? onRestoreBackup;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final effectiveBanner = statusBanner ??
        (statusMessage != null
            ? StatusBannerMessage(
                message: statusMessage!,
                severity: StatusSeverity.success,
              )
            : null);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.statsMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsHeader(onSaveSettings: onSaveSettings),
              if (effectiveBanner != null) ...[
                const SizedBox(height: AppSpacing.md),
                _SettingsStatusBanner(banner: effectiveBanner),
              ],
              const SizedBox(height: AppSpacing.lg),
              _buildResponsiveGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponsiveGrid() {
    final mediaCard = SettingsMediaCard(
      settingsController: settingsController,
      libraryController: libraryController,
      nasInputController: nasInputController,
      onAddFolderFromInput: onAddFolderFromInput,
      onAddFolderFromPicker: onAddFolderFromPicker,
      onRemoveFolder: onRemoveFolder,
      onTriggerScan: onTriggerScan,
      onRemoveSource: onRemoveSource,
      onReactivateSource: onReactivateSource,
      onRescanSource: onRescanSource,
    );
    final appearanceCard = SettingsAppearanceCard(
      settingsController: settingsController,
      effectMode: effectMode,
    );
    final subtitleCard = SettingsSubtitleSection(
      settingsController: settingsController,
    );
    final syncCard = SettingsSyncCard(
      settingsController: settingsController,
      libraryController: libraryController,
      onSyncNow: onSyncNow,
      onClearCache: onClearCache,
      onResetDatabase: onResetDatabase,
      onRetryFailedThumbnails: onRetryFailedThumbnails,
      onCreateBackup: onCreateBackup,
      onRestoreBackup: onRestoreBackup,
      isBusy: isBusy,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppSpacing.settingsTwoColumnBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    mediaCard,
                    const SizedBox(height: AppSpacing.md),
                    syncCard,
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  children: [
                    appearanceCard,
                    const SizedBox(height: AppSpacing.md),
                    subtitleCard,
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            mediaCard,
            const SizedBox(height: AppSpacing.md),
            appearanceCard,
            const SizedBox(height: AppSpacing.md),
            subtitleCard,
            const SizedBox(height: AppSpacing.md),
            syncCard,
          ],
        );
      },
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.onSaveSettings});

  final VoidCallback onSaveSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.settingsTab,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                AppStrings.settingsPageSubtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: onSaveSettings,
            icon: const Icon(
              Icons.save_outlined,
              size: AppSpacing.iconSizeMd,
            ),
            label: const Text(AppStrings.saveSettingsButton),
          ),
        ],
      ),
    );
  }
}

class _SettingsStatusBanner extends StatelessWidget {
  const _SettingsStatusBanner({required this.banner});

  final StatusBannerMessage banner;

  ({Color fill, Color border, Color foreground, IconData icon}) _style() {
    switch (banner.severity) {
      case StatusSeverity.success:
        return (
          fill: AppColors.successBannerFill,
          border: AppColors.successBannerBorder,
          foreground: AppColors.successGreen,
          icon: Icons.check_circle_outline,
        );
      case StatusSeverity.warning:
        return (
          fill: AppColors.warningBannerFill,
          border: AppColors.warningBannerBorder,
          foreground: AppColors.warningAmber,
          icon: Icons.warning_amber_rounded,
        );
      case StatusSeverity.error:
        return (
          fill: AppColors.dangerTileFill,
          border: AppColors.dangerTileBorder,
          foreground: AppColors.errorRed,
          icon: Icons.error_outline,
        );
      case StatusSeverity.info:
        return (
          fill: AppColors.infoBannerFill,
          border: AppColors.infoBannerBorder,
          foreground: AppColors.sapphireBright,
          icon: Icons.info_outline,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: s.fill,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: s.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(s.icon, size: AppSpacing.iconSizeMd, color: s.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  banner.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: s.foreground,
                      ),
                ),
                if (banner.detail != null && banner.detail!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    banner.detail!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
