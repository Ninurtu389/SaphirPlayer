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

        return !hasAnyContent
            ? Center(
                child: Text(
                  AppStrings.emptyHomeMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                children: [
                  if (hero != null) ...[
                    _buildHeroBanner(context, hero),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  _MediaRail(
                    title: AppStrings.continueWatchingTitle,
                    items: homeController.continueWatching,
                    effectMode: effectMode,
                    onSelectItem: onSelectItem,
                    onOpenSeries: onOpenSeries,
                  ),
                  _MediaRail(
                    title: AppStrings.recentlyAddedTitle,
                    items: homeController.recentlyAdded,
                    effectMode: effectMode,
                    onSelectItem: onSelectItem,
                    onOpenSeries: onOpenSeries,
                  ),
                  _MediaRail(
                    title: AppStrings.rediscoverTitle,
                    items: homeController.rediscoverItems,
                    effectMode: effectMode,
                    onSelectItem: onSelectItem,
                    onOpenSeries: onOpenSeries,
                  ),
                  _MediaRail(
                    title: AppStrings.seriesCountLabel,
                    items: homeController.seriesItems,
                    effectMode: effectMode,
                    onSelectItem: onSelectItem,
                    onOpenSeries: onOpenSeries,
                  ),
                  _MediaRail(
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

  Widget _buildHeroBanner(BuildContext context, MediaCardItem hero) {
    final hasImage =
        hero.imagePath != null && File(hero.imagePath!).existsSync();
    final isGlass = effectMode == EffectMode.glass;
    final infoText = hero.remainingMinutes > 0
        ? '${hero.subtitle} · ${hero.remainingMinutes} ${AppStrings.remainingMinutesSuffix}'
        : hero.subtitle;
    final fallbackColors = AppColors.coverGradientForTitle(hero.title);

    return SizedBox(
      height: AppSpacing.heroBannerHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            Image.file(
              File(hero.imagePath!),
              fit: BoxFit.cover,
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: fallbackColors,
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
                      letterSpacing: 4.0,
                    ),
                  ),
                ),
              ),
            ),
          if (isGlass)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.centerRight,
                  radius: 0.9,
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
          Padding(
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                    if (hero.progressRatio > 0 && !hero.isCompleted) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: AppSpacing.heroProgressWidth,
                        child: ClipRRect(
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
                            icon: const Icon(Icons.info_outline),
                            label: const Text(AppStrings.detailsButton),
                          ),
                        TextButton.icon(
                          onPressed: () {
                            final pick = homeController.pickRandomItem();
                            if (pick != null) {
                              onSelectItem(pick);
                            }
                          },
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
          ),
        ],
      ),
    );
  }
}

class _MediaRail extends StatefulWidget {
  const _MediaRail({
    required this.title,
    required this.items,
    required this.effectMode,
    required this.onSelectItem,
    required this.onOpenSeries,
  });

  final String title;
  final List<MediaCardItem> items;
  final EffectMode effectMode;
  final ValueChanged<MediaCardItem> onSelectItem;
  final ValueChanged<int> onOpenSeries;

  @override
  State<_MediaRail> createState() => _MediaRailState();
}

class _MediaRailState extends State<_MediaRail> {
  final ScrollController _scrollController = ScrollController();
  bool _isHovered = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollIndicators);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollIndicators();
    });
  }

  @override
  void didUpdateWidget(covariant _MediaRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScrollIndicators();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollIndicators() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final pos = _scrollController.position;
    final nextLeft = pos.pixels > AppSpacing.scrollEdgeTolerance;
    final nextRight = pos.maxScrollExtent > AppSpacing.scrollEdgeTolerance &&
        pos.pixels < pos.maxScrollExtent - AppSpacing.scrollEdgeTolerance;
    if (nextLeft != _canScrollLeft || nextRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = nextLeft;
        _canScrollRight = nextRight;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) {
      return;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    final target = (_scrollController.offset + delta).clamp(0.0, maxExtent);
    if (widget.effectMode == EffectMode.glass) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: AppSpacing.hoverAnimationMs),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: SizedBox(
              height: AppSpacing.tileRailHeight,
              child: Stack(
                children: [
                  NotificationListener<ScrollMetricsNotification>(
                    onNotification: (_) {
                      _updateScrollIndicators();
                      return false;
                    },
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xs,
                      ),
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: AppSpacing.railSpacing),
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        return MediaTile(
                          item: item,
                          effectMode: widget.effectMode,
                          onTap: () {
                            if (item.mediaType == 'series' &&
                                item.seriesId != null) {
                              widget.onOpenSeries(item.seriesId!);
                            } else {
                              widget.onSelectItem(item);
                            }
                          },
                        );
                      },
                    ),
                  ),
                  if (_isHovered && _canScrollLeft)
                    Positioned(
                      left: AppSpacing.sm,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _RailArrowButton(
                          icon: Icons.chevron_left,
                          tooltip: AppStrings.scrollLeftTooltip,
                          onPressed: () => _scrollBy(-AppSpacing.railScrollStep),
                        ),
                      ),
                    ),
                  if (_isHovered && _canScrollRight)
                    Positioned(
                      right: AppSpacing.sm,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _RailArrowButton(
                          icon: Icons.chevron_right,
                          tooltip: AppStrings.scrollRightTooltip,
                          onPressed: () => _scrollBy(AppSpacing.railScrollStep),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailArrowButton extends StatelessWidget {
  const _RailArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.railArrowButtonSize,
      height: AppSpacing.railArrowButtonSize,
      decoration: const BoxDecoration(
        color: AppColors.scrollArrowBackground,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: AppColors.textPrimary,
          size: AppSpacing.iconSizeLg,
        ),
      ),
    );
  }
}
