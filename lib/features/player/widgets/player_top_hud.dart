import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/formatters.dart';
import '../playback_session.dart';
import '../player_models.dart';

class PlayerTopHud extends StatelessWidget {
  const PlayerTopHud({
    super.key,
    required this.entry,
    required this.isFullscreen,
    required this.onClose,
    required this.onToggleFullscreen,
    this.hasEpisodeQueue = false,
    this.sleepTimerOption = SleepTimerOption.off,
    this.sleepTimerRemaining,
    this.onAddBookmark,
    this.onCaptureScreenshot,
    this.onToggleEpisodeDrawer,
    this.onToggleMiniPlayer,
    this.onToggleDiagnostics,
    this.onToggleShortcutSheet,
  });

  final PlaybackQueueEntry? entry;
  final bool isFullscreen;
  final VoidCallback onClose;
  final VoidCallback onToggleFullscreen;
  final bool hasEpisodeQueue;
  final SleepTimerOption sleepTimerOption;
  final Duration? sleepTimerRemaining;
  final VoidCallback? onAddBookmark;
  final VoidCallback? onCaptureScreenshot;
  final VoidCallback? onToggleEpisodeDrawer;
  final VoidCallback? onToggleMiniPlayer;
  final VoidCallback? onToggleDiagnostics;
  final VoidCallback? onToggleShortcutSheet;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: AppSpacing.zero,
      left: AppSpacing.zero,
      right: AppSpacing.zero,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.playerTopHudHeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: const BoxDecoration(
          gradient: AppColors.playerTopHudGradient,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact =
                constraints.maxWidth < AppSpacing.compactTopHudBreakpoint;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: AppStrings.playerCloseTooltip,
                  onPressed: onClose,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _buildTitleColumn(context)),
                if (sleepTimerOption != SleepTimerOption.off)
                  _buildSleepBadge(context),
                ..._buildActions(isCompact),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTitleColumn(BuildContext context) {
    final hudSubtitle = entry != null
        ? Formatters.formatPlayerHudSubtitle(entry!.subtitle, entry!.artist)
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entry?.title ?? AppStrings.appTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (hudSubtitle.isNotEmpty)
          Text(
            hudSubtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _buildSleepBadge(BuildContext context) {
    final label = sleepTimerOption == SleepTimerOption.endOfEpisode
        ? AppStrings.sleepTimerBadgeEndOfEp
        : Formatters.formatSleepTimerRemaining(
            sleepTimerRemaining ?? Duration.zero,
          );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, right: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.badgePaddingH,
          vertical: AppSpacing.badgePaddingV,
        ),
        decoration: BoxDecoration(
          color: AppColors.badgeBackground,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: AppColors.sapphireGlow,
            width: AppSpacing.borderWidthThin,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: AppSpacing.sleepBadgeFontSize,
                color: AppColors.sapphireBright,
              ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(bool isCompact) {
    return [
      if (!isCompact && onAddBookmark != null)
        IconButton(
          tooltip: AppStrings.playerBookmarkTooltip,
          onPressed: onAddBookmark,
          icon: const Icon(Icons.bookmark_add_outlined),
        ),
      if (!isCompact && onCaptureScreenshot != null)
        IconButton(
          tooltip: AppStrings.playerScreenshotTooltip,
          onPressed: onCaptureScreenshot,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      if (hasEpisodeQueue && onToggleEpisodeDrawer != null)
        IconButton(
          tooltip: AppStrings.playerEpisodeDrawerTooltip,
          onPressed: onToggleEpisodeDrawer,
          icon: const Icon(Icons.playlist_play),
        ),
      if (onToggleMiniPlayer != null)
        IconButton(
          tooltip: AppStrings.playerMiniPlayerTooltip,
          onPressed: onToggleMiniPlayer,
          icon: const Icon(Icons.picture_in_picture_alt),
        ),
      if (!isCompact && onToggleDiagnostics != null)
        IconButton(
          tooltip: AppStrings.playerDiagnosticsTooltip,
          onPressed: onToggleDiagnostics,
          icon: const Icon(Icons.info_outline),
        ),
      if (!isCompact && onToggleShortcutSheet != null)
        IconButton(
          tooltip: AppStrings.playerShortcutsTooltip,
          onPressed: onToggleShortcutSheet,
          icon: const Icon(Icons.help_outline),
        ),
      IconButton(
        tooltip: AppStrings.playerFullscreenTooltip,
        onPressed: onToggleFullscreen,
        icon: Icon(isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
      ),
    ];
  }
}
