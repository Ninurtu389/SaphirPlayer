import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/controllers/library_controller.dart';
import '../../../core/controllers/settings_controller.dart';
import '../../../core/theme/effect_mode.dart';

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
  });

  final SettingsController settingsController;
  final LibraryController libraryController;
  final TextEditingController nasInputController;
  final EffectMode effectMode;
  final String? statusMessage;
  final VoidCallback onAddFolderFromInput;
  final VoidCallback onAddFolderFromPicker;
  final ValueChanged<String> onRemoveFolder;
  final VoidCallback onTriggerScan;
  final VoidCallback onSaveSettings;
  final VoidCallback onSyncNow;
  final VoidCallback onClearCache;
  final VoidCallback onResetDatabase;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.maxSettingsWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.settingsTab,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildMediaSection(context),
              const SizedBox(height: AppSpacing.md),
              _buildAppearanceSection(context),
              const SizedBox(height: AppSpacing.md),
              _buildSyncSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaSection(BuildContext context) {
    final folders = settingsController.nasPaths;
    return _SettingsSectionCard(
      title: AppStrings.settingsMediaSectionTitle,
      description: AppStrings.settingsMediaSectionDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nasInputController,
                  onSubmitted: (_) => onAddFolderFromInput(),
                  decoration: const InputDecoration(
                    labelText: AppStrings.nasPathLabel,
                    hintText: AppStrings.nasPathHint,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ElevatedButton.icon(
                onPressed: onAddFolderFromPicker,
                icon: const Icon(
                  Icons.create_new_folder_outlined,
                  size: AppSpacing.iconSizeMd,
                ),
                label: const Text(AppStrings.addFolderButton),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (folders.isEmpty)
            Text(
              AppStrings.noFoldersConfigured,
              style: Theme.of(context).textTheme.bodySmall,
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
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: libraryController.isScanning ? null : onTriggerScan,
                icon: const Icon(Icons.refresh, size: AppSpacing.iconSizeMd),
                label: const Text(AppStrings.scanButton),
              ),
              if (libraryController.statusMessage.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    libraryController.statusMessage,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context) {
    return _SettingsSectionCard(
      title: AppStrings.settingsAppearanceSectionTitle,
      description: AppStrings.settingsAppearanceSectionDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<EffectMode>(
            segments: const [
              ButtonSegment<EffectMode>(
                value: EffectMode.glass,
                label: Text(AppStrings.effectGlassLabel),
              ),
              ButtonSegment<EffectMode>(
                value: EffectMode.lean,
                label: Text(AppStrings.effectLeanLabel),
              ),
            ],
            selected: {effectMode},
            onSelectionChanged: (selection) {
              settingsController.updateEffectMode(selection.first);
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            effectMode == EffectMode.glass
                ? AppStrings.settingsEffectGlassDesc
                : AppStrings.settingsEffectLeanDesc,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: AppSpacing.dividerThickness),
          const SizedBox(height: AppSpacing.xs),
          Material(
            color: AppColors.borderTransparent,
            child: SwitchListTile(
              tileColor: AppColors.borderTransparent,
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.perDeviceEffectLabel),
              subtitle: Text(
                AppStrings.settingsPerDeviceDesc,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: settingsController.perDeviceEffect,
              onChanged: settingsController.updatePerDeviceEffect,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSection(BuildContext context) {
    return _SettingsSectionCard(
      title: AppStrings.settingsSyncSectionTitle,
      description: AppStrings.settingsSyncSectionDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${AppStrings.cacheSectionTitle}: ${settingsController.formattedCacheSize}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              ElevatedButton.icon(
                onPressed: onSaveSettings,
                icon: const Icon(
                  Icons.save_outlined,
                  size: AppSpacing.iconSizeMd,
                ),
                label: const Text(AppStrings.saveSettingsButton),
              ),
              OutlinedButton.icon(
                onPressed: onSyncNow,
                icon: const Icon(Icons.sync, size: AppSpacing.iconSizeMd),
                label: const Text(AppStrings.syncNowButton),
              ),
              OutlinedButton.icon(
                onPressed: onClearCache,
                icon: const Icon(
                  Icons.delete_outline,
                  size: AppSpacing.iconSizeMd,
                ),
                label: const Text(AppStrings.clearCacheButton),
              ),
              OutlinedButton.icon(
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
            ],
          ),
          if (statusMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              statusMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.successGreen,
                  ),
            ),
          ],
        ],
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

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.anthraciteSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
