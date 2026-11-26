import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import '../../core/storage/portable_paths.dart';

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

class ThumbnailGeneratorService {
  ThumbnailGeneratorService._();

  static Future<String?> generateEpisodeThumbnail({
    required String videoFilePath,
    required int durationMs,
    required bool isPlaybackActive,
    ThumbnailMediaKitSession? mediaKitSession,
    bool allowMediaKitFallback = true,
  }) async {
    return generateThumbnail(
      videoFilePath: videoFilePath,
      durationMs: durationMs,
      isPlaybackActive: isPlaybackActive,
      prefix: 'ep',
      mediaKitSession: mediaKitSession,
      allowMediaKitFallback: allowMediaKitFallback,
    );
  }

  static Future<String?> generateThumbnail({
    required String videoFilePath,
    required int durationMs,
    required bool isPlaybackActive,
    String prefix = 'ep',
    ThumbnailMediaKitSession? mediaKitSession,
    bool allowMediaKitFallback = true,
  }) async {
    if (isPlaybackActive) {
      return null;
    }

    final videoFile = File(videoFilePath);
    if (!await videoFile.exists()) {
      return null;
    }
    try {
      if (await videoFile.length() == 0) {
        return null;
      }
    } on FileSystemException {
      return null;
    }

    final cacheDir = await PortablePaths.getCacheDirectory();
    final hashName = _stablePathHash(videoFilePath);
    final outputPath = p.join(cacheDir, '${prefix}_$hashName.jpg');
    final outputFile = File(outputPath);

    if (await outputFile.exists()) {
      try {
        if (await outputFile.length() > 0) {
          return outputPath;
        }
        await outputFile.delete();
      } on FileSystemException {
        return null;
      }
    }

    final seekSeconds = _computeSeekSeconds(durationMs);

    final ffmpegResult = await _tryGenerateWithFfmpeg(
      videoFilePath: videoFilePath,
      seekSeconds: seekSeconds,
      outputPath: outputPath,
    );
    if (ffmpegResult != null) {
      return ffmpegResult;
    }

    if (isPlaybackActive || !allowMediaKitFallback) {
      return null;
    }

    return _tryGenerateWithMediaKit(
      videoFilePath: videoFilePath,
      durationMs: durationMs,
      seekSeconds: seekSeconds,
      outputPath: outputPath,
      session: mediaKitSession,
    );
  }

  static Future<String?> _tryGenerateWithFfmpeg({
    required String videoFilePath,
    required int seekSeconds,
    required String outputPath,
  }) async {
    final ffmpegExe = _resolveFfmpegExecutable();
    if (ffmpegExe == null) {
      return null;
    }

    try {
      final result = await Process.run(
        ffmpegExe,
        [
          '-y',
          '-ss',
          seekSeconds.toString(),
          '-i',
          videoFilePath,
          '-frames:v',
          '1',
          '-vf',
          'scale=${AppSpacing.thumbWidth.toInt()}:${AppSpacing.thumbHeight.toInt()}:force_original_aspect_ratio=decrease,pad=${AppSpacing.thumbWidth.toInt()}:${AppSpacing.thumbHeight.toInt()}:(ow-iw)/2:(oh-ih)/2:black',
          '-q:v',
          '5',
          outputPath,
        ],
        runInShell: false,
      );

      final outFile = File(outputPath);
      if (result.exitCode == 0 &&
          await outFile.exists() &&
          await outFile.length() > 0) {
        return outputPath;
      }
      if (await outFile.exists()) {
        await outFile.delete();
      }
      return null;
    } on ProcessException {
      return null;
    }
  }

  static Future<String?> _tryGenerateWithMediaKit({
    required String videoFilePath,
    required int durationMs,
    required int seekSeconds,
    required String outputPath,
    ThumbnailMediaKitSession? session,
  }) async {
    ThumbnailMediaKitSession? ownedSession;
    try {
      final activeSession =
          session ?? (ownedSession = await ThumbnailMediaKitSession.create());
      if (activeSession == null) {
        return null;
      }

      final player = activeSession.player;
      await player.stop();
      await player.setVolume(0.0);
      await player.open(Media(videoFilePath), play: true);

      final width = await player.stream.width
          .firstWhere((w) => w != null && w > 0)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (width == null || width <= 0) {
        await player.stop();
        return null;
      }

      var effectiveSeekSeconds = seekSeconds;
      var knownDuration = player.state.duration;
      if (knownDuration <= Duration.zero && durationMs <= 0) {
        knownDuration = await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => Duration.zero,
            );
      }

      final totalMs = durationMs > 0 ? durationMs : knownDuration.inMilliseconds;
      if (totalMs > 0) {
        effectiveSeekSeconds = _computeSeekSeconds(totalMs);
        final maxSeekSeconds =
            (totalMs / AppSpacing.millisecondsPerSecond).floor() - 1;
        if (maxSeekSeconds >= 1 && effectiveSeekSeconds > maxSeekSeconds) {
          effectiveSeekSeconds = maxSeekSeconds;
        }
      }

      await player.seek(Duration(seconds: effectiveSeekSeconds));
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await player.pause();

      final bytes = await player.screenshot(format: 'image/jpeg');
      await player.stop();

      if (bytes != null && bytes.isNotEmpty) {
        await File(outputPath).writeAsBytes(bytes, flush: true);
        if (await File(outputPath).exists()) {
          return outputPath;
        }
      }
      return null;
    } catch (e) {
      debugPrint('ThumbnailGeneratorService: media_kit error: $e');
      return null;
    } finally {
      if (ownedSession != null) {
        await ownedSession.dispose();
      }
    }
  }

  static String _stablePathHash(String input) {
    final bytes = utf8.encode(input);
    var hashA = 0x811c9dc5;
    var hashB = 0x9e3779b9;
    for (final byte in bytes) {
      hashA ^= byte;
      hashA = (hashA * 0x01000193) & 0xFFFFFFFF;
      hashB ^= (byte + 0x55) & 0xFF;
      hashB = (hashB * 0x85EBCA6B) & 0xFFFFFFFF;
    }
    final hexA = hashA.toRadixString(16).padLeft(8, '0');
    final hexB = hashB.toRadixString(16).padLeft(8, '0');
    return '$hexA$hexB';
  }

  static String? _resolveFfmpegExecutable() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final localFfmpeg = File(p.join(exeDir, 'ffmpeg.exe'));
    if (localFfmpeg.existsSync()) {
      return localFfmpeg.path;
    }
    return 'ffmpeg';
  }

  static int _computeSeekSeconds(int durationMs) {
    if (durationMs <= 0) {
      return 30;
    }
    final targetMs = (durationMs * AppSpacing.thumbnailSeekRatio).round();
    final seconds = (targetMs / AppSpacing.millisecondsPerSecond).round();
    return seconds < 5 ? 5 : seconds;
  }
}
