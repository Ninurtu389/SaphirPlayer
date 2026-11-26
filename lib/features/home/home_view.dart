import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/effect_mode.dart';
import '../../widgets/media_tile.dart';
import '../library/library_models.dart';
import 'home_controller.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.homeController,
    required this.effectMode,
    required this.onSelectItem,
    required this.onOpenSeries,
    required this.onTriggerScan,
  });

  final HomeController homeController;
  final EffectMode effectMode;
  final ValueChanged<MediaCardItem> onSelectItem;
  final ValueChanged<int> onOpenSeries;
  final VoidCallback onTriggerScan;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: homeController,
      builder: (context, _) {
        final hero = homeController.heroItem;
        final hasAnyContent = hero != null ||
            homeController.continueWatching.isNotEmpty ||
            homeController.rediscoverItems.isNotEmpty ||
            homeController.recentlyAdded.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: homeController.updateSearchQuery,
                    decoration: const InputDecoration(
                      hintText: AppStrings.searchHint,
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton.icon(
                  onPressed: () {
                    final pick = homeController.pickRandomItem();
                    if (pick != null) {
                      onSelectItem(pick);
                    }
                  },
                  icon: const Icon(Icons.shuffle, size: AppSpacing.iconSizeMd),
                  label: const Text(AppStrings.randomPickButton),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: AppStrings.scanButton,
                  onPressed: onTriggerScan,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: !hasAnyContent
                  ? Center(
                      child: Text(
                        AppStrings.emptyHomeMessage,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView(
                      children: [
                        if (hero != null) ...[
                          _buildHeroBanner(context, hero),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        _buildRail(
                          context,
                          AppStrings.continueWatchingTitle,
                          homeController.continueWatching,
                        ),
                        _buildRail(
                          context,
                          AppStrings.rediscoverTitle,
                          homeController.rediscoverItems,
                        ),
                        _buildRail(
                          context,
                          AppStrings.recentlyAddedTitle,
                          homeController.recentlyAdded,
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeroBanner(BuildContext context, MediaCardItem hero) {
    final hasImage =
        hero.imagePath != null && File(hero.imagePath!).existsSync();
    final isGlass = effectMode == EffectMode.glass;
    final infoText = hero.remainingMinutes > 0
        ? '${hero.subtitle} · ${hero.remainingMinutes} ${AppStrings.remainingMinutesSuffix}'
        : hero.subtitle;

    return Container(
      height: AppSpacing.heroBannerHeight,
      decoration: BoxDecoration(
        color: AppColors.anthraciteSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: isGlass ? AppColors.sapphireGlow : AppColors.borderSubtle,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              Image.file(
                File(hero.imagePath!),
                fit: BoxFit.cover,
              )
            else
              Container(color: AppColors.elevatedSurface),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    AppColors.heroGradientStart,
                    AppColors.heroGradientMid,
                    AppColors.heroGradientEnd,
                  ],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.cardGradientBottom,
                    AppColors.cardGradientTop,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSpacing.heroContentMaxWidth,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hero.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (infoText.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          infoText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ],
                      if (hero.progressRatio > 0 && !hero.isCompleted) ...[
                        const SizedBox(height: AppSpacing.sm),
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                          child: LinearProgressIndicator(
                            value: hero.progressRatio,
                            minHeight: AppSpacing.progressBarHeight,
                            backgroundColor: AppColors.progressTrack,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.sapphireBright,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => onSelectItem(hero),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(
                              hero.progressRatio > 0
                                  ? AppStrings.resumeButton
                                  : AppStrings.playNowButton,
                            ),
                          ),
                          if (hero.seriesId != null)
                            OutlinedButton.icon(
                              onPressed: () => onOpenSeries(hero.seriesId!),
                              icon: const Icon(Icons.list_alt),
                              label: const Text(AppStrings.openSeriesButton),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRail(
    BuildContext context,
    String title,
    List<MediaCardItem> items,
  ) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: AppSpacing.tileRailHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AppSpacing.railSpacing),
              itemBuilder: (context, index) {
                final item = items[index];
                return MediaTile(
                  item: item,
                  effectMode: effectMode,
                  onTap: () {
                    if (item.mediaType == 'series' && item.seriesId != null) {
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
  }
}
