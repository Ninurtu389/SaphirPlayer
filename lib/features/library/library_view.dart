import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/library_controller.dart';
import '../../core/theme/effect_mode.dart';
import '../../widgets/media_tile.dart';
import '../library/library_models.dart';

class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.libraryController,
    required this.effectMode,
    required this.onSelectItem,
    required this.onOpenSeries,
    required this.onTriggerScan,
  });

  final LibraryController libraryController;
  final EffectMode effectMode;
  final ValueChanged<MediaCardItem> onSelectItem;
  final ValueChanged<int> onOpenSeries;
  final VoidCallback onTriggerScan;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: libraryController,
      builder: (context, _) {
        final items = libraryController.filteredItems;
        final activeFilter = libraryController.activeFilter;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.libraryOverviewTitle,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          '${libraryController.seriesCount} ${AppStrings.seriesCountLabel} · ${libraryController.movieCount} ${AppStrings.moviesCountLabel}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: AppSpacing.searchBarWidth,
                    child: TextField(
                      onChanged: libraryController.updateSearchQuery,
                      decoration: const InputDecoration(
                        hintText: AppStrings.searchHint,
                        prefixIcon: Icon(
                          Icons.search,
                          size: AppSpacing.iconSizeMd,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton.icon(
                    onPressed:
                        libraryController.isScanning ? null : onTriggerScan,
                    icon: const Icon(
                      Icons.refresh,
                      size: AppSpacing.iconSizeMd,
                    ),
                    label: const Text(AppStrings.scanButton),
                  ),
                ],
              ),
              if (libraryController.statusMessage.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  libraryController.statusMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
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
                onSelectionChanged: (selection) {
                  libraryController.setFilter(selection.first);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          AppStrings.emptyLibraryMessage,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: AppSpacing.libraryGridMaxExtent,
                          mainAxisExtent: AppSpacing.libraryGridMainAxisExtent,
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
                              if (item.mediaType == 'series' &&
                                  item.seriesId != null) {
                                onOpenSeries(item.seriesId!);
                              } else {
                                onSelectItem(item);
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
