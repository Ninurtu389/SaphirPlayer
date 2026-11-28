import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import '../../core/storage/portable_paths.dart';
import 'thumbnail_cache_key.dart';
import 'thumbnail_ffmpeg_runner.dart';
import 'thumbnail_media_kit_session.dart';

export 'thumbnail_cache_key.dart';
export 'thumbnail_media_kit_session.dart';

class ThumbnailGenerationResult {
  const ThumbnailGenerationResult({
    this.fileName,
    this.durationMs,
  });

  final String? fileName;
  final int? durationMs;
}

class ThumbnailGeneratorService {
  ThumbnailGeneratorService._();

  static void killActiveProcesses() =>
      ThumbnailFfmpegRunner.killActiveProcesses();

  @visibleForTesting
  static void resetExecutableCacheForTesting() =>
      ThumbnailFfmpegRunner.resetExecutableCache();

  static Future<ThumbnailGenerationResult?> generateEpisodeThumbnail({
    required String videoFilePath,
    required int durationMs,
    required bool Function() isPlaybackActive,
    int? fileSize,
    int? modifiedAt,
    ThumbnailMediaKitSession? mediaKitSession,
    bool allowMediaKitFallback = true,
  }) {
    return generateThumbnail(
      videoFilePath: videoFilePath,
      durationMs: durationMs,
      isPlaybackActive: isPlaybackActive,
      prefix: 'ep',
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      mediaKitSession: mediaKitSession,
      allowMediaKitFallback: allowMediaKitFallback,
    );
  }

  static Future<ThumbnailGenerationResult?> generateThumbnail({
    required String videoFilePath,
    required int durationMs,
    required bool Function() isPlaybackActive,
    String prefix = 'ep',
    int? fileSize,
    int? modifiedAt,
    ThumbnailMediaKitSession? mediaKitSession,
    bool allowMediaKitFallback = true,
  }) async {
    final outcome = await generateThumbnailWithOutcome(
      videoFilePath: videoFilePath,
      durationMs: durationMs,
      isPlaybackActive: isPlaybackActive,
      prefix: prefix,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      mediaKitSession: mediaKitSession,
      allowMediaKitFallback: allowMediaKitFallback,
    );
    if (!outcome.isSuccess) {
      return null;
    }
    return ThumbnailGenerationResult(
      fileName: outcome.fileName,
      durationMs: outcome.durationMs,
    );
  }

  static Future<ThumbnailGenerationOutcome> generateThumbnailWithOutcome({
    required String videoFilePath,
    required int durationMs,
    required bool Function() isPlaybackActive,
    String prefix = 'ep',
    int? fileSize,
    int? modifiedAt,
    ThumbnailMediaKitSession? mediaKitSession,
    bool allowMediaKitFallback = true,
  }) async {
    if (isPlaybackActive()) {
      return const ThumbnailGenerationOutcome(
        failureKind: ThumbnailFailureKind.cancelled,
      );
    }

    final videoFile = File(videoFilePath);
    if (!await videoFile.exists()) {
      return const ThumbnailGenerationOutcome(
        failureKind: ThumbnailFailureKind.transient,
        errorMessage: 'video file missing or unreachable',
      );
    }

    int effectiveSize;
    int effectiveModifiedAt;
    if (fileSize != null && modifiedAt != null) {
      effectiveSize = fileSize;
      effectiveModifiedAt = modifiedAt;
    } else {
      try {
        final stat = await videoFile.stat();
        effectiveSize = fileSize ?? stat.size;
        effectiveModifiedAt =
            modifiedAt ?? stat.modified.millisecondsSinceEpoch;
      } on FileSystemException catch (e) {
        return ThumbnailGenerationOutcome(
          failureKind: ThumbnailFailureKind.transient,
          errorMessage: ThumbnailCacheKey.sanitizeErrorMessage(e.message),
        );
      }
    }
    if (effectiveSize <= 0) {
      return const ThumbnailGenerationOutcome(
        failureKind: ThumbnailFailureKind.permanent,
        errorMessage: 'video file is empty',
      );
    }

    final cacheDir = await PortablePaths.getCacheDirectory();
    final fileName = ThumbnailCacheKey.buildCacheFileName(
      prefix: prefix,
      filePath: videoFilePath,
      fileSize: effectiveSize,
      modifiedAt: effectiveModifiedAt,
    );
    final outputPath = p.join(cacheDir, fileName);
    final outputFile = File(outputPath);

    if (await outputFile.exists()) {
      if (await ThumbnailCacheKey.isValidImageFile(outputFile)) {
        return ThumbnailGenerationOutcome(fileName: fileName);
      }
      await ThumbnailFfmpegRunner.deleteIfExists(outputFile);
    }

    if (isPlaybackActive()) {
      return const ThumbnailGenerationOutcome(
        failureKind: ThumbnailFailureKind.cancelled,
      );
    }

    final tempPath = ThumbnailCacheKey.buildTempFilePath(
      cacheDir: cacheDir,
      finalFileName: fileName,
    );
    final tempFile = File(tempPath);
    final seekSeconds = computeSeekSeconds(durationMs);

    try {
      var ffmpegOk = await ThumbnailFfmpegRunner.tryGenerate(
        videoFilePath: videoFilePath,
        seekSeconds: seekSeconds,
        outputPath: tempPath,
        isPlaybackActive: isPlaybackActive,
      );
      int? probedDurationMs;
      if (!ffmpegOk && durationMs <= 0 && !isPlaybackActive()) {
        probedDurationMs =
            await ThumbnailFfmpegRunner.probeDurationMs(videoFilePath);
        if (probedDurationMs != null &&
            probedDurationMs > 0 &&
            !isPlaybackActive()) {
          final adjustedSeek = computeSeekSeconds(probedDurationMs);
          if (adjustedSeek != seekSeconds) {
            ffmpegOk = await ThumbnailFfmpegRunner.tryGenerate(
              videoFilePath: videoFilePath,
              seekSeconds: adjustedSeek,
              outputPath: tempPath,
              isPlaybackActive: isPlaybackActive,
            );
          }
        }
      }
      if (ffmpegOk &&
          await _commitTempFile(
            tempFile: tempFile,
            outputFile: outputFile,
            isPlaybackActive: isPlaybackActive,
          )) {
        if (durationMs <= 0 &&
            probedDurationMs == null &&
            !isPlaybackActive()) {
          probedDurationMs =
              await ThumbnailFfmpegRunner.probeDurationMs(videoFilePath);
        }
        return ThumbnailGenerationOutcome(
          fileName: fileName,
          durationMs: probedDurationMs,
        );
      }

      if (isPlaybackActive()) {
        return const ThumbnailGenerationOutcome(
          failureKind: ThumbnailFailureKind.cancelled,
        );
      }
      if (!allowMediaKitFallback) {
        return const ThumbnailGenerationOutcome(
          failureKind: ThumbnailFailureKind.transient,
          errorMessage: 'ffmpeg failed without fallback',
        );
      }

      final mkResult = await _tryGenerateWithMediaKit(
        videoFilePath: videoFilePath,
        durationMs: durationMs,
        seekSeconds: seekSeconds,
        outputPath: tempPath,
        isPlaybackActive: isPlaybackActive,
        session: mediaKitSession,
      );
      if (isPlaybackActive()) {
        return const ThumbnailGenerationOutcome(
          failureKind: ThumbnailFailureKind.cancelled,
        );
      }
      if (!mkResult.ok ||
          !await _commitTempFile(
            tempFile: tempFile,
            outputFile: outputFile,
            isPlaybackActive: isPlaybackActive,
          )) {
        return const ThumbnailGenerationOutcome(
          failureKind: ThumbnailFailureKind.transient,
          errorMessage: 'thumbnail generation failed',
        );
      }
      return ThumbnailGenerationOutcome(
        fileName: fileName,
        durationMs: mkResult.durationMs,
      );
    } finally {
      await ThumbnailFfmpegRunner.deleteIfExists(tempFile);
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
          .timeout(
            const Duration(seconds: AppSpacing.thumbnailOpenTimeoutSeconds),
            onTimeout: () => null,
          );
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

      final totalMs =
          durationMs > 0 ? durationMs : knownDuration.inMilliseconds;
      if (totalMs > 0) {
        effectiveSeekSeconds = computeSeekSeconds(totalMs);
      }

      if (isPlaybackActive()) {
        await player.stop();
        return (ok: false, durationMs: null);
      }

      await player.seek(Duration(seconds: effectiveSeekSeconds));
      var seekReached = false;
      await player.stream.position.firstWhere((pos) {
        if ((pos.inSeconds - effectiveSeekSeconds).abs() <= 5) {
          seekReached = true;
          return true;
        }
        return false;
      }).timeout(
        const Duration(milliseconds: AppSpacing.thumbnailSeekWaitTimeoutMs),
        onTimeout: () => player.state.position,
      );
      if (!seekReached &&
          effectiveSeekSeconds > 10 &&
          (player.state.position.inSeconds - effectiveSeekSeconds).abs() > 15) {
        await player.stop();
        return (ok: false, durationMs: null);
      }

      // Allow libmpv to decode and present a video frame at the seek target
      // before pausing, otherwise screenshot() can capture a black frame.
      await Future<void>.delayed(
        const Duration(milliseconds: AppSpacing.thumbnailFrameSettleMs),
      );
      await player.pause();

      if (isPlaybackActive()) {
        await player.stop();
        return (ok: false, durationMs: null);
      }

      var bytes = await player.screenshot(format: 'image/jpeg');
      if (bytes == null || bytes.isEmpty) {
        await Future<void>.delayed(
          const Duration(milliseconds: AppSpacing.thumbnailFrameSettleMs),
        );
        if (!isPlaybackActive()) {
          bytes = await player.screenshot(format: 'image/jpeg');
        }
      }
      await player.stop();

      if (bytes != null && bytes.isNotEmpty) {
        final outFile = File(outputPath);
        await outFile.writeAsBytes(bytes, flush: true);
        if (await ThumbnailCacheKey.isValidImageFile(outFile)) {
          final detectedMs = knownDuration.inMilliseconds > 0
              ? knownDuration.inMilliseconds
              : null;
          return (ok: true, durationMs: detectedMs);
        }
        await ThumbnailFfmpegRunner.deleteIfExists(outFile);
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

  static Future<bool> _commitTempFile({
    required File tempFile,
    required File outputFile,
    required bool Function() isPlaybackActive,
  }) async {
    if (isPlaybackActive()) {
      return false;
    }
    if (!await ThumbnailCacheKey.isValidImageFile(tempFile)) {
      return false;
    }
    try {
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      await tempFile.rename(outputFile.path);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @visibleForTesting
  static int computeSeekSeconds(int durationMs) {
    if (durationMs <= 0) {
      return AppSpacing.thumbnailMinSeekSeconds;
    }
    final totalSeconds =
        (durationMs / AppSpacing.millisecondsPerSecond).floor();
    if (totalSeconds <= 1) {
      return 0;
    }
    final ratioSeconds = ((durationMs * AppSpacing.thumbnailSeekRatio) /
            AppSpacing.millisecondsPerSecond)
        .round();

    if (totalSeconds > AppSpacing.thumbnailMinSeekSeconds + 2) {
      final target = ratioSeconds < AppSpacing.thumbnailMinSeekSeconds
          ? AppSpacing.thumbnailMinSeekSeconds
          : ratioSeconds;
      final maxSeek = totalSeconds - 2;
      return target > maxSeek ? maxSeek : target;
    }

    final maxSeek = totalSeconds - 1;
    if (totalSeconds <= AppSpacing.thumbnailShortVideoThresholdSeconds) {
      final target = ratioSeconds < AppSpacing.thumbnailShortVideoSeekSeconds
          ? AppSpacing.thumbnailShortVideoSeekSeconds
          : ratioSeconds;
      return target > maxSeek ? maxSeek : target;
    }

    final target = ratioSeconds < 5 ? 5 : ratioSeconds;
    return target > maxSeek ? maxSeek : target;
  }
}
