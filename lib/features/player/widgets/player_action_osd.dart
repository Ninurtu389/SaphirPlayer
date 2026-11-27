import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../widgets/surface_panel.dart';
import '../player_models.dart';

class PlayerActionOsd extends StatelessWidget {
  const PlayerActionOsd({
    super.key,
    required this.message,
    required this.kind,
    required this.effectMode,
  });

  final String? message;
  final PlayerActionOsdKind? kind;
  final EffectMode effectMode;

  @override
  Widget build(BuildContext context) {
    final visible = message != null && message!.isNotEmpty;
    if (!visible && effectMode == EffectMode.lean) {
      return const SizedBox.shrink();
    }

    final panel = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSpacing.osdMaxWidth),
      child: SurfacePanel(
        effectMode: effectMode,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        borderRadius: AppSpacing.radiusSm,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForKind(kind),
              size: AppSpacing.iconSizeMd,
              color: AppColors.sapphireBright,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                message ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );

    return Positioned(
      top: AppSpacing.osdTopOffset,
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: effectMode == EffectMode.glass
              ? AnimatedOpacity(
                  opacity: visible
                      ? AppSpacing.opacityVisible
                      : AppSpacing.opacityHidden,
                  duration: const Duration(
                    milliseconds: AppSpacing.hudFadeAnimationMs,
                  ),
                  child: panel,
                )
              : panel,
        ),
      ),
    );
  }

  static IconData _iconForKind(PlayerActionOsdKind? kind) {
    switch (kind) {
      case PlayerActionOsdKind.volume:
        return Icons.volume_up;
      case PlayerActionOsdKind.mute:
        return Icons.volume_off;
      case PlayerActionOsdKind.seekBack:
        return Icons.replay_10;
      case PlayerActionOsdKind.seekForward:
        return Icons.forward_10;
      case PlayerActionOsdKind.speed:
        return Icons.speed;
      case PlayerActionOsdKind.aspectMode:
        return Icons.aspect_ratio;
      case PlayerActionOsdKind.screenshot:
        return Icons.camera_alt_outlined;
      case PlayerActionOsdKind.bookmark:
        return Icons.bookmark_added_outlined;
      case PlayerActionOsdKind.audioDelay:
        return Icons.audiotrack;
      case PlayerActionOsdKind.subtitleDelay:
      case PlayerActionOsdKind.subtitle:
        return Icons.subtitles;
      case PlayerActionOsdKind.nightMode:
        return Icons.nightlight_round;
      case PlayerActionOsdKind.volumeBoost:
        return Icons.graphic_eq;
      case PlayerActionOsdKind.sleepTimer:
        return Icons.bedtime_outlined;
      case PlayerActionOsdKind.frameStep:
        return Icons.skip_next;
      case PlayerActionOsdKind.chapter:
        return Icons.menu_book_outlined;
      case PlayerActionOsdKind.introSkip:
        return Icons.fast_forward;
      case null:
        return Icons.info_outline;
    }
  }
}
