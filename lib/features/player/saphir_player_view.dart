import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/effect_mode.dart';
import '../../widgets/surface_panel.dart';
import 'saphir_player_controller.dart';

class SaphirPlayerView extends StatefulWidget {
  const SaphirPlayerView({
    super.key,
    required this.controller,
    required this.effectMode,
    required this.onClose,
  });

  final SaphirPlayerController controller;
  final EffectMode effectMode;
  final VoidCallback onClose;

  @override
  State<SaphirPlayerView> createState() => _SaphirPlayerViewState();
}

class _SaphirPlayerViewState extends State<SaphirPlayerView> {
  final FocusNode _focusNode = FocusNode();
  bool _isSeekHovered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      widget.controller.togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.controller.seekRelativeSeconds(-AppSpacing.seekStepSeconds);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.controller.seekRelativeSeconds(AppSpacing.seekStepSeconds);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _exitPlayer();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handlePointerDown(PointerDownEvent event) {
    widget.controller.registerUserActivity();
    if ((event.buttons & kForwardMouseButton) != 0) {
      widget.controller.playNextEpisode();
    } else if ((event.buttons & kBackMouseButton) != 0) {
      widget.controller.playPreviousEpisode();
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final delta = event.scrollDelta.dy < 0
          ? AppSpacing.volumeStep
          : -AppSpacing.volumeStep;
      widget.controller.adjustVolume(delta);
    }
  }

  Future<void> _exitPlayer() async {
    await widget.controller.stopAndClose();
    widget.onClose();
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final isGlass = widget.effectMode == EffectMode.glass;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final entry = widget.controller.currentEntry;
        final next = widget.controller.nextEntry;
        final hudVisible = widget.controller.isHudVisible;
        final durMs = widget.controller.duration.inMilliseconds;
        final posMs = widget.controller.position.inMilliseconds;
        final sliderValue = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

        final nextTooltip = next != null
            ? '${AppStrings.playerNextEpisodeTooltip}: ${next.subtitle.isNotEmpty ? next.subtitle : next.title}'
            : AppStrings.playerNextEpisodeTooltip;

        final topHud = Positioned(
          top: 0,
          left: 0,
          right: 0,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: AppStrings.playerCloseTooltip,
                  onPressed: _exitPlayer,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry?.title ?? AppStrings.appTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (entry != null && entry.subtitle.isNotEmpty)
                        Text(
                          entry.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: AppStrings.playerFullscreenTooltip,
                  onPressed: widget.controller.toggleFullscreen,
                  icon: Icon(
                    widget.controller.isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                  ),
                ),
              ],
            ),
          ),
        );

        final bottomHud = Positioned(
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
                Row(
                  children: [
                    Text(
                      _formatDuration(widget.controller.position),
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
                            onChanged: widget.controller.seekToRatio,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _formatDuration(widget.controller.duration),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    IconButton(
                      tooltip: AppStrings.playerPrevEpisodeTooltip,
                      onPressed: widget.controller.hasPreviousEpisode
                          ? widget.controller.playPreviousEpisode
                          : null,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    IconButton(
                      tooltip: AppStrings.playerSeekBackTooltip,
                      onPressed: () => widget.controller
                          .seekRelativeSeconds(-AppSpacing.seekStepSeconds),
                      icon: const Icon(Icons.replay_10),
                    ),
                    IconButton(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      constraints: const BoxConstraints(),
                      tooltip: widget.controller.isPlaying
                          ? AppStrings.playerPauseTooltip
                          : AppStrings.playerPlayTooltip,
                      onPressed: widget.controller.togglePlayPause,
                      icon: Icon(
                        widget.controller.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: AppSpacing.iconSizeXl,
                        color: AppColors.sapphireBright,
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.playerSeekForwardTooltip,
                      onPressed: () => widget.controller
                          .seekRelativeSeconds(AppSpacing.seekStepSeconds),
                      icon: const Icon(Icons.forward_10),
                    ),
                    IconButton(
                      tooltip: nextTooltip,
                      onPressed: widget.controller.hasNextEpisode
                          ? widget.controller.playNextEpisode
                          : null,
                      icon: const Icon(Icons.skip_next),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    IconButton(
                      tooltip: widget.controller.isMuted
                          ? AppStrings.playerUnmuteTooltip
                          : AppStrings.playerMuteTooltip,
                      onPressed: widget.controller.toggleMute,
                      icon: Icon(
                        widget.controller.isMuted
                            ? Icons.volume_off
                            : Icons.volume_up,
                        size: AppSpacing.iconSizeMd,
                      ),
                    ),
                    SizedBox(
                      width: AppSpacing.hudSliderWidth,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: AppSpacing.progressBarHeight,
                          activeTrackColor: AppColors.sapphireBright,
                          inactiveTrackColor: AppColors.progressTrack,
                          thumbColor: AppColors.textPrimary,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius:
                                AppSpacing.playerSeekThumbRadius,
                          ),
                        ),
                        child: Slider(
                          min: AppSpacing.volumeMin,
                          max: AppSpacing.volumeMax,
                          value: widget.controller.volume.clamp(
                            AppSpacing.volumeMin,
                            AppSpacing.volumeMax,
                          ),
                          onChanged: (val) => widget.controller
                              .adjustVolume(val - widget.controller.volume),
                        ),
                      ),
                    ),
                    const Spacer(),
                    _buildAudioMenu(),
                    _buildSubtitleMenu(),
                    _buildSpeedMenu(),
                  ],
                ),
              ],
            ),
          ),
        );

        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handlePointerDown,
            onPointerHover: (_) => widget.controller.registerUserActivity(),
            onPointerMove: (_) => widget.controller.registerUserActivity(),
            onPointerSignal: _handlePointerSignal,
            child: MouseRegion(
              cursor: hudVisible
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.none,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: widget.controller.toggleFullscreen,
                onTap: widget.controller.registerUserActivity,
                child: ColoredBox(
                  color: AppColors.oledBackground,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Video(
                        controller: widget.controller.videoController,
                        controls: NoVideoControls,
                      ),
                      if (widget.controller.errorMessage != null)
                        Center(
                          child: SurfacePanel(
                            effectMode: widget.effectMode,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.controller.errorMessage!,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                ElevatedButton(
                                  onPressed: _exitPlayer,
                                  child: const Text(AppStrings.backButton),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (widget.controller.showAutoNextCard && next != null)
                        Positioned(
                          right: AppSpacing.lg,
                          bottom: hudVisible
                              ? AppSpacing.autoNextBottomWithHud
                              : AppSpacing.lg,
                          child: SizedBox(
                            width: AppSpacing.autoNextCardWidth,
                            child: SurfacePanel(
                              effectMode: widget.effectMode,
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${AppStrings.autoNextTitle} (${widget.controller.autoNextRemainingSeconds} ${AppStrings.autoNextSecondsSuffix})',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppColors.sapphireBright,
                                        ),
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(
                                    next.subtitle.isNotEmpty
                                        ? next.subtitle
                                        : next.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Row(
                                    children: [
                                      ElevatedButton(
                                        onPressed:
                                            widget.controller.playNextEpisode,
                                        child: const Text(
                                            AppStrings.autoNextPlayNowButton),
                                      ),
                                      const SizedBox(width: AppSpacing.xs),
                                      TextButton(
                                        onPressed:
                                            widget.controller.dismissAutoNext,
                                        child: const Text(
                                            AppStrings.autoNextCancelButton),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (isGlass) ...[
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: !hudVisible,
                            child: AnimatedOpacity(
                              opacity: hudVisible ? 1.0 : 0.0,
                              duration: const Duration(
                                milliseconds: AppSpacing.hudFadeAnimationMs,
                              ),
                              child: Stack(
                                children: [topHud, bottomHud],
                              ),
                            ),
                          ),
                        ),
                      ] else if (hudVisible) ...[
                        topHud,
                        bottomHud,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAudioMenu() {
    final tracks = widget.controller.audioTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    if (tracks.isEmpty) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<AudioTrack>(
      tooltip: AppStrings.playerAudioTrackTooltip,
      icon: const Icon(Icons.audiotrack),
      onSelected: widget.controller.selectAudioTrack,
      itemBuilder: (context) => tracks
          .map(
            (track) => PopupMenuItem<AudioTrack>(
              value: track,
              child: Text(
                track.title ?? track.language ?? 'Spur ${track.id}',
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSubtitleMenu() {
    final tracks = widget.controller.subtitleTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    return PopupMenuButton<SubtitleTrack>(
      tooltip: AppStrings.playerSubtitleTrackTooltip,
      icon: const Icon(Icons.subtitles),
      onSelected: widget.controller.selectSubtitleTrack,
      itemBuilder: (context) => [
        PopupMenuItem<SubtitleTrack>(
          value: SubtitleTrack.no(),
          child: const Text(AppStrings.playerSubtitleOffLabel),
        ),
        ...tracks.map(
          (track) => PopupMenuItem<SubtitleTrack>(
            value: track,
            child: Text(
              track.title ?? track.language ?? 'Untertitel ${track.id}',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedMenu() {
    final currentSpeed = widget.controller.playbackSpeed;
    return PopupMenuButton<double>(
      tooltip: AppStrings.playerSpeedTooltip,
      onSelected: widget.controller.setPlaybackSpeed,
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
