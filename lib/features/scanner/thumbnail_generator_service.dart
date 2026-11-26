import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import '../../core/storage/portable_paths.dart';

class ThumbnailGeneratorService {
  ThumbnailGeneratorService._();

  static Future<String?> generateEpisodeThumbnail({
    required String videoFilePath,
    required int durationMs,
    required bool isPlaybackActive,
  }) async {
    if (isPlaybackActive) {
      return null;
    }

    final cacheDir = await PortablePaths.getCacheDirectory();
    final hashName =
        base64Url.encode(utf8.encode(videoFilePath)).replaceAll('=', '');
    final outputPath = p.join(cacheDir, 'ep_$hashName.jpg');
    final outputFile = File(outputPath);

    if (await outputFile.exists()) {
      return outputPath;
    }

    final ffmpegExe = _resolveFfmpegExecutable();
    if (ffmpegExe == null) {
      return null;
    }

    final seekSeconds = _computeSeekSeconds(durationMs);
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

      if (result.exitCode == 0 && await outputFile.exists()) {
        return outputPath;
      }
      return null;
    } on ProcessException {
      return null;
    }
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
