import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../playback_session.dart';

class PlayerTopHud extends StatelessWidget {
  const PlayerTopHud({
    super.key,
    required this.entry,
    required this.isFullscreen,
    required this.onClose,
    required this.onToggleFullscreen,
  });

  final PlaybackQueueEntry? entry;
  final bool isFullscreen;
  final VoidCallback onClose;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.playerTopHudHeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          gradient: AppColors.playerTopHudGradient,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              tooltip: AppStrings.playerCloseTooltip,
              onPressed: onClose,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry?.title ?? AppStrings.appTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (entry != null && entry!.subtitle.isNotEmpty)
                    Text(
                      entry!.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: AppStrings.playerFullscreenTooltip,
              onPressed: onToggleFullscreen,
              icon: Icon(
                isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
