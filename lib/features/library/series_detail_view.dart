import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/effect_mode.dart';
import '../../widgets/surface_panel.dart';
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
        const SizedBox(height: AppSpacing.md),
        if (seasons.isNotEmpty)
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: List.generate(seasons.length, (index) {
              final season = seasons[index];
              final selected = index == _selectedSeasonIndex;
              return ChoiceChip(
                label:
                    Text('${AppStrings.seasonPrefix} ${season.seasonNumber}'),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _selectedSeasonIndex = index;
                  });
                },
              );
            }),
          ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: activeSeason == null
              ? const SizedBox.shrink()
              : ListView.separated(
                  itemCount: activeSeason.episodes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    return _buildEpisodeRow(
                      context,
                      activeSeason.episodes[index],
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

    return Container(
      constraints: const BoxConstraints(
        minHeight: AppSpacing.seriesDetailHeaderHeight,
      ),
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
          children: [
            if (hasPoster)
              Positioned.fill(
                child: Image.file(
                  File(detail.posterPath!),
                  fit: BoxFit.cover,
                ),
              ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.heroGradientStart,
                      AppColors.heroGradientMid,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasPoster) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      child: SizedBox(
                        width: AppSpacing.seriesDetailPosterWidth,
                        height: AppSpacing.seriesDetailHeaderHeight -
                            AppSpacing.xl,
                        child: Image.file(
                          File(detail.posterPath!),
                          fit: BoxFit.cover,
                          cacheWidth: AppSpacing.thumbWidth.toInt(),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: AppStrings.backButton,
                              onPressed: widget.onBack,
                              icon: const Icon(Icons.arrow_back),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                detail.title,
                                style:
                                    Theme.of(context).textTheme.headlineMedium,
                              ),
                            ),
                          ],
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
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Text(
                              '${AppStrings.seriesProgressLabel}: ${detail.watchedEpisodes}/${detail.totalEpisodes} ${AppStrings.watchedBadge}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusSm,
                                ),
                                child: LinearProgressIndicator(
                                  value: detail.overallProgress,
                                  minHeight: AppSpacing.progressBarHeight,
                                  backgroundColor: AppColors.progressTrack,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    AppColors.sapphireBright,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeRow(BuildContext context, EpisodeEntry ep) {
    final hasThumb =
        ep.thumbPath != null && File(ep.thumbPath!).existsSync();
    final thumbWidth = AppSpacing.thumbWidth * AppSpacing.seriesDetailThumbScale;
    final thumbHeight =
        AppSpacing.thumbHeight * AppSpacing.seriesDetailThumbScale;

    return SurfacePanel(
      effectMode: widget.effectMode,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          InkWell(
            onTap: () => widget.onPlayEpisode(ep),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: SizedBox(
              width: thumbWidth,
              height: thumbHeight,
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
              onTap: () => widget.onPlayEpisode(ep),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${AppStrings.episodePrefix} ${ep.episodeNumber} · ${ep.title}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (ep.isCompleted) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
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
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: AppStrings.toggleWatchedAction,
            onPressed: () => widget.onToggleWatched(ep),
            icon: Icon(
              ep.isCompleted ? Icons.visibility_off : Icons.check_circle_outline,
            ),
          ),
        ],
      ),
    );
  }
}
