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
import 'widgets/player_auto_next_card.dart';
import 'widgets/player_bottom_hud.dart';
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
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: widget.controller.toggleFullscreen,
                onTap: widget.controller.registerUserActivity,
                child: ColoredBox(
                  color: AppColors.oledBackground,
                  child: _buildPlayerStack(context, hudVisible),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerStack(BuildContext context, bool hudVisible) {
    final isGlass = widget.effectMode == EffectMode.glass;
    final next = widget.controller.nextEntry;

    final topHud = PlayerTopHud(
      entry: widget.controller.currentEntry,
      isFullscreen: widget.controller.isFullscreen,
      onClose: _exitPlayer,
      onToggleFullscreen: widget.controller.toggleFullscreen,
    );
    final bottomHud = PlayerBottomHud(controller: widget.controller);

    return Stack(
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
                    style: Theme.of(context).textTheme.titleMedium,
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
          PlayerAutoNextCard(
            nextEntry: next,
            remainingSeconds: widget.controller.autoNextRemainingSeconds,
            effectMode: widget.effectMode,
            hudVisible: hudVisible,
            onPlayNext: widget.controller.playNextEpisode,
            onDismiss: widget.controller.dismissAutoNext,
          ),
        if (isGlass)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !hudVisible,
              child: AnimatedOpacity(
                opacity: hudVisible ? 1.0 : 0.0,
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
      ],
    );
  }
}
