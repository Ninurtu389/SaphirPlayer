import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../core/utils/formatters.dart';
import '../../../widgets/surface_panel.dart';
import '../player_models.dart';
import '../saphir_player_controller.dart';

class PlayerSeekBar extends StatefulWidget {
  const PlayerSeekBar({
    super.key,
    required this.controller,
    required this.effectMode,
  });

  final SaphirPlayerController controller;
  final EffectMode effectMode;

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  bool _isSeekHovered = false;
  double? _hoverRatio;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return ValueListenableBuilder<({Duration position, Duration duration})>(
      valueListenable: controller.progressListenable,
      builder: (context, progress, _) {
        final durMs = progress.duration.inMilliseconds;
        final posMs = progress.position.inMilliseconds;
        final sliderValue = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

        return Row(
          children: [
            Text(
              Formatters.formatPlayerDuration(progress.position),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SizedBox(
                height: AppSpacing.seekBarHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) => _buildTrackArea(
                    context,
                    constraints.maxWidth,
                    sliderValue,
                    durMs,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: AppStrings.playerTimeToggleTooltip,
              child: InkWell(
                onTap: controller.cycleTimeDisplayMode,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Text(
                    controller.formatRightTimeLabel(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrackArea(
    BuildContext context,
    double trackWidth,
    double sliderValue,
    int durMs,
  ) {
    final controller = widget.controller;
    final hoverRatio = _hoverRatio;
    final showTooltip = _isSeekHovered && hoverRatio != null && durMs > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isSeekHovered = true),
      onExit: (_) => setState(() {
        _isSeekHovered = false;
        _hoverRatio = null;
      }),
      onHover: (event) {
        if (trackWidth <= 0) return;
        setState(() {
          _hoverRatio = (event.localPosition.dx / trackWidth).clamp(0.0, 1.0);
        });
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (durMs > 0 &&
              (controller.chapters.isNotEmpty ||
                  controller.bookmarks.isNotEmpty))
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SeekMarkersPainter(
                    durationMs: durMs,
                    chapters: controller.chapters,
                    bookmarks: controller.bookmarks,
                  ),
                ),
              ),
            ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: AppSpacing.playerSeekTrackHeight,
              activeTrackColor: AppColors.sapphireBright,
              inactiveTrackColor: AppColors.progressTrack,
              thumbColor: AppColors.sapphireBright,
              overlayColor: AppColors.sapphireGlow,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: _isSeekHovered
                    ? AppSpacing.playerSeekThumbRadiusHover
                    : AppSpacing.playerSeekThumbRadius,
              ),
            ),
            child: Slider(
              value: sliderValue,
              onChanged: controller.seekToRatio,
            ),
          ),
          if (showTooltip)
            _buildHoverTooltip(context, trackWidth, hoverRatio, durMs),
        ],
      ),
    );
  }

  Widget _buildHoverTooltip(
    BuildContext context,
    double trackWidth,
    double ratio,
    int durMs,
  ) {
    final hoverPos = Duration(milliseconds: (durMs * ratio).round());
    final chapter = widget.controller.chapterAtPosition(hoverPos);
    final rawLeft = (ratio * trackWidth) -
        (AppSpacing.seekHoverTooltipMaxWidth * AppSpacing.halfFactor);
    final maxLeft =
        (trackWidth - AppSpacing.seekHoverTooltipMaxWidth).clamp(
      AppSpacing.zero,
      trackWidth,
    );
    final left = rawLeft.clamp(AppSpacing.zero, maxLeft);

    return Positioned(
      left: left,
      bottom: AppSpacing.seekHoverTooltipOffsetY,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.seekHoverTooltipMaxWidth,
          ),
          child: SurfacePanel(
            effectMode: widget.effectMode,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            borderRadius: AppSpacing.radiusSm,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Formatters.formatPlayerDuration(hoverPos),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.sapphireBright,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (chapter != null)
                  Text(
                    chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekMarkersPainter extends CustomPainter {
  const _SeekMarkersPainter({
    required this.durationMs,
    required this.chapters,
    required this.bookmarks,
  });

  final int durationMs;
  final List<PlayerChapter> chapters;
  final List<MediaBookmark> bookmarks;

  @override
  void paint(Canvas canvas, Size size) {
    if (durationMs <= 0 || size.width <= 0) {
      return;
    }
    final centerY = size.height * AppSpacing.halfFactor;
    final chapterPaint = Paint()
      ..color = AppColors.chapterMarker
      ..strokeWidth = AppSpacing.chapterMarkerWidth;

    for (final chapter in chapters) {
      if (chapter.startMs <= 0) continue;
      final x = (chapter.startMs / durationMs).clamp(0.0, 1.0) * size.width;
      final halfH = AppSpacing.chapterMarkerHeight * AppSpacing.halfFactor;
      canvas.drawLine(
        Offset(x, centerY - halfH),
        Offset(x, centerY + halfH),
        chapterPaint,
      );
    }

    final bookmarkPaint = Paint()..color = AppColors.bookmarkMarker;
    for (final bm in bookmarks) {
      final x = (bm.positionMs / durationMs).clamp(0.0, 1.0) * size.width;
      canvas.drawCircle(
        Offset(x, centerY),
        AppSpacing.bookmarkMarkerRadius,
        bookmarkPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SeekMarkersPainter oldDelegate) {
    return oldDelegate.durationMs != durationMs ||
        oldDelegate.chapters != chapters ||
        oldDelegate.bookmarks != bookmarks;
  }
}
