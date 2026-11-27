import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../core/utils/formatters.dart';
import '../player_models.dart';
import '../saphir_player_controller.dart';
import 'player_subtitle_style_dialog.dart';

class PlayerTrackMenus extends StatelessWidget {
  const PlayerTrackMenus({
    super.key,
    required this.controller,
    required this.effectMode,
  });

  final SaphirPlayerController controller;
  final EffectMode effectMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AudioTrackMenu(controller: controller),
        _SubtitleTrackMenu(controller: controller, effectMode: effectMode),
        IconButton(
          tooltip: AppStrings.playerAspectModeTooltip,
          onPressed: controller.cycleAspectMode,
          icon: const Icon(Icons.aspect_ratio, size: AppSpacing.iconSizeMd),
        ),
        _SleepTimerMenu(controller: controller),
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
    return PopupMenuButton<Object>(
      tooltip: AppStrings.playerAudioTrackTooltip,
      icon: const Icon(Icons.audiotrack),
      onOpened: () => controller.setMenuOrDialogOpen(true),
      onCanceled: () => controller.setMenuOrDialogOpen(false),
      onSelected: (value) {
        controller.setMenuOrDialogOpen(false);
        if (value is AudioTrack) {
          controller.selectAudioTrack(value);
        } else if (value == _AudioAction.nightMode) {
          controller.toggleNightMode();
        } else if (value == _AudioAction.volumeBoost) {
          controller.toggleVolumeBoost();
        }
      },
      itemBuilder: (context) => [
        ...tracks.map(
          (track) => PopupMenuItem<Object>(
            value: track,
            child: Text(
              Formatters.formatAudioTrackLabel(
                track.title,
                track.language,
                track.id,
              ),
              style: TextStyle(
                color: track.id == controller.activeAudioTrack.id
                    ? AppColors.sapphireBright
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ),
        if (tracks.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: _AudioAction.nightMode,
          child: _CheckRow(
            label: AppStrings.playerNightModeLabel,
            checked: controller.isNightMode,
          ),
        ),
        PopupMenuItem<Object>(
          value: _AudioAction.volumeBoost,
          child: _CheckRow(
            label: AppStrings.playerVolumeBoostLabel,
            checked: controller.isVolumeBoostEnabled,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          enabled: false,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _DelayControlRow(
              label: AppStrings.playerAudioDelayLabel,
              delayMs: controller.audioDelayMs,
              onDecrease: () =>
                  controller.adjustAudioDelay(-AppSpacing.delayStepMs),
              onIncrease: () =>
                  controller.adjustAudioDelay(AppSpacing.delayStepMs),
              onReset: controller.resetAudioDelay,
            ),
          ),
        ),
      ],
    );
  }
}

enum _AudioAction { nightMode, volumeBoost }

enum _SubtitleAction { off, loadExternal, openStyle }

class _SubtitleTrackMenu extends StatelessWidget {
  const _SubtitleTrackMenu({
    required this.controller,
    required this.effectMode,
  });

  final SaphirPlayerController controller;
  final EffectMode effectMode;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.subtitleTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    return PopupMenuButton<Object>(
      tooltip: AppStrings.playerSubtitleTrackTooltip,
      icon: const Icon(Icons.subtitles),
      onOpened: () => controller.setMenuOrDialogOpen(true),
      onCanceled: () => controller.setMenuOrDialogOpen(false),
      onSelected: (value) {
        controller.setMenuOrDialogOpen(false);
        if (value is SubtitleTrack) {
          controller.selectSubtitleTrack(value);
        } else if (value == _SubtitleAction.off) {
          controller.selectSubtitleTrack(SubtitleTrack.no());
        } else if (value == _SubtitleAction.loadExternal) {
          controller.loadExternalSubtitle(
            AppStrings.playerPickSubtitleDialogTitle,
          );
        } else if (value == _SubtitleAction.openStyle) {
          controller.setMenuOrDialogOpen(true);
          showDialog<void>(
            context: context,
            builder: (_) => PlayerSubtitleStyleDialog(
              controller: controller,
              effectMode: effectMode,
            ),
          ).whenComplete(() => controller.setMenuOrDialogOpen(false));
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<Object>(
          value: _SubtitleAction.off,
          child: Text(AppStrings.playerSubtitleOffLabel),
        ),
        ...tracks.map(
          (track) => PopupMenuItem<Object>(
            value: track,
            child: Text(
              Formatters.formatSubtitleTrackLabel(
                track.title,
                track.language,
                track.id,
              ),
              style: TextStyle(
                color: track.id == controller.activeSubtitleTrack.id
                    ? AppColors.sapphireBright
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: _SubtitleAction.loadExternal,
          child: Text(AppStrings.playerLoadExternalSubLabel),
        ),
        const PopupMenuItem<Object>(
          value: _SubtitleAction.openStyle,
          child: Text(AppStrings.playerSubtitleStyleLabel),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          enabled: false,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _DelayControlRow(
              label: AppStrings.playerSubtitleDelayLabel,
              delayMs: controller.subtitleDelayMs,
              onDecrease: () =>
                  controller.adjustSubtitleDelay(-AppSpacing.delayStepMs),
              onIncrease: () =>
                  controller.adjustSubtitleDelay(AppSpacing.delayStepMs),
              onReset: controller.resetSubtitleDelay,
            ),
          ),
        ),
      ],
    );
  }
}

class _SleepTimerMenu extends StatelessWidget {
  const _SleepTimerMenu({required this.controller});

  final SaphirPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.sleepTimerOption;
    return PopupMenuButton<SleepTimerOption>(
      tooltip: AppStrings.playerSleepTimerTooltip,
      onOpened: () => controller.setMenuOrDialogOpen(true),
      onCanceled: () => controller.setMenuOrDialogOpen(false),
      icon: Icon(
        Icons.bedtime_outlined,
        size: AppSpacing.iconSizeMd,
        color: active != SleepTimerOption.off
            ? AppColors.sapphireBright
            : AppColors.textPrimary,
      ),
      onSelected: (opt) {
        controller.setMenuOrDialogOpen(false);
        controller.setSleepTimer(opt);
      },
      itemBuilder: (context) => SleepTimerOption.values
          .map(
            (opt) => PopupMenuItem<SleepTimerOption>(
              value: opt,
              child: _CheckRow(
                label: Formatters.formatSleepTimerOptionLabel(opt),
                checked: opt == active,
              ),
            ),
          )
          .toList(),
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
      onOpened: () => controller.setMenuOrDialogOpen(true),
      onCanceled: () => controller.setMenuOrDialogOpen(false),
      onSelected: (speed) {
        controller.setMenuOrDialogOpen(false);
        controller.setPlaybackSpeed(speed);
      },
      itemBuilder: (context) => AppSpacing.playbackSpeeds
          .map(
            (speed) => PopupMenuItem<double>(
              value: speed,
              child: Text(
                Formatters.formatPlaybackSpeed(speed),
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
          Formatters.formatPlaybackSpeed(currentSpeed),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.checked});

  final String label;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          checked ? Icons.check_box : Icons.check_box_outline_blank,
          size: AppSpacing.iconSizeSm,
          color: checked ? AppColors.sapphireBright : AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(label)),
      ],
    );
  }
}

class _DelayControlRow extends StatelessWidget {
  const _DelayControlRow({
    required this.label,
    required this.delayMs,
    required this.onDecrease,
    required this.onIncrease,
    required this.onReset,
  });

  final String label;
  final int delayMs;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ${Formatters.formatDelayMs(delayMs)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: onDecrease,
              child: const Text(AppStrings.playerDelayMinusLabel),
            ),
            TextButton(
              onPressed: onIncrease,
              child: const Text(AppStrings.playerDelayPlusLabel),
            ),
            TextButton(
              onPressed: onReset,
              child: const Text(AppStrings.playerDelayResetLabel),
            ),
          ],
        ),
      ],
    );
  }
}
