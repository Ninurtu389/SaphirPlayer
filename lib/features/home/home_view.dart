import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/local_file_service.dart';
import '../../core/theme/effect_mode.dart';
import '../library/library_models.dart';
import 'home_controller.dart';
import 'widgets/media_rail.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.homeController,
    required this.effectMode,
    required this.onSelectItem,
    required this.onOpenSeries,
  });

  final HomeController homeController;
  final EffectMode effectMode;
  final ValueChanged<MediaCardItem> onSelectItem;
  final ValueChanged<int> onOpenSeries;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: homeController,
      builder: (context, _) {
        final hero = homeController.heroItem;
        final hasAnyContent = hero != null ||
            homeController.continueWatching.isNotEmpty ||
            homeController.rediscoverItems.isNotEmpty ||
            homeController.recentlyAdded.isNotEmpty ||
            homeController.seriesItems.isNotEmpty ||
            homeController.movieItems.isNotEmpty;

        if (!hasAnyContent) {
          return Center(
            child: Text(
              AppStrings.emptyHomeMessage,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            if (hero != null) ...[
              _HeroBanner(
                hero: hero,
                effectMode: effectMode,
                onPlay: () => onSelectItem(hero),
                onOpenSeries: onOpenSeries,
                onPickRandom: () {
                  final pick = homeController.pickRandomItem();
                  if (pick != null) {
                    onSelectItem(pick);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            MediaRail(
              title: AppStrings.continueWatchingTitle,
              items: homeController.continueWatching,
              effectMode: effectMode,
              onSelectItem: onSelectItem,
              onOpenSeries: onOpenSeries,
            ),
            MediaRail(
              title: AppStrings.recentlyAddedTitle,
              items: homeController.recentlyAdded,
              effectMode: effectMode,
              onSelectItem: onSelectItem,
              onOpenSeries: onOpenSeries,
            ),
            MediaRail(
              title: AppStrings.rediscoverTitle,
              items: homeController.rediscoverItems,
              effectMode: effectMode,
              onSelectItem: onSelectItem,
              onOpenSeries: onOpenSeries,
            ),
            MediaRail(
              title: AppStrings.seriesCountLabel,
              items: homeController.seriesItems,
              effectMode: effectMode,
              onSelectItem: onSelectItem,
              onOpenSeries: onOpenSeries,
            ),
            MediaRail(
              title: AppStrings.moviesCountLabel,
              items: homeController.movieItems,
              effectMode: effectMode,
              onSelectItem: onSelectItem,
              onOpenSeries: onOpenSeries,
            ),
          ],
        );
      },
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.hero,
    required this.effectMode,
    required this.onPlay,
    required this.onOpenSeries,
    required this.onPickRandom,
  });

  final MediaCardItem hero;
  final EffectMode effectMode;
  final VoidCallback onPlay;
  final ValueChanged<int> onOpenSeries;
  final VoidCallback onPickRandom;

  @override
  Widget build(BuildContext context) {
    final imageProvider = LocalFileService.imageProviderForPath(hero.imagePath);
    final isGlass = effectMode == EffectMode.glass;

    return SizedBox(
      height: AppSpacing.heroBannerHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageProvider != null)
            Image(image: imageProvider, fit: BoxFit.cover)
          else
            _HeroFallbackBackdrop(hero: hero),
          if (isGlass)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.centerRight,
                  radius: AppSpacing.heroGlowRadius,
                  colors: [
                    AppColors.sapphireGlow,
                    AppColors.borderTransparent,
                  ],
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.heroHorizontalFadeGradient,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.heroVerticalFadeGradient,
            ),
          ),
          _HeroOverlayContent(
            hero: hero,
            onPlay: onPlay,
            onOpenSeries: onOpenSeries,
            onPickRandom: onPickRandom,
          ),
        ],
      ),
    );
  }
}

class _HeroFallbackBackdrop extends StatelessWidget {
  const _HeroFallbackBackdrop({required this.hero});

  final MediaCardItem hero;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.coverGradientForTitle(hero.title),
        ),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xxl),
          child: Text(
            hero.monogram,
            style: const TextStyle(
              fontSize: AppSpacing.heroMonogramFontSize,
              fontWeight: FontWeight.w900,
              color: AppColors.dividerHairline,
              letterSpacing: AppSpacing.heroMonogramLetterSpacing,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroOverlayContent extends StatelessWidget {
  const _HeroOverlayContent({
    required this.hero,
    required this.onPlay,
    required this.onOpenSeries,
    required this.onPickRandom,
  });

  final MediaCardItem hero;
  final VoidCallback onPlay;
  final ValueChanged<int> onOpenSeries;
  final VoidCallback onPickRandom;

  @override
  Widget build(BuildContext context) {
    final infoText = hero.remainingMinutes > 0
        ? '${hero.subtitle} · ${hero.remainingMinutes} ${AppStrings.remainingMinutesSuffix}'
        : hero.subtitle;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
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
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              if (infoText.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  infoText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
              if (hero.progressRatio > 0 && !hero.isCompleted) ...[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: AppSpacing.heroProgressWidth,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    child: LinearProgressIndicator(
                      value: hero.progressRatio,
                      minHeight: AppSpacing.progressBarHeight,
                      backgroundColor: AppColors.progressTrack,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.sapphireBright,
                      ),
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
                    onPressed: onPlay,
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
                      icon: const Icon(Icons.info_outline),
                      label: const Text(AppStrings.detailsButton),
                    ),
                  TextButton.icon(
                    onPressed: onPickRandom,
                    icon: const Icon(
                      Icons.shuffle,
                      size: AppSpacing.iconSizeMd,
                    ),
                    label: const Text(AppStrings.randomPickShortButton),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
