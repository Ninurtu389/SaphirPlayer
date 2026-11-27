import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import '../../core/storage/portable_paths.dart';

class ThumbnailGenerationResult {
  const ThumbnailGenerationResult({
    this.fileName,
    this.durationMs,
  });

  final String? fileName;
  final int? durationMs;
}

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

  static bool _ffmpegResolved = false;
  static String? _cachedFfmpegExe;
  static bool _ffprobeResolved = false;
  static String? _cachedFfprobeExe;

  @visibleForTesting
  static void resetExecutableCacheForTesting() {
    _ffmpegResolved = false;
    _cachedFfmpegExe = null;
    _ffprobeResolved = false;
    _cachedFfprobeExe = null;
  }

  static Future<ThumbnailGenerationResult?> generateEpisodeThumbnail({
    required String videoFilePath,
    required int durationMs,
    required bool Function() isPlaybackActive,
    ThumbnailMediaKitSession? mediaKitSession,
    bool allowMediaKitFallback = true,
  }) {
    return generateThumbnail(
      videoFilePath: videoFilePath,
      durationMs: durationMs,
      isPlaybackActive: isPlaybackActive,
      prefix: 'ep',
      mediaKitSession: mediaKitSession,
      allowMediaKitFallback: allowMediaKitFallback,
    );
  }

  static Future<ThumbnailGenerationResult?> generateThumbnail({
    required String videoFilePath,
    required int durationMs,
    required bool Function() isPlaybackActive,
    String prefix = 'ep',
    ThumbnailMediaKitSession? mediaKitSession,
    bool allowMediaKitFallback = true,
  }) async {
    if (isPlaybackActive()) {
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
    final fileName = '${prefix}_$hashName.jpg';
    final outputPath = p.join(cacheDir, fileName);
    final outputFile = File(outputPath);

    if (await outputFile.exists()) {
      try {
        if (await outputFile.length() > 0) {
          return ThumbnailGenerationResult(fileName: fileName);
        }
        await outputFile.delete();
      } on FileSystemException {
        return null;
      }
    }

    if (isPlaybackActive()) {
      return null;
    }

    final seekSeconds = _computeSeekSeconds(durationMs);

    final ffmpegOk = await _tryGenerateWithFfmpeg(
      videoFilePath: videoFilePath,
      seekSeconds: seekSeconds,
      outputPath: outputPath,
      isPlaybackActive: isPlaybackActive,
    );
    if (ffmpegOk) {
      int? probedDurationMs;
      if (durationMs <= 0 && !isPlaybackActive()) {
        probedDurationMs = await _probeDurationWithFfprobe(videoFilePath);
      }
      return ThumbnailGenerationResult(
        fileName: fileName,
        durationMs: probedDurationMs,
      );
    }

    if (isPlaybackActive() || !allowMediaKitFallback) {
      return null;
    }

    final mkResult = await _tryGenerateWithMediaKit(
      videoFilePath: videoFilePath,
      durationMs: durationMs,
      seekSeconds: seekSeconds,
      outputPath: outputPath,
      isPlaybackActive: isPlaybackActive,
      session: mediaKitSession,
    );
    if (!mkResult.ok) {
      return null;
    }
    return ThumbnailGenerationResult(
      fileName: fileName,
      durationMs: mkResult.durationMs,
    );
  }

  static Future<bool> _tryGenerateWithFfmpeg({
    required String videoFilePath,
    required int seekSeconds,
    required String outputPath,
    required bool Function() isPlaybackActive,
  }) async {
    if (isPlaybackActive()) {
      return false;
    }
    final ffmpegExe = await _resolveFfmpegExecutable();
    if (ffmpegExe == null || isPlaybackActive()) {
      return false;
    }

    Process? process;
    try {
      process = await Process.start(
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
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: AppSpacing.ffmpegTimeoutSeconds),
      );
      final outFile = File(outputPath);
      if (exitCode == 0 &&
          !isPlaybackActive() &&
          await outFile.exists() &&
          await outFile.length() > 0) {
        return true;
      }
      await _deleteIfExists(outFile);
      return false;
    } on TimeoutException {
      process?.kill();
      await _deleteIfExists(File(outputPath));
      return false;
    } on ProcessException {
      return false;
    }
  }

  static Future<int?> _probeDurationWithFfprobe(String videoFilePath) async {
    final ffprobeExe = await _resolveFfprobeExecutable();
    if (ffprobeExe == null) {
      return null;
    }
    Process? process;
    try {
      process = await Process.start(
        ffprobeExe,
        [
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'default=noprint_wrappers=1:nokey=1',
          videoFilePath,
        ],
        runInShell: false,
      );
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      unawaited(process.stderr.drain<void>());
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: AppSpacing.ffmpegTimeoutSeconds),
      );
      if (exitCode != 0) {
        return null;
      }
      final raw = (await stdoutFuture).trim();
      final seconds = double.tryParse(raw);
      if (seconds != null && seconds > 0 && seconds.isFinite) {
        return (seconds * AppSpacing.millisecondsPerSecond).round();
      }
      return null;
    } on TimeoutException {
      process?.kill();
      return null;
    } on ProcessException {
      return null;
    }
  }

  static Future<({bool ok, int? durationMs})> _tryGenerateWithMediaKit({
    required String videoFilePath,
    required int durationMs,
    required int seekSeconds,
    required String outputPath,
    required bool Function() isPlaybackActive,
    ThumbnailMediaKitSession? session,
  }) async {
    ThumbnailMediaKitSession? ownedSession;
    try {
      if (isPlaybackActive()) {
        return (ok: false, durationMs: null);
      }
      final activeSession =
          session ?? (ownedSession = await ThumbnailMediaKitSession.create());
      if (activeSession == null || isPlaybackActive()) {
        return (ok: false, durationMs: null);
      }

      final player = activeSession.player;
      await player.stop();
      await player.setVolume(0.0);
      await player.open(Media(videoFilePath), play: true);

      final width = await player.stream.width
          .firstWhere((w) => w != null && w > 0)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (width == null || width <= 0 || isPlaybackActive()) {
        await player.stop();
        return (ok: false, durationMs: null);
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

      if (isPlaybackActive()) {
        await player.stop();
        return (ok: false, durationMs: null);
      }

      await player.seek(Duration(seconds: effectiveSeekSeconds));
      await player.stream.position
          .firstWhere(
            (pos) => (pos.inSeconds - effectiveSeekSeconds).abs() <= 2,
          )
          .timeout(
            const Duration(milliseconds: AppSpacing.thumbnailSeekWaitTimeoutMs),
            onTimeout: () => player.state.position,
          );
      await player.pause();

      if (isPlaybackActive()) {
        await player.stop();
        return (ok: false, durationMs: null);
      }

      final bytes = await player.screenshot(format: 'image/jpeg');
      await player.stop();

      if (bytes != null && bytes.isNotEmpty) {
        await File(outputPath).writeAsBytes(bytes, flush: true);
        if (await File(outputPath).exists()) {
          final detectedMs =
              knownDuration.inMilliseconds > 0 ? knownDuration.inMilliseconds : null;
          return (ok: true, durationMs: detectedMs);
        }
      }
      return (ok: false, durationMs: null);
    } catch (e) {
      debugPrint('ThumbnailGeneratorService: media_kit error: $e');
      return (ok: false, durationMs: null);
    } finally {
      if (ownedSession != null) {
        await ownedSession.dispose();
      }
    }
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Unvollständige Cache-Datei ignorieren
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

  static Future<String?> _resolveFfmpegExecutable() async {
    if (_ffmpegResolved) {
      return _cachedFfmpegExe;
    }
    _cachedFfmpegExe = await _probeExecutable('ffmpeg', 'ffmpeg.exe');
    _ffmpegResolved = true;
    return _cachedFfmpegExe;
  }

  static Future<String?> _resolveFfprobeExecutable() async {
    if (_ffprobeResolved) {
      return _cachedFfprobeExe;
    }
    _cachedFfprobeExe = await _probeExecutable('ffprobe', 'ffprobe.exe');
    _ffprobeResolved = true;
    return _cachedFfprobeExe;
  }

  static Future<String?> _probeExecutable(String command, String winName) async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final localExe = File(p.join(exeDir, winName));
    if (localExe.existsSync()) {
      return localExe.path;
    }
    Process? process;
    try {
      process = await Process.start(
        command,
        const ['-version'],
        runInShell: false,
      );
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      final code = await process.exitCode.timeout(const Duration(seconds: 2));
      return code == 0 ? command : null;
    } on TimeoutException {
      process?.kill();
      return null;
    } on ProcessException {
      return null;
    }
  }

  static int _computeSeekSeconds(int durationMs) {
    if (durationMs <= 0) {
      return 30;
    }
    final targetMs = (durationMs * AppSpacing.thumbnailSeekRatio).round();
    final seconds = (targetMs / AppSpacing.millisecondsPerSecond).round();
    final shortThresholdMs =
        AppSpacing.thumbnailShortVideoThresholdSeconds *
            AppSpacing.millisecondsPerSecond;
    if (durationMs < shortThresholdMs) {
      return seconds < AppSpacing.thumbnailShortVideoSeekSeconds
          ? AppSpacing.thumbnailShortVideoSeekSeconds
          : seconds;
    }
    return seconds < 5 ? 5 : seconds;
  }
}
