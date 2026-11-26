import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/effect_mode.dart';
import 'library_models.dart';

class SeriesDetailView extends StatefulWidget {
  const SeriesDetailView({
    super.key,
    required this.detail,
    required this.effectMode,
    required this.onBack,
    required this.onPlayEpisode,
    required this.onToggleWatched,
  });

  final SeriesDetailData detail;
  final EffectMode effectMode;
  final VoidCallback onBack;
  final ValueChanged<EpisodeEntry> onPlayEpisode;
  final ValueChanged<EpisodeEntry> onToggleWatched;

  @override
  State<SeriesDetailView> createState() => _SeriesDetailViewState();
}

class _SeriesDetailViewState extends State<SeriesDetailView> {
  int _selectedSeasonIndex = 0;

  @override
  Widget build(BuildContext context) {
    final seasons = widget.detail.seasons;
    final activeSeason = seasons.isNotEmpty
        ? seasons[_selectedSeasonIndex.clamp(0, seasons.length - 1)]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSeriesHeader(context),
        if (seasons.isNotEmpty) _buildSeasonTabs(context, seasons),
        Expanded(
          child: activeSeason == null
              ? const SizedBox.shrink()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  itemCount: activeSeason.episodes.length,
                  separatorBuilder: (context, index) => const Divider(
                    height: AppSpacing.dividerThickness,
                    color: AppColors.dividerHairline,
                  ),
                  itemBuilder: (context, index) {
                    return _EpisodeRow(
                      episode: activeSeason.episodes[index],
                      effectMode: widget.effectMode,
                      onPlay: () =>
                          widget.onPlayEpisode(activeSeason.episodes[index]),
                      onToggleWatched: () =>
                          widget.onToggleWatched(activeSeason.episodes[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSeriesHeader(BuildContext context) {
    final detail = widget.detail;
    final hasPoster =
        detail.posterPath != null && File(detail.posterPath!).existsSync();
    final isGlass = widget.effectMode == EffectMode.glass;
    final resumeEp = detail.nextResumeEpisode;
    final fallbackColors = AppColors.coverGradientForTitle(detail.title);

    final playButtonLabel = resumeEp != null && resumeEp.positionMs > 0
        ? '${AppStrings.resumeButton} (S${resumeEp.seasonNumber.toString().padLeft(2, '0')}E${resumeEp.episodeNumber.toString().padLeft(2, '0')})'
        : AppStrings.playEpisodeOneButton;

    return SizedBox(
      height: AppSpacing.seriesDetailHeaderHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPoster)
            Image.file(
              File(detail.posterPath!),
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
            ),
          if (isGlass)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.0,
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
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.lg,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.badgeBackground,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: AppStrings.backButton,
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
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
                      detail.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    if (detail.summary != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        detail.summary!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Text(
                          '${detail.watchedEpisodes} / ${detail.totalEpisodes} ${AppStrings.episodesCountLabel} ${AppStrings.watchedBadge.toLowerCase()}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                            child: LinearProgressIndicator(
                              value: detail.overallProgress,
                              minHeight: AppSpacing.progressBarHeight,
                              backgroundColor: AppColors.progressTrack,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.sapphireBright,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (resumeEp != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton.icon(
                        onPressed: () => widget.onPlayEpisode(resumeEp),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(playButtonLabel),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonTabs(BuildContext context, List<SeasonGroup> seasons) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.dividerHairline),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(seasons.length, (index) {
            final season = seasons[index];
            final selected = index == _selectedSeasonIndex;
            return InkWell(
              onTap: () => setState(() => _selectedSeasonIndex = index),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${AppStrings.seasonPrefix} ${season.seasonNumber}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: selected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      height: AppSpacing.seasonTabIndicatorHeight,
                      width: AppSpacing.xl,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.sapphireBright
                            : AppColors.borderTransparent,
                        borderRadius: BorderRadius.circular(AppSpacing.xxs),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    required this.episode,
    required this.effectMode,
    required this.onPlay,
    required this.onToggleWatched,
  });

  final EpisodeEntry episode;
  final EffectMode effectMode;
  final VoidCallback onPlay;
  final VoidCallback onToggleWatched;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final hasThumb =
        ep.thumbPath != null && File(ep.thumbPath!).existsSync();
    final durationText = ep.formattedDuration;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _isHovered ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            InkWell(
              onTap: widget.onPlay,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: SizedBox(
                width: AppSpacing.episodeThumbWidth,
                height: AppSpacing.episodeThumbHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasThumb)
                        Image.file(
                          File(ep.thumbPath!),
                          fit: BoxFit.cover,
                          cacheWidth: AppSpacing.thumbWidth.toInt(),
                          cacheHeight: AppSpacing.thumbHeight.toInt(),
                        )
                      else
                        Container(
                          color: AppColors.elevatedSurface,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.play_arrow,
                            color: AppColors.sapphireBright,
                            size: AppSpacing.iconSizeLg,
                          ),
                        ),
                      if (_isHovered)
                        Container(
                          color: AppColors.badgeBackground,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.play_arrow,
                            color: AppColors.textPrimary,
                            size: AppSpacing.iconSizeXl,
                          ),
                        ),
                      if (ep.progressRatio > 0 && !ep.isCompleted)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: ep.progressRatio,
                            minHeight: AppSpacing.progressBarHeight,
                            backgroundColor: AppColors.progressTrack,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.sapphireBright,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: InkWell(
                onTap: widget.onPlay,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ep.episodeNumber}. ${ep.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        if (durationText.isNotEmpty) ...[
                          Text(
                            durationText,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (ep.isCompleted)
                            const SizedBox(width: AppSpacing.sm),
                        ],
                        if (ep.isCompleted) ...[
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.successGreen,
                            size: AppSpacing.iconSizeSm,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            AppStrings.watchedBadge,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.successGreen),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              tooltip: AppStrings.toggleWatchedAction,
              onPressed: widget.onToggleWatched,
              icon: Icon(
                ep.isCompleted
                    ? Icons.visibility_off
                    : Icons.check_circle_outline,
                color: ep.isCompleted
                    ? AppColors.textSecondary
                    : AppColors.sapphireBright,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
