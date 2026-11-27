import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/effect_mode.dart';
import '../../widgets/surface_panel.dart';
import 'saphir_player_controller.dart';
import 'widgets/player_action_osd.dart';
import 'widgets/player_auto_next_card.dart';
import 'widgets/player_bottom_hud.dart';
import 'widgets/player_diagnostics_overlay.dart';
import 'widgets/player_episode_drawer.dart';
import 'widgets/player_intro_skip_button.dart';
import 'widgets/player_mini_hud.dart';
import 'widgets/player_shortcut_sheet.dart';
import 'widgets/player_top_hud.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _restoreFocus() {
    if (mounted) {
      _focusNode.requestFocus();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final c = widget.controller;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.space) {
      c.togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      c.seekRelativeSeconds(
        -(shift ? AppSpacing.seekStepLongSeconds : AppSpacing.seekStepSeconds),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      c.seekRelativeSeconds(
        shift ? AppSpacing.seekStepLongSeconds : AppSpacing.seekStepSeconds,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      c.adjustVolume(AppSpacing.volumeStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      c.adjustVolume(-AppSpacing.volumeStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      c.toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      c.toggleMute();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      c.playNextEpisode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP) {
      c.playPreviousEpisode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      c.jumpToNextChapter();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      c.jumpToPreviousChapter();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.period) {
      c.stepFrame(forward: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.comma) {
      c.stepFrame(forward: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      c.cycleAspectMode();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      c.addBookmarkAtCurrentPosition();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      c.captureScreenshot();
      return KeyEventResult.handled;
    }
    if (!c.isMiniPlayer && key == LogicalKeyboardKey.keyE) {
      c.toggleEpisodeDrawer();
      return KeyEventResult.handled;
    }
    if (!c.isMiniPlayer && key == LogicalKeyboardKey.keyI) {
      c.toggleDiagnostics();
      return KeyEventResult.handled;
    }
    if (!c.isMiniPlayer &&
        (key == LogicalKeyboardKey.keyH ||
            key == LogicalKeyboardKey.question ||
            event.character == '?')) {
      c.toggleShortcutSheet();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (c.closeTopOverlay()) return KeyEventResult.handled;
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final hudVisible = widget.controller.isHudVisible;
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
              child: ColoredBox(
                color: AppColors.oledBackground,
                child: _buildPlayerStack(context, hudVisible),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerStack(BuildContext context, bool hudVisible) {
    final c = widget.controller;
    final isGlass = widget.effectMode == EffectMode.glass;
    final topHud = _buildTopHud(c);
    final bottomHud = PlayerBottomHud(
      controller: c,
      effectMode: widget.effectMode,
      onReturnFocus: _restoreFocus,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: c.toggleFullscreen,
          onTap: c.registerUserActivity,
          child: Video(controller: c.videoController, controls: NoVideoControls),
        ),
        if (c.errorMessage != null) _buildErrorCard(context, c.errorMessage!),
        if (!c.isMiniPlayer) _buildProgressOverlays(c, hudVisible),
        if (c.isMiniPlayer)
          PlayerMiniHud(
            isPlaying: c.isPlaying,
            effectMode: widget.effectMode,
            onTogglePlayPause: c.togglePlayPause,
            onExitMiniPlayer: c.toggleMiniPlayer,
            onClose: _exitPlayer,
            onStartDrag: c.startMiniPlayerWindowDrag,
          )
        else if (isGlass)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !hudVisible,
              child: AnimatedOpacity(
                opacity: hudVisible
                    ? AppSpacing.opacityVisible
                    : AppSpacing.opacityHidden,
                duration: const Duration(
                  milliseconds: AppSpacing.hudFadeAnimationMs,
                ),
                child: Stack(children: [topHud, bottomHud]),
              ),
            ),
          )
        else if (hudVisible) ...[
          topHud,
          bottomHud,
        ],
        if (!c.isMiniPlayer && c.showDiagnostics)
          PlayerDiagnosticsOverlay(
            diagnostics: c.diagnostics,
            effectMode: widget.effectMode,
            onClose: () {
              c.toggleDiagnostics();
              _restoreFocus();
            },
          ),
        if (!c.isMiniPlayer && c.isEpisodeDrawerOpen && c.session != null)
          PlayerEpisodeDrawer(
            queue: c.session!.queue,
            currentIndex: c.currentIndex,
            effectMode: widget.effectMode,
            onSelectIndex: (idx) {
              c.playEntryAtIndex(idx);
              _restoreFocus();
            },
            onClose: () {
              c.toggleEpisodeDrawer();
              _restoreFocus();
            },
          ),
        if (!c.isMiniPlayer && c.isShortcutSheetOpen)
          PlayerShortcutSheet(
            effectMode: widget.effectMode,
            onClose: () {
              c.toggleShortcutSheet();
              _restoreFocus();
            },
          ),
        PlayerActionOsd(
          message: c.osdMessage,
          kind: c.osdKind,
          effectMode: widget.effectMode,
        ),
      ],
    );
  }

  Widget _buildTopHud(SaphirPlayerController c) {
    return PlayerTopHud(
      entry: c.currentEntry,
      isFullscreen: c.isFullscreen,
      onClose: _exitPlayer,
      onToggleFullscreen: c.toggleFullscreen,
      hasEpisodeQueue: (c.session?.queue.length ?? 0) > 1,
      sleepTimerOption: c.sleepTimerOption,
      sleepTimerRemaining: c.sleepTimerRemaining,
      onAddBookmark: c.addBookmarkAtCurrentPosition,
      onCaptureScreenshot: c.captureScreenshot,
      onToggleEpisodeDrawer: c.toggleEpisodeDrawer,
      onToggleMiniPlayer: c.toggleMiniPlayer,
      onToggleDiagnostics: c.toggleDiagnostics,
      onToggleShortcutSheet: c.toggleShortcutSheet,
    );
  }

  Widget _buildProgressOverlays(SaphirPlayerController c, bool hudVisible) {
    return ValueListenableBuilder<({Duration position, Duration duration})>(
      valueListenable: c.progressListenable,
      builder: (context, _, __) {
        final next = c.nextEntry;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (c.showIntroSkipButton)
              PlayerIntroSkipButton(
                effectMode: widget.effectMode,
                hudVisible: hudVisible,
                selectedSeconds: c.effectiveIntroSkipSeconds,
                onSkipIntro: c.skipIntro,
                onSelectSeconds: c.setSeriesIntroSkipSeconds,
                onDismiss: c.dismissIntroSkip,
              ),
            if (c.showAutoNextCard && next != null)
              PlayerAutoNextCard(
                nextEntry: next,
                remainingSeconds: c.autoNextRemainingSeconds,
                effectMode: widget.effectMode,
                hudVisible: hudVisible,
                onPlayNext: c.playNextEpisode,
                onDismiss: c.dismissAutoNext,
              ),
          ],
        );
      },
    );
  }

  Widget _buildErrorCard(BuildContext context, String message) {
    return Center(
      child: SurfacePanel(
        effectMode: widget.effectMode,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _exitPlayer,
              child: const Text(AppStrings.backButton),
            ),
          ],
        ),
      ),
    );
  }
}
