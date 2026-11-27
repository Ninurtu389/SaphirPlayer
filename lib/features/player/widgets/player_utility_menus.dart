import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/formatters.dart';
import '../player_models.dart';
import '../saphir_player_controller.dart';
import 'player_audio_subtitle_menus.dart';

class PlayerChapterNavButtons extends StatelessWidget {
  const PlayerChapterNavButtons({
    super.key,
    required this.controller,
    this.onReturnFocus,
  });

  final SaphirPlayerController controller;
  final VoidCallback? onReturnFocus;

  @override
  Widget build(BuildContext context) {
    if (controller.chapters.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: AppStrings.playerChapterPrevTooltip,
          onPressed: () {
            controller.jumpToPreviousChapter();
            onReturnFocus?.call();
          },
          icon: const Icon(
            Icons.fast_rewind,
            size: AppSpacing.iconSizeMd,
          ),
        ),
        IconButton(
          tooltip: AppStrings.playerChapterNextTooltip,
          onPressed: () {
            controller.jumpToNextChapter();
            onReturnFocus?.call();
          },
          icon: const Icon(
            Icons.fast_forward,
            size: AppSpacing.iconSizeMd,
          ),
        ),
      ],
    );
  }
}

class PlayerBookmarkMenu extends StatelessWidget {
  const PlayerBookmarkMenu({
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
    final bookmarks = controller.bookmarks;
    return PopupMenuButton<MediaBookmark>(
      tooltip: AppStrings.playerBookmarksTooltip,
      icon: Icon(
        Icons.bookmarks_outlined,
        size: AppSpacing.iconSizeMd,
        color: bookmarks.isNotEmpty
            ? AppColors.sapphireBright
            : AppColors.textPrimary,
      ),
      onOpened: () => controller.setMenuOrDialogOpen(true),
      onCanceled: _closeMenu,
      onSelected: (bm) {
        _closeMenu();
        controller.seekToBookmark(bm);
      },
      itemBuilder: (context) => [
        PopupMenuItem<MediaBookmark>(
          enabled: false,
          child: Text(
            AppStrings.playerBookmarkListTitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.sapphireBright,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const PopupMenuDivider(),
        if (bookmarks.isEmpty)
          const PopupMenuItem<MediaBookmark>(
            enabled: false,
            child: Text(AppStrings.playerNoBookmarksLabel),
          )
        else
          ...bookmarks.map(
            (bm) => PopupMenuItem<MediaBookmark>(
              value: bm,
              child: _BookmarkMenuRow(
                bookmark: bm,
                onDelete: () {
                  controller.deleteBookmark(bm.id);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _BookmarkMenuRow extends StatelessWidget {
  const _BookmarkMenuRow({
    required this.bookmark,
    required this.onDelete,
  });

  final MediaBookmark bookmark;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final timeStr = Formatters.formatPlayerDuration(
      Duration(milliseconds: bookmark.positionMs),
    );
    final label = bookmark.label.trim().isNotEmpty
        ? '$timeStr${AppStrings.metadataSeparator}${bookmark.label.trim()}'
        : timeStr;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: AppStrings.playerBookmarkDeletedOsd,
          onPressed: onDelete,
          icon: const Icon(
            Icons.delete_outline,
            size: AppSpacing.iconSizeSm,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class PlayerSleepTimerMenu extends StatelessWidget {
  const PlayerSleepTimerMenu({
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
    final active = controller.sleepTimerOption;
    return PopupMenuButton<SleepTimerOption>(
      tooltip: AppStrings.playerSleepTimerTooltip,
      onOpened: () => controller.setMenuOrDialogOpen(true),
      onCanceled: _closeMenu,
      icon: Icon(
        Icons.bedtime_outlined,
        size: AppSpacing.iconSizeMd,
        color: active != SleepTimerOption.off
            ? AppColors.sapphireBright
            : AppColors.textPrimary,
      ),
      onSelected: (opt) {
        _closeMenu();
        controller.setSleepTimer(opt);
      },
      itemBuilder: (context) => SleepTimerOption.values
          .map(
            (opt) => PopupMenuItem<SleepTimerOption>(
              value: opt,
              child: PlayerMenuCheckRow(
                label: Formatters.formatSleepTimerOptionLabel(opt),
                checked: opt == active,
              ),
            ),
          )
          .toList(),
    );
  }
}

class PlayerPlaybackSpeedMenu extends StatelessWidget {
  const PlayerPlaybackSpeedMenu({
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
    final currentSpeed = controller.playbackSpeed;
    return PopupMenuButton<double>(
      tooltip: AppStrings.playerSpeedTooltip,
      onOpened: () => controller.setMenuOrDialogOpen(true),
      onCanceled: _closeMenu,
      onSelected: (speed) {
        _closeMenu();
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
