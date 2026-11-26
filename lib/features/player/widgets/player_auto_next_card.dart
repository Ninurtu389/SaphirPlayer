import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../widgets/surface_panel.dart';
import '../playback_session.dart';

class PlayerAutoNextCard extends StatelessWidget {
  const PlayerAutoNextCard({
    super.key,
    required this.nextEntry,
    required this.remainingSeconds,
    required this.effectMode,
    required this.hudVisible,
    required this.onPlayNext,
    required this.onDismiss,
  });

  final PlaybackQueueEntry nextEntry;
  final int remainingSeconds;
  final EffectMode effectMode;
  final bool hudVisible;
  final VoidCallback onPlayNext;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: AppSpacing.lg,
      bottom: hudVisible ? AppSpacing.autoNextBottomWithHud : AppSpacing.lg,
      child: SizedBox(
        width: AppSpacing.autoNextCardWidth,
        child: SurfacePanel(
          effectMode: effectMode,
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${AppStrings.autoNextTitle} ($remainingSeconds ${AppStrings.autoNextSecondsSuffix})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.sapphireBright,
                    ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                nextEntry.subtitle.isNotEmpty
                    ? nextEntry.subtitle
                    : nextEntry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  ElevatedButton(
                    onPressed: onPlayNext,
                    child: const Text(AppStrings.autoNextPlayNowButton),
                  ),
                  TextButton(
                    onPressed: onDismiss,
                    child: const Text(AppStrings.autoNextCancelButton),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
