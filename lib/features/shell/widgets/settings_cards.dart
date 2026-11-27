import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/controllers/library_controller.dart';
import '../../../core/controllers/settings_controller.dart';
import '../../../core/theme/effect_mode.dart';
import 'settings_subtitle_section.dart';

class SettingsMediaCard extends StatelessWidget {
  const SettingsMediaCard({
    super.key,
    required this.settingsController,
    required this.libraryController,
    required this.nasInputController,
    required this.onAddFolderFromInput,
    required this.onAddFolderFromPicker,
    required this.onRemoveFolder,
    required this.onTriggerScan,
  });

  final SettingsController settingsController;
  final LibraryController libraryController;
  final TextEditingController nasInputController;
  final VoidCallback onAddFolderFromInput;
  final VoidCallback onAddFolderFromPicker;
  final ValueChanged<String> onRemoveFolder;
  final VoidCallback onTriggerScan;

  @override
  Widget build(BuildContext context) {
    final folders = settingsController.nasPaths;
    return SettingsSectionCard(
      icon: Icons.folder_copy_outlined,
      title: AppStrings.settingsMediaSectionTitle,
      description: AppStrings.settingsMediaSectionDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputRow(),
          const SizedBox(height: AppSpacing.md),
          if (folders.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.elevatedSurface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Text(
                AppStrings.noFoldersConfigured,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: folders.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) => _FolderListItem(
                folderPath: folders[index],
                onRemove: () => onRemoveFolder(folders[index]),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: libraryController.isScanning ? null : onTriggerScan,
                icon: const Icon(Icons.refresh, size: AppSpacing.iconSizeMd),
                label: const Text(AppStrings.scanButton),
              ),
              if (libraryController.statusMessage.isNotEmpty)
                Text(
                  libraryController.statusMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow() {
    final field = TextField(
      controller: nasInputController,
      onSubmitted: (_) => onAddFolderFromInput(),
      decoration: InputDecoration(
        labelText: AppStrings.nasPathLabel,
        hintText: AppStrings.nasPathHint,
        isDense: true,
        suffixIcon: IconButton(
          tooltip: AppStrings.settingsAddManualFolderTooltip,
          onPressed: onAddFolderFromInput,
          icon: const Icon(
            Icons.add_circle_outline,
            size: AppSpacing.iconSizeMd,
          ),
        ),
      ),
    );
    final addBtn = OutlinedButton.icon(
      onPressed: onAddFolderFromPicker,
      icon: const Icon(
        Icons.create_new_folder_outlined,
        size: AppSpacing.iconSizeMd,
      ),
      label: const Text(AppStrings.addFolderButton),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppSpacing.settingsCompactRowBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: AppSpacing.xs),
              addBtn,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: AppSpacing.sm),
            addBtn,
          ],
        );
      },
    );
  }
}

class SettingsAppearanceCard extends StatelessWidget {
  const SettingsAppearanceCard({
    super.key,
    required this.settingsController,
    required this.effectMode,
  });

  final SettingsController settingsController;
  final EffectMode effectMode;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      icon: Icons.display_settings_outlined,
      title: AppStrings.settingsAppearanceSectionTitle,
      description: AppStrings.settingsAppearanceSectionDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEffectModeSelector(),
          const SizedBox(height: AppSpacing.md),
          const Divider(
            height: AppSpacing.dividerThickness,
            color: AppColors.dividerHairline,
          ),
          const SizedBox(height: AppSpacing.xs),
          SettingsToggleTile(
            title: AppStrings.perDeviceEffectLabel,
            subtitle: AppStrings.settingsPerDeviceDesc,
            value: settingsController.perDeviceEffect,
            onChanged: settingsController.updatePerDeviceEffect,
          ),
          const Divider(
            height: AppSpacing.dividerThickness,
            color: AppColors.dividerHairline,
          ),
          SettingsToggleTile(
            title: AppStrings.settingsHwdecLabel,
            subtitle: AppStrings.settingsHwdecDesc,
            value: settingsController.hardwareAccelerationEnabled,
            onChanged: settingsController.updateHardwareAcceleration,
          ),
        ],
      ),
    );
  }

  Widget _buildEffectModeSelector() {
    final glassCard = _EffectModeOptionCard(
      icon: Icons.auto_awesome_outlined,
      title: AppStrings.effectGlassLabel,
      description: AppStrings.settingsEffectGlassDesc,
      selected: effectMode == EffectMode.glass,
      onTap: () => settingsController.updateEffectMode(EffectMode.glass),
    );
    final leanCard = _EffectModeOptionCard(
      icon: Icons.bolt_outlined,
      title: AppStrings.effectLeanLabel,
      description: AppStrings.settingsEffectLeanDesc,
      selected: effectMode == EffectMode.lean,
      onTap: () => settingsController.updateEffectMode(EffectMode.lean),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppSpacing.settingsCompactRowBreakpoint) {
          return Column(
            children: [
              glassCard,
              const SizedBox(height: AppSpacing.sm),
              leanCard,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: glassCard),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: leanCard),
            ],
          ),
        );
      },
    );
  }
}

class _EffectModeOptionCard extends StatelessWidget {
  const _EffectModeOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.activeTileFill : AppColors.elevatedSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: selected ? AppColors.sapphireBright : AppColors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: AppSpacing.iconSizeSm,
                  color: selected
                      ? AppColors.sapphireBright
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderListItem extends StatelessWidget {
  const _FolderListItem({
    required this.folderPath,
    required this.onRemove,
  });

  final String folderPath;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.folder_outlined,
            color: AppColors.sapphireBright,
            size: AppSpacing.iconSizeMd,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              folderPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            tooltip: AppStrings.removeFolderTooltip,
            onPressed: onRemove,
            icon: const Icon(
              Icons.delete_outline,
              size: AppSpacing.iconSizeMd,
            ),
          ),
        ],
      ),
    );
  }
}
