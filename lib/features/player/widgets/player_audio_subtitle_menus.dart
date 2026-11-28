import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../core/utils/formatters.dart';
import '../saphir_player_controller.dart';
import 'player_subtitle_style_dialog.dart';

enum _AudioAction { auto, nightMode, volumeBoost }

enum _SubtitleAction { auto, off, loadExternal, openStyle }

class PlayerAudioTrackMenu extends StatelessWidget {
  const PlayerAudioTrackMenu({
    super.key,
    required this.controller,
    this.onReturnFocus,
  });

  final SaphirPlayerController controller;
  final VoidCallback? onReturnFocus;

  void _closeMenu() {
    controller.setMenuOrDialogOpen(false);
    onReturnFocus?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = controller.audioTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    return PopupMenuButton<Object>(
      tooltip: AppStrings.playerAudioTrackTooltip,
      icon: const Icon(Icons.audiotrack),
      onOpened: () => controller.setMenuOrDialogOpen(true),
      onCanceled: _closeMenu,
      onSelected: (value) {
        _closeMenu();
        if (value is AudioTrack) {
          controller.selectAudioTrack(value);
        } else if (value == _AudioAction.auto) {
          controller.selectAudioTrack(AudioTrack.auto());
        } else if (value == _AudioAction.nightMode) {
          controller.toggleNightMode();
        } else if (value == _AudioAction.volumeBoost) {
          controller.toggleVolumeBoost();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<Object>(
          value: _AudioAction.auto,
          child: Text(
            AppStrings.playerTrackAutoLabel,
            style: TextStyle(
              color: controller.activeAudioTrack.id == 'auto'
                  ? AppColors.sapphireBright
                  : AppColors.textPrimary,
              fontWeight: controller.activeAudioTrack.id == 'auto'
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
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
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: _AudioAction.nightMode,
          child: PlayerMenuCheckRow(
            label: AppStrings.playerNightModeLabel,
            checked: controller.isNightMode,
          ),
        ),
        PopupMenuItem<Object>(
          value: _AudioAction.volumeBoost,
          child: PlayerMenuCheckRow(
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

class PlayerSubtitleTrackMenu extends StatelessWidget {
  const PlayerSubtitleTrackMenu({
    super.key,
    required this.controller,
    required this.effectMode,
    this.onReturnFocus,
  });

  final SaphirPlayerController controller;
  final EffectMode effectMode;
  final VoidCallback? onReturnFocus;

  void _closeMenu() {
    controller.setMenuOrDialogOpen(false);
    onReturnFocus?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = controller.subtitleTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final isOff = controller.activeSubtitleTrack.id == 'no';

    return PopupMenuButton<Object>(
      tooltip: AppStrings.playerSubtitleTrackTooltip,
      icon: const Icon(Icons.subtitles),
      onOpened: () => controller.setMenuOrDialogOpen(true),
      onCanceled: _closeMenu,
      onSelected: (value) {
        if (value == _SubtitleAction.openStyle) {
          controller.setMenuOrDialogOpen(true);
          showDialog<void>(
            context: context,
            builder: (_) => PlayerSubtitleStyleDialog(
              controller: controller,
              effectMode: effectMode,
            ),
          ).whenComplete(_closeMenu);
          return;
        }
        _closeMenu();
        if (value is SubtitleTrack) {
          controller.selectSubtitleTrack(value);
        } else if (value == _SubtitleAction.auto) {
          controller.selectSubtitleTrack(SubtitleTrack.auto());
        } else if (value == _SubtitleAction.off) {
          controller.selectSubtitleTrack(SubtitleTrack.no());
        } else if (value == _SubtitleAction.loadExternal) {
          controller
              .loadExternalSubtitle(AppStrings.playerPickSubtitleDialogTitle)
              .whenComplete(() => onReturnFocus?.call());
        }
      },
      itemBuilder: (context) => _buildMenuItems(context, tracks, isOff),
    );
  }

  List<PopupMenuEntry<Object>> _buildMenuItems(
    BuildContext context,
    List<SubtitleTrack> tracks,
    bool isOff,
  ) =>
      [
        PopupMenuItem<Object>(
          value: _SubtitleAction.auto,
          child: Text(
            AppStrings.playerTrackAutoLabel,
            style: TextStyle(
              color: controller.activeSubtitleTrack.id == 'auto'
                  ? AppColors.sapphireBright
                  : AppColors.textPrimary,
              fontWeight: controller.activeSubtitleTrack.id == 'auto'
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
        PopupMenuItem<Object>(
          value: _SubtitleAction.off,
          child: Text(
            AppStrings.playerSubtitleOffLabel,
            style: TextStyle(
              color: isOff ? AppColors.sapphireBright : AppColors.textPrimary,
              fontWeight: isOff ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
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
      ];
}

class PlayerMenuCheckRow extends StatelessWidget {
  const PlayerMenuCheckRow({
    super.key,
    required this.label,
    required this.checked,
  });

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
        Wrap(
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
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
