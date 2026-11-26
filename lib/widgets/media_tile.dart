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
    this.height = AppSpacing.tileCardHeight,
  });

  final MediaCardItem item;
  final EffectMode effectMode;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  bool _isHovered = false;
  bool _isFocused = false;

  bool get _isActive => _isHovered || _isFocused;

  @override
  Widget build(BuildContext context) {
    final isGlass = widget.effectMode == EffectMode.glass;
    final animDuration = isGlass
        ? const Duration(milliseconds: AppSpacing.hoverAnimationMs)
        : Duration.zero;
    final item = widget.item;
    final hasImage =
        item.imagePath != null && File(item.imagePath!).existsSync();

    final borderColor = _isActive
        ? (isGlass ? AppColors.sapphireHoverBorder : AppColors.sapphireBright)
        : AppColors.borderTransparent;

    final borderWidth = _isActive
        ? AppSpacing.tileBorderWidthHover
        : AppSpacing.tileBorderWidthDefault;

    final scale = (isGlass && _isActive)
        ? AppSpacing.tileHoverScale
        : AppSpacing.tileRestScale;

    final shadows = (isGlass && _isActive)
        ? const [
            BoxShadow(
              color: AppColors.sapphireHoverShadow,
              blurRadius: AppSpacing.tileHoverElevationBlur,
            ),
          ]
        : const <BoxShadow>[];

    final radius = BorderRadius.circular(AppSpacing.radiusMd);

    final tileBody = Container(
      decoration: BoxDecoration(
        color: _isActive && !isGlass
            ? AppColors.surfaceHover
            : AppColors.anthraciteSurface,
        borderRadius: radius,
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (focused) => setState(() => _isFocused = focused),
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
                  _CoverFallback(title: item.title, monogram: item.monogram),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.cardOverlayGradient,
                  ),
                ),
                if (_isActive)
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
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      decoration: const BoxDecoration(
                        color: AppColors.badgeBackground,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: AppColors.successGreen,
                        size: AppSpacing.iconSizeSm,
                      ),
                    ),
                  ),
                if (item.remainingMinutes > 0 && !item.isCompleted)
                  Positioned(
                    top: AppSpacing.xs,
                    left: AppSpacing.xs,
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
                Positioned(
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                  bottom: AppSpacing.sm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
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
      ),
    );

    final sizedTile = widget.width.isFinite
        ? SizedBox(
            width: widget.width,
            height: widget.height,
            child: tileBody,
          )
        : AspectRatio(
            aspectRatio: AppSpacing.thumbWidth / AppSpacing.thumbHeight,
            child: tileBody,
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: isGlass
          ? AnimatedScale(
              scale: scale,
              duration: animDuration,
              curve: Curves.easeOutCubic,
              child: sizedTile,
            )
          : sizedTile,
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({
    required this.title,
    required this.monogram,
  });

  final String title;
  final String monogram;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.coverGradientForTitle(title);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(
          monogram,
          style: const TextStyle(
            fontSize: AppSpacing.monogramFontSize,
            fontWeight: FontWeight.w800,
            color: AppColors.dividerHairline,
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }
}
