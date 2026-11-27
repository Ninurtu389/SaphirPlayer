import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../widgets/surface_panel.dart';

class PlayerMiniHud extends StatelessWidget {
  const PlayerMiniHud({
    super.key,
    required this.isPlaying,
    required this.effectMode,
    required this.onTogglePlayPause,
    required this.onExitMiniPlayer,
    required this.onClose,
    required this.onStartDrag,
  });

  final bool isPlaying;
  final EffectMode effectMode;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onExitMiniPlayer;
  final VoidCallback onClose;
  final VoidCallback onStartDrag;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: AppSpacing.xs,
          left: AppSpacing.xs,
          right: AppSpacing.xs,
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => onStartDrag(),
                  child: const SizedBox(height: AppSpacing.miniPlayerDragBarHeight),
                ),
              ),
              SurfacePanel(
                effectMode: effectMode,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxs,
                  vertical: AppSpacing.zero,
                ),
                borderRadius: AppSpacing.radiusSm,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: isPlaying
                          ? AppStrings.playerPauseTooltip
                          : AppStrings.playerPlayTooltip,
                      onPressed: onTogglePlayPause,
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        size: AppSpacing.iconSizeMd,
                        color: AppColors.sapphireBright,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: AppStrings.playerMiniPlayerExitTooltip,
                      onPressed: onExitMiniPlayer,
                      icon: const Icon(
                        Icons.open_in_full,
                        size: AppSpacing.iconSizeSm,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: AppStrings.playerCloseTooltip,
                      onPressed: onClose,
                      icon: const Icon(
                        Icons.close,
                        size: AppSpacing.iconSizeSm,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
