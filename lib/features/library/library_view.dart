import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/library_controller.dart';
import '../../core/theme/effect_mode.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/media_tile.dart';
import '../library/library_models.dart';

class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.libraryController,
    required this.effectMode,
    required this.onSelectItem,
    required this.onOpenSeries,
    this.onRetryScan,
  });

  final LibraryController libraryController;
  final EffectMode effectMode;
  final ValueChanged<MediaCardItem> onSelectItem;
  final ValueChanged<int> onOpenSeries;
  final VoidCallback? onRetryScan;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: libraryController,
      builder: (context, _) {
        final items = libraryController.filteredItems;
        final activeFilter = libraryController.activeFilter;
        final showStatusBar = libraryController.isScanning ||
            libraryController.hasScanError ||
            libraryController.hasScanWarning ||
            libraryController.hasSyncIssue;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LibraryHeader(
                activeFilter: activeFilter,
                onFilterChanged: libraryController.setFilter,
              ),
              if (showStatusBar) ...[
                const SizedBox(height: AppSpacing.sm),
                _LibraryScanStatusBar(
                  libraryController: libraryController,
                  onRetryScan: onRetryScan,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          AppStrings.emptyLibraryMessage,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : _LibraryGrid(
                        items: items,
                        effectMode: effectMode,
                        onSelectItem: onSelectItem,
                        onOpenSeries: onOpenSeries,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.activeFilter,
    required this.onFilterChanged,
  });

  final LibraryFilter activeFilter;
  final ValueChanged<LibraryFilter> onFilterChanged;

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
          Text(
            AppStrings.libraryOverviewTitle,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          SegmentedButton<LibraryFilter>(
            segments: const [
              ButtonSegment<LibraryFilter>(
                value: LibraryFilter.all,
                label: Text(AppStrings.filterAllLabel),
              ),
              ButtonSegment<LibraryFilter>(
                value: LibraryFilter.series,
                label: Text(AppStrings.filterSeriesLabel),
              ),
              ButtonSegment<LibraryFilter>(
                value: LibraryFilter.movies,
                label: Text(AppStrings.filterMoviesLabel),
              ),
            ],
            selected: {activeFilter},
            onSelectionChanged: (selection) => onFilterChanged(selection.first),
          ),
        ],
      ),
    );
  }
}

class _LibraryScanStatusBar extends StatelessWidget {
  const _LibraryScanStatusBar({
    required this.libraryController,
    this.onRetryScan,
  });

  final LibraryController libraryController;
  final VoidCallback? onRetryScan;

  @override
  Widget build(BuildContext context) {
    final isScanning = libraryController.isScanning;
    final isError = !isScanning && libraryController.hasScanError;
    final isWarning = !isScanning && libraryController.hasScanWarning;
    final foreground = isScanning
        ? AppColors.sapphireBright
        : (isError ? AppColors.errorRed : AppColors.warningAmber);
    final fill = isScanning
        ? AppColors.infoBannerFill
        : (isError ? AppColors.dangerTileFill : AppColors.warningBannerFill);
    final border = isScanning
        ? AppColors.infoBannerBorder
        : (isError
            ? AppColors.dangerTileBorder
            : AppColors.warningBannerBorder);

    final primaryText = isScanning
        ? Formatters.formatScanPhaseLabel(libraryController.scanPhase)
        : (libraryController.scanFeedback?.message ??
            libraryController.statusMessage);
    final detailText =
        isScanning ? null : libraryController.scanFeedback?.detail;
    final canRetry = !isScanning &&
        (libraryController.scanFeedback?.canRetry ?? false) &&
        onRetryScan != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: border),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            isScanning
                ? Icons.sync
                : (isError ? Icons.error_outline : Icons.warning_amber_rounded),
            size: AppSpacing.iconSizeMd,
            color: foreground,
          ),
          if (primaryText.isNotEmpty)
            Text(
              primaryText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          if (detailText != null && detailText.isNotEmpty)
            Text(
              detailText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (libraryController.hasSyncIssue &&
              libraryController.lastSyncStatusMessage != null &&
              (isError || isWarning || !isScanning))
            Text(
              '${AppStrings.scanSyncWarningPrefix} ${libraryController.lastSyncStatusMessage}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.warningAmber,
                  ),
            ),
          if (canRetry)
            TextButton.icon(
              onPressed: onRetryScan,
              icon: const Icon(Icons.replay, size: AppSpacing.iconSizeSm),
              label: const Text(AppStrings.scanRetryButton),
            ),
        ],
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.items,
    required this.effectMode,
    required this.onSelectItem,
    required this.onOpenSeries,
  });

  final List<MediaCardItem> items;
  final EffectMode effectMode;
  final ValueChanged<MediaCardItem> onSelectItem;
  final ValueChanged<int> onOpenSeries;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.xs),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: AppSpacing.libraryGridMaxExtent,
        childAspectRatio: AppSpacing.thumbWidth / AppSpacing.thumbHeight,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MediaTile(
          item: item,
          effectMode: effectMode,
          width: double.infinity,
          onTap: () {
            if (item.mediaType == 'series' && item.seriesId != null) {
              onOpenSeries(item.seriesId!);
            } else {
              onSelectItem(item);
            }
          },
        );
      },
    );
  }
}
