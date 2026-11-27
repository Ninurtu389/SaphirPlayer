import 'package:material_ui/material_ui.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_spacing.dart';
import '../core/services/local_file_service.dart';
import '../core/theme/effect_mode.dart';
import '../core/utils/formatters.dart';
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
    final radius = BorderRadius.circular(AppSpacing.radiusMd);

    final tileBody = Container(
      decoration: BoxDecoration(
        color: _isActive && !isGlass
            ? AppColors.surfaceHover
            : AppColors.anthraciteSurface,
        borderRadius: radius,
        border: Border.all(
          color: _isActive
              ? (isGlass
                  ? AppColors.sapphireHoverBorder
                  : AppColors.sapphireBright)
              : AppColors.borderTransparent,
          width: _isActive
              ? AppSpacing.tileBorderWidthHover
              : AppSpacing.tileBorderWidthDefault,
        ),
        boxShadow: (isGlass && _isActive)
            ? const [
                BoxShadow(
                  color: AppColors.sapphireHoverShadow,
                  blurRadius: AppSpacing.tileHoverElevationBlur,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: AppColors.borderTransparent,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (focused) => setState(() => _isFocused = focused),
            child: _TileContent(item: widget.item, isActive: _isActive),
          ),
        ),
      ),
    );

    final sizedTile = widget.width.isFinite
        ? SizedBox(width: widget.width, height: widget.height, child: tileBody)
        : AspectRatio(
            aspectRatio: AppSpacing.thumbWidth / AppSpacing.thumbHeight,
            child: tileBody,
          );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: isGlass
          ? AnimatedScale(
              scale: _isActive
                  ? AppSpacing.tileHoverScale
                  : AppSpacing.tileRestScale,
              duration:
                  const Duration(milliseconds: AppSpacing.hoverAnimationMs),
              curve: Curves.easeOutCubic,
              child: sizedTile,
            )
          : sizedTile,
    );
  }
}

class _TileContent extends StatelessWidget {
  const _TileContent({
    required this.item,
    required this.isActive,
  });

  final MediaCardItem item;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final imageProvider = LocalFileService.imageProviderForPath(
      item.imagePath,
      cacheWidth: AppSpacing.thumbWidth.toInt(),
      cacheHeight: AppSpacing.thumbHeight.toInt(),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageProvider != null)
          Image(image: imageProvider, fit: BoxFit.cover)
        else
          _CoverFallback(title: item.title, monogram: item.monogram),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.cardOverlayGradient),
        ),
        if (isActive)
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
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                Formatters.formatRemainingMinutes(item.remainingMinutes),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        Positioned(
          left: AppSpacing.sm,
          right: AppSpacing.sm,
          bottom: AppSpacing.sm,
          child: _TileMetadataOverlay(item: item),
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
    );
  }
}

class _TileMetadataOverlay extends StatelessWidget {
  const _TileMetadataOverlay({required this.item});

  final MediaCardItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
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
            letterSpacing: AppSpacing.monogramLetterSpacing,
          ),
        ),
      ),
    );
  }
}
