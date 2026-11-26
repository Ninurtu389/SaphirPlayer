import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/formatters.dart';
import '../saphir_player_controller.dart';
import 'player_track_menus.dart';

class PlayerBottomHud extends StatefulWidget {
  const PlayerBottomHud({
    super.key,
    required this.controller,
  });

  final SaphirPlayerController controller;

  @override
  State<PlayerBottomHud> createState() => _PlayerBottomHudState();
}

class _PlayerBottomHudState extends State<PlayerBottomHud> {
  bool _isSeekHovered = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final durMs = controller.duration.inMilliseconds;
    final posMs = controller.position.inMilliseconds;
    final sliderValue = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
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
            _buildSeekRow(context, sliderValue),
            const SizedBox(height: AppSpacing.xs),
            _buildControlsRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekRow(BuildContext context, double sliderValue) {
    final controller = widget.controller;
    return Row(
      children: [
        Text(
          Formatters.formatPlayerDuration(controller.position),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: MouseRegion(
            onEnter: (_) => setState(() => _isSeekHovered = true),
            onExit: (_) => setState(() => _isSeekHovered = false),
            child: SliderTheme(
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
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          Formatters.formatPlayerDuration(controller.duration),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildControlsRow(BuildContext context) {
    final controller = widget.controller;
    final next = controller.nextEntry;
    final nextTooltip = next != null
        ? '${AppStrings.playerNextEpisodeTooltip}: ${next.subtitle.isNotEmpty ? next.subtitle : next.title}'
        : AppStrings.playerNextEpisodeTooltip;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxWidth < AppSpacing.compactPlayerBreakpoint;

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

        if (isCompact) {
          return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            children: [
              ...transportButtons,
              muteButton,
              PlayerTrackMenus(controller: controller),
            ],
          );
        }

        return Row(
          children: [
            ...transportButtons,
            const SizedBox(width: AppSpacing.md),
            muteButton,
            SizedBox(
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
                  max: AppSpacing.volumeMax,
                  value: controller.volume.clamp(
                    AppSpacing.volumeMin,
                    AppSpacing.volumeMax,
                  ),
                  onChanged: (val) =>
                      controller.adjustVolume(val - controller.volume),
                ),
              ),
            ),
            const Spacer(),
            PlayerTrackMenus(controller: controller),
          ],
        );
      },
    );
  }
}
