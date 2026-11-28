import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/constants/app_spacing.dart';

class ThumbnailMediaKitSession {
  ThumbnailMediaKitSession._({
    required this.player,
    required this.videoController,
  });

  final Player player;
  final VideoController videoController;

  static Future<ThumbnailMediaKitSession?> create() async {
    Player? player;
    try {
      player = Player(
        configuration: const PlayerConfiguration(
          muted: true,
          osc: false,
        ),
      );
      final videoController = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          width: AppSpacing.thumbWidth.toInt(),
          height: AppSpacing.thumbHeight.toInt(),
          enableHardwareAcceleration: false,
        ),
      );
      await videoController.platform.future.timeout(
        const Duration(seconds: 3),
      );

      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty(
          'vf',
          'scale=${AppSpacing.thumbWidth.toInt()}:${AppSpacing.thumbHeight.toInt()}:force_original_aspect_ratio=decrease',
        );
      }

      return ThumbnailMediaKitSession._(
        player: player,
        videoController: videoController,
      );
    } catch (e) {
      debugPrint('ThumbnailMediaKitSession.create failed: $e');
      await player?.dispose();
      return null;
    }
  }

  Future<void> dispose() async {
    await player.dispose();
  }
}
