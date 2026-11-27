import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/local_file_service.dart';
import '../../core/theme/effect_mode.dart';
import '../../core/utils/formatters.dart';
import 'library_models.dart';
import 'widgets/episode_row.dart';

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
        _SeriesDetailHeader(
          detail: widget.detail,
          effectMode: widget.effectMode,
          onBack: widget.onBack,
          onPlayEpisode: widget.onPlayEpisode,
        ),
        if (seasons.isNotEmpty)
          _SeasonTabs(
            seasons: seasons,
            selectedIndex: _selectedSeasonIndex,
            onSelectSeason: (index) =>
                setState(() => _selectedSeasonIndex = index),
          ),
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
                    final ep = activeSeason.episodes[index];
                    return EpisodeRow(
                      episode: ep,
                      effectMode: widget.effectMode,
                      onPlay: () => widget.onPlayEpisode(ep),
                      onToggleWatched: () => widget.onToggleWatched(ep),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SeriesDetailHeader extends StatelessWidget {
  const _SeriesDetailHeader({
    required this.detail,
    required this.effectMode,
    required this.onBack,
    required this.onPlayEpisode,
  });

  final SeriesDetailData detail;
  final EffectMode effectMode;
  final VoidCallback onBack;
  final ValueChanged<EpisodeEntry> onPlayEpisode;

  @override
  Widget build(BuildContext context) {
    final imageProvider =
        LocalFileService.imageProviderForPath(detail.posterPath);
    final isGlass = effectMode == EffectMode.glass;
    final resumeEp = detail.nextResumeEpisode;
    final playButtonLabel = Formatters.formatSeriesPlayButton(resumeEp);

    return SizedBox(
      height: AppSpacing.seriesDetailHeaderHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageProvider != null)
            Image(image: imageProvider, fit: BoxFit.cover)
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppColors.coverGradientForTitle(detail.title),
                ),
              ),
            ),
          if (isGlass)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: AppSpacing.seriesHeaderGlowRadius,
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
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
          ),
          _HeaderInfoOverlay(
            detail: detail,
            resumeEp: resumeEp,
            playButtonLabel: playButtonLabel,
            onPlayEpisode: onPlayEpisode,
          ),
        ],
      ),
    );
  }
}

class _HeaderInfoOverlay extends StatelessWidget {
  const _HeaderInfoOverlay({
    required this.detail,
    required this.resumeEp,
    required this.playButtonLabel,
    required this.onPlayEpisode,
  });

  final SeriesDetailData detail;
  final EpisodeEntry? resumeEp;
  final String playButtonLabel;
  final ValueChanged<EpisodeEntry> onPlayEpisode;

  @override
  Widget build(BuildContext context) {
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
                    Formatters.formatSeriesWatchedProgress(
                      detail.watchedEpisodes,
                      detail.totalEpisodes,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
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
                  onPressed: () => onPlayEpisode(resumeEp!),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(playButtonLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonTabs extends StatelessWidget {
  const _SeasonTabs({
    required this.seasons,
    required this.selectedIndex,
    required this.onSelectSeason,
  });

  final List<SeasonGroup> seasons;
  final int selectedIndex;
  final ValueChanged<int> onSelectSeason;

  @override
  Widget build(BuildContext context) {
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
            final selected = index == selectedIndex;
            return InkWell(
              onTap: () => onSelectSeason(index),
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
