import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../saphir_player_controller.dart';
import 'player_seek_bar.dart';
import 'player_track_menus.dart';

class PlayerBottomHud extends StatelessWidget {
  const PlayerBottomHud({
    super.key,
    required this.controller,
    this.effectMode = EffectMode.glass,
    this.onReturnFocus,
  });

  final SaphirPlayerController controller;
  final EffectMode effectMode;
  final VoidCallback? onReturnFocus;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: AppSpacing.zero,
      left: AppSpacing.zero,
      right: AppSpacing.zero,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.playerBottomHudHeight,
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          gradient: AppColors.playerBottomHudGradient,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PlayerSeekBar(controller: controller, effectMode: effectMode),
            const SizedBox(height: AppSpacing.xs),
            _buildControlsRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsRow(BuildContext context) {
    final next = controller.nextEntry;
    final nextTooltip = next != null
        ? '${AppStrings.playerNextEpisodeTooltip}: ${next.subtitle.isNotEmpty ? next.subtitle : next.title}'
        : AppStrings.playerNextEpisodeTooltip;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxWidth < AppSpacing.compactPlayerBreakpoint;
        final useWrapLayout =
            constraints.maxWidth < AppSpacing.maxSettingsWidth;
        final transportButtons = [
          IconButton(
            tooltip: AppStrings.playerPrevEpisodeTooltip,
            onPressed: controller.hasPreviousEpisode
                ? controller.playPreviousEpisode
                : null,
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton(
            tooltip: AppStrings.playerSeekBackTooltip,
            onPressed: () =>
                controller.seekRelativeSeconds(-AppSpacing.seekStepSeconds),
            icon: const Icon(Icons.replay_10),
          ),
          IconButton(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            constraints: const BoxConstraints(),
            tooltip: controller.isPlaying
                ? AppStrings.playerPauseTooltip
                : AppStrings.playerPlayTooltip,
            onPressed: controller.togglePlayPause,
            icon: Icon(
              controller.isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              size: isCompact ? AppSpacing.iconSizeLg : AppSpacing.iconSizeXl,
              color: AppColors.sapphireBright,
            ),
          ),
          IconButton(
            tooltip: AppStrings.playerSeekForwardTooltip,
            onPressed: () =>
                controller.seekRelativeSeconds(AppSpacing.seekStepSeconds),
            icon: const Icon(Icons.forward_10),
          ),
          IconButton(
            tooltip: nextTooltip,
            onPressed:
                controller.hasNextEpisode ? controller.playNextEpisode : null,
            icon: const Icon(Icons.skip_next),
          ),
        ];

        final muteButton = IconButton(
          tooltip: controller.isMuted
              ? AppStrings.playerUnmuteTooltip
              : AppStrings.playerMuteTooltip,
          onPressed: controller.toggleMute,
          icon: Icon(
            controller.isMuted ? Icons.volume_off : Icons.volume_up,
            size: AppSpacing.iconSizeMd,
          ),
        );

        final volumeSlider = SizedBox(
          width: AppSpacing.hudSliderWidth,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: AppSpacing.progressBarHeight,
              activeTrackColor: AppColors.sapphireBright,
              inactiveTrackColor: AppColors.progressTrack,
              thumbColor: AppColors.textPrimary,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: AppSpacing.playerSeekThumbRadius,
              ),
            ),
            child: Slider(
              min: AppSpacing.volumeMin,
              max: controller.maxVolume,
              value: controller.volume.clamp(
                AppSpacing.volumeMin,
                controller.maxVolume,
              ),
              onChanged: (val) =>
                  controller.adjustVolume(val - controller.volume),
            ),
          ),
        );

        if (useWrapLayout) {
          return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            children: [
              ...transportButtons,
              muteButton,
              if (!isCompact) volumeSlider,
              PlayerTrackMenus(
                controller: controller,
                effectMode: effectMode,
                onReturnFocus: onReturnFocus,
              ),
            ],
          );
        }

        return Row(
          children: [
            ...transportButtons,
            const SizedBox(width: AppSpacing.md),
            muteButton,
            volumeSlider,
            const Spacer(),
            PlayerTrackMenus(
              controller: controller,
              effectMode: effectMode,
              onReturnFocus: onReturnFocus,
            ),
          ],
        );
      },
    );
  }
}
