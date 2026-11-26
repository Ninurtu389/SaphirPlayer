import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../widgets/media_tile.dart';
import '../../library/library_models.dart';

class MediaRail extends StatefulWidget {
  const MediaRail({
    super.key,
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
  State<MediaRail> createState() => _MediaRailState();
}

class _MediaRailState extends State<MediaRail> {
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
  void didUpdateWidget(covariant MediaRail oldWidget) {
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
                      itemBuilder: (context, index) =>
                          _buildTile(widget.items[index]),
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
                          onPressed: () =>
                              _scrollBy(-AppSpacing.railScrollStep),
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

  Widget _buildTile(MediaCardItem item) {
    return MediaTile(
      item: item,
      effectMode: widget.effectMode,
      onTap: () {
        if (item.mediaType == 'series' && item.seriesId != null) {
          widget.onOpenSeries(item.seriesId!);
        } else {
          widget.onSelectItem(item);
        }
      },
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
