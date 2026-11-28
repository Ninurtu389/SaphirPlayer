import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/controllers/library_controller.dart';
import '../../../core/controllers/settings_controller.dart';
import '../../../core/models/media_source_models.dart';
import '../../../core/utils/formatters.dart';
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
    this.onRemoveSource,
    this.onReactivateSource,
    this.onRescanSource,
  });

  final SettingsController settingsController;
  final LibraryController libraryController;
  final TextEditingController nasInputController;
  final VoidCallback onAddFolderFromInput;
  final VoidCallback onAddFolderFromPicker;
  final ValueChanged<String> onRemoveFolder;
  final VoidCallback onTriggerScan;
  final ValueChanged<MediaSourceEntry>? onRemoveSource;
  final ValueChanged<String>? onReactivateSource;
  final ValueChanged<String>? onRescanSource;

  @override
  Widget build(BuildContext context) {
    final sources = settingsController.mediaSources;
    return SettingsSectionCard(
      icon: Icons.folder_copy_outlined,
      title: AppStrings.settingsMediaSectionTitle,
      description: AppStrings.settingsMediaSectionDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputRow(),
          const SizedBox(height: AppSpacing.md),
          if (sources.isEmpty)
            _EmptySourcesBox()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sources.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) => _MediaSourceTile(
                source: sources[index],
                isScanning: libraryController.isScanning,
                onRescan: () => onRescanSource?.call(sources[index].rootPath),
                onReactivate: () =>
                    onReactivateSource?.call(sources[index].sourceId),
                onRemove: () => onRemoveSource != null
                    ? onRemoveSource!(sources[index])
                    : onRemoveFolder(sources[index].rootPath),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          _ScanFooterRow(
            libraryController: libraryController,
            onTriggerScan: onTriggerScan,
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

class _EmptySourcesBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _ScanFooterRow extends StatelessWidget {
  const _ScanFooterRow({
    required this.libraryController,
    required this.onTriggerScan,
  });

  final LibraryController libraryController;
  final VoidCallback onTriggerScan;

  @override
  Widget build(BuildContext context) {
    final isScanning = libraryController.isScanning;
    final canRetry =
        (libraryController.scanFeedback?.canRetry ?? false) && !isScanning;
    final statusText = isScanning
        ? Formatters.formatScanPhaseLabel(libraryController.scanPhase)
        : libraryController.statusMessage;
    final statusColor = libraryController.hasScanError
        ? AppColors.errorRed
        : (libraryController.hasScanWarning
            ? AppColors.warningAmber
            : AppColors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: isScanning ? null : onTriggerScan,
              icon: const Icon(Icons.refresh, size: AppSpacing.iconSizeMd),
              label: const Text(AppStrings.scanButton),
            ),
            if (statusText.isNotEmpty)
              Text(
                statusText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: statusColor,
                    ),
              ),
            if (canRetry)
              TextButton.icon(
                onPressed: onTriggerScan,
                icon: const Icon(Icons.replay, size: AppSpacing.iconSizeSm),
                label: const Text(AppStrings.scanRetryButton),
              ),
          ],
        ),
        if (libraryController.hasSyncIssue &&
            libraryController.lastSyncStatusMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${AppStrings.scanSyncWarningPrefix} ${libraryController.lastSyncStatusMessage}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.warningAmber,
                ),
          ),
        ],
      ],
    );
  }
}

class _MediaSourceTile extends StatelessWidget {
  const _MediaSourceTile({
    required this.source,
    required this.isScanning,
    required this.onRescan,
    required this.onReactivate,
    required this.onRemove,
  });

  final MediaSourceEntry source;
  final bool isScanning;
  final VoidCallback onRescan;
  final VoidCallback onReactivate;
  final VoidCallback onRemove;

  Color _dotColor() {
    switch (source.badgeKind) {
      case SourceBadgeKind.disabled:
        return AppColors.textSecondary;
      case SourceBadgeKind.complete:
        return AppColors.successGreen;
      case SourceBadgeKind.warning:
        return AppColors.warningAmber;
      case SourceBadgeKind.error:
        return AppColors.errorRed;
      case SourceBadgeKind.active:
        return AppColors.sapphireBright;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = _dotColor();
    final statusLine = '${Formatters.formatSourceStatusLabel(source)}'
        '${AppStrings.metadataSeparator}${Formatters.formatSourceMetrics(source)}';
    final hasError =
        source.lastScanError != null && source.lastScanError!.isNotEmpty;

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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: AppSpacing.sourceStatusDotSize,
            height: AppSpacing.sourceStatusDotSize,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: source.rootPath,
                  child: Text(
                    Formatters.formatCompactPath(source.rootPath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: source.isDisabled
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                        ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  statusLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (hasError)
                  Text(
                    source.lastScanError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.warningAmber,
                        ),
                  ),
              ],
            ),
          ),
          if (source.isActive)
            IconButton(
              tooltip: AppStrings.sourceRescanTooltip,
              onPressed: isScanning ? null : onRescan,
              icon: const Icon(
                Icons.refresh,
                size: AppSpacing.iconSizeMd,
              ),
            )
          else
            IconButton(
              tooltip: AppStrings.sourceReactivateTooltip,
              onPressed: onReactivate,
              icon: const Icon(
                Icons.play_circle_outline,
                size: AppSpacing.iconSizeMd,
                color: AppColors.sapphireBright,
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
