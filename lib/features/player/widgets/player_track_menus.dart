import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../saphir_player_controller.dart';
import 'player_audio_subtitle_menus.dart';
import 'player_utility_menus.dart';

class PlayerTrackMenus extends StatelessWidget {
  const PlayerTrackMenus({
    super.key,
    required this.controller,
    required this.effectMode,
    this.onReturnFocus,
  });

  final SaphirPlayerController controller;
  final EffectMode effectMode;
  final VoidCallback? onReturnFocus;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerChapterNavButtons(
          controller: controller,
          onReturnFocus: onReturnFocus,
        ),
        PlayerBookmarkMenu(
          controller: controller,
          onReturnFocus: onReturnFocus,
        ),
        PlayerAudioTrackMenu(
          controller: controller,
          onReturnFocus: onReturnFocus,
        ),
        PlayerSubtitleTrackMenu(
          controller: controller,
          effectMode: effectMode,
          onReturnFocus: onReturnFocus,
        ),
        IconButton(
          tooltip: AppStrings.playerAspectModeTooltip,
          onPressed: () {
            controller.cycleAspectMode();
            onReturnFocus?.call();
          },
          icon: const Icon(Icons.aspect_ratio, size: AppSpacing.iconSizeMd),
        ),
        PlayerSleepTimerMenu(
          controller: controller,
          onReturnFocus: onReturnFocus,
        ),
        PlayerPlaybackSpeedMenu(
          controller: controller,
          onReturnFocus: onReturnFocus,
        ),
      ],
    );
  }
}
