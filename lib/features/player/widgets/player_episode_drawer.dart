import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../widgets/surface_panel.dart';
import '../playback_session.dart';

class PlayerEpisodeDrawer extends StatelessWidget {
  const PlayerEpisodeDrawer({
    super.key,
    required this.queue,
    required this.currentIndex,
    required this.effectMode,
    required this.onSelectIndex,
    required this.onClose,
  });

  final List<PlaybackQueueEntry> queue;
  final int currentIndex;
  final EffectMode effectMode;
  final ValueChanged<int> onSelectIndex;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isCompactHeight = screenSize.height < AppSpacing.minWindowHeight;
    final drawerWidth = math.min(
      AppSpacing.episodeDrawerWidth,
      screenSize.width * AppSpacing.drawerMaxWidthFraction,
    );
    return Positioned(
      top: isCompactHeight ? AppSpacing.xs : AppSpacing.osdTopOffset,
      right: AppSpacing.md,
      bottom: isCompactHeight ? AppSpacing.xs : AppSpacing.drawerBottomOffset,
      child: SizedBox(
        width: drawerWidth,
        child: SurfacePanel(
          effectMode: effectMode,
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.playerEpisodeDrawerTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: AppStrings.playerCloseOverlayAction,
                    onPressed: onClose,
                    icon: const Icon(
                      Icons.close,
                      size: AppSpacing.iconSizeMd,
                    ),
                  ),
                ],
              ),
              const Divider(height: AppSpacing.dividerThickness),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: ListView.separated(
                  itemCount: queue.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.xxs),
                  itemBuilder: (context, index) => _DrawerEpisodeTile(
                    entry: queue[index],
                    isActive: index == currentIndex,
                    onTap: () => onSelectIndex(index),
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

class _DrawerEpisodeTile extends StatelessWidget {
  const _DrawerEpisodeTile({
    required this.entry,
    required this.isActive,
    required this.onTap,
  });

  final PlaybackQueueEntry entry;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = entry.subtitle.isNotEmpty ? entry.subtitle : entry.title;
    return Material(
      color: isActive ? AppColors.activeTileFill : AppColors.borderTransparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.play_arrow : Icons.movie_outlined,
                size: AppSpacing.iconSizeSm,
                color: isActive
                    ? AppColors.sapphireBright
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isActive
                            ? AppColors.sapphireBright
                            : AppColors.textPrimary,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
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
