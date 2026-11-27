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
  });

  final LibraryController libraryController;
  final EffectMode effectMode;
  final ValueChanged<MediaCardItem> onSelectItem;
  final ValueChanged<int> onOpenSeries;

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
              SizedBox(
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
                      onSelectionChanged: (selection) {
                        libraryController.setFilter(selection.first);
                      },
                    ),
                  ],
                ),
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
                          childAspectRatio:
                              AppSpacing.thumbWidth / AppSpacing.thumbHeight,
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
