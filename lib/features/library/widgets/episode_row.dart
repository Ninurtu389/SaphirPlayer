import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/local_file_service.dart';
import '../../../core/theme/effect_mode.dart';
import '../library_models.dart';

class EpisodeRow extends StatefulWidget {
  const EpisodeRow({
    super.key,
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
  State<EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<EpisodeRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _isHovered
              ? AppColors.surfaceHover
              : AppColors.borderTransparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            _EpisodeThumbnail(
              episode: ep,
              isHovered: _isHovered,
              onTap: widget.onPlay,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _EpisodeInfo(episode: ep, onTap: widget.onPlay),
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

class _EpisodeThumbnail extends StatelessWidget {
  const _EpisodeThumbnail({
    required this.episode,
    required this.isHovered,
    required this.onTap,
  });

  final EpisodeEntry episode;
  final bool isHovered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageProvider = LocalFileService.imageProviderForPath(
      episode.thumbPath,
      cacheWidth: AppSpacing.thumbWidth.toInt(),
      cacheHeight: AppSpacing.thumbHeight.toInt(),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: SizedBox(
        width: AppSpacing.episodeThumbWidth,
        height: AppSpacing.episodeThumbHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageProvider != null)
                Image(image: imageProvider, fit: BoxFit.cover)
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
              if (isHovered)
                Container(
                  color: AppColors.badgeBackground,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.play_arrow,
                    color: AppColors.textPrimary,
                    size: AppSpacing.iconSizeXl,
                  ),
                ),
              if (episode.progressRatio > 0 && !episode.isCompleted)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: episode.progressRatio,
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
    );
  }
}

class _EpisodeInfo extends StatelessWidget {
  const _EpisodeInfo({
    required this.episode,
    required this.onTap,
  });

  final EpisodeEntry episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final durationText = episode.formattedDuration;
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${episode.episodeNumber}. ${episode.title}',
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
                if (episode.isCompleted) const SizedBox(width: AppSpacing.sm),
              ],
              if (episode.isCompleted) ...[
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
    );
  }
}
