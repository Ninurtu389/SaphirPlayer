import 'package:material_ui/material_ui.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_strings.dart';
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
    this.onRemove,
    this.width = AppSpacing.tileCardWidth,
    this.height = AppSpacing.tileCardHeight,
  });

  final MediaCardItem item;
  final EffectMode effectMode;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
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
    final activeBorderColor =
        isGlass ? AppColors.sapphireHoverBorder : AppColors.sapphireBright;

    final tileBody = Container(
      decoration: BoxDecoration(
        color: _isActive && !isGlass
            ? AppColors.surfaceHover
            : AppColors.anthraciteSurface,
        borderRadius: radius,
        boxShadow: (isGlass && _isActive)
            ? const [
                BoxShadow(
                  color: AppColors.sapphireHoverShadow,
                  blurRadius: AppSpacing.tileHoverElevationBlur,
                ),
              ]
            : const <BoxShadow>[],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: _isActive ? activeBorderColor : AppColors.borderTransparent,
          width: AppSpacing.tileBorderWidthHover,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Material(
              color: AppColors.borderTransparent,
              child: InkWell(
                onTap: widget.onTap,
                onFocusChange: (focused) =>
                    setState(() => _isFocused = focused),
                child: _TileContent(item: widget.item, isActive: _isActive),
              ),
            ),
            if (widget.onRemove != null && _isActive)
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: _RemoveTileButton(onRemove: widget.onRemove!),
              ),
          ],
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

class _RemoveTileButton extends StatelessWidget {
  const _RemoveTileButton({required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSpacing.tileRemoveButtonSize,
      height: AppSpacing.tileRemoveButtonSize,
      child: Material(
        color: AppColors.badgeBackground,
        shape: const CircleBorder(
          side: BorderSide(
            color: AppColors.sapphireBright,
            width: AppSpacing.borderWidthThin,
          ),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: AppStrings.removeFromContinueWatchingTooltip,
          onPressed: onRemove,
          icon: const Icon(
            Icons.close,
            size: AppSpacing.introDismissIconSize,
            color: AppColors.textPrimary,
          ),
        ),
      ),
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
          Image(
            image: imageProvider,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                _CoverFallback(title: item.title, monogram: item.monogram),
          )
        else
          _CoverFallback(title: item.title, monogram: item.monogram),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.cardOverlayGradient),
        ),
        if (isActive) _buildActiveIcon(),
        if (item.isCompleted) _buildCompletedBadge(),
        if (item.remainingMinutes > 0 && !item.isCompleted)
          _buildRemainingBadge(context),
        Positioned(
          left: AppSpacing.sm,
          right: AppSpacing.sm,
          bottom: AppSpacing.sm,
          child: _TileMetadataOverlay(item: item),
        ),
        if (item.progressRatio > AppSpacing.zero && !item.isCompleted)
          Positioned(
            left: AppSpacing.zero,
            right: AppSpacing.zero,
            bottom: AppSpacing.zero,
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

  Widget _buildActiveIcon() {
    final isSeries = item.mediaType == 'series';
    return Padding(
      padding: EdgeInsets.only(
        bottom: isSeries ? AppSpacing.lg : AppSpacing.zero,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: const BoxDecoration(
            color: AppColors.badgeBackground,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isSeries ? Icons.view_list_rounded : Icons.play_arrow,
            color: AppColors.textPrimary,
            size: AppSpacing.iconSizeLg,
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedBadge() {
    return Positioned(
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
    );
  }

  Widget _buildRemainingBadge(BuildContext context) {
    return Positioned(
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
    );
  }
}

class _TileMetadataOverlay extends StatelessWidget {
  const _TileMetadataOverlay({required this.item});

  final MediaCardItem item;

  @override
  Widget build(BuildContext context) {
    final subtitleText =
        Formatters.formatMediaTileSubtitle(item.subtitle, item.artist);
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
        if (subtitleText.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subtitleText,
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
