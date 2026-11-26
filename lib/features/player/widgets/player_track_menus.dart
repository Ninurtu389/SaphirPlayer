import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/formatters.dart';
import '../saphir_player_controller.dart';

class PlayerTrackMenus extends StatelessWidget {
  const PlayerTrackMenus({
    super.key,
    required this.controller,
  });

  final SaphirPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AudioTrackMenu(controller: controller),
        _SubtitleTrackMenu(controller: controller),
        _PlaybackSpeedMenu(controller: controller),
      ],
    );
  }
}

class _AudioTrackMenu extends StatelessWidget {
  const _AudioTrackMenu({required this.controller});

  final SaphirPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.audioTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    if (tracks.isEmpty) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<AudioTrack>(
      tooltip: AppStrings.playerAudioTrackTooltip,
      icon: const Icon(Icons.audiotrack),
      onSelected: controller.selectAudioTrack,
      itemBuilder: (context) => tracks
          .map(
            (track) => PopupMenuItem<AudioTrack>(
              value: track,
              child: Text(
                Formatters.formatAudioTrackLabel(
                  track.title,
                  track.language,
                  track.id,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SubtitleTrackMenu extends StatelessWidget {
  const _SubtitleTrackMenu({required this.controller});

  final SaphirPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.subtitleTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    return PopupMenuButton<SubtitleTrack>(
      tooltip: AppStrings.playerSubtitleTrackTooltip,
      icon: const Icon(Icons.subtitles),
      onSelected: controller.selectSubtitleTrack,
      itemBuilder: (context) => [
        PopupMenuItem<SubtitleTrack>(
          value: SubtitleTrack.no(),
          child: const Text(AppStrings.playerSubtitleOffLabel),
        ),
        ...tracks.map(
          (track) => PopupMenuItem<SubtitleTrack>(
            value: track,
            child: Text(
              Formatters.formatSubtitleTrackLabel(
                track.title,
                track.language,
                track.id,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaybackSpeedMenu extends StatelessWidget {
  const _PlaybackSpeedMenu({required this.controller});

  final SaphirPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final currentSpeed = controller.playbackSpeed;
    return PopupMenuButton<double>(
      tooltip: AppStrings.playerSpeedTooltip,
      onSelected: controller.setPlaybackSpeed,
      itemBuilder: (context) => AppSpacing.playbackSpeeds
          .map(
            (speed) => PopupMenuItem<double>(
              value: speed,
              child: Text(
                '${speed}x',
                style: TextStyle(
                  color: speed == currentSpeed
                      ? AppColors.sapphireBright
                      : AppColors.textPrimary,
                  fontWeight: speed == currentSpeed
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          '${currentSpeed}x',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
