import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_strings.dart';
import '../core/theme/effect_mode.dart';
import '../features/library/library_models.dart';

class MediaTile extends StatefulWidget {
  const MediaTile({
    super.key,
    required this.item,
    required this.effectMode,
    required this.onTap,
    this.width = AppSpacing.tileCardWidth,
  });

  final MediaCardItem item;
  final EffectMode effectMode;
  final VoidCallback onTap;
  final double width;

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isGlass = widget.effectMode == EffectMode.glass;
    final animDuration = isGlass
        ? const Duration(milliseconds: AppSpacing.hoverAnimationMs)
        : Duration.zero;
    final item = widget.item;
    final hasImage =
        item.imagePath != null && File(item.imagePath!).existsSync();

    final borderColor = _isHovered
        ? (isGlass ? AppColors.sapphireHoverBorder : AppColors.sapphireBright)
        : AppColors.borderSubtle;

    final borderWidth = _isHovered
        ? AppSpacing.tileBorderWidthHover
        : AppSpacing.tileBorderWidthDefault;

    final scale = (isGlass && _isHovered)
        ? AppSpacing.tileHoverScale
        : AppSpacing.tileRestScale;

    final shadows = (isGlass && _isHovered)
        ? const [
            BoxShadow(
              color: AppColors.sapphireHoverShadow,
              blurRadius: AppSpacing.tileHoverElevationBlur,
            ),
          ]
        : const <BoxShadow>[];

    final cardContent = AnimatedContainer(
      duration: animDuration,
      curve: Curves.easeOutCubic,
      width: widget.width,
      decoration: BoxDecoration(
        color: AppColors.anthraciteSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: shadows,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: AppSpacing.tilePosterHeight,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.radiusMd),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasImage)
                      Image.file(
                        File(item.imagePath!),
                        fit: BoxFit.cover,
                        cacheWidth: AppSpacing.thumbWidth.toInt(),
                        cacheHeight: AppSpacing.thumbHeight.toInt(),
                      )
                    else
                      Container(
                        color: AppColors.elevatedSurface,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.play_circle_outline,
                          color: _isHovered
                              ? AppColors.sapphireBright
                              : AppColors.textSecondary,
                          size: AppSpacing.xl,
                        ),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.cardGradientTop,
                            AppColors.cardGradientBottom,
                          ],
                        ),
                      ),
                    ),
                    if (_isHovered)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xs),
                          decoration: const BoxDecoration(
                            color: AppColors.badgeBackground,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: AppColors.textPrimary,
                            size: AppSpacing.iconSizeLg,
                          ),
                        ),
                      ),
                    if (item.isCompleted)
                      Positioned(
                        top: AppSpacing.xs,
                        right: AppSpacing.xs,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.badgeBackground,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: AppColors.successGreen,
                                size: AppSpacing.iconSizeSm,
                              ),
                              SizedBox(width: AppSpacing.xxs),
                              Text(
                                AppStrings.watchedBadge,
                                style: TextStyle(
                                  fontSize: AppSpacing.sm,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (item.remainingMinutes > 0 && !item.isCompleted)
                      Positioned(
                        right: AppSpacing.xs,
                        bottom: AppSpacing.xs,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.badgeBackground,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: Text(
                            '${item.remainingMinutes} ${AppStrings.remainingMinutesSuffix}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    if (item.progressRatio > 0 && !item.isCompleted)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: item.progressRatio,
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
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: isGlass
          ? AnimatedScale(
              scale: scale,
              duration: animDuration,
              curve: Curves.easeOutCubic,
              child: cardContent,
            )
          : cardContent,
    );
  }
}
